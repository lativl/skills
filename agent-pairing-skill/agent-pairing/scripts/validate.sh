#!/bin/bash
# agent-pairing validator. bash 3.2 compatible. Spec: rev.6 (4b3f8e3) §3.2, §3.8, §6, §7.
# D1: state lives in shell variables — no mktemp. D2: no `| while`. D8: literal enum compare.
set -u
MODE="${1:-}"; TOPIC="${2:-}"
usage() { echo "usage: validate.sh --check|--render <topic-dir>" >&2; exit 3; }
[ -n "$MODE" ] && [ -n "$TOPIC" ] || usage
[ "$MODE" = "--check" ] || [ "$MODE" = "--render" ] || usage
case "$TOPIC" in *[[:space:]]*) echo "VIOLATION USAGE $TOPIC: path must not contain whitespace" >&2; exit 3;; esac
TURNS="$TOPIC/turns"
[ -d "$TURNS" ] || { echo "VIOLATION NO_TURNS $TOPIC: no turns/ directory" >&2; exit 2; }

VIOLATIONS=0
fail() { VIOLATIONS=$((VIOLATIONS+1)); echo "VIOLATION $1 $2: $3" >&2; }

fm_get() { awk -v k="$2" '/^---$/{c++; next}
  c==1 && index($0, k": ")==1 {sub("^"k": ",""); print; exit} c>=2{exit}' "$1"; }

# D33 — structural pass, run BEFORE any key is read. Same block definition as fm_get: line 1 is
# `---`, the block ends at the first subsequent `---`, the body is not inspected (so a body
# horizontal rule stays legal — see D33 for why that narrowing is deliberate).
FM_ERR=""
fm_structure() { # <file>; sets FM_ERR and returns 1 when the block is malformed
  FM_ERR="$(awk '
    NR==1 { if ($0 != "---") { print "front matter does not open with --- on line 1"; bad=1; exit }
            next }
    done_fm == 1 { next }
    $0 == "---" { done_fm=1; next }
    {
      if ($0 !~ /^[A-Za-z_][A-Za-z0-9_]*:( |$)/) {
        print "line " NR " is not a flat key: value pair: " $0; bad=1; exit }
      k=$0; sub(/:.*/, "", k)
      if (k in seen) { print "duplicate front-matter key: " k; bad=1; exit }
      seen[k]=1
    }
    END { if (bad != 1 && done_fm != 1) print "front matter block is never closed by ---" }
  ' "$1")"
  [ -z "$FM_ERR" ]; }

# D15 — every git read goes through this wrapper: `git -C`, replace-objects off, no index locks.
# GIT_OPTIONAL_LOCKS=0 is what actually keeps --check read-only against the WORK repo: a plain
# `git status --porcelain` may refresh and rewrite .git/index, which no snapshot test would catch.
g() { GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 git -C "$@"; }
repo_root() { case "$1" in */.git) dirname "$1";; *) echo "$1";; esac; }   # close-time reads

seq_of()  { b="$(basename "$1")"; echo "${b%%-*}"; }
is_sha()  { case "$1" in *[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 40 ]; }
# S1 (acceptance round 2, schema gap) + codex round 3 finding C — §3.2 requires ISO-8601
# timestamps; a portable `case` glob, bash 3.2, no GNU `date -d`. rev.1 matched only the one form
# every template and fixture in this skill happens to use (`YYYY-MM-DDTHH:MM:SSZ`) and did no range
# check at all, so it REJECTED legitimate ISO-8601 a real caller can send — a numeric UTC offset
# (`+02:00`) or fractional seconds (`.123Z`) — while ACCEPTING an impossible, merely well-shaped
# value like `2026-99-99T99:99:99Z`. Widened to the forms this protocol will actually see (`Z`,
# `+HH:MM`/`-HH:MM`, optional `.`-fraction before either), plus range plausibility on the fixed-
# width fields (month 01-12, day 01-31, hour 00-23, minute/second 00-59). Still a syntax+range
# check, not a calendar check (2026-02-30 or 2026-04-31 still pass, and the offset's own HH:MM is
# unchecked) — consistent with `is_sha`'s own scope just above (format, not full semantic
# validity).
is_iso8601() {
  v="$1"
  case "$v" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*Z) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9]) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*[+-][0-9][0-9]:[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  mo="${v:5:2}"; da="${v:8:2}"; hh="${v:11:2}"; mi="${v:14:2}"; se="${v:17:2}"
  [ "$((10#$mo))" -ge 1 ] && [ "$((10#$mo))" -le 12 ] || return 1
  [ "$((10#$da))" -ge 1 ] && [ "$((10#$da))" -le 31 ] || return 1
  [ "$((10#$hh))" -ge 0 ] && [ "$((10#$hh))" -le 23 ] || return 1
  [ "$((10#$mi))" -ge 0 ] && [ "$((10#$mi))" -le 59 ] || return 1
  [ "$((10#$se))" -ge 0 ] && [ "$((10#$se))" -le 59 ] || return 1
}
canon() { # directory path, possibly with a missing suffix (D7)
  raw="$1"; probe="$1"; suffix=""
  while [ ! -d "$probe" ] && [ "$probe" != "/" ]; do
    suffix="/$(basename "$probe")$suffix"
    parent="$(dirname "$probe")"
    [ "$parent" != "$probe" ] || break
    probe="$parent"
  done
  [ -d "$probe" ] || { echo "$raw"; return; }
  resolved="$(cd "$probe" 2>/dev/null && pwd -P)" || { echo "$raw"; return; }
  printf '%s%s\n' "$resolved" "$suffix"
}
in_list() { v="$1"; for w in $2; do [ "$w" = "$v" ] && return 0; done; return 1; }   # D8

STATUSES="VERIFIED REJECTED SUPERSEDED ABORTED"
# REASONS is the UNION — the schema stage only asks "is this a reason at all". Which reasons are
# legal for which status is D31's matrix, enforced in Task 3. Rev.5's comment here claimed
# `never-dispatched` was "deliberately NOT" in this list while it sat in the very next token: a
# global claim contradicted by the line it annotated. The claim is now true because the list it
# describes actually exists (ABORTED_REASONS), rather than being asserted about this one.
REASONS="verification-failed review-failed no-op-result out-of-scope-changes patch-apply-failed agent-declined-with-question residue-after-termination replaced-by-retry collision never-dispatched dispatch-confirmed-absent terminated-before-result transport-lossy other"
# D31 — §3.2's terminal-status table, one list per status, each member traceable to a spec line:
#   ABORTED    §3.2 (dispatch-confirmed-absent, terminated-before-result), §3.6 (transport-lossy),
#              §6.3.3 (never-dispatched), plus `other`.
#   SUPERSEDED §3.2 "open attempt made obsolete by replacement or collision".
#   REJECTED   §3.4/§3.6/§4 — everything that failed a gate or left residue.
ABORTED_REASONS="never-dispatched dispatch-confirmed-absent terminated-before-result transport-lossy other"
SUPERSEDED_REASONS="replaced-by-retry collision other"
REJECTED_REASONS="verification-failed review-failed no-op-result out-of-scope-changes patch-apply-failed agent-declined-with-question residue-after-termination other"
# D31 — a DENY list, not an allow list. `result_sha: null` is legal for a REJECTED result unless the
# reason itself implies a landed commit (a no-op names base_sha; out-of-scope names a diff). The
# rev.5 allow list would have rejected §3.2's own example — "a NORMAL result with no reported SHA
# while the tip moved is REJECTED" — which is REJECTED + verification-failed + null.
COMMIT_BEARING_REASONS="no-op-result out-of-scope-changes"
# D37: the deny list's missing half. §3.2 reserves `null` for "no-commit failure results (ABORTED,
# declined)", so a REJECTED result whose reason means nothing landed may not NAME a commit either.
# D31 forbade null for commit-bearing reasons and stopped there, which left
# `REJECTED + agent-declined-with-question + <sha>` — a record claiming a commit after a decline —
# validating. `residue-after-termination` is deliberately absent: §4 step 3 records it for
# UNCOMMITTED residue, and the reason can accompany a landed zombie commit.
SHA_FORBIDDEN_REASONS="patch-apply-failed agent-declined-with-question"
# --- Reason-class closure (three review rounds each found one more hole of the SAME shape:
# never-dispatched, then dispatch-confirmed-absent, then the ones below — each patched alone). The
# reviewer's rule, encoded as a rule rather than as arms: every reason whose text implies the job
# EXECUTED requires a dispatch receipt on file for that attempt. §3.2 orders `intent` strictly
# before `dispatch`, and its fail-closed commit rule means every real dispatch leaves a committed
# receipt — so a receiptless attempt disproves any reason claiming a post-dispatch outcome. These
# are explicit lists, D31's own style, so a future addition to REASONS forces a membership decision
# here instead of silently opening a fourth hole.
# `transport-lossy` — §3.6 defines it as an integrity failure of a RELAYED result: impossible
# without something having been relayed, i.e. dispatched.
# `verification-failed`, `review-failed`, `no-op-result`, `patch-apply-failed`,
# `agent-declined-with-question` — each describes a delivered job's OUTPUT, impossible pre-dispatch.
DISPATCH_REQUIRED_REASONS="transport-lossy verification-failed review-failed no-op-result patch-apply-failed agent-declined-with-question"
# `residue-after-termination`, `out-of-scope-changes` — §3.2's worktree-gate-failure path
# legitimately produces a RECEIPTLESS REJECTED for these two, but only when the owner is the one
# who observed the residue/diff standing in for a receipt — i.e. a resolvable owner_answer_ref.
DISPATCH_OR_OWNER_ANSWER_REASONS="residue-after-termination out-of-scope-changes"
# `never-dispatched` and `dispatch-confirmed-absent` already carry their own INVERTED guards
# (REASON_CONTRADICTED, in the result loop below) — not disturbed here. `other` (free text, no
# shape claim) and the SUPERSEDED reasons `replaced-by-retry`/`collision` (claims about
# parallel/future records, not disprovable from this record set) are deliberately NOT constrained.
SOURCES="direct validated-uncommitted token-search owner-answer"
GENERAL_ACTIONS="authorize-remediation authorize-cleanup authorize-close cancel-close record-decision other"
DISPATCH_ACTIONS="dispatch-job-found dispatch-confirmed-absent dispatch-termination-confirmed dispatch-unresolved"
ACTIONABLE_DISPATCH="dispatch-job-found dispatch-confirmed-absent dispatch-termination-confirmed"
TKINDS="NORMAL REVIEW REMEDIATION"
KINDS="assignment intent dispatch result late owner-question owner-answer close"
ATTEMPT_LINKED="intent dispatch result late"

