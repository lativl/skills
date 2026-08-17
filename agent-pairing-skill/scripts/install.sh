#!/bin/bash
# bash 3.2 compatible. Installs the agent-pairing release into BOTH runtimes.
#
#   install.sh --source ABSOLUTE_REPO_DIR --claude-root ABSOLUTE_HOME --codex-root ABSOLUTE_HOME
#              [--record-root ABSOLUTE_PATH]...  [--legacy-invalid-ack ABSOLUTE_FILE]...
#
# FOUR destinations, ONE release:
#     Claude agent-pairing · Claude pair-with-primary · Codex agent-pairing · Codex pair-with-primary
#
# They ship together or not at all. Two runtimes disagreeing about the protocol is precisely the
# state the protocol exists to make impossible: a primary on one version and a participant on the
# other would each be following rules the other does not implement, and the record would not record
# that fact.
#
# Each individual rename is atomic; the cross-root operation is transaction-LIKE, not
# filesystem-atomic. So the swap window is kept as small as possible — everything is staged and
# verified first — and any detected failure restores a coherent previous release rather than leaving
# a mixed steady state.
set -u

SOURCE="" CLAUDE_ROOT="" CODEX_ROOT="" RECORD_ROOTS="" ACK_FILES=""
FAIL_AT="${AP_INSTALL_FAIL_AT:-}"   # failure injection, for tests/install-smoke.sh only
# TEST-ONLY. The installer runs the full package gate four times per release (source, stage, and
# both installed roots), and each run takes minutes. The smoke harness drives the installer a dozen
# times to exercise the guards, the topic gate, the swap and the rollback -- none of which the suites
# affect -- so it sets this to keep those cases fast. It runs at least one case WITHOUT it, so the
# real path is still proven. A release must never set it: skipping the suites is the difference
# between installing a verified package and installing whatever happens to be on disk.
SKIP_SUITES="${AP_INSTALL_SKIP_SUITES:-}"
# ...and it is REFUSED unless both runtime roots are under a temporary directory. "Documented as
# test-only" is not a control: an environment variable that silently disables every package gate is
# a production bypass no matter what the comment says, and the release evidence claims those gates
# protected the release. Enforced below, once the roots are known.

die() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }
say() { printf '%s\n' "$1"; }

