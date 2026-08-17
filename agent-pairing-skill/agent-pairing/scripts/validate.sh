#!/bin/bash
# bash 3.2 compatible. Default agent-pairing validator — protocol v2 ONLY.
#
#   /bin/bash scripts/validate.sh --check  TOPIC_DIR
#   /bin/bash scripts/validate.sh --render TOPIC_DIR
#
# Historical v1 topics are NOT accepted here. They are inspected only by the explicit frozen
# validator, scripts/validate-v1.sh. A missing, malformed, or mixed protocol version is a violation;
# it never silently selects legacy behavior.
#
# Exit codes:
#   0  the topic satisfies the v2 grammar; the classification is on stdout
#   2  protocol violation; the exact violation code is on stderr
#   3  invalid CLI usage or unusable environment
#
# Record data is consumed ONLY from committed Git objects. The record working tree is never a source
# of truth: a participant that could act on an uncommitted receipt is exactly the v1 defect this
# protocol exists to remove, and a validator that reads the working tree would bless it.
set -u

V2_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

v2_usage() {
  printf 'usage: validate.sh --check TOPIC_DIR\n       validate.sh --render TOPIC_DIR\n' >&2
  [ $# -gt 0 ] && printf 'error: %s\n' "$1" >&2
  exit 3
}

# A violation is terminal and fail-closed. Code first so callers can assert on an exact token.
v2_violation() { # <code> <detail>
  printf 'VIOLATION %s %s\n' "$1" "$2" >&2
  exit 2
}

# An environment failure is NOT a violation: it means the evidence could not be read at all, which
# must never be reported as a clean topic or as a merely-invalid one.
v2_fatal() { # <detail>
  printf 'FATAL %s\n' "$1" >&2
  exit 3
}

# --- CLI -------------------------------------------------------------------------------------------
[ $# -eq 2 ] || v2_usage "expected exactly two arguments, got $#"
V2_MODE="$1"
V2_TOPIC="$2"
case "$V2_MODE" in
  --check|--render) ;;
  *) v2_usage "unknown mode: $V2_MODE" ;;
esac
[ -n "$V2_TOPIC" ] || v2_usage "empty TOPIC_DIR"
[ -d "$V2_TOPIC" ] || v2_usage "no such directory: $V2_TOPIC"

# --- committed-object access -----------------------------------------------------------------------
# GIT_NO_REPLACE_OBJECTS keeps a replace ref from substituting the bytes under audit.
# GIT_OPTIONAL_LOCKS=0 keeps a read-only check from writing into someone else's record repository.
v2_git() { # <topic> <git-args...>
  v2_g_topic="$1"; shift
  GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 git -C "$v2_g_topic" "$@"
}

V2_WORK=""
v2_cleanup() { [ -n "$V2_WORK" ] && case "$V2_WORK" in /tmp/agent-pairing-v2.?*) rm -rf "$V2_WORK";; esac; }
trap v2_cleanup EXIT
V2_WORK="$(mktemp -d /tmp/agent-pairing-v2.XXXXXX)" || v2_fatal "temp allocation failed"
[ -n "$V2_WORK" ] && [ -d "$V2_WORK" ] || v2_fatal "temp allocation produced no directory"
V2_STAGE_N=0

# Copy one committed blob into a checked temporary file and print that file's path. Parsing happens
# only against these copies, never against the record working tree. Git's own diagnosis is kept in a
# sibling file rather than discarded, so an unreadable object can be reported with its reason.
V2_GIT_ERR=""
v2_stage_committed() { # <topic> <path-in-tree>
  V2_STAGE_N=$((V2_STAGE_N + 1))
  v2_s_file="$V2_WORK/blob.$V2_STAGE_N"
  v2_s_err="$V2_WORK/blob.$V2_STAGE_N.err"
  if ! v2_git "$1" show "HEAD:$2" >"$v2_s_file" 2>"$v2_s_err"; then
    V2_GIT_ERR="$(tr '\n' ';' <"$v2_s_err")"
    return 1
  fi
  V2_GIT_ERR=""
  printf '%s\n' "$v2_s_file"
}

# Read one front-matter scalar from a staged file. The key must be spelled `key: ` — a bare `key:2`
# is not a YAML mapping entry and is not silently accepted here either. The value is returned
# verbatim to end of line, so a trailing space or a quoted "2" stays distinguishable from 2.
v2_fm_get() { # <staged-file> <key>
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    c >= 2 { exit }' "$1"
}