ALL=""; ATTEMPTS=""
require() { f="$1"; shift; for k in "$@"; do [ -n "$(fm_get "$f" "$k")" ] || fail MISSING_KEY "$f" "missing $k"; done; }
files_of_kind() { echo "$ALL" | awk -v k="$1" '$2==k{print $3}'; }
attempt_count() { echo "$ATTEMPTS" | awk -v t="$1" -v a="$2" -v k="$3" '$1==t&&$2==a&&$3==k' | grep -c .; }

# §3.0 step 3 / §2.1 — TOPIC.md is written and committed at OPEN, before any record exists, and
# pins base_sha plus the explicit base ref. It is therefore the accepted_sha seed (§6 step 2) and
# the identity source for §3.4 check 2; the first assignment is validated AGAINST it (Task 3),
# never used as the seed. base_ref is presence-checked only — see D33. Each key produces at most
# ONE code: an absent base_sha reports the missing key and is not then shape-checked or
# cross-checked, because three codes for one deletion is how a case starts passing for a
# neighbour's reason.
TOPICMD="$TOPIC/TOPIC.md"
# TOPIC_FM_OK gates EVERY later `fm_get "$TOPICMD" …` (the base cross-check, `accepted_sha_upto`'s
# seed, `TOPIC_ID`, and the TOPIC_MISMATCH loop). Without it, D33's headline — "front matter is
# validated STRUCTURALLY before any key is read" — was false for TOPIC.md specifically: those four
# readers were guarded only by `[ -f ]`, so a truncated or preamble-prefixed TOPIC.md was still
# mined for whatever `fm_get` happened to recover, and a second code could fire off a recovered
# value. The run has already exited 2 by then, so this is a false self-claim rather than a
# fail-open — but the claim is the thing D33 is for, and each reader degrades safely on empty.
TOPIC_FM_OK=no
if [ ! -f "$TOPICMD" ]; then
  fail TOPIC_MISSING "$TOPIC" "no TOPIC.md — §3.0 step 3 writes it before any record"
elif ! fm_structure "$TOPICMD"; then
  fail FM_MALFORMED "$TOPICMD" "$FM_ERR"
else
  TOPIC_FM_OK=yes
  for k in topic_id base_sha base_ref session_branch session_worktree work_repo_common_dir; do
    [ -n "$(fm_get "$TOPICMD" "$k")" ] || fail TOPIC_MISSING_KEY "$TOPICMD" "missing $k"
  done
  tbs="$(fm_get "$TOPICMD" base_sha)"
  [ -z "$tbs" ] || is_sha "$tbs" || fail BAD_SHA "$TOPICMD" "base_sha"
fi

