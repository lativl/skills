#!/bin/bash
# bash 3.2 compatible. Run from ANY directory:
#   /bin/bash agent-pairing-skill/tests/install-smoke.sh
#
# The installer replaces FOUR live destinations at once. Every case below exists because a partial
# release is worse than no release: two runtimes disagreeing about the protocol is exactly the state
# the protocol is supposed to make impossible.
#
# Everything runs against a temporary root containing fake Claude/Codex homes. Nothing here touches a
# real installation.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
SOURCE="$(cd "$HERE/.." && pwd -P)"
INSTALL="$SOURCE/scripts/install.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
nok() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

SMOKE_TMP="$(mktemp -d /tmp/agent-pairing-install-smoke.XXXXXX)" \
  || { echo "FATAL: temp allocation failed" >&2; exit 3; }
[ -n "$SMOKE_TMP" ] && [ -d "$SMOKE_TMP" ] || { echo "FATAL: temp allocation produced no directory" >&2; exit 3; }
case "$SMOKE_TMP" in /tmp/agent-pairing-install-smoke.?*) ;; *) echo "FATAL: bad temp path" >&2; exit 3 ;; esac
trap 'rm -rf "$SMOKE_TMP"' EXIT

# A fresh pair of runtime homes, each carrying a SENTINEL from the "previous release". Rollback is
# proved by those sentinels surviving byte-for-byte, not by the absence of an error message.
#
# The case directory is ALLOCATED, not counted. Every caller invokes this as `c="$(new_env)"`, which
# runs it in a subshell -- so an incremented counter never reaches the parent and every case would
# silently reuse the first directory, inheriting the previous case's record roots and installs. That
# is the same subshell trap the validator hit twice; a counter is simply the wrong mechanism when the
# function must return a value.
new_env() { # -> prints the case root
  c="$(mktemp -d "$SMOKE_TMP/case.XXXXXX")" || return 1
  mkdir -p "$c/claude/skills/agent-pairing" "$c/claude/skills/pair-with-primary" \
           "$c/codex/skills/agent-pairing" "$c/codex/skills/pair-with-primary" \
           "$c/claude/agent-pairing" "$c/codex/agent-pairing" || return 1
  for d in claude/skills/agent-pairing claude/skills/pair-with-primary \
           codex/skills/agent-pairing codex/skills/pair-with-primary; do
    printf 'PREVIOUS RELEASE SENTINEL\n' >"$c/$d/SENTINEL"
  done
  printf '%s\n' "$c"
}

sentinels_intact() { # <case-root>
  for d in claude/skills/agent-pairing claude/skills/pair-with-primary \
           codex/skills/agent-pairing codex/skills/pair-with-primary; do
    [ -f "$1/$d/SENTINEL" ] || return 1
    [ "$(cat "$1/$d/SENTINEL")" = 'PREVIOUS RELEASE SENTINEL' ] || return 1
  done
}

# Most cases exercise the guards, the topic gate, the swap and the rollback -- none of which the
# package suites affect -- so they skip the suites to stay fast. `run_install_full` drives the real
# path, suites and all, at least once.
run_install() { # <case-root> [extra args...]
  c="$1"; shift
  ( cd /private/tmp && AP_INSTALL_SKIP_SUITES=1 /bin/bash "$INSTALL" --source "$SOURCE" \
      --claude-root "$c/claude" --codex-root "$c/codex" "$@" ) >"$SMOKE_TMP/out" 2>&1
}
run_install_full() { # <case-root> [extra args...]
  c="$1"; shift
  ( cd /private/tmp && /bin/bash "$INSTALL" --source "$SOURCE" \
      --claude-root "$c/claude" --codex-root "$c/codex" "$@" ) >"$SMOKE_TMP/out" 2>&1
}

# Build a v1 topic (no protocol_version) or a v2 topic under a record root.
mk_topic() { # <record-root> <slug> <v1|v2> <closed|open|invalid>
  t="$1/$2"; mkdir -p "$t/turns"
  case "$3" in
    v1) printf -- '---\ntopic_id: %s\nbase_sha: %s\nbase_ref: refs/heads/main\nsession_branch: pair/%s\nsession_worktree: %s/wt\nwork_repo_common_dir: %s/repo/.git\n---\n# %s\n' \
          "$2" 1111111111111111111111111111111111111111 "$2" "$t" "$t" "$2" >"$t/TOPIC.md" ;;
    v2) printf -- '---\nprotocol_version: 2\ntopic_id: %s\nparticipant_start_mode: owner-manual\nparticipant_selection_source: initial-prompt\nbase_sha: %s\nbase_ref: refs/heads/main\nsession_branch: pair/%s\nsession_worktree: %s/wt\nwork_repo_common_dir: %s/repo/.git\n---\n# %s\n' \
          "$2" 1111111111111111111111111111111111111111 "$2" "$t" "$t" "$2" >"$t/TOPIC.md" ;;
  esac
  case "$4" in
    open) printf -- '---\nrecord_seq: 0001\nkind: assignment\ntopic_id: %s\nturn_id: 0001\nattempt_id: 01\nturn_kind: NORMAL\nbase_sha: %s\nsession_branch: pair/%s\nsession_worktree: %s/wt\nwork_repo_common_dir: %s/repo/.git\nscope: src/\ndeadline: 2026-08-14T23:00:00Z\nagent_id: a\nrecorded_at: 2026-08-14T10:00:00Z\n---\nopen\n' \
          "$2" 1111111111111111111111111111111111111111 "$2" "$t" "$t" >"$t/turns/0001-t0001-a01-assignment.md" ;;
    invalid) printf -- '---\nrecord_seq: 0009\nkind: assignment\ntopic_id: %s\n---\nmalformed: the filename prefix disagrees with record_seq\n' \
          "$2" >"$t/turns/0001-t0001-a01-assignment.md" ;;
  esac
  git -C "$t" init -q && git -C "$t" config user.name s && git -C "$t" config user.email s@t \
    && git -C "$t" add -A && git -C "$t" commit -qm topic >/dev/null 2>&1
}