# Refuse a path that is empty, relative, whitespace-only, the filesystem root, or `..`-escaping —
# BEFORE it can reach mkdir, mv or rm. Every one of those is a destructive operation on a path
# nobody chose, and the check has to come first because the damage is done by the time you notice.
require_safe_path() { # <label> <path>
  case "$2" in
    '') die "$1 is empty" ;;
    /) die "$1 must not be the filesystem root" ;;
    /*) ;;
    *) die "$1 must be an absolute path (got '$2')" ;;
  esac
  case "$2" in
    *..*) die "$1 must not contain '..' (got '$2')" ;;
    *[!\ ]*) ;;
    *) die "$1 is whitespace only" ;;
  esac
}

# `shift 2` with only one argument left returns 1 and shifts NOTHING, so without this check the loop
# re-reads the same option forever. An installer that hangs on a typo is worse than one that refuses.
need_value() { [ $# -ge 2 ] || die "$1 requires a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --source)              need_value "$@"; SOURCE="$2"; shift 2 ;;
    --claude-root)         need_value "$@"; CLAUDE_ROOT="$2"; shift 2 ;;
    --codex-root)          need_value "$@"; CODEX_ROOT="$2"; shift 2 ;;
    --record-root)         need_value "$@"; RECORD_ROOTS="$RECORD_ROOTS
$2"; shift 2 ;;
    --legacy-invalid-ack)  need_value "$@"; ACK_FILES="$ACK_FILES
$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_safe_path "--source" "$SOURCE"
require_safe_path "--claude-root" "$CLAUDE_ROOT"
require_safe_path "--codex-root" "$CODEX_ROOT"
[ -d "$SOURCE" ] || die "--source is not a directory: $SOURCE"
for p in agent-pairing/SKILL.md agent-pairing/scripts/validate.sh agent-pairing/scripts/validate-v1.sh \
         pair-with-primary/SKILL.md; do
  [ -f "$SOURCE/$p" ] || die "--source does not look like the repository package: missing $p"
done
for r in "$CLAUDE_ROOT" "$CODEX_ROOT"; do
  [ -d "$r" ] || die "runtime root is not a directory: $r"
done

if [ -n "$SKIP_SUITES" ]; then
  for r in "$CLAUDE_ROOT" "$CODEX_ROOT"; do
    case "$(cd "$r" 2>/dev/null && pwd -P)" in
      /private/tmp/*|/tmp/*|/private/var/folders/*|/var/folders/*) ;;
      *) die "AP_INSTALL_SKIP_SUITES is refused for '$r': it disables every package gate and is usable only against temporary roots" ;;
    esac
  done
fi

WORK="$(mktemp -d /tmp/agent-pairing-install.XXXXXX)" || die "temp allocation failed"
[ -n "$WORK" ] && [ -d "$WORK" ] || die "temp allocation produced no directory"
cleanup() { case "$WORK" in /tmp/agent-pairing-install.?*) rm -rf "$WORK" ;; esac; }

VALIDATE="$SOURCE/agent-pairing/scripts/validate.sh"
VALIDATE_V1="$SOURCE/agent-pairing/scripts/validate-v1.sh"

# ================================================================================================
# 1. The open-topic gate
# ================================================================================================
# With no --record-root given, the default is the record root of EVERY runtime being written. A
# default covering only one would let an open topic in the other pass a check it was never
# enumerated by — fail-open on a stated safety precondition.
if [ -z "$(printf '%s' "$RECORD_ROOTS" | tr -d '\n')" ]; then
  RECORD_ROOTS="$CLAUDE_ROOT/agent-pairing
$CODEX_ROOT/agent-pairing"
  ROOTS_ARE_DEFAULT=yes
else
  ROOTS_ARE_DEFAULT=no
fi

SELECTED_ROOTS=""
while IFS= read -r root; do
  [ -n "$root" ] || continue
  require_safe_path "--record-root" "$root"
  if [ ! -d "$root" ]; then
    # An EXPLICIT root that does not exist is an error — somebody asserted it. A configured DEFAULT
    # that does not exist is reported and skipped, because nobody did.
    [ "$ROOTS_ARE_DEFAULT" = yes ] || die "--record-root does not exist: $root"
    say "record root absent, skipping: $root"
    continue
  fi
  SELECTED_ROOTS="$SELECTED_ROOTS
$root"
done <<EOF
$RECORD_ROOTS
EOF

# The empty-string SHA-256. An acknowledgement binding this digest would be binding "no output at
# all", which is the one thing the evidence must never be.
EMPTY_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

ack_field() { awk -v k="$2" '$1 == k ":" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$1"; }

# One acknowledgement, checked against one exit-2 frozen-v1 topic. This is the ONLY
# acknowledgement-eligible outcome in the whole gate.
check_acknowledgement() { # <topic-dir> <stderr-file> -> 0 when an exact ack permits this topic
  a_topic="$1" a_err="$2"
  a_bytes="$(LC_ALL=C wc -c <"$a_err" | tr -d ' ')"
  a_digest="$(shasum -a 256 "$a_err" | awk '{print $1}')"
  [ "$a_bytes" -gt 0 ] || { say "  no acknowledgement possible: the validator produced no stderr"; return 1; }
  [ "$a_digest" != "$EMPTY_SHA256" ] || { say "  no acknowledgement possible: stderr digest is the empty-string digest"; return 1; }

  a_canon="$(cd "$a_topic" && pwd -P)" || return 1
  a_head="$(git -C "$a_topic" rev-parse HEAD 2>/dev/null)" || return 1
  a_tree="$(git -C "$a_topic" rev-parse 'HEAD^{tree}' 2>/dev/null)" || return 1
  # A dirty record repository cannot be pinned: the acknowledgement would describe bytes that are
  # not the bytes on disk.
  [ -z "$(git -C "$a_topic" status --porcelain 2>/dev/null)" ] \
    || { say "  no acknowledgement possible: the record repository is dirty"; return 1; }

  a_matched=0
  while IFS= read -r ackf; do
    [ -n "$ackf" ] || continue
    [ "$(ack_field "$ackf" topic_path)" = "$a_canon" ] || continue
    a_matched=$((a_matched + 1))
    a_use="$ackf"
  done <<EOF
$ACK_FILES
EOF
  [ "$a_matched" -eq 1 ] || {
    [ "$a_matched" -eq 0 ] && say "  no acknowledgement names this topic"
    [ "$a_matched" -gt 1 ] && say "  REFUSED: $a_matched acknowledgements name this topic"
    return 1
  }

  for f in ack_version record_head record_tree validator_exit validator_stdout_byte_count \
           validator_stderr_byte_count validator_stderr_sha256 owner tracker_ref reason \
           no_live_participant liveness_evidence_ref acknowledged_at; do
    [ -n "$(ack_field "$a_use" "$f")" ] || { say "  REFUSED: acknowledgement is missing $f"; return 1; }
  done
  [ "$(ack_field "$a_use" ack_version)" = 1 ] || { say "  REFUSED: unsupported ack_version"; return 1; }
  [ "$(ack_field "$a_use" record_head)" = "$a_head" ] || { say "  REFUSED: record_head does not match HEAD"; return 1; }
  [ "$(ack_field "$a_use" record_tree)" = "$a_tree" ] || { say "  REFUSED: record_tree does not match HEAD^{tree}"; return 1; }
  [ "$(ack_field "$a_use" validator_exit)" = 2 ] || { say "  REFUSED: validator_exit must be 2"; return 1; }
  [ "$(ack_field "$a_use" validator_stdout_byte_count)" = 0 ] || { say "  REFUSED: stdout must be exactly zero bytes"; return 1; }
  [ "$(ack_field "$a_use" validator_stderr_byte_count)" = "$a_bytes" ] || { say "  REFUSED: stderr byte count disagrees"; return 1; }
  [ "$(ack_field "$a_use" validator_stderr_sha256)" = "$a_digest" ] || { say "  REFUSED: stderr digest disagrees"; return 1; }
  # The literal `true`, not merely a truthy-looking value: this is the owner asserting nobody is
  # still working in that topic, which is the fact the whole quarantine rests on.
  [ "$(ack_field "$a_use" no_live_participant)" = true ] \
    || { say "  REFUSED: no_live_participant must be the literal true"; return 1; }

  say "  ACKNOWLEDGED by $(basename "$a_use")"
  say "    owner:            $(ack_field "$a_use" owner)"
  say "    tracker:          $(ack_field "$a_use" tracker_ref)"
  say "    reason:           $(ack_field "$a_use" reason)"
  say "    liveness:         no_live_participant=true, evidence=$(ack_field "$a_use" liveness_evidence_ref)"
  say "    record HEAD:      $a_head"
  say "    record tree:      $a_tree"
  say "    stderr bytes:     $a_bytes"
  say "    stderr sha256:    $a_digest"
  say "    ack file sha256:  $(shasum -a 256 "$a_use" | awk '{print $1}')"
  return 0
}

TOPICS_SEEN=0
while IFS= read -r root; do
  [ -n "$root" ] || continue
  say "enumerating record root: $root"
  for topic in "$root"/*; do
    [ -d "$topic" ] || continue
    slug="$(basename "$topic")"

    # A directory under a record root is a TOPIC unless it is provably not one. Skipping on a missing
    # working-tree TOPIC.md meant deleting that one file removed a topic from the gate entirely,
    # records and all — the gate would then proceed over a topic nobody had classified.
    if ! git -C "$topic" rev-parse --git-dir >/dev/null 2>&1; then
      # Not a repository at all: it cannot hold records, so it is not a topic.
      [ -n "$(ls -A "$topic" 2>/dev/null)" ] \
        && die "'$slug' sits under a record root but is not a Git repository; move it out or make it a topic"
      continue
    fi
    TOPICS_SEEN=$((TOPICS_SEEN + 1))

    # The version is read from the COMMITTED TOPIC.md, like everything else the protocol trusts. A
    # working-tree read would let an uncommitted edit choose which validator judges the topic.
    git -C "$topic" cat-file -e HEAD:TOPIC.md 2>/dev/null \
      || die "topic '$slug' has no committed TOPIC.md; it cannot be classified and must not be enumerated by a gate it cannot satisfy"
    ver="$(git -C "$topic" show HEAD:TOPIC.md 2>/dev/null | awk '/^---$/ { c++; next } c == 1 && $1 == "protocol_version:" { print $2; exit } c >= 2 { exit }')"
    case "$ver" in
      '') v="$VALIDATE_V1"; vlabel="frozen v1" ;;
      1)  v="$VALIDATE_V1"; vlabel="frozen v1" ;;
      2)  v="$VALIDATE"; vlabel="v2" ;;
      *)  die "topic '$slug' declares protocol_version '$ver', which selects no validator" ;;
    esac

    # Canonical evidence capture: fixed environment, streams kept separate and unnormalized.
    LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 /bin/bash "$v" --check "$topic" \
      >"$WORK/t.out" 2>"$WORK/t.err"
    rc=$?
    cls="$(grep -m1 '^classification:' "$WORK/t.out" 2>/dev/null)"
    say "  $slug [$vlabel] exit $rc ${cls:-}"

    if [ "$rc" -eq 0 ]; then
      # Exact CLOSED permits, for either protocol version. Anything else refuses, and no
      # acknowledgement can override it: an acknowledgement is for evidence that cannot be
      # classified, never for a topic that classified and said something inconvenient.
      [ "$cls" = 'classification: CLOSED' ] \
        || die "topic '$slug' is not CLOSED (${cls:-no classification}); every valid topic must be exact CLOSED before this release replaces the manuals"
      continue
    fi

    if [ "$rc" -eq 2 ] && [ "$vlabel" = "frozen v1" ]; then
      [ ! -s "$WORK/t.out" ] \
        || die "topic '$slug': frozen-v1 exit 2 wrote to stdout; the acknowledgement evidence is not canonical"
      check_acknowledgement "$topic" "$WORK/t.err" || die "topic '$slug' is an invalid v1 record with no exact owner acknowledgement"
      # Reproduce it. A digest that does not reproduce is not evidence of anything.
      LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 /bin/bash "$v" --check "$topic" \
        >"$WORK/t.out2" 2>"$WORK/t.err2"
      rc2=$?
      { [ "$rc2" -eq 2 ] && [ ! -s "$WORK/t.out2" ] \
        && [ "$(shasum -a 256 "$WORK/t.err2" | awk '{print $1}')" = "$(shasum -a 256 "$WORK/t.err" | awk '{print $1}')" ]; } \
        || die "topic '$slug': the frozen-v1 evidence did not reproduce"
      continue
    fi

    die "topic '$slug': validator exit $rc cannot be acknowledged (only a frozen-v1 exit 2 with deterministic stderr is acknowledgement-eligible)"
  done
done <<EOF
$SELECTED_ROOTS
EOF
say "topic gate: $TOPICS_SEEN topic(s) inspected, all permit deployment"

# ================================================================================================
# 2. Validate the source, then stage
# ================================================================================================
if [ -n "$SKIP_SUITES" ]; then
  say "WARNING: AP_INSTALL_SKIP_SUITES is set — package gates are being SKIPPED (test harness only)"
else
  say "running the source gate from a neutral directory"
  ( cd /private/tmp && /bin/bash "$SOURCE/agent-pairing/tests/run-tests.sh" ) >"$WORK/gate.out" 2>&1 \
    || { sed -n '$p' "$WORK/gate.out" >&2; die "the source package gate failed; nothing was installed"; }
fi

STAGE="$WORK/stage"
mkdir -p "$STAGE" || die "cannot create the staging area"
for pkg in agent-pairing pair-with-primary; do
  cp -R "$SOURCE/$pkg" "$STAGE/$pkg" || die "cannot stage $pkg"
  find "$STAGE/$pkg" -name '.DS_Store' -delete 2>/dev/null
done

# Verify every STAGE before touching a live destination.
for pkg in agent-pairing pair-with-primary; do
  [ -f "$STAGE/$pkg/SKILL.md" ] || die "staged $pkg has no SKILL.md"
done
if [ -z "$SKIP_SUITES" ]; then
  ( cd /private/tmp && /bin/bash "$STAGE/agent-pairing/tests/run-tests.sh" ) >"$WORK/stage.out" 2>&1 \
    || { sed -n '$p' "$WORK/stage.out" >&2; die "the STAGED package gate failed; nothing was installed"; }
fi
say "staged and verified both packages"

# ================================================================================================
# 3. Save, swap, and roll back on any failure
# ================================================================================================
# Rollback bookkeeping lives in FILES, one record per line, not in space-delimited strings.
#
# `for entry in $SWAPPED` splits on whitespace, and an absolute path may legally contain a space —
# the path guard rejects a whitespace-ONLY path, not a path with a space in it. With a root like
# `/private/tmp/ap space/claude`, rollback split the entry and ran `rm -rf /private/tmp/ap`: a
# destructive operation on a path nobody named, while the destination it was supposed to restore was
# left swapped. The rollback path is exactly where that must not happen.
SWAP_LOG="$WORK/swapped"    # "destination<TAB>backup", newest first
CREATED_LOG="$WORK/created" # destinations that had no previous installation
: >"$SWAP_LOG" || die "cannot create the swap log"
: >"$CREATED_LOG" || die "cannot create the created log"

rollback() {
  say "ROLLING BACK"
  # Newest first, so a destination is restored before anything that was swapped before it.
  if [ -s "$SWAP_LOG" ]; then
    while IFS="$(printf '\t')" read -r dest backup; do
      [ -n "$dest" ] || continue
      rm -rf "$dest"
      [ -d "$backup" ] && mv "$backup" "$dest" && say "  restored $dest"
    done <"$WORK/swapped.reversed"
  fi
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    rm -rf "$dest" && say "  removed $dest (no previous installation)"
  done <"$CREATED_LOG"
}

# Backup and staging slots are numbered, not derived from the root's BASENAME. Two distinct roots may
# legitimately share one — `/a/runtime` and `/b/runtime` — and the derived names then collided: the
# second `mv` nested one destination inside the other's backup, and rollback restored an aggregate
# directory to one destination while the next step could not find its backup at all. Four
# destinations, not restored coherently, from two roots that were merely named alike.
SWAP_N=0
install_one() { # <runtime-root> <package>
  dest="$1/skills/$2"
  require_safe_path "destination" "$dest"
  mkdir -p "$1/skills" || die "cannot create $1/skills"
  SWAP_N=$((SWAP_N + 1))
  staged_copy="$WORK/swap.$SWAP_N"
  cp -R "$STAGE/$2" "$staged_copy" || { rollback; die "cannot prepare the swap copy for $dest"; }
  if [ -d "$dest" ]; then
    backup="$WORK/backup.$SWAP_N"
    [ -e "$backup" ] && { rollback; die "backup slot $backup already exists"; }
    mv "$dest" "$backup" || { rollback; die "cannot save the previous $dest"; }
    printf '%s\t%s\n' "$dest" "$backup" >>"$SWAP_LOG"
    # Newest-first copy, rebuilt after each swap so rollback never has to reverse it under duress.
    ( cat "$SWAP_LOG" | tail -r 2>/dev/null || tac "$SWAP_LOG" ) >"$WORK/swapped.reversed"
  else
    printf '%s\n' "$dest" >>"$CREATED_LOG"
  fi
  mv "$staged_copy" "$dest" || { rollback; die "cannot install $dest"; }
  say "  installed $dest"
}

say "swapping all four destinations"
install_one "$CLAUDE_ROOT" agent-pairing
[ "$FAIL_AT" = after-first-swap ] && { rollback; die "injected failure: after-first-swap"; }
install_one "$CLAUDE_ROOT" pair-with-primary
install_one "$CODEX_ROOT" agent-pairing
install_one "$CODEX_ROOT" pair-with-primary

# ================================================================================================
# 4. Post-install validation — the installed copies must actually run
# ================================================================================================
say "validating the installed packages"
[ "$FAIL_AT" = post-install-validation ] && { rollback; die "injected failure: post-install-validation"; }

for r in "$CLAUDE_ROOT" "$CODEX_ROOT"; do
  if [ -z "$SKIP_SUITES" ]; then
    ( cd /private/tmp && /bin/bash "$r/skills/agent-pairing/tests/run-tests.sh" ) >"$WORK/post.out" 2>&1 \
      || { sed -n '$p' "$WORK/post.out" >&2; rollback; die "the installed package gate failed under $r"; }
  fi
  # The participant contract is fast and always runs: it is the cheapest proof that the installed
  # tree is executable at all.
  ( cd /private/tmp && /bin/bash "$r/skills/pair-with-primary/tests/run-tests.sh" ) >"$WORK/post.out" 2>&1 \
    || { sed -n '$p' "$WORK/post.out" >&2; rollback; die "the installed participant contract failed under $r"; }
done

# Cross-root parity: same bytes, same modes, both runtimes. A release where the two roots differ is
# two releases wearing one version number.
manifest_of() { # <dir>
  ( cd "$1" && find . -type f ! -name '.DS_Store' | LC_ALL=C sort \
      | while read -r f; do
          printf '%s %s %s\n' "$f" "$(shasum -a 256 "$f" | awk '{print $1}')" "$(ls -l "$f" | awk '{print $1}')"
        done )
}
for pkg in agent-pairing pair-with-primary; do
  manifest_of "$STAGE/$pkg" >"$WORK/m.src"
  manifest_of "$CLAUDE_ROOT/skills/$pkg" >"$WORK/m.claude"
  manifest_of "$CODEX_ROOT/skills/$pkg" >"$WORK/m.codex"
  cmp -s "$WORK/m.src" "$WORK/m.claude" || { rollback; die "$pkg: the Claude install does not match the source"; }
  cmp -s "$WORK/m.claude" "$WORK/m.codex" || { rollback; die "$pkg: the two runtimes do not match"; }
  say "  parity verified: $pkg"
done

# Backups go last, and only once every destination has passed.
while IFS="$(printf '\t')" read -r dest backup; do
  [ -n "$backup" ] || continue
  case "$backup" in "$WORK"/backup.*) rm -rf "$backup" ;; esac
done <"$SWAP_LOG"
cleanup
say "release installed to all four destinations"