for f in "$TURNS"/*.md; do
  # An empty turns/ is a freshly opened topic (§3.0), not corruption. NO_TURNS is reserved for a
  # MISSING turns/ directory, checked above.
  [ -e "$f" ] || break
  fm_structure "$f" || { fail FM_MALFORMED "$f" "$FM_ERR"; continue; }   # D33, before any fm_get
  seqfm="$(fm_get "$f" record_seq)"; kind="$(fm_get "$f" kind)"
  [ -n "$seqfm" ] && [ -n "$kind" ] || { fail FM_UNPARSEABLE "$f" "no record_seq/kind front matter"; continue; }
  [ "$(seq_of "$f")" = "$seqfm" ] || fail SEQ_FILENAME_MISMATCH "$f" "prefix $(seq_of "$f") != record_seq $seqfm"
  case "$seqfm" in [0-9][0-9][0-9][0-9]) ;; *) fail WIDTH "$f" "record_seq width";; esac
  in_list "$kind" "$KINDS" || { fail BAD_KIND "$f" "kind=$kind"; continue; }
  ALL="$ALL$seqfm $kind $f
"
  require "$f" topic_id recorded_at
  # S1 — §3.2's common `recorded_at` key. Every kind gets it (the assignment/dispatch/result
  # deadline/dispatched_at/observed_at checks below are the kind-specific siblings of this one).
  is_iso8601 "$(fm_get "$f" recorded_at)" || fail BAD_TIMESTAMP "$f" "recorded_at"
  if in_list "$kind" "$ATTEMPT_LINKED" || [ "$kind" = "assignment" ]; then
    require "$f" turn_id attempt_id turn_kind
    tk="$(fm_get "$f" turn_kind)"; in_list "$tk" "$TKINDS" || fail BAD_TURN_KIND "$f" "turn_kind=$tk"
    t="$(fm_get "$f" turn_id)"; a="$(fm_get "$f" attempt_id)"
    case "$t" in [0-9][0-9][0-9][0-9]) ;; *) fail WIDTH "$f" "turn_id width";; esac
    case "$a" in [0-9][0-9]) ;; *) fail WIDTH "$f" "attempt_id width";; esac
    ATTEMPTS="$ATTEMPTS$t $a $kind $f
"
  fi
  late_tail_bad=no   # NIT: set below when the late-index WIDTH check fires, so FILENAME_SHAPE can
                      # suppress its own fire for the SAME defect (one-defect-one-code, S2's own rule)
  case "$kind" in
    assignment)
      require "$f" base_sha session_branch session_worktree work_repo_common_dir scope deadline agent_id
      is_sha "$(fm_get "$f" base_sha)" || fail BAD_SHA "$f" "base_sha"
      is_iso8601 "$(fm_get "$f" deadline)" || fail BAD_TIMESTAMP "$f" "deadline" ;;                  # S1
    intent) require "$f" assignment_ref idempotency_token ;;
    dispatch)
      require "$f" assignment_ref transport job_id dispatched_at intent_ref receipt_source
      src="$(fm_get "$f" receipt_source)"; in_list "$src" "$SOURCES" || fail BAD_RECEIPT_SOURCE "$f" "receipt_source=$src"
      if [ "$src" = "owner-answer" ] && [ -z "$(fm_get "$f" owner_answer_ref)" ]; then
        fail MISSING_KEY "$f" "owner_answer_ref required for receipt_source=owner-answer"; fi
      is_iso8601 "$(fm_get "$f" dispatched_at)" || fail BAD_TIMESTAMP "$f" "dispatched_at" ;;         # S1
    result)
      # result_sha is a REQUIRED key (fable P1-C): absent is MISSING_KEY, never treated as null.
      require "$f" assignment_ref status observed_at result_sha
      is_iso8601 "$(fm_get "$f" observed_at)" || fail BAD_TIMESTAMP "$f" "observed_at"                # S1
      st="$(fm_get "$f" status)"; in_list "$st" "$STATUSES" || fail BAD_STATUS "$f" "status=$st"
      if [ "$st" != "VERIFIED" ]; then
        rs="$(fm_get "$f" reason)"; in_list "$rs" "$REASONS" || fail BAD_REASON "$f" "reason=$rs"; fi
      sha="$(fm_get "$f" result_sha)"
      if [ -n "$sha" ] && [ "$sha" != "null" ]; then is_sha "$sha" || fail BAD_SHA "$f" "result_sha=$sha"; fi ;;
    late)
      require "$f" assignment_ref named_sha
      ns="$(fm_get "$f" named_sha)"                       # value-checked, not merely present
      if [ -n "$ns" ] && [ "$ns" != "null" ]; then is_sha "$ns" || fail BAD_SHA "$f" "named_sha=$ns"; fi
      case "$(basename "$f")" in
        *-late-[0-9][0-9].md) ;;
        *) fail WIDTH "$f" "late index (expect -late-KK.md)"; late_tail_bad=yes ;;
      esac ;;
    owner-question)
      require "$f" question_id blocks
      # M-1 — `blocks` has three legal shapes: tTTTT-aAA, CLOSING:<id>, or free-form general text.
      # Nothing checked the SHAPE, so a typo like `t001-a1` (wrong width) silently fell through to
      # `ctx=other` downstream — legalizing a GENERAL answer where a DISPATCH answer was intended.
      # Only fail on text that LOOKS LIKE a malformed attempt reference (starts `t<digit>`); a
      # free-form general value is never required to avoid that prefix, so nothing else is touched.
      bl="$(fm_get "$f" blocks)"
      case "$bl" in
        t[0-9][0-9][0-9][0-9]-a[0-9][0-9]) ;;                # legal attempt form
        CLOSING:*) ;;                                        # legal close form
        t[0-9]*) fail BLOCKS_SHAPE "$f" "blocks=$bl looks like a malformed attempt reference" ;;
        *) ;;                                                # free-form general value — legal
      esac ;;
    owner-answer)   require "$f" question_ref action ;;   # enum + context checked in Task 3
    close)
      require "$f" close_id final_accepted_sha
      is_sha "$(fm_get "$f" final_accepted_sha)" || fail BAD_SHA "$f" "final_accepted_sha" ;;
  esac
  # S2 (acceptance round 2, schema gap) — §3.2's filename grammar was only partly enforced
  # (SEQ_FILENAME_MISMATCH covers the leading SSSS; the late-index check above covers only the
  # trailing -KK). Validate the WHOLE basename against its kind and front-matter tuple:
  # SSSS-tTTTT-aAA-<kind>[-KK].md for attempt-linked kinds (assignment included), SSSS-<kind>.md
  # for owner/close records. Exact filenames are durable cross-references (assignment_ref,
  # question_ref, intent_ref, …), so a misleading name that still validates is a real hazard.
  # Built from the FILE'S OWN seq prefix (`seq_of`), never the front-matter `record_seq`: a seq
  # mismatch is SEQ_FILENAME_MISMATCH's own violation, reported above — this check owns only the
  # kind/turn/attempt/late-suffix shape, so one filename defect reports one code.
  pfx="$(seq_of "$f")"
  if in_list "$kind" "$ATTEMPT_LINKED" || [ "$kind" = "assignment" ]; then
    # Only compared once turn_id/attempt_id are individually well-formed: a malformed WIDTH is
    # that check's own single code, reported above — this rule owns the filename/front-matter
    # AGREEMENT, not the front-matter shape itself, so the two do not double-report one defect.
    case "$t" in [0-9][0-9][0-9][0-9]) tid_ok=yes ;; *) tid_ok=no ;; esac
    case "$a" in [0-9][0-9]) aid_ok=yes ;; *) aid_ok=no ;; esac
    if [ "$tid_ok" = yes ] && [ "$aid_ok" = yes ]; then
      case "$kind" in
        late) want="${pfx}-t${t}-a${a}-late-[0-9][0-9].md"; want_msg="${pfx}-t${t}-a${a}-late-KK.md" ;;
        *)    want="${pfx}-t${t}-a${a}-${kind}.md"; want_msg="$want" ;;
      esac
      case "$(basename "$f")" in
        $want) ;;
        *)
          # NIT: a bad late tail is already WIDTH's own code (set above) — don't also fire
          # FILENAME_SHAPE for the identical defect. Any OTHER mismatch on a late record (wrong
          # turn/attempt/kind segment) still reaches here and fires normally.
          if [ "$kind" = late ] && [ "$late_tail_bad" = yes ]; then :
          else fail FILENAME_SHAPE "$f" "basename does not match $want_msg"; fi ;;
      esac
    fi
  else
    want="${pfx}-${kind}.md"
    [ "$(basename "$f")" = "$want" ] || fail FILENAME_SHAPE "$f" "basename does not match $want"
  fi
done

# §3.0 step 3 pins the base BEFORE any assignment exists, so the seed cannot be validated by the
# thing it seeds: the FIRST assignment is validated against TOPIC.md, never the other way round.
# This lives in Task 1 — not Task 3 — because the suite is cumulative and Task 1's own `BAD_SHA`
# cases mutate a `base_sha`, which necessarily also breaks this agreement; an assertion naming a
# code its own task does not yet produce would fail at Task 1 and pass at Task 3.
# Guarded on both values: an ABSENT base_sha is already TOPIC_MISSING_KEY and is not re-reported.
# `first_assign_rec` is the SUBJECT of this cross-check and nothing else — no identity or base value
# is ever derived from an assignment (D32). TOPIC_FM_OK (D33) gates the read: a malformed block is
# not mined for a base_sha that then produces a second, misleading code.
first_assign_rec="$(files_of_kind assignment | head -1)"
topic_base="$( [ "$TOPIC_FM_OK" = yes ] && fm_get "$TOPICMD" base_sha )"
if [ -n "$first_assign_rec" ] && [ -n "$topic_base" ] \
   && [ "$(fm_get "$first_assign_rec" base_sha)" != "$topic_base" ]; then
  fail TOPIC_BASE_MISMATCH "$first_assign_rec" "first assignment base_sha != TOPIC.md base_sha"; fi

# (Task 2 inserts sequence/linkage; Task 3 conditional values; Tasks 4-5 classification.)
SORTED="$(echo "$ALL" | grep . | sort)"

for dup in $(echo "$SORTED" | awk '{print $1}' | uniq -d); do
  fail SEQ_DUP "$TURNS" "record_seq $dup duplicated"; done
expected=1
for s in $(echo "$SORTED" | awk '{print $1}' | sort -u); do
  want=$(printf '%04d' "$expected")
  [ "$s" = "$want" ] || fail SEQ_GAP "$TURNS" "expected $want, found $s"
  expected=$((expected+1)); done

resolve() { # <ref> <expected-kind> -> path or empty
  [ -n "$1" ] && [ -e "$TURNS/$1" ] && [ "$(fm_get "$TURNS/$1" kind)" = "$2" ] && echo "$TURNS/$1"; }

while read -r seq kind f; do
  [ -n "${seq:-}" ] || continue
  case "$kind" in
    intent|dispatch|result|late)
      aref="$(fm_get "$f" assignment_ref)"; ap="$(resolve "$aref" assignment)"
      if [ -z "$ap" ]; then fail LINK_DANGLING "$f" "assignment_ref $aref"; else
        for k in topic_id turn_id attempt_id turn_kind; do
          [ "$(fm_get "$f" "$k")" = "$(fm_get "$ap" "$k")" ] || fail LINK_TUPLE_MISMATCH "$f" "$k differs from $aref"
        done
        [ "$seq" \> "$(fm_get "$ap" record_seq)" ] || fail LINK_ORDER "$f" "record precedes its assignment"
      fi ;;
  esac
  case "$kind" in
    dispatch)
      iref="$(fm_get "$f" intent_ref)"; ip="$(resolve "$iref" intent)"
      if [ -z "$ip" ]; then fail LINK_DANGLING "$f" "intent_ref $iref"; else
        for k in turn_id attempt_id assignment_ref; do
          [ "$(fm_get "$f" "$k")" = "$(fm_get "$ip" "$k")" ] || fail LINK_TUPLE_MISMATCH "$f" "$k differs from $iref"
        done
        [ "$seq" \> "$(fm_get "$ip" record_seq)" ] || fail LINK_ORDER "$f" "receipt precedes its intent"
      fi ;;
    result)
      dseq="$(echo "$ATTEMPTS" | awk -v t="$(fm_get "$f" turn_id)" -v a="$(fm_get "$f" attempt_id)" \
              '$1==t&&$2==a&&$3=="dispatch"{print $4}')"
      [ -n "$dseq" ] && { [ "$seq" \> "$(fm_get "$dseq" record_seq)" ] || fail LINK_ORDER "$f" "result precedes its receipt"; } ;;
    owner-answer)
      q="$(fm_get "$f" question_ref)"; found=no
      for qf in $(files_of_kind owner-question); do [ "$(fm_get "$qf" question_id)" = "$q" ] && found=yes; done
      [ "$found" = yes ] || fail ANSWER_DANGLING "$f" "question_ref $q resolves to no question" ;;
  esac
  oar="$(fm_get "$f" owner_answer_ref)"
  [ -n "$oar" ] && [ -z "$(resolve "$oar" owner-answer)" ] && fail LINK_DANGLING "$f" "owner_answer_ref $oar"
done <<< "$SORTED"

for tok in $(for i in $(files_of_kind intent); do fm_get "$i" idempotency_token; done | sort | uniq -d); do
  fail TOKEN_DUP "$TURNS" "idempotency_token $tok reused"; done

for qf in $(files_of_kind owner-question); do
  qid="$(fm_get "$qf" question_id)"; n=0
  for af in $(files_of_kind owner-answer); do [ "$(fm_get "$af" question_ref)" = "$qid" ] && n=$((n+1)); done
  [ "$n" -le 1 ] || fail ANSWER_DUP "$qf" "question $qid has $n answers"; done

for k in assignment intent dispatch result; do
  for ta in $(echo "$ATTEMPTS" | grep . | awk -v k="$k" '$3==k{print $1"-"$2}' | sort | uniq -d); do
    fail MULTI_PER_ATTEMPT "$TURNS" "more than one $k for attempt $ta"; done; done

for ta in $(echo "$ATTEMPTS" | grep . | awk '$3=="late"{print $1"-"$2}' | sort -u); do
  t="${ta%-*}"; a="${ta#*-}"; prev=0
  for lf in $(echo "$ATTEMPTS" | grep . | awk -v t="$t" -v a="$a" '$1==t&&$2==a&&$3=="late"{print $4}' | sort); do
    # Found while writing the WIDTH/FILENAME_SHAPE NIT test: a malformed late-tail filename (e.g.
    # `-late-1.md`) reaches here regardless of the earlier per-file WIDTH check (that check does not
    # `continue`). The sed below then fails to match and passes the WHOLE basename through
    # unchanged, which `$((10#$kk))` evaluates as an arithmetic expression — under `set -u` an
    # unset-variable reference (e.g. `t0001`) inside that string crashes the entire run instead of
    # reporting a clean violation. The malformed tail is already WIDTH's own code (reported in the
    # per-file loop); skip it here rather than re-derive or crash on it.
    case "$(basename "$lf")" in
      *-late-[0-9][0-9].md) ;;
      *) continue ;;
    esac
    kk="$(basename "$lf" | sed -E 's/.*-late-([0-9][0-9])\.md$/\1/')"
    [ "$((10#$kk))" -gt "$prev" ] || fail LATE_NONMONOTONIC "$lf" "late index $kk not > $prev"
    prev="$((10#$kk))"; done; done

newest_assign="$(echo "$SORTED" | awk '$2=="assignment"{print $3}' | tail -1)"
for a in $(files_of_kind assignment); do
  if [ "$(attempt_count "$(fm_get "$a" turn_id)" "$(fm_get "$a" attempt_id)" result)" -eq 0 ] \
     && [ "$a" != "$newest_assign" ]; then
    fail OPEN_NOT_NEWEST "$a" "open assignment is not the newest assignment record"; fi; done

# --- Task 3: conditional-value rules and the full close-lifecycle ordering ---
question_of_answer() { for qf in $(files_of_kind owner-question); do
  [ "$(fm_get "$qf" question_id)" = "$(fm_get "$1" question_ref)" ] && { echo "$qf"; return; }; done; }
answer_of_question() { for af in $(files_of_kind owner-answer); do
  [ "$(fm_get "$af" question_ref)" = "$(fm_get "$1" question_id)" ] && { echo "$af"; return; }; done; }
body_nonempty() { awk '/^---$/{c++; next} c>=2 && NF' "$1" | grep -q .; }

for af in $(files_of_kind owner-answer); do
  ac="$(fm_get "$af" action)"; qf="$(question_of_answer "$af")"
  [ -n "$qf" ] || continue                       # ANSWER_DANGLING already reported
  aseq="$(fm_get "$af" record_seq)"; qseq="$(fm_get "$qf" record_seq)"
  [ "$aseq" \> "$qseq" ] || fail LINK_ORDER "$af" "answer must follow question $qseq"
  blocks="$(fm_get "$qf" blocks)"
  case "$blocks" in
    t[0-9][0-9][0-9][0-9]-a[0-9][0-9]) ctx=attempt ;;
    CLOSING:*)                          ctx=close ;;
    *)                                  ctx=other ;;
  esac
  if in_list "$ac" "$DISPATCH_ACTIONS"; then
    [ "$ctx" = attempt ] || fail ACTION_CONTEXT "$af" "$ac requires a question blocking tTTTT-aAA (got $blocks)"
    case "$ac" in
      dispatch-job-found)
        { [ -n "$(fm_get "$af" transport)" ] && [ -n "$(fm_get "$af" job_id)" ]; } \
          || fail MISSING_EVIDENCE "$af" "dispatch-job-found requires transport + job_id" ;;
      dispatch-confirmed-absent|dispatch-termination-confirmed)
        [ -n "$(fm_get "$af" evidence)" ] || fail MISSING_EVIDENCE "$af" "$ac requires captured evidence" ;;
    esac
  elif in_list "$ac" "$GENERAL_ACTIONS"; then
    [ "$ctx" = attempt ] && fail ACTION_CONTEXT "$af" "$ac is not a legal answer to a DISPATCH_UNKNOWN question"
    if [ "$ctx" = close ]; then
      # §3.8 step 3: "the only safe resolution is cancel-close" — nothing else may resolve it.
      case "$ac" in cancel-close) ;; *) fail ACTION_CONTEXT "$af" "$ac may not resolve a CLOSING question";; esac
    fi
    if [ "$ac" = "cancel-close" ]; then
      [ "$ctx" = close ] || fail ACTION_CONTEXT "$af" "cancel-close requires blocks: CLOSING:<close_id>"
      cid="${blocks#CLOSING:}"; found=no
      for cf in $(files_of_kind close); do
        if [ "$(fm_get "$cf" close_id)" = "$cid" ]; then
          found=yes; cseq="$(fm_get "$cf" record_seq)"
          [ "$qseq" \> "$cseq" ] || fail LINK_ORDER "$qf" "close $cseq must precede its question"
        fi
      done
      [ "$found" = yes ] || fail ACTION_CONTEXT "$af" "cancel-close names unknown close_id $cid"
    fi
    [ "$ac" = "other" ] && { body_nonempty "$af" || fail MISSING_EVIDENCE "$af" "action: other requires an explanation"; }
  else
    fail BAD_ACTION "$af" "action=$ac"
  fi
done

for rf in $(files_of_kind result); do
  af="$(resolve "$(fm_get "$rf" assignment_ref)" assignment)"; [ -n "$af" ] || continue
  st="$(fm_get "$rf" status)"; rs="$(fm_get "$rf" result_sha)"
  reason="$(fm_get "$rf" reason)"; tk="$(fm_get "$rf" turn_kind)"
  base="$(fm_get "$af" base_sha)"
  # D31 — §3.2's terminal-status matrix. EVERY status lands in exactly one branch; the schema
  # stage's union check only proves the reason is a reason at all, which is how `ABORTED` with a
  # landed commit, `SUPERSEDED: never-dispatched` and `VERIFIED` with a failure reason all passed.
  case "$st" in
    VERIFIED)
      [ -z "$reason" ] || fail BAD_REASON "$rf" "VERIFIED carries no reason (got $reason)"
      if [ "$tk" = REVIEW ]; then
        [ "$rs" = "$base" ] || fail RESULT_SHA_RULE "$rf" "REVIEW result_sha must equal base_sha"
      else
        is_sha "$rs" && [ "$rs" != "$base" ] \
          || fail RESULT_SHA_RULE "$rf" "$tk VERIFIED must name a non-stationary commit"
      fi ;;
    ABORTED)
      in_list "$reason" "$ABORTED_REASONS" \
        || fail BAD_REASON "$rf" "reason=$reason is not an ABORTED reason"
      # §3.2: ABORTED requires tip = HEAD = base_sha and a clean tree. Nothing landed, so there is
      # no commit to name — a SHA here is a contradiction in the record, not a stray field.
      [ "$rs" = null ] || fail RESULT_SHA_RULE "$rf" "ABORTED must carry result_sha: null (got $rs)" ;;
    SUPERSEDED)
      in_list "$reason" "$SUPERSEDED_REASONS" \
        || fail BAD_REASON "$rf" "reason=$reason is not a SUPERSEDED reason" ;;
    REJECTED)
      in_list "$reason" "$REJECTED_REASONS" \
        || fail BAD_REASON "$rf" "reason=$reason is not a REJECTED reason"
      # D31: deny list. §3.2's own example (no reported SHA while the tip moved) is REJECTED +
      # verification-failed + null and must stay legal.
      if [ "$rs" = null ] && in_list "$reason" "$COMMIT_BEARING_REASONS"; then
        fail RESULT_SHA_RULE "$rf" "null result_sha is not legal for REJECTED:$reason"; fi
      # D37: and the other direction — a no-commit reason may not name a commit.
      if [ "$rs" != null ] && in_list "$reason" "$SHA_FORBIDDEN_REASONS"; then
        fail RESULT_SHA_RULE "$rf" "REJECTED:$reason must carry result_sha: null (got $rs)"; fi
      # MINOR — D31's own comment says a no-op names base_sha. A forged no-op sha equal to an
      # unexplained tip flips arm 5's verdict from UNRECORDED_DRIFT (alarm) to REMEDIATION_REQUIRED
      # (mechanical) — alarm-softening. `no-op-result` is stationary by definition, so it may name
      # ONLY the attempt's own base_sha (checked once rs is known non-null, above).
      if [ "$rs" != null ] && [ "$reason" = no-op-result ] && [ "$rs" != "$base" ]; then
        fail RESULT_SHA_RULE "$rf" "REJECTED:no-op-result must name base_sha (got $rs)"; fi ;;
  esac
  # The sibling of the VERIFIED REVIEW rule: §3.2 forbids commits for the whole turn kind, so a
  # REVIEW result in ANY status names base_sha or nothing.
  if [ "$tk" = REVIEW ] && [ "$st" != VERIFIED ] && [ "$rs" != null ] && [ "$rs" != "$base" ]; then
    fail RESULT_SHA_RULE "$rf" "REVIEW result_sha must be base_sha or null (got $rs)"; fi
  # §3.2's enum calls `other` "mandatory free text" — the same requirement the owner-answer loop
  # already enforces for `action: other`; a rule that holds in one place and not its twin is how
  # this document keeps re-shipping the same defect.
  if [ "$reason" = other ] && ! body_nonempty "$rf"; then
    fail MISSING_EVIDENCE "$rf" "reason: other requires explanatory body text"; fi
  case "$reason" in
    dispatch-confirmed-absent|terminated-before-result)
      roar="$(fm_get "$rf" owner_answer_ref)"
      [ -n "$roar" ] || fail MISSING_EVIDENCE "$rf" "$reason requires owner_answer_ref"
      # C1 — §3.2 authorizes closing an un-receipted attempt ONLY via dispatch-resolution actions.
      # Requiring owner_answer_ref present (above) is not requiring it AUTHORIZE THIS CLOSE: D25's
      # loop binds cross-wired ACTIONABLE actions (a result citing the OTHER dispatch action) but its
      # general branch (`authorize-remediation|…|record-decision|other`) is a deliberate no-op — so a
      # result citing a GENERAL answer (e.g. `record-decision`) fell through both checks and closed a
      # possibly-live attempt with no owner ever having confirmed it absent/terminated. Fail here,
      # before the general branch's `: ;;` can ever be reached for THIS reason/action pair.
      if [ -n "$roar" ]; then
        rap="$(resolve "$roar" owner-answer)"   # empty => LINK_DANGLING already reported elsewhere
        if [ -n "$rap" ]; then
          ract="$(fm_get "$rap" action)"
          case "$reason" in
            dispatch-confirmed-absent) rwant=dispatch-confirmed-absent ;;
            terminated-before-result)  rwant=dispatch-termination-confirmed ;;
          esac
          [ "$ract" = "$rwant" ] \
            || fail OWNER_ANSWER_MISMATCH "$rf" "$reason cites an answer with action=$ract, not $rwant"
        fi
      fi
      # Same class as below (a reason whose justification IS a record shape must be validated
      # against that shape): `dispatch-confirmed-absent` claims the owner confirmed NO dispatch
      # receipt exists for this attempt. A receipt on file is the very thing supposedly confirmed
      # absent — self-contradicted, independent of whether the owner_answer_ref itself checks out.
      # A `late` record is the SAME class of evidence as a receipt (§6.0 treats a recovered
      # dispatch as post-dispatch evidence to be validated, not ignored): it is an observation that
      # arrived FOR this attempt, which is durable proof something was in fact dispatched — exactly
      # what "confirmed absent" denies. codex round 3 finding A extends the guard to cover it.
      # `terminated-before-result` legitimately coexists with a receipt (job_id fencing), so this
      # guard is scoped to `dispatch-confirmed-absent` only.
      if [ "$reason" = dispatch-confirmed-absent ]; then
        rt="$(fm_get "$rf" turn_id)"; ra="$(fm_get "$rf" attempt_id)"
        { [ "$(attempt_count "$rt" "$ra" dispatch)" -eq 0 ] && [ "$(attempt_count "$rt" "$ra" late)" -eq 0 ]; } \
          || fail REASON_CONTRADICTED "$rf" "dispatch-confirmed-absent with a dispatch receipt or late observation on file for this attempt"
      fi ;;
    never-dispatched)
      # §6.3.3 authorizes this reason as MECHANICAL — no owner involved — precisely because §3.2
      # orders intent strictly before dispatch: "no intent" is durable proof nothing was ever
      # dispatched. Nothing previously checked the reason AGAINST that proof, so a self-declared
      # `never-dispatched` closed an attempt whose own intent (and even receipt) record disproved
      # it — the two-agents-in-one-worktree failure the design names as failure #1.
      # codex round 3 finding A: a `late` record for this attempt is the same proof — it is an
      # observation that ARRIVED for the attempt, which cannot happen for something never
      # dispatched — and was not checked, so a self-declared `never-dispatched` could close an
      # attempt whose own `late` record disproved it.
      rt="$(fm_get "$rf" turn_id)"; ra="$(fm_get "$rf" attempt_id)"
      { [ "$(attempt_count "$rt" "$ra" intent)" -eq 0 ] && [ "$(attempt_count "$rt" "$ra" dispatch)" -eq 0 ] \
        && [ "$(attempt_count "$rt" "$ra" late)" -eq 0 ]; } \
        || fail REASON_CONTRADICTED "$rf" "never-dispatched with a committed intent/receipt/late-observation for this attempt" ;;
  esac
  # --- Reason-class closure rule, driven by DISPATCH_REQUIRED_REASONS / DISPATCH_OR_OWNER_ANSWER_REASONS
  # above, plus the one-off `terminated-before-result` intent floor. Distinct var names (rct/rca) so
  # this block reads independently of the rt/ra assigned inside the case arms just above.
  if in_list "$reason" "$DISPATCH_REQUIRED_REASONS" || in_list "$reason" "$DISPATCH_OR_OWNER_ANSWER_REASONS" \
     || [ "$reason" = terminated-before-result ]; then
    rct="$(fm_get "$rf" turn_id)"; rca="$(fm_get "$rf" attempt_id)"
  fi
  if in_list "$reason" "$DISPATCH_REQUIRED_REASONS"; then
    [ "$(attempt_count "$rct" "$rca" dispatch)" -ge 1 ] \
      || fail REASON_CONTRADICTED "$rf" "$reason implies the job executed but no dispatch receipt is on file for this attempt"
  fi
  if in_list "$reason" "$DISPATCH_OR_OWNER_ANSWER_REASONS"; then
    roar2="$(fm_get "$rf" owner_answer_ref)"; rap2="$(resolve "$roar2" owner-answer)"
    { [ "$(attempt_count "$rct" "$rca" dispatch)" -ge 1 ] || [ -n "$rap2" ]; } \
      || fail REASON_CONTRADICTED "$rf" "$reason implies execution but has neither a dispatch receipt nor a resolvable owner_answer_ref"
  fi
  if [ "$reason" = terminated-before-result ]; then
    # §6.3.3's proof, the same shape as `never-dispatched`'s: no intent means provably nothing was
    # ever dispatched, so there is nothing to have been terminated. The RECEIPT exemption above
    # (job_id fencing legitimately coexisting with a receipt-less fence) is untouched — this is an
    # independent floor on `intent`, not a replacement for the owner_answer_ref requirement.
    [ "$(attempt_count "$rct" "$rca" intent)" -ge 1 ] \
      || fail REASON_CONTRADICTED "$rf" "terminated-before-result with no intent on file for this attempt"
  fi
done

for qf in $(files_of_kind owner-question); do
  sref="$(fm_get "$qf" supersedes_question_ref)"; [ -n "$sref" ] || continue
  old=""
  for candidate in $(files_of_kind owner-question); do
    [ "$(fm_get "$candidate" question_id)" = "$sref" ] && old="$candidate"
  done
  if [ -z "$old" ]; then fail BAD_SUPERSEDES "$qf" "$sref does not resolve"; continue; fi
  [ "$(fm_get "$old" record_seq)" \< "$(fm_get "$qf" record_seq)" ] \
    || fail BAD_SUPERSEDES "$qf" "superseded question must be earlier"
  [ "$(fm_get "$old" blocks)" = "$(fm_get "$qf" blocks)" ] \
    || fail BAD_SUPERSEDES "$qf" "superseded question blocks a different state"
  oldans="$(answer_of_question "$old")"
  if [ -z "$oldans" ]; then
    fail BAD_SUPERSEDES "$qf" "superseded question is unanswered"
  # codex round 3 finding B (second half): §5's supersession flow is "answered dispatch-unresolved,
  # THEN the primary opens a superseding question on explicit owner request" — the old question's
  # answer must already exist BEFORE it is superseded. Nothing checked that ORDER, only that old was
  # answered AT SOME POINT: old could be asked early and left open while a later, unrelated question
  # (this one, superseding it) got asked and answered, and only afterward did old finally receive its
  # own (possibly actionable) answer. Arm 3 (§6.3.3) classifies from the latest ANSWER by record_seq,
  # so a late-arriving answer to a nominally-"superseded" question would still win over the answer
  # that was supposed to supersede it — a result effectively citing a superseded authorization. Not a
  # second copy of arm 3's ordering rule: this fixes it at its source, the one place a question is
  # declared superseded, so arm 3's existing "latest answer wins" logic needs no change.
  elif ! [ "$(fm_get "$oldans" record_seq)" \< "$(fm_get "$qf" record_seq)" ]; then
    fail BAD_SUPERSEDES "$qf" "superseded question's answer must precede the superseding question"
  fi
done

# Close lifecycles: EVERY close, in record order (codex 3 + fable P1-D).
cancelling_answer_seq() { # <close-file> -> seq of its cancel-close answer, or empty
  cid="$(fm_get "$1" close_id)"; cseq="$(fm_get "$1" record_seq)"
  for af in $(files_of_kind owner-answer); do
    [ "$(fm_get "$af" action)" = "cancel-close" ] || continue
    qf="$(question_of_answer "$af")"; [ -n "$qf" ] || continue
    qseq="$(fm_get "$qf" record_seq)"; aseq="$(fm_get "$af" record_seq)"
    [ "$(fm_get "$qf" blocks)" = "CLOSING:$cid" ] \
      && [ "$qseq" \> "$cseq" ] && [ "$aseq" \> "$qseq" ] \
      && { echo "$aseq"; return; }
  done; }
close_is_cancelled() { [ -n "$(cancelling_answer_seq "$1")" ] && echo yes || echo no; }

for cf in $(echo "$SORTED" | awk '$2=="close"{print $3}'); do
  cid="$(fm_get "$cf" close_id)"; cseq="$(fm_get "$cf" record_seq)"
  # D30 — §3.8 step 1's second precondition, checked for EVERY close (a close that was later
  # cancelled was still written over whatever was live at the time). Rev.5 enforced only the SHA
  # half via D17: `assignment → intent → dispatch → close` with no result validated clean, and arm
  # 1 then classified CLOSING/CLOSED over a possibly-live agent before arm 3 could ever object.
  # Distinct variable names (aseq2/qseq2/ansf) so the window scan below keeps its own seq/kind/f.
  for a2 in $(files_of_kind assignment); do
    aseq2="$(fm_get "$a2" record_seq)"; [ "$aseq2" \< "$cseq" ] || continue
    rseq=""
    for r2 in $(echo "$ATTEMPTS" | grep . | awk -v t="$(fm_get "$a2" turn_id)" \
                 -v a="$(fm_get "$a2" attempt_id)" '$1==t&&$2==a&&$3=="result"{print $4}'); do
      rseq="$(fm_get "$r2" record_seq)"; done
    { [ -n "$rseq" ] && [ "$rseq" \< "$cseq" ]; } \
      || fail CLOSE_PRECONDITION "$cf" "close $cid precedes the terminal result of $(basename "$a2")"
  done
  for q2 in $(files_of_kind owner-question); do
    qseq2="$(fm_get "$q2" record_seq)"; [ "$qseq2" \< "$cseq" ] || continue
    ansf="$(answer_of_question "$q2")"
    { [ -n "$ansf" ] && [ "$(fm_get "$ansf" record_seq)" \< "$cseq" ]; } \
      || fail CLOSE_PRECONDITION "$cf" "close $cid precedes the answer to $(basename "$q2")"
  done
  endseq="$(cancelling_answer_seq "$cf")"           # empty => window runs to EOF
  qcount=0
  while read -r seq kind f; do
    [ -n "${seq:-}" ] || continue
    [ "$seq" \> "$cseq" ] || continue
    [ -n "$endseq" ] && { [ "$seq" \> "$endseq" ] && continue; }   # past the cancellation: legal
    case "$kind" in
      owner-question)
        if [ "$(fm_get "$f" blocks)" = "CLOSING:$cid" ]; then
          qcount=$((qcount+1))
          [ "$qcount" -le 1 ] || fail CLOSE_ORDER "$f" "more than one question blocks close $cid"
        else fail CLOSE_ORDER "$f" "unrelated question inside the window of close $cid"; fi ;;
      owner-answer)
        qf="$(question_of_answer "$f")"
        { [ -n "$qf" ] && [ "$(fm_get "$qf" blocks)" = "CLOSING:$cid" ]; } \
          || fail CLOSE_ORDER "$f" "unrelated answer inside the window of close $cid" ;;
      *) fail CLOSE_ORDER "$f" "$kind record inside the window of close $cid" ;;
    esac
  done <<< "$SORTED"
done

# accepted_sha as of a given record_seq — record-only, so it belongs to this stage and Task 4's
# classifier calls it with 9999. (D17 needs it here; the classifier needs the same walk.)
# §6 step 2: the seed is the base PINNED IN TOPIC.md at OPEN — not the first assignment's
# base_sha. A freshly opened or owner-only topic has a pinned base and no assignment at all, and
# rev.5 dereferenced an empty $first_assign on exactly that path. `TOPIC_BASE_MISMATCH` below
# keeps the two in agreement once a first assignment exists, so nothing else needs the variable —
# it is removed rather than left as a second, weaker source of the same value.
accepted_sha_upto() { # <seq>
  # D33: gated on TOPIC_FM_OK, not on `[ -f ]` — a malformed block is never mined for a seed.
  acc="$( [ "$TOPIC_FM_OK" = yes ] && fm_get "$TOPICMD" base_sha )"   # TOPIC_MISSING already reported
  while read -r seq kind f; do
    [ "${kind:-}" = "result" ] || continue
    [ "$seq" \> "$1" ] && continue
    [ "$(fm_get "$f" status)" = "VERIFIED" ] || continue
    [ "$(fm_get "$f" turn_kind)" = "REVIEW" ] && continue
    acc="$(fm_get "$f" result_sha)"
  done <<< "$SORTED"; echo "$acc"; }

for cf in $(files_of_kind close); do        # D17 / codex N4
  want="$(accepted_sha_upto "$(fm_get "$cf" record_seq)")"
  [ "$(fm_get "$cf" final_accepted_sha)" = "$want" ] \
    || fail CLOSE_SHA_MISMATCH "$cf" "final_accepted_sha != record-derived accepted_sha ($want)"
done

for qid in $(for q in $(files_of_kind owner-question); do fm_get "$q" question_id; done | sort | uniq -d); do
  fail QUESTION_DUP "$TURNS" "question_id $qid is not unique"; done

for cid in $(for c in $(files_of_kind close); do fm_get "$c" close_id; done | sort | uniq -d); do
  fail CLOSE_ID_DUP "$TURNS" "close_id $cid is not unique"; done   # else cancellation is ambiguous

# D25 — a record citing an owner answer must bind that authorization on ALL FIVE dimensions:
# WHAT it authorized (values), WHEN (the answer must already exist), WHOSE attempt, and WHETHER the
# action authorizes anything at all. Rev.5 checked only the values, so a receipt citing a FUTURE
# answer, ANOTHER attempt's answer, or a `dispatch-unresolved` answer passed here and arm 3 then
# returned `OPEN (dispatched)` on its dispatch count — before the classification-stage
# `materialized()` probe could object. This whole binding lives in the VIOLATION stage for that
# reason: anything expressed as a classification sits unreachable behind that early return (the way
# rev.4's version died, and the way `materialized()` itself finally died — it is deleted; see D25).
for f in $(echo "$SORTED" | awk '{print $3}'); do
  oar="$(fm_get "$f" owner_answer_ref)"; [ -n "$oar" ] || continue
  ap="$(resolve "$oar" owner-answer)"; [ -n "$ap" ] || continue   # LINK_DANGLING already reported
  act="$(fm_get "$ap" action)"
  # (i) forward-only (D18), universal: an append-only log cannot be authorized by its own future.
  [ "$(fm_get "$f" record_seq)" \> "$(fm_get "$ap" record_seq)" ] \
    || fail OWNER_ANSWER_ORDER "$f" "cites answer $oar, which does not precede it"
  # (ii) one answer authorizes ONE attempt — the tuple its question named. Scoped to the dispatch
  # actions on purpose: §3.3 step 1's `authorize-remediation` answer is cited by the NEW
  # remediation assignment, whose tuple differs from the dead attempt its question blocked, so a
  # universal tuple rule would reject a spec-legal record.
  if in_list "$act" "$ACTIONABLE_DISPATCH"; then
    qf2="$(question_of_answer "$ap")"
    if [ -n "$qf2" ]; then
      qb="$(fm_get "$qf2" blocks)"
      [ "t$(fm_get "$f" turn_id)-a$(fm_get "$f" attempt_id)" = "$qb" ] \
        || fail OWNER_ANSWER_TUPLE "$f" "cites an answer authorizing $qb, not this attempt"
    fi
  fi
  # (iii) every action lands in exactly one branch — no silent default.
  case "$act" in
    dispatch-job-found)
      [ "$(fm_get "$f" kind)" = dispatch ] \
        || fail OWNER_ANSWER_MISMATCH "$f" "dispatch-job-found must be materialized by a dispatch receipt"
      [ "$(fm_get "$f" receipt_source)" = owner-answer ] \
        || fail OWNER_ANSWER_MISMATCH "$f" "receipt_source must be owner-answer"
      [ "$(fm_get "$f" transport)" = "$(fm_get "$ap" transport)" ] \
        || fail OWNER_ANSWER_MISMATCH "$f" "transport differs from the authorized transport"
      [ "$(fm_get "$f" job_id)" = "$(fm_get "$ap" job_id)" ] \
        || fail OWNER_ANSWER_MISMATCH "$f" "job_id differs from the authorized job_id" ;;
    dispatch-confirmed-absent|dispatch-termination-confirmed)
      case "$act" in
        dispatch-confirmed-absent)      wr=dispatch-confirmed-absent ;;
        dispatch-termination-confirmed) wr=terminated-before-result ;;
      esac
      [ "$(fm_get "$f" kind)" = result ] \
        || fail OWNER_ANSWER_MISMATCH "$f" "$act must be materialized by a result"
      # §3.2 has TWO truthful materializations of an actionable dispatch answer: the worktree gate
      # PASSING (ABORTED + the exactly-matching reason) or that same gate FAILING on this owner-
      # authorized attempt (REJECTED + residue/out-of-scope, the DISPATCH_OR_OWNER_ANSWER_REASONS
      # set that already requires this same owner_answer_ref). Checking only the pass path made the
      # gate-failure record — the crash-recovery path this protocol exists for — unrecordable: it
      # would fire this MISMATCH twice with no valid encoding available at all.
      fst="$(fm_get "$f" status)"; frs="$(fm_get "$f" reason)"
      if [ "$fst" = ABORTED ] && [ "$frs" = "$wr" ]; then
        :   # gate passed
      elif [ "$fst" = REJECTED ] && in_list "$frs" "$DISPATCH_OR_OWNER_ANSWER_REASONS"; then
        :   # gate failed — the truthful residue/out-of-scope record citing the same answer
      else
        fail OWNER_ANSWER_MISMATCH "$f" "$act must materialize as ABORTED+$wr (gate passed) or REJECTED+{$DISPATCH_OR_OWNER_ANSWER_REASONS} (gate failed)"
      fi ;;
    dispatch-unresolved)
      # §3.2: "no materialization occurs and state remains DISPATCH_UNKNOWN". An answer that
      # authorizes nothing cannot be cited by anything.
      fail OWNER_ANSWER_UNAUTHORIZED "$f" "dispatch-unresolved authorizes no record" ;;
    authorize-remediation|authorize-cleanup|authorize-close|cancel-close|record-decision|other)
      # General authorizations prescribe no materializing record (§3.2), so only (i) applies. They
      # are deliberately left citable — §3.4 check 7's out-of-scope acceptance and §3.3 step 1's
      # remediation authorization are both records citing a general answer.
      # I2 — EXCEPT a dispatch record claiming owner-answer provenance: §3.2 only ever materializes
      # that receipt shape via `dispatch-job-found`, so a `dispatch` + `receipt_source: owner-answer`
      # citing a general action is a record falsely claiming owner-materialized provenance, even
      # though — unlike C1 — the classification outcome is unchanged (a general answer's dispatch
      # would validate as an ordinary `direct` receipt).
      if [ "$(fm_get "$f" kind)" = dispatch ] && [ "$(fm_get "$f" receipt_source)" = owner-answer ]; then
        fail OWNER_ANSWER_MISMATCH "$f" "dispatch receipt_source=owner-answer cites action=$act, not dispatch-job-found"
      fi ;;
    *)
      fail OWNER_ANSWER_UNAUTHORIZED "$f" "action=$act cannot authorize a record" ;;
  esac
done

# D32 — topic identity is validated ONCE, globally, and every consumer reads the validated value.
# TOPIC.md's topic_id when present, otherwise the first record in seq order fixes it. Rev.5 derived
# the authoritative topic from the FIRST ASSIGNMENT inside arm 6 while permitting later
# assignment/owner/close records to carry a different topic_id — so "is this commit ours?" depended
# on which record you asked.
# TOPIC.md's topic_id is the ONLY source. There is deliberately no first-record fallback: D33 makes
# TOPIC.md and its topic_id required, so a fallback could fire only on a run that TOPIC_MISSING or
# TOPIC_MISSING_KEY has already failed, and on that path it changes nothing observable — it would
# adopt the first record's own value, which every record then matches. An unreachable, untested
# branch is the same shape as the NOCOMMIT_REASONS list D31 deletes rather than shrinks.
TOPIC_ID=""
[ "$TOPIC_FM_OK" = yes ] && TOPIC_ID="$(fm_get "$TOPICMD" topic_id)"   # D33 gate
if [ -n "$TOPIC_ID" ]; then                 # empty only when the gate above already failed
  for f in $(echo "$SORTED" | awk '{print $3}'); do
    [ "$(fm_get "$f" topic_id)" = "$TOPIC_ID" ] \
      || fail TOPIC_ID_MISMATCH "$f" "topic_id != $TOPIC_ID (the topic's validated identity)"
  done
fi

# §3.4 check 2 + §3.0. Existence, structure and required keys were established in Task 1's stage;
# the TOPIC_FM_OK guard only prevents reading keys out of a file the structural pass already
# rejected — it is not an "absent means fine" fallback, because TOPIC_MISSING / FM_MALFORMED has
# already made this run exit 2 (D33).
if [ "$TOPIC_FM_OK" = yes ]; then
  for k in session_branch session_worktree work_repo_common_dir; do
    want="$(fm_get "$TOPICMD" "$k")"
    for a in $(files_of_kind assignment); do
      [ "$(fm_get "$a" "$k")" = "$want" ] || fail TOPIC_MISMATCH "$a" "$k disagrees with TOPIC.md"
    done; done
fi
# (`TOPIC_BASE_MISMATCH` is NOT re-checked here: Task 1's schema stage owns it, beside the gate
# that establishes the seed. Duplicating it would double-report one violation.)

[ "$VIOLATIONS" -gt 0 ] && exit 2

accepted_sha() { accepted_sha_upto 9999; }        # the Task-3 walk, whole record

classify_work_repo_arms() {
  # D10 — §6.2 identity gate before trusting anything about the worktree.
  if [ ! -d "$cdir" ] || [ ! -d "$wt" ]; then
    echo "postcondition work-repo-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: work-repo)"; return; fi
  root="$(repo_root "$cdir")"; registered=no; want="$(canon "$wt")"
  wl="$(g "$root" worktree list --porcelain 2>/dev/null)"; wl_rc=$?   # D26: failure ≠ "no entry"
  if [ "$wl_rc" -ne 0 ]; then
    echo "postcondition work-repo-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: worktree-list)"; return; fi
  while read -r key val; do
    [ "${key:-}" = "worktree" ] && [ "$(canon "$val")" = "$want" ] && registered=yes
  done <<< "$wl"
  # D26 — the remaining `|| echo none` / `|| echo 0` sentinels are gone. Each of these reads is
  # consumed as a VALUE; a sentinel let a FAILED read flow into a comparison and answer it.
  wtcommon="$(g "$wt" rev-parse --git-common-dir 2>/dev/null)"; wtc_rc=$?
  if [ "$wtc_rc" -ne 0 ]; then
    echo "postcondition worktree-identity: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: git-common-dir)"; return; fi
  case "$wtcommon" in /*) ;; *)
    wtcommon="$(cd "$wt" && cd "$wtcommon" 2>/dev/null && pwd -P)" || {
      echo "postcondition worktree-identity: UNAVAILABLE"
      echo "classification: UNRECORDED_DRIFT (unverified: git-common-dir)"; return; } ;;
  esac
  headbr="$(g "$wt" symbolic-ref --short HEAD 2>/dev/null)"; hb_rc=$?
  if [ "$hb_rc" -ne 0 ]; then     # detached HEAD or an unreadable worktree — never "matches $br"
    echo "postcondition worktree-identity: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: head-branch)"; return; fi
  if [ "$registered" != yes ] || [ "$(canon "$wtcommon")" != "$(canon "$cdir")" ] || [ "$headbr" != "$br" ]; then
    echo "postcondition worktree-identity: FAIL"
    echo "classification: UNRECORDED_DRIFT"; return; fi
  echo "postcondition worktree-identity: PASS"

  tip="$(g "$root" rev-parse "refs/heads/$br" 2>/dev/null)"; tip_rc=$?
  head="$(g "$wt" rev-parse HEAD 2>/dev/null)"; head_rc=$?
  if [ "$tip_rc" -ne 0 ] || [ "$head_rc" -ne 0 ]; then
    echo "postcondition work-repo-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: branch-tip)"; return; fi
  # D26 — a FAILED status command must never read as "clean". Capture the status separately.
  dirty="$(g "$wt" status --porcelain 2>/dev/null)"; dirty_rc=$?   # D15: no index rewrite
  if [ "$dirty_rc" -ne 0 ]; then
    echo "postcondition worktree-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: worktree-status)"; return; fi
  if [ "$tip" = "$ACCEPTED" ] && [ "$head" = "$ACCEPTED" ] && [ -z "$dirty" ]; then
    echo "classification: IDLE"; return; fi
  for rf in $(files_of_kind result); do
    case "$(fm_get "$rf" status)" in REJECTED|SUPERSEDED) ;; *) continue;; esac
    [ "$(fm_get "$rf" result_sha)" = "$tip" ] && { echo "classification: REMEDIATION_REQUIRED"; return; }
  done
  # Arm 6 — D14: the range must be NON-EMPTY, else "all commits carry trailers" is vacuous.
  # D26: `|| echo 0` made an UNREADABLE range indistinguishable from an EMPTY one.
  n="$(g "$root" rev-list --count "$ACCEPTED..$tip" 2>/dev/null)"; n_rc=$?
  if [ "$n_rc" -ne 0 ]; then
    echo "postcondition commit-range-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: commit-range)"; return; fi
  # C2 (acceptance round 2, coverage gap) — the trailer walk's own `rev-list` read (inside
  # `all_commits_carry_closed_attempt_trailers`) can fail independently of the `--count` read just
  # above. Before this fix its failure collapsed into the ordinary "no" answer ("not every commit
  # carries the trailers"), which is indistinguishable from a genuinely untrailered range and drops
  # straight into `UNRECORDED_DRIFT` with no `(unverified: …)` marker — a failed read silently read
  # as data. `trailer_result` now carries a third value so the caller can tell the two apart.
  trailer_result="$([ "$n" -gt 0 ] && all_commits_carry_closed_attempt_trailers "$ACCEPTED" "$tip")"
  if [ "$trailer_result" = unavailable ]; then
    echo "postcondition trailer-range-readable: UNAVAILABLE"
    echo "classification: UNRECORDED_DRIFT (unverified: trailer-range)"; return; fi
  if [ "$trailer_result" = yes ]; then
    echo "classification: REMEDIATION_REQUIRED"; return; fi
  echo "classification: UNRECORDED_DRIFT"; }

one_trailer() { # <repo-root> <commit> <key>; print the sole value, or fail (rc 1)
  # D26 — the pipeline's upstream statuses were discarded: only awk's status survived, so a failed
  # `show` or `interpret-trailers` arrived as "no trailer of that key". No behavioural delta today
  # (an empty `vals` already returned 1), so this ships WITHOUT a RED test — stated, not claimed.
  # It is here so a future refactor that distinguishes "absent" from "unreadable" cannot silently
  # inherit the conflation.
  msg="$(g "$1" show -s --format=%B "$2" 2>/dev/null)" || return 1
  parsed="$(printf '%s\n' "$msg" | g "$1" interpret-trailers --parse 2>/dev/null)" || return 1
  vals="$(printf '%s\n' "$parsed" | awk -F': ' -v k="$3" '$1==k{sub(/^[^:]*: /, ""); print}')" || return 1
  [ "$(printf '%s\n' "$vals" | grep -c .)" -eq 1 ] || return 1
  printf '%s\n' "$vals"
}

all_commits_carry_closed_attempt_trailers() { # <from> <to> -> yes/no/unavailable (D20, C2)
  # D32: the ONE consumer of topic identity reads the value validated in Task 3, not a
  # re-derivation from the first assignment — otherwise a later record carrying a second topic_id
  # changes what "our commit" means without any rule objecting. (No identity is derived from an
  # assignment any more. `first_assign_rec` survives in Task 1 as the SUBJECT of the
  # TOPIC_BASE_MISMATCH cross-check and `newest_assign` in Task 2 as OPEN_NOT_NEWEST's subject;
  # neither seeds ACCEPTED or TOPIC_ID. "Removed" was the wrong word, not the wrong property.)
  bad=0; root="$(repo_root "$cdir")"; active_topic="$TOPIC_ID"
  # C2 — a FAILED walk is not "no" (not-all-trailered): that reading is the same conflation D26
  # forbade elsewhere, a failed read flowing into the answer as if it were data. `unavailable` is
  # its own outcome, so the caller can emit a distinguishing `(unverified: …)` marker instead of
  # a silent, indistinguishable UNRECORDED_DRIFT.
  rl="$(g "$root" rev-list "$1..$2" 2>/dev/null)"; rl_rc=$?
  [ "$rl_rc" -eq 0 ] || { echo unavailable; return; }
  while read -r sha; do
    [ -n "${sha:-}" ] || continue
    topic="$(one_trailer "$root" "$sha" Agent-Pairing-Topic)" || { bad=1; continue; }
    t="$(one_trailer "$root" "$sha" Agent-Pairing-Turn)" || { bad=1; continue; }
    a="$(one_trailer "$root" "$sha" Agent-Pairing-Attempt)" || { bad=1; continue; }
    [ "$topic" = "$active_topic" ] || bad=1
    [ "$(attempt_count "$t" "$a" result)" -ge 1 ] || bad=1
  done <<< "$rl"
  [ "$bad" -eq 0 ] && echo yes || echo no; }

latest_active_close() {   # newest close that is NOT cancelled — scans backward (codex N6)
  for cf in $(files_of_kind close | sort -r); do
    [ "$(close_is_cancelled "$cf")" = yes ] || { echo "$cf"; return; }
  done; }

check_thread_header() { # sets PC
  # D26 — `--show-toplevel`'s output is consumed as a VALUE (it is canonicalized and compared), so
  # its status is captured. `|| true` conflated "not a repo" with "the read failed".
  top="$(g "$TOPIC" rev-parse --show-toplevel 2>/dev/null)"; top_rc=$?
  if [ "$top_rc" -ne 0 ] || [ -z "$top" ] || [ "$(canon "$top")" != "$(canon "$TOPIC")" ]; then
    echo "postcondition thread-header: UNAVAILABLE"; PC=un; return; fi
  # D26 — the committed blob is DATA. Rev.5 piped `git show` straight into awk, so a FAILED read
  # reached awk as empty input and printed FAIL: "the header does not say CLOSED" and "the header
  # could not be read" became the same answer. Capture the status, then scan the captured text.
  hdr="$(g "$TOPIC" show HEAD:THREAD.md 2>/dev/null)"; hdr_rc=$?
  # D24: scan the whole header block (to the first blank line), never a fixed line count.
  header_says_closed() {
    printf '%s\n' "$hdr" | awk '/^$/{exit} /^status: CLOSED$/{f=1} END{exit !f}'; }
  # `ls-files --error-unmatch` and `diff --quiet` are BOOLEAN PREDICATES, not data reads: a non-zero
  # exit already IS the not-satisfied answer, so they fail closed by construction (D26's scope).
  if ! g "$TOPIC" ls-files --error-unmatch THREAD.md >/dev/null 2>&1 \
     || ! g "$TOPIC" diff --quiet HEAD -- THREAD.md; then
    echo "postcondition thread-header: FAIL"; PC=no; return; fi
  if [ "$hdr_rc" -ne 0 ]; then
    echo "postcondition thread-header: UNAVAILABLE"; PC=un; return; fi
  if header_says_closed; then echo "postcondition thread-header: PASS"; PC=ok
  else echo "postcondition thread-header: FAIL"; PC=no; fi; }

check_worktree_absent() { # <common-dir> <worktree> ; sets PC   (D26)
  root="$(repo_root "$1")"
  [ -d "$1" ] || { echo "postcondition worktree-absent: UNAVAILABLE"; PC=un; return; }
  want="$(canon "$2")"
  # A dangling symlink is NOT absence: -e is false for one, -L is true.
  if [ -e "$2" ] || [ -L "$2" ]; then echo "postcondition worktree-absent: FAIL"; PC=no; return; fi
  wl="$(g "$root" worktree list --porcelain 2>/dev/null)"; wl_rc=$?
  if [ "$wl_rc" -ne 0 ]; then echo "postcondition worktree-absent: UNAVAILABLE"; PC=un; return; fi
  listed=no
  while read -r key val; do
    [ "${key:-}" = "worktree" ] && [ "$(canon "$val")" = "$want" ] && listed=yes
  done <<< "$wl"
  if [ "$listed" = yes ]; then echo "postcondition worktree-absent: FAIL"; PC=no
  else echo "postcondition worktree-absent: PASS"; PC=ok; fi; }

check_branch_at_final() { # <common-dir> <branch> <final-sha> ; sets PC   (D26)
  [ -d "$1" ] || { echo "postcondition branch-at-final: UNAVAILABLE"; PC=un; return; }
  tip="$(g "$(repo_root "$1")" rev-parse "refs/heads/$2" 2>/dev/null)"; tip_rc=$?
  if [ "$tip_rc" -ne 0 ]; then echo "postcondition branch-at-final: UNAVAILABLE"; PC=un; return; fi
  if [ "$tip" = "$3" ]; then echo "postcondition branch-at-final: PASS"; PC=ok
  else echo "postcondition branch-at-final: FAIL"; PC=no; fi; }

# `materialized()` is DELETED, not kept as a guard. It could never return `yes`: it searched for a
# later `dispatch` (for `dispatch-job-found`) or a later `result` (for the two termination actions)
# of this same attempt, and BOTH of arm 3's early returns fire before it is ever consulted — a
# dispatch for this attempt returns `OPEN (dispatched)`, and a result for this attempt means the
# assignment is matched and arm 3 never runs at all. So the search set was always empty and the
# function always echoed `no`. That is the same unreachable-branch shape rev.5's D25 note describes,
# with the reachability half left behind when the values moved to the violation stage. Arm 3's two
# early returns ARE the reachability test; the record-shape binding lives entirely in
# `OWNER_ANSWER_MISMATCH` / `ORDER` / `TUPLE` / `UNAUTHORIZED` (Task 3). Deliberately NOT fixed by
# hoisting the question loop above the dispatch-count return: that would change what
# `OPEN (dispatched)` means, and is next round's finding.

classify() { # <check|render>
  cmode="$1"; ACCEPTED="$(accepted_sha)"; echo "accepted_sha: $ACCEPTED"
  # D24 — the two header lines, emitted on EVERY path (empty when there is no open attempt), so
  # --check and --render cannot drift. Rev.4 asserted these in a test and emitted them nowhere.
  oa=""; oat=""; oaa=""
  while read -r seq kind f; do
    [ "${kind:-}" = "assignment" ] || continue
    [ "$(attempt_count "$(fm_get "$f" turn_id)" "$(fm_get "$f" attempt_id)" result)" -eq 0 ] && oa="$f"
  done <<< "$SORTED"
  if [ -n "$oa" ]; then
    oat="$(fm_get "$oa" turn_id)"; oaa="$(fm_get "$oa" attempt_id)"
    echo "open_attempt: t$oat-a$oaa"
    dsp=""
    for df in $(echo "$ATTEMPTS" | awk -v t="$oat" -v a="$oaa" '$1==t&&$2==a&&$3=="dispatch"{print $4}'); do
      dsp="$(fm_get "$df" dispatched_at)"; done
    echo "dispatched_at: $dsp"
  else echo "open_attempt:"; echo "dispatched_at:"; fi
  # Identity comes from TOPIC.md, never from "the newest assignment". Correctness argument, not
  # taste: `classify` runs only when VIOLATIONS is 0, and Task 3's TOPIC_MISMATCH forbids any
  # assignment from disagreeing with TOPIC.md, so on every path that reaches here the two sources
  # are provably equal — while TOPIC.md is additionally defined for a topic with no assignment at
  # all (freshly opened, or owner-only), where the old expression dereferenced an empty path.
  # classify runs only when VIOLATIONS is 0, so TOPIC_FM_OK is necessarily `yes` here; the reads
  # are listed under D33 as consumers of the gate rather than as unguarded ones.
  cdir="$(fm_get "$TOPICMD" work_repo_common_dir)"
  wt="$(fm_get "$TOPICMD" session_worktree)"
  br="$(fm_get "$TOPICMD" session_branch)"
  latest_close="$(latest_active_close)"

  # Arm 1 — latest non-cancelled close (found by backward scan, not by "last record wins").
  if [ -n "$latest_close" ]; then
    cid="$(fm_get "$latest_close" close_id)"
    for qf in $(files_of_kind owner-question); do
      [ "$(fm_get "$qf" blocks)" = "CLOSING:$cid" ] || continue
      [ -n "$(answer_of_question "$qf")" ] || { echo "classification: AWAITING_OWNER"; return; }
    done
    unv=""
    if [ "$cmode" = render ]; then echo "postcondition thread-header: PROJECTED"; th=ok
    else check_thread_header; th="$PC"; fi
    check_worktree_absent "$cdir" "$wt";  wta="$PC"
    check_branch_at_final "$cdir" "$br" "$(fm_get "$latest_close" final_accepted_sha)"; bra="$PC"
    [ "$wta" = un ] && unv="${unv}worktree-absent"
    [ "$bra" = un ] && unv="${unv}${unv:+,}branch-at-final"
    [ "$th"  = un ] && unv="${unv}${unv:+,}thread-header"
    if [ "$th" = ok ] && [ "$wta" = ok ] && [ "$bra" = ok ]; then echo "classification: CLOSED"
    else echo "classification: CLOSING:$cid${unv:+ (unverified: $unv)}"; fi
    return
  fi

  # Arm 2 — any unanswered owner question.
  for qf in $(files_of_kind owner-question); do
    [ -n "$(answer_of_question "$qf")" ] || { echo "classification: AWAITING_OWNER"; return; }; done

  # Arm 3 — unmatched assignment.
  open_assign=""
  while read -r seq kind f; do
    [ "${kind:-}" = "assignment" ] || continue
    [ "$(attempt_count "$(fm_get "$f" turn_id)" "$(fm_get "$f" attempt_id)" result)" -eq 0 ] && open_assign="$f"
  done <<< "$SORTED"
  if [ -n "$open_assign" ]; then
    t="$(fm_get "$open_assign" turn_id)"; a="$(fm_get "$open_assign" attempt_id)"
    [ "$(attempt_count "$t" "$a" intent)"   -eq 0 ] && { echo "classification: OPEN (never-dispatched)"; return; }
    [ "$(attempt_count "$t" "$a" dispatch)" -gt 0 ] && { echo "classification: OPEN (dispatched)"; return; }
    # B1 (acceptance rev.2) — §6.3.3: classify from the LATEST answered question blocking this
    # attempt, not the first. A topic can carry more than one owner-question blocking the same
    # attempt (e.g. the owner first authorises a dispatch action, then a later question for the
    # SAME attempt is answered `dispatch-unresolved`, explicitly withdrawing it). Scanning forward
    # and stopping at the first actionable answer ignored that later, superseding answer and
    # classified OWNER_ACTION_PENDING — i.e. replay would execute authorization the owner already
    # withdrew. Select the answer with the highest record_seq among questions blocking this
    # attempt, then classify from THAT one; `dispatch-unresolved` falls through to DISPATCH_UNKNOWN
    # with no other automatic question, exactly as §6.3.3 requires.
    latest_af=""; latest_aseq=""
    for qf in $(files_of_kind owner-question); do
      [ "$(fm_get "$qf" blocks)" = "t$t-a$a" ] || continue
      af="$(answer_of_question "$qf")"; [ -n "$af" ] || continue
      aseq="$(fm_get "$af" record_seq)"
      { [ -z "$latest_aseq" ] || [ "$aseq" \> "$latest_aseq" ]; } && { latest_af="$af"; latest_aseq="$aseq"; }
    done
    if [ -n "$latest_af" ] && in_list "$(fm_get "$latest_af" action)" "$ACTIONABLE_DISPATCH"; then
      # No materialization probe here — see the note above `classify`: the two early returns above
      # already exclude every attempt whose authorization HAS materialized.
      echo "classification: OWNER_ACTION_PENDING"; return
    fi
    echo "classification: DISPATCH_UNKNOWN"; return
  fi

  classify_work_repo_arms   # Task 5
}

if [ "$MODE" = "--render" ]; then
  TMPF="$TOPIC/THREAD.md.tmp.$$"
  # D35 — every write here used to be unchecked and the exit was an unconditional 0, so a full
  # disk, an unreadable record or a failed rename published a TRUNCATED THREAD.md and reported
  # success. Now: one status for the whole group, one for the rename. On either failure remove ONLY
  # our own temp path (prefix-guarded — never THREAD.md) and exit 2. Atomicity is unchanged: the
  # temp file is created in the SAME directory as THREAD.md, so the mv is a same-fs rename.
  render_fail() { # <why>
    case "$TMPF" in "$TOPIC"/THREAD.md.tmp.*) rm -f "$TMPF";; esac
    echo "VIOLATION RENDER_FAILED $TOPIC: $1; previous THREAD.md left intact" >&2
    exit 2; }
  RENDER_RC=0
  { echo "GENERATED — do not edit — regenerate with: validate.sh --render <topic-dir>" || RENDER_RC=1
    out="$(classify render)" || RENDER_RC=1
    echo "$out" || RENDER_RC=1
    case "$out" in *"classification: CLOSED"*) echo "status: CLOSED" || RENDER_RC=1;; esac
    echo || RENDER_RC=1
    while read -r seq kind f; do
      [ -n "${seq:-}" ] || continue
      printf -- '---8<--- %s ---\n\n' "$(basename "$f")" || RENDER_RC=1
      cat "$f" || RENDER_RC=1
      echo || RENDER_RC=1
    done <<< "$SORTED"
  } > "$TMPF" || RENDER_RC=1
  # `{ ... }` is a group, not a subshell (the converse of D2), so RENDER_RC survives the
  # redirection — the same fact D2 relies on, used in the other direction. A failed redirection
  # skips the group entirely and lands on the `|| RENDER_RC=1` above.
  [ "$RENDER_RC" -eq 0 ] \
    || render_fail "render group failed (unwritable temp path or unreadable record)"
  mv "$TMPF" "$TOPIC/THREAD.md" || render_fail "atomic rename failed"
  exit 0
fi
classify check; exit 0
