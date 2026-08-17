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
#   2  protocol violation; each exact violation code is on stderr
#   3  invalid CLI usage, or evidence that could not be read at all
#
# The 2/3 split is load-bearing. Exit 2 means "these records are wrong"; exit 3 means "this repository
# could not be read, so no claim about the records is available". Collapsing them would let a damaged
# repository be reported as a merely-invalid topic, or — worse — as a clean one.
#
# Record data is consumed ONLY from committed Git objects. The record working tree is never a source
# of truth: a participant that could act on an uncommitted receipt is exactly the v1 defect this
# protocol exists to remove, and a validator that read the working tree would bless it. The working
# tree is compared against the committed tree for ONE purpose — to report residue.
set -u

V2_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

v2_usage() {
  printf 'usage: validate.sh --check TOPIC_DIR\n       validate.sh --render TOPIC_DIR\n' >&2
  [ $# -gt 0 ] && printf 'error: %s\n' "$1" >&2
  exit 3
}

# A boundary violation is terminal on its own: with no trustworthy topic identity or protocol
# version there is nothing left to validate, and continuing would attribute record-level codes to a
# topic the validator has already refused to interpret.
v2_violation() { # <code> <subject> <detail>
  printf 'VIOLATION %s %s: %s\n' "$1" "$2" "$3" >&2
  exit 2
}

# --- CLI ---------------------------------------------------------------------------------------------
[ $# -eq 2 ] || v2_usage "expected exactly two arguments, got $#"
V2_MODE="$1"
V2_TOPIC="$2"
case "$V2_MODE" in
  --check|--render) ;;
  *) v2_usage "unknown mode: $V2_MODE" ;;
esac
[ -n "$V2_TOPIC" ] || v2_usage "empty TOPIC_DIR"
[ -d "$V2_TOPIC" ] || v2_usage "no such directory: $V2_TOPIC"

# --- staging area ------------------------------------------------------------------------------------
# Every committed blob is copied here before it is parsed. Allocation is checked BEFORE the path is
# used, because an unchecked allocation leaves an empty variable and the next redirection writes to a
# path nobody chose.
V2_WORK=""
v2_cleanup() {
  [ -n "$V2_WORK" ] || return 0
  case "$V2_WORK" in /tmp/agent-pairing-v2.?*) rm -rf "$V2_WORK" ;; esac
}
trap v2_cleanup EXIT
V2_WORK="$(mktemp -d /tmp/agent-pairing-v2.XXXXXX)" \
  || { printf 'FATAL temp allocation failed\n' >&2; exit 3; }
[ -n "$V2_WORK" ] && [ -d "$V2_WORK" ] \
  || { printf 'FATAL temp allocation produced no directory\n' >&2; exit 3; }

. "$V2_SELF_DIR/lib/v2-record.sh" || { printf 'FATAL cannot load lib/v2-record.sh\n' >&2; exit 3; }
. "$V2_SELF_DIR/lib/v2-schema.sh" || { printf 'FATAL cannot load lib/v2-schema.sh\n' >&2; exit 3; }

# --- the record repository -----------------------------------------------------------------------------
v2_git "$V2_TOPIC" rev-parse --git-dir >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC" "not a Git record repository; v2 reads records only from committed objects"
v2_git "$V2_TOPIC" rev-parse --verify HEAD >/dev/null 2>&1 \
  || v2_violation RECORD_REPO "$V2_TOPIC" "record repository has no commit at HEAD"

# --- the compatibility boundary --------------------------------------------------------------------------
# The declared version is read from the COMMITTED TOPIC.md, so a topic cannot be talked into v2 by an
# uncommitted edit. An ABSENT TOPIC.md and an UNREADABLE one are different facts: the path is
# resolved first (absent => violation), then the object is read (unreadable => fatal).
v2_git "$V2_TOPIC" rev-parse --verify --quiet "HEAD:TOPIC.md" >/dev/null 2>&1 \
  || v2_violation TOPIC_MISSING "$V2_TOPIC" "HEAD:TOPIC.md does not exist in the committed tree"
