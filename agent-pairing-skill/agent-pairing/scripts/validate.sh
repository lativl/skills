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
# only against these copies, never against the record working tree.
v2_stage_committed() { # <topic> <path-in-tree>
  V2_STAGE_N=$((V2_STAGE_N + 1))
  v2_s_file="$V2_WORK/blob.$V2_STAGE_N"
  v2_git "$1" show "HEAD:$2" >"$v2_s_file" 2>/dev/null || return 1
  printf '%s\n' "$v2_s_file"
}

# Read one front-matter scalar from a staged file. The value is returned verbatim between the first
# colon-space and end of line, so a trailing space or a quoted "2" stays distinguishable from 2.
v2_fm_get() { # <staged-file> <key>
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit 0; inside = 1; next }
    inside && $0 == "---" { exit 0 }
    inside {
      pos = index($0, ":")
      if (pos == 0) next
      k = substr($0, 1, pos - 1)
      if (k != key) next
      v = substr($0, pos + 1)
      sub(/^[ \t]+/, "", v)
      print v
      exit 0
    }' "$1"
}

v2_list_records() { # <topic>
  # An absent turns/ path is an EMPTY record set, not an error: `ls-tree -r --name-only HEAD turns`
  # exits zero with no output when the path does not exist (verified on Apple Git 2.50.1). A
  # `cat-file -e … || return 0` guard would be worse than useless here — it cannot distinguish an
  # absent path from a genuine read failure, and would turn fail-closed I/O into an empty record set.
  v2_git "$1" ls-tree -r --name-only HEAD turns | LC_ALL=C sort
}

# --- the record repository ---------------------------------------------------------------------------
v2_git "$V2_TOPIC" rev-parse --git-dir >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC: not a Git record repository; v2 reads records only from committed objects"
v2_git "$V2_TOPIC" rev-parse --verify HEAD >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC: record repository has no commit at HEAD"

# --- the compatibility boundary ----------------------------------------------------------------------
# The declared version is read from the COMMITTED TOPIC.md, so a topic cannot be talked into v2 by an
# uncommitted edit.
V2_TOPIC_BLOB="$(v2_stage_committed "$V2_TOPIC" TOPIC.md)" \
  || v2_violation TOPIC_MISSING "$V2_TOPIC: HEAD:TOPIC.md is not readable"
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
  || v2_violation GIT_READ "$V2_TOPIC: cannot enumerate committed records under turns/"

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