# The front-matter block must be structurally sound BEFORE any key is read: exactly one opening and
# one closing `---`, flat `key: value` entries, and no duplicate key. Without this, a topic that
# declares `protocol_version: 2` and then `protocol_version: 1` is accepted on the first match —
# precisely the "mixed version" input the compatibility boundary is required to reject.
V2_FM_ERR=""
v2_fm_structure() { # <staged-file>; sets V2_FM_ERR, returns 1 when malformed
  V2_FM_ERR="$(awk '
    NR == 1 { if ($0 != "---") { print "front matter does not open with --- on line 1"; bad = 1; exit }
              next }
    done_fm == 1 { next }
    $0 == "---" { done_fm = 1; next }
    {
      if ($0 == "") { print "blank line inside front matter (line " NR ")"; bad = 1; exit }
      if ($0 !~ /^[A-Za-z_][A-Za-z0-9_]*:( |$)/) {
        print "line " NR " is not a flat key: value pair: " $0; bad = 1; exit }
      k = $0; sub(/:.*/, "", k)
      if (k in seen) { print "duplicate front-matter key: " k; bad = 1; exit }
      seen[k] = 1
    }
    END { if (bad != 1 && done_fm != 1) print "front matter block is never closed by ---" }
  ' "$1")"
  [ -z "$V2_FM_ERR" ]
}

v2_list_records() { # <topic>
  # An absent turns/ path is an EMPTY record set, not an error: `ls-tree -r --name-only HEAD turns`
  # exits zero with no output when the path does not exist (verified on Apple Git 2.50.1). A
  # `cat-file -e … || return 0` guard would be worse than useless here — it cannot distinguish an
  # absent path from a genuine read failure, and would turn fail-closed I/O into an empty record set.
  #
  # The read is NOT piped into `sort`: a pipeline's status is its LAST command's, so `ls-tree | sort`
  # reports `sort`'s success and a damaged record tree reads as an empty record set — a corrupt
  # repository classified as a clean, never-dispatched topic. Status is captured on its own line.
  v2_lr_out="$V2_WORK/records.list"
  v2_lr_err="$V2_WORK/records.err"
  if ! v2_git "$1" ls-tree -r --name-only HEAD turns >"$v2_lr_out" 2>"$v2_lr_err"; then
    V2_GIT_ERR="$(tr '\n' ';' <"$v2_lr_err")"
    return 1
  fi
  LC_ALL=C sort "$v2_lr_out"
}

# --- the record repository ---------------------------------------------------------------------------
v2_git "$V2_TOPIC" rev-parse --git-dir >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC: not a Git record repository; v2 reads records only from committed objects"
v2_git "$V2_TOPIC" rev-parse --verify HEAD >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC: record repository has no commit at HEAD"

# --- the compatibility boundary ----------------------------------------------------------------------
# The declared version is read from the COMMITTED TOPIC.md, so a topic cannot be talked into v2 by an
# uncommitted edit.
#
# An ABSENT TOPIC.md and an UNREADABLE one are different facts and get different exits. The path is
# resolved first: if `HEAD:TOPIC.md` names no object the topic is malformed (violation, exit 2); if
# it names an object that then fails to read, the evidence is unavailable (fatal, exit 3). Collapsing
# the two would let a damaged repository be reported as a merely-invalid topic.
v2_git "$V2_TOPIC" rev-parse --verify --quiet "HEAD:TOPIC.md" >/dev/null 2>&1 \
  || v2_violation TOPIC_MISSING "$V2_TOPIC: HEAD:TOPIC.md does not exist in the committed tree"
V2_TOPIC_BLOB="$(v2_stage_committed "$V2_TOPIC" TOPIC.md)" \
  || v2_fatal "$V2_TOPIC: HEAD:TOPIC.md names an object that cannot be read: $V2_GIT_ERR"
v2_fm_structure "$V2_TOPIC_BLOB" \
  || v2_violation TOPIC_FM_MALFORMED "$V2_TOPIC: TOPIC.md front matter is malformed: $V2_FM_ERR"
V2_TOPIC_VERSION="$(v2_fm_get "$V2_TOPIC_BLOB" protocol_version)"
case "$V2_TOPIC_VERSION" in
  2) ;;
  '') v2_violation PROTOCOL_VERSION "$V2_TOPIC: TOPIC.md declares no protocol_version; the default validator accepts only 2" ;;
  *)  v2_violation PROTOCOL_VERSION "$V2_TOPIC: TOPIC.md declares protocol_version '$V2_TOPIC_VERSION'; the default validator accepts only the exact scalar 2 (scripts/validate-v1.sh reads historical records)" ;;
esac

V2_TOPIC_ID="$(v2_fm_get "$V2_TOPIC_BLOB" topic_id)"
[ -n "$V2_TOPIC_ID" ] || v2_violation TOPIC_ID "$V2_TOPIC: TOPIC.md declares no topic_id"

# --- records -----------------------------------------------------------------------------------------
V2_RECORDS="$(v2_list_records "$V2_TOPIC")" \
  || v2_fatal "$V2_TOPIC: cannot enumerate committed records under turns/: $V2_GIT_ERR"

V2_RECORD_COUNT=0
for v2_r in $V2_RECORDS; do
  V2_RECORD_COUNT=$((V2_RECORD_COUNT + 1))
done

# --- classification ------------------------------------------------------------------------------------
# Task 1 pins only the no-record branch. Later tasks replace this with the full replay precedence.
if [ "$V2_RECORD_COUNT" -eq 0 ]; then
  printf 'classification: AWAITING_PARTICIPANT\n'
else
  v2_violation UNKNOWN_KIND "$V2_TOPIC: record kinds are not implemented yet"
fi

exit 0