V2_TOPIC_BLOB="$(v2_stage_committed "$V2_TOPIC" TOPIC.md)" \
  || v2_fatal "$V2_TOPIC: HEAD:TOPIC.md names an object that cannot be read: $(v2_git_err)"
v2_fm_structure "$V2_TOPIC_BLOB" \
  || v2_violation TOPIC_FM_MALFORMED "$V2_TOPIC" "TOPIC.md front matter is malformed: $V2_FM_ERR"

V2_TOPIC_VERSION="$(v2_fm_get "$V2_TOPIC_BLOB" protocol_version)"
case "$V2_TOPIC_VERSION" in
  2) ;;
  '') v2_violation PROTOCOL_VERSION "$V2_TOPIC" "TOPIC.md declares no protocol_version; the default validator accepts only 2" ;;
  *)  v2_violation PROTOCOL_VERSION "$V2_TOPIC" "TOPIC.md declares protocol_version '$V2_TOPIC_VERSION'; the default validator accepts only the exact scalar 2 (scripts/validate-v1.sh reads historical records)" ;;
esac

# Topic identity is established ONCE, from TOPIC.md, and every record is checked against it. There is
# deliberately no "first record wins" fallback: if identity could be derived from a record, then
# "is this record ours?" would depend on which record you asked.
V2_TOPIC_ID="$(v2_fm_get "$V2_TOPIC_BLOB" topic_id)"
[ -n "$V2_TOPIC_ID" ] || v2_violation TOPIC_ID "$V2_TOPIC" "TOPIC.md declares no topic_id"

# --- residue -------------------------------------------------------------------------------------------
# Reported BEFORE any classification. Record bytes that exist only in the working tree are not
# records, but they are evidence of an interrupted write, and a topic carrying them has no
# trustworthy state to report.
v2_check_uncommitted_residue "$V2_TOPIC"

# --- records --------------------------------------------------------------------------------------------
V2_RECORDS="$(v2_list_records "$V2_TOPIC")" \
  || v2_fatal "$V2_TOPIC: cannot enumerate committed records under turns/: $(v2_git_err)"

# One line per record: `record_seq kind basename staged-path`. A file, not a shell string, because
# every later stage reads it with `while read < file` — a pipe would run the loop in a subshell and
# discard the accounting it does.
V2_TSV="$V2_WORK/records.tsv"
: >"$V2_TSV" || v2_fatal "cannot create the record index"

V2_SAVED_IFS="$IFS"
IFS='
'
for v2_path in $V2_RECORDS; do
  IFS="$V2_SAVED_IFS"
  v2_name="${v2_path#turns/}"
  # The record tree is FLAT and every record is a `.md` file. A nested or oddly-named committed path
  # is not silently skipped: a path the validator declines to interpret is a record whose effect on
  # state is unknown, which is the same hazard as an unknown kind.
  case "$v2_name" in
    */*)   v2_fail RECORD_PATH "$v2_path" "records live directly under turns/, not in a subdirectory"; IFS='
'; continue ;;
    *.md)  ;;
    *)     v2_fail RECORD_PATH "$v2_path" "record files are named SSSS-....md"; IFS='
'; continue ;;
  esac

  v2_staged="$(v2_stage_committed "$V2_TOPIC" "$v2_path")" \
    || v2_fatal "$V2_TOPIC: $v2_path names an object that cannot be read: $(v2_git_err)"

  if ! v2_fm_structure "$v2_staged"; then
    v2_fail FM_MALFORMED "$v2_name" "$V2_FM_ERR"
    IFS='
'; continue
  fi
  if ! v2_require_common "$v2_staged" "$v2_name"; then
    IFS='
'; continue
  fi

  v2_kind="$(v2_fm_get "$v2_staged" kind)"
  if v2_in_list "$v2_kind" "$V2_ATTEMPT_KINDS"; then
    v2_require_attempt_tuple "$v2_staged" "$v2_name" || { IFS='
'; continue; }
  fi
  v2_require_filename "$v2_staged" "$v2_name" || { IFS='
'; continue; }
  v2_validate_kind "$v2_staged" "$v2_name"

  printf '%s %s %s %s\n' "$(v2_fm_get "$v2_staged" record_seq)" "$v2_kind" "$v2_name" "$v2_staged" >>"$V2_TSV"
  IFS='
'
done
IFS="$V2_SAVED_IFS"

# --- ordering ---------------------------------------------------------------------------------------------
# `record_seq` is the ordering authority. It is strictly increasing AND contiguous from 0001: a gap
# is indistinguishable from a record that was written and then lost, and an append-only log that
# cannot tell those apart cannot claim to be replayable.
V2_SORTED="$V2_WORK/records.sorted"
LC_ALL=C sort "$V2_TSV" >"$V2_SORTED" || v2_fatal "cannot order the record index"

# Contiguity is derived from the COMMITTED FILENAMES, not from the records that survived front-matter
# validation. Deriving it from survivors would make every schema defect also report a phantom gap:
# one mutation, two codes, and the second one blaming a record that is not wrong. The filename prefix
# exists whatever the front matter says, and a prefix that disagrees with `record_seq` is
# SEQ_FILENAME_MISMATCH's own violation.
V2_PREFIXES="$V2_WORK/prefixes"
awk '{ n = $0; sub(/^turns\//, "", n); sub(/-.*/, "", n); print n }' "$V2_WORK/records.list" \
  | LC_ALL=C sort >"$V2_PREFIXES" || v2_fatal "cannot order the record filenames"