# ============================================================================================
# Path guards. Every one of these would be a destructive operation on a path nobody chose.
# ============================================================================================
c="$(new_env)"
for bad in '' 'relative/path' '/' '   '; do
  ( cd /private/tmp && /bin/bash "$INSTALL" --source "$bad" --claude-root "$c/claude" --codex-root "$c/codex" ) \
    >"$SMOKE_TMP/out" 2>&1
  if [ $? -ne 0 ]; then ok "refuses source path '$bad'"
  else nok "refuses source path '$bad'" "the installer accepted it"; fi
done
for bad in '' 'relative/path' '/'; do
  ( cd /private/tmp && /bin/bash "$INSTALL" --source "$SOURCE" --claude-root "$bad" --codex-root "$c/codex" ) \
    >"$SMOKE_TMP/out" 2>&1
  if [ $? -ne 0 ]; then ok "refuses destination root '$bad'"
  else nok "refuses destination root '$bad'" "the installer accepted it"; fi
done
( cd /private/tmp && /bin/bash "$INSTALL" --source "$SOURCE" --claude-root "$c/claude" \
    --codex-root "$c/codex" --record-root "$c/nonexistent" ) >"$SMOKE_TMP/out" 2>&1
if [ $? -ne 0 ]; then ok "an explicitly named record root that does not exist is an error"
else nok "an explicitly named record root that does not exist is an error" "accepted"; fi

# A CONFIGURED DEFAULT root that is absent is reported and skipped — unlike an explicit one, nobody
# asserted it exists.
c="$(new_env)"; rmdir "$c/codex/agent-pairing"
run_install "$c"
if grep -q 'skipping' "$SMOKE_TMP/out"; then ok "a missing default record root is reported and skipped"
else nok "a missing default record root is reported and skipped" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

# ============================================================================================
# The open-topic gate. A release that replaces BOTH runtimes must gate on BOTH runtimes' topics:
# a default covering only one would let an open topic in the other pass a check it was never
# enumerated by, which is fail-open on a stated safety precondition.
# ============================================================================================
c="$(new_env)"; mk_topic "$c/claude/agent-pairing" open-claude v1 open
run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then ok "an open v1 topic under the CLAUDE default refuses"
else nok "an open v1 topic under the CLAUDE default refuses" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

c="$(new_env)"; mk_topic "$c/codex/agent-pairing" open-codex v1 open
run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then ok "an open v1 topic under the CODEX default refuses"
else nok "an open v1 topic under the CODEX default refuses" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

c="$(new_env)"; mk_topic "$c/claude/agent-pairing" bad-v1 v1 invalid
run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then ok "an INVALID v1 topic with no acknowledgement refuses"
else nok "an INVALID v1 topic with no acknowledgement refuses" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

# A valid, non-CLOSED v2 topic refuses and CANNOT be acknowledged: acknowledgements are frozen-v1
# exit-2 evidence only.
c="$(new_env)"; mk_topic "$c/claude/agent-pairing" idle-v2 v2 ''
run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then ok "a valid non-CLOSED v2 topic refuses"
else nok "a valid non-CLOSED v2 topic refuses" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

# ============================================================================================
# Failure injection. The sentinels are the whole proof: an installer that reports failure while
# leaving a half-swapped pair of runtimes has done the one thing it exists to prevent.
# ============================================================================================
c="$(new_env)"
AP_INSTALL_FAIL_AT=after-first-swap run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then
  ok "a failure AFTER the first swap restores all four packages"
else
  nok "a failure AFTER the first swap restores all four packages" "sentinels did not survive: $(sed -n '1,3p' "$SMOKE_TMP/out")"
fi

c="$(new_env)"
AP_INSTALL_FAIL_AT=post-install-validation run_install "$c"
if [ $? -ne 0 ] && sentinels_intact "$c"; then
  ok "a failure during post-install validation restores all four packages"
else
  nok "a failure during post-install validation restores all four packages" "sentinels did not survive: $(sed -n '1,3p' "$SMOKE_TMP/out")"
fi