v2_prev_seq=""
v2_expect_seq=1
while read -r v2_seq; do
  [ -n "${v2_seq:-}" ] || continue
  case "$v2_seq" in [0-9][0-9][0-9][0-9]) ;; *) continue ;; esac   # RECORD_PATH/RECORD_SEQ own this
  if [ "$v2_seq" = "$v2_prev_seq" ]; then
    v2_fail SEQ_DUP "turns/" "record_seq $v2_seq is used by more than one record"
  else
    v2_want="$(printf '%04d' "$v2_expect_seq")"
    [ "$v2_seq" = "$v2_want" ] || v2_fail SEQ_GAP "turns/" "expected record_seq $v2_want, found $v2_seq"
    v2_expect_seq=$((v2_expect_seq + 1))
  fi
  v2_prev_seq="$v2_seq"
done <"$V2_PREFIXES"

# Epochs are non-decreasing but MAY be equal: two records committed in the same second are ordinary,
# and `record_seq` breaks the tie. Only a DECREASE is a defect — it would let stored arithmetic
# describe a history that ran backwards. Read over validated records only, since an unvalidated
# record has no epoch worth comparing.
v2_prev_epoch=""
v2_prev_name=""
while read -r v2_seq v2_kind v2_name v2_staged; do
  [ -n "${v2_seq:-}" ] || continue
  v2_epoch="$(v2_fm_get "$v2_staged" recorded_epoch)"
  if [ -n "$v2_prev_epoch" ] && [ "$v2_epoch" -lt "$v2_prev_epoch" ]; then
    v2_fail EPOCH_ORDER "$v2_name" "recorded_epoch $v2_epoch precedes $v2_prev_epoch on $v2_prev_name"
  fi
  v2_prev_epoch="$v2_epoch"
  v2_prev_name="$v2_name"
done <"$V2_SORTED"

[ "$V2_VIOLATIONS" -eq 0 ] || exit 2

# --- classification -------------------------------------------------------------------------------------------
# Tasks 3-8 replace this with the full replay precedence. Until then only the no-attempt branch is
# pinned: a topic with no admission has no participant, and one with an admission and nothing else is
# idle.
V2_ADMISSION_COUNT="$(awk '$2 == "admission"' "$V2_SORTED" | grep -c . || true)"
V2_RECORD_COUNT="$(grep -c . "$V2_SORTED" || true)"

if [ "$V2_ADMISSION_COUNT" -eq 0 ]; then
  printf 'classification: AWAITING_PARTICIPANT\n'
elif [ "$V2_RECORD_COUNT" -eq "$V2_ADMISSION_COUNT" ]; then
  printf 'classification: IDLE\n'
else
  printf 'classification: WORKING\n'
fi

exit 0