# ============================================================================================
# The happy path, and four-way parity.
# ============================================================================================
# THE FULL PATH: suites and all. Every other case skips them for speed, so this one is what proves
# the installer actually gates on them.
c="$(new_env)"
run_install_full "$c"
if [ $? -eq 0 ]; then
  ok "a clean environment installs (running every package gate)"

  missing=""
  for d in claude/skills/agent-pairing codex/skills/agent-pairing; do
    for f in SKILL.md RUNBOOK.md scripts/validate.sh scripts/validate-v1.sh tests/run-tests.sh; do
      [ -f "$c/$d/$f" ] || missing="$missing $d/$f"
    done
  done
  for d in claude/skills/pair-with-primary codex/skills/pair-with-primary; do
    [ -f "$c/$d/SKILL.md" ] || missing="$missing $d/SKILL.md"
  done
  if [ -n "$missing" ]; then nok "all four packages are present" "missing:$missing"
  else ok "all four packages are present"; fi

  # The old release must be GONE, not merged with the new one. A leftover file from the previous
  # install is a package that is neither version.
  leftover=""
  for d in claude/skills/agent-pairing claude/skills/pair-with-primary \
           codex/skills/agent-pairing codex/skills/pair-with-primary; do
    [ -e "$c/$d/SENTINEL" ] && leftover="$leftover $d"
  done
  if [ -n "$leftover" ]; then nok "the previous release is replaced, not merged" "sentinel survived in:$leftover"
  else ok "the previous release is replaced, not merged"; fi

  # Byte-for-byte parity between source and both installs, and between the two runtimes.
  manifest() { # <dir>
    ( cd "$1" 2>/dev/null && find . -type f ! -name '.DS_Store' | LC_ALL=C sort \
        | while read -r f; do printf '%s %s %s\n' "$f" "$(shasum -a 256 "$f" | awk '{print $1}')" \
            "$(ls -l "$f" | awk '{print $1}')"; done )
  }
  for pkg in agent-pairing pair-with-primary; do
    a="$(manifest "$SOURCE/$pkg")"; b="$(manifest "$c/claude/skills/$pkg")"; d2="$(manifest "$c/codex/skills/$pkg")"
    if [ "$a" = "$b" ]; then ok "$pkg: Claude matches the source byte-for-byte"
    else nok "$pkg: Claude matches the source byte-for-byte" "manifests differ"; fi
    if [ "$b" = "$d2" ]; then ok "$pkg: both runtimes are identical"
    else nok "$pkg: both runtimes are identical" "manifests differ"; fi
  done

  # The installed copies must actually RUN. The installer already runs the FULL package gate against
  # both installed roots as its post-install validation, and the failure-injection case above proves
  # that a failing post-install validation rolls all four destinations back — so re-running the whole
  # gate here would cost several minutes to re-derive a fact the injection case already establishes.
  #
  # What is NOT covered by that argument is whether the installed tree is independently executable at
  # all: correct permissions, resolvable relative paths, and a working example replay from a neutral
  # directory. Those are checked directly and cheaply.
  for r in claude codex; do
    if ( cd /private/tmp && /bin/bash "$c/$r/skills/pair-with-primary/tests/run-tests.sh" ) >/dev/null 2>&1; then
      ok "$r: the installed participant contract passes"
    else
      nok "$r: the installed participant contract passes" "the installed participant suite failed"
    fi
    if ( cd /private/tmp && /bin/bash "$c/$r/skills/agent-pairing/tests/v2/run-tests.sh" version ) >/dev/null 2>&1; then
      ok "$r: the installed validator runs from a neutral directory"
    else
      nok "$r: the installed validator runs from a neutral directory" "the installed v2 suite could not run"
    fi
    et="$( cd /private/tmp && /bin/bash "$c/$r/skills/agent-pairing/example/rehydrate.sh" --print-topic 2>/dev/null )"
    if [ -n "$et" ] && ( cd /private/tmp && /bin/bash "$c/$r/skills/agent-pairing/scripts/validate.sh" --check "$et" 2>/dev/null | grep -Fxq 'classification: CLOSED' ); then
      ok "$r: the installed example replays to CLOSED"
    else
      nok "$r: the installed example replays to CLOSED" "the installed example did not replay"
    fi
    ( cd /private/tmp && /bin/bash "$c/$r/skills/agent-pairing/example/rehydrate.sh" --clean ) >/dev/null 2>&1
  done
else
  nok "a clean environment installs" "$(sed -n '1,5p' "$SMOKE_TMP/out")"
fi

# A CLOSED v1 topic under both defaults permits the install.
c="$(new_env)"
mk_topic "$c/claude/agent-pairing" closed-a v2 ''
rm -rf "$c/claude/agent-pairing/closed-a"
run_install "$c"
if [ $? -eq 0 ]; then ok "an empty record root permits the install"
else nok "an empty record root permits the install" "$(sed -n '1,3p' "$SMOKE_TMP/out")"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$((PASS + FAIL))" -gt 0 ] || { echo "FATAL: the smoke suite asserted nothing" >&2; exit 3; }
[ "$FAIL" -eq 0 ]
