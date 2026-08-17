#!/bin/bash
# bash 3.2 compatible. Regenerates the shipped v2 example. Run from anywhere:
#   /bin/bash agent-pairing/example/build.sh
#
# Builds a complete topic that ends in exact `CLOSED`, then bundles both repositories. The example is
# the only place a reader can see the whole protocol at once, so it deliberately contains the hard
# parts rather than a happy path:
#
#   turn 1  NORMAL   — dispatch, ACK, exact capture, VERIFIED, the accepted SHA advances
#   turn 2  REVIEW   — stationary: reviews turn 1's commit and may not move it
#   turn 3  NORMAL   — the ACK never arrives, the attempt is FENCED, a late ACK arrives after the
#                      boundary and is preserved as evidence that changes nothing
#   close            — every postcondition proved
#
# Everything is deterministic: fixed identity, fixed timestamps, fixed epochs. Two builds produce
# byte-identical commits, so FINAL_SHA is a stable artifact rather than a per-run accident.
set -u
EX="$(cd "$(dirname "$0")" && pwd -P)"

export GIT_AUTHOR_NAME=agent-pairing-example
export GIT_AUTHOR_EMAIL=example@invalid
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_AUTHOR_DATE='2026-08-14T10:00:00+0000'
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
export TZ=UTC
export GIT_NO_REPLACE_OBJECTS=1

ROOT="$(mktemp -d /tmp/ap-v2-example.XXXXXX)" || { echo "FATAL: temp allocation failed" >&2; exit 3; }
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "FATAL: temp allocation produced no directory" >&2; exit 3; }
case "$ROOT" in /tmp/ap-v2-example.?*) ;; *) echo "FATAL: $ROOT is not under the expected prefix" >&2; exit 3 ;; esac
R="$ROOT/repo"; W="$ROOT/wt"; T="$ROOT/topic"
TOPIC_ID=example-v2
BRANCH="pair/$TOPIC_ID"

die() { echo "FATAL: $1" >&2; exit 3; }
gc() { git -C "$1" commit -qm "$2" || die "commit failed in $1"; }
gcf() { git -C "$1" commit -q -F "$2" || die "commit failed in $1"; }

# --- the work repo and its session worktree ------------------------------------------------------------
mkdir -p "$R" && git -C "$R" init -q -b main || die "cannot create the work repo"
printf 'seed\n' >"$R/README.md"
mkdir -p "$R/src" && printf 'original\n' >"$R/src/app.txt"
git -C "$R" add -A && gc "$R" seed
B0="$(git -C "$R" rev-parse HEAD)" || die "cannot read the base"
git -C "$R" worktree add -q "$W" -b "$BRANCH" "$B0" || die "cannot create the session worktree"

# Turn 1's real commit, with the three attribution trailers as ONE final paragraph.
printf 'improved\n' >"$W/src/app.txt"
git -C "$W" add -A || die "cannot stage turn 1"
cat >"$ROOT/msg1" <<MSG
improve app text

Agent-Pairing-Topic: $TOPIC_ID
Agent-Pairing-Turn: 0001
Agent-Pairing-Attempt: 01
MSG
gcf "$W" "$ROOT/msg1"
C1="$(git -C "$W" rev-parse HEAD)" || die "cannot read turn 1's commit"

# --- the record repository ---------------------------------------------------------------------------
mkdir -p "$T/turns" && git -C "$T" init -q -b main || die "cannot create the record repo"

rec() { cat >"$T/turns/$1"; }

cat >"$T/TOPIC.md" <<TOPIC
---
protocol_version: 2
topic_id: $TOPIC_ID
participant_start_mode: owner-manual
participant_selection_source: initial-prompt
base_sha: $B0
base_ref: refs/heads/main
session_branch: $BRANCH
session_worktree: $W
work_repo_common_dir: $R/.git
---

# $TOPIC_ID

## Charter
Improve \`src/app.txt\`, review the change, and close.

Done when: the accepted SHA names the improved text and every turn has a terminal result.

## Preconditions
One machine, one shared filesystem. The record repo and the session worktree are both local.

## Registry
- \`participant-a\` — owner-relayed, \`commits\`, worktree visible. The authority is the admission
  record, not this section.

## Verification profiles

\`\`\`yaml
profile_id: shell-pinned
lock_identity: sha256:0000000000000000000000000000000000000000000000000000000000000000
bootstrap_command: true
verification_command: test -s src/app.txt
required_tools: bash 3.2
required_environment_names: NONE
\`\`\`

## DECISIONS
- 2026-08-14 — the example ships a fenced attempt on purpose: a protocol is only legible once you
  can see what it does when delivery fails.

## Onboarding
See \`templates/onboarding.md\`. This example is replayed by the package gate, not worked by an agent.
TOPIC

rec 0001-admission.md <<'REC'
---
protocol_version: 2
record_seq: 0001
kind: admission
topic_id: example-v2
recorded_epoch: 1000
recorded_at: 2026-08-14T10:00:00Z
admission_id: adm-0001
agent_id: participant-a
join_mode: owner-manual
transport: human-relay
capability: commits
worktree_visible: true
durable_address_kind: human-relay
durable_address: owner-relay-desk
searchability: unsearchable
token_search_recipe_ref: null
report_channel: human-relay
ack_evidence_class: human-relayed
receipt_commit_timeout_seconds: 300
default_ack_timeout_seconds: 600
---
The owner confirmed the participant joined by topic ID and supplied a durable relay address.
REC

# --- one full turn: assignment, intent, receipt, ACK, capture, result ------------------------------------
turn() { # <seq0> <turn> <attempt> <kind> <base> <epoch0> <token> <job> <profile> <report> <status> <sha>
  s0="$1" tn="$2" at="$3" tk="$4" base="$5" e0="$6" tok="$7" job="$8" prof="$9" report="${10}" st="${11}" sha="${12}"
  s1="$(printf '%04d' $((10#$s0 + 1)))"; s2="$(printf '%04d' $((10#$s0 + 2)))"
  s3="$(printf '%04d' $((10#$s0 + 3)))"; s4="$(printf '%04d' $((10#$s0 + 4)))"
  s5="$(printf '%04d' $((10#$s0 + 5)))"
  A="$s0-t$tn-a$at-assignment.md"; I="$s1-t$tn-a$at-intent.md"; D="$s2-t$tn-a$at-dispatch.md"
  K="$s3-t$tn-a$at-ack.md"; P="$s4-t$tn-a$at-result-capture.md"

  rec "$A" <<REC
---
protocol_version: 2
record_seq: $s0
kind: assignment
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
base_sha: $base
session_branch: $BRANCH
session_worktree: $W
work_repo_common_dir: $R/.git
scope: src/
agent_id: participant-a
admission_ref: 0001-admission.md
ack_timeout_seconds: 600
work_timeout_seconds: 3600
verification_profile_id: $prof
recorded_epoch: $e0
recorded_at: 2026-08-14T10:00:00Z
---
Goal: see the charter.
Deliverable: a commit under \`src/\` with the attempt trailers.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
REC

  rec "$I" <<REC
---
protocol_version: 2
record_seq: $s1
kind: intent
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
assignment_ref: $A
idempotency_token: $tok
admission_ref: 0001-admission.md
expected_dispatch_ref: $D
receipt_commit_timeout_seconds: 300
receipt_commit_by_epoch: $((e0 + 10 + 300))
recorded_epoch: $((e0 + 10))
recorded_at: 2026-08-14T10:00:00Z
---
Committed dispatch authorization. This commit strictly precedes dispatch.
REC

  rec "$D" <<REC
---
protocol_version: 2
record_seq: $s2
kind: dispatch
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
assignment_ref: $A
transport: human-relay
job_id: $job
intent_ref: $I
admission_ref: 0001-admission.md
dispatched_epoch: $((e0 + 20))
ack_due_epoch: $((e0 + 20 + 600))
receipt_source: direct
recorded_epoch: $((e0 + 20))
recorded_at: 2026-08-14T10:00:00Z
---
Captured dispatch receipt. The ACK budget starts when THIS record is committed.
REC

  [ "$st" = FENCED ] && return 0

  rec "$K" <<REC
---
protocol_version: 2
record_seq: $s3
kind: ack
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
assignment_ref: $A
intent_ref: $I
dispatch_ref: $D
admission_ref: 0001-admission.md
job_id: $job
idempotency_token: $tok
observed_head: $base
preflight_clean: true
relayed_base_sha: null
ack_evidence_class: human-relayed
ack_captured_epoch: $((e0 + 30))
work_due_epoch: $((e0 + 30 + 3600))
recorded_epoch: $((e0 + 30))
recorded_at: 2026-08-14T10:00:00Z
---
Acknowledgement captured. The work budget starts here, not at the receipt.
REC

  mkdir -p "$T/artifacts/t$tn-a$at"
  printf '%s\n' "$report" >"$T/artifacts/t$tn-a$at/report.md"
  ART="$T/artifacts/t$tn-a$at/report.md"
  BC="$(LC_ALL=C wc -c <"$ART" | tr -d ' ')"
  SH="$(shasum -a 256 "$ART" | awk '{print $1}')"
  rec "$P" <<REC
---
protocol_version: 2
record_seq: $s4
kind: result-capture
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
assignment_ref: $A
dispatch_ref: $D
ack_ref: $K
artifact_ref: artifacts/t$tn-a$at/report.md
author_byte_count: $BC
author_sha256: $SH
observed_byte_count: $BC
observed_sha256: $SH
encoding: utf-8
trailing_newline: present
captured_epoch: $((e0 + 40))
recorded_epoch: $((e0 + 40))
recorded_at: 2026-08-14T10:00:00Z
---
Exact participant bytes, captured without normalization and committed before interpretation.
REC

  rec "$s5-t$tn-a$at-result.md" <<REC
---
protocol_version: 2
record_seq: $s5
kind: result
topic_id: $TOPIC_ID
turn_id: $tn
attempt_id: $at
turn_kind: $tk
assignment_ref: $A
dispatch_ref: $D
ack_ref: $K
result_capture_ref: $P
status: $st
result_sha: $sha
observed_at: 2026-08-14T10:00:00Z
recorded_epoch: $((e0 + 50))
recorded_at: 2026-08-14T10:00:00Z
---
## Verification
\`test -s src/app.txt\` under profile \`shell-pinned\` — exit 0.

## Primary commentary (separate)
Kept apart from the participant's own words, which live in the captured artifact.
REC
}

turn 0002 0001 01 NORMAL "$B0" 1010 tok-0001 job-0001 shell-pinned 'Improved the app text. test -s src/app.txt passed.' VERIFIED "$C1"
turn 0008 0002 01 REVIEW "$C1" 1110 tok-0002 job-0002 shell-pinned 'Reviewed turn 1. No BLOCKING findings; one NONBLOCKING note. PASS.' VERIFIED "$C1"

# --- turn 3: the ACK never arrives, so the attempt is FENCED --------------------------------------------
turn 0014 0003 01 NORMAL "$C1" 1210 tok-0003 job-0003 null '' FENCED ''

rec 0017-t0003-a01-fence-initiated.md <<REC
---
protocol_version: 2
record_seq: 0017
kind: fence-initiated
topic_id: $TOPIC_ID
turn_id: 0003
attempt_id: 01
turn_kind: NORMAL
trigger: ack-timeout
assignment_ref: 0014-t0003-a01-assignment.md
dispatch_ref: 0016-t0003-a01-dispatch.md
ack_ref: null
job_id: job-0003
due_epoch: $((1210 + 20 + 600))
observed_epoch: $((1210 + 20 + 700))
recorded_epoch: $((1210 + 20 + 700))
recorded_at: 2026-08-14T10:00:00Z
---
The ACK budget expired with no acknowledgement. Committed BEFORE asking the transport to terminate
the job, so a crash in between leaves the boundary in the history rather than an unrecorded kill.
REC

rec 0018-t0003-a01-late-01.md <<REC
---
protocol_version: 2
record_seq: 0018
kind: late
topic_id: $TOPIC_ID
turn_id: 0003
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0014-t0003-a01-assignment.md
named_sha: null
recorded_epoch: $((1210 + 20 + 900))
recorded_at: 2026-08-14T10:00:00Z
---
The participant's acknowledgement arrived AFTER the fence was committed, correctly formed and
binding this attempt.

It is preserved here as evidence and it cancels nothing. A late ACK does not mean the fence was
wrong; it means the acknowledgement arrived after the boundary. The attempt does not reopen, and
retry stays forbidden until termination is confirmed — missing ACK is missing evidence, never
evidence of death.
REC

rec 0019-t0003-a01-result.md <<REC
---
protocol_version: 2
record_seq: 0019
kind: result
topic_id: $TOPIC_ID
turn_id: 0003
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0014-t0003-a01-assignment.md
dispatch_ref: 0016-t0003-a01-dispatch.md
ack_ref: null
result_capture_ref: null
status: ABORTED
reason: ack-timeout
result_sha: null
observed_at: 2026-08-14T10:00:00Z
recorded_epoch: $((1210 + 20 + 1000))
recorded_at: 2026-08-14T10:00:00Z
---
Termination confirmed with the transport by \`job_id\`, and the worktree observed clean and
stationary at the assigned base. \`ack_ref: null\` because no acknowledgement was ever captured —
that absence is the trigger, not an omission.
REC

rec 0020-close.md <<REC
---
protocol_version: 2
record_seq: 0020
kind: close
topic_id: $TOPIC_ID
recorded_epoch: 3000
recorded_at: 2026-08-14T10:00:00Z
close_id: close-0001
final_accepted_sha: $C1
---
Charter disposition: the app text was improved (turn 1) and reviewed (turn 2). Turn 3 was fenced on
an ACK timeout and terminated without landing anything, so the accepted SHA is unchanged from turn 1.

Follow-ups: none.
REC

git -C "$T" add -A && gc "$T" "records for $TOPIC_ID" || die "cannot commit the records"

# --- close postconditions, performed for real ------------------------------------------------------------
git -C "$R" worktree remove --force "$W" || die "cannot remove the session worktree"
/bin/bash "$EX/../scripts/validate.sh" --render "$T" || die "render failed"
git -C "$T" add -A && gc "$T" "render THREAD.md at close" || die "cannot commit THREAD.md"

# --- prove it before shipping it ---------------------------------------------------------------------------
OUT="$("/bin/bash" "$EX/../scripts/validate.sh" --check "$T" 2>&1)" || die "the built example does not validate:
$OUT"
printf '%s\n' "$OUT" | grep -Fx 'classification: CLOSED' >/dev/null \
  || die "the built example is not CLOSED:
$OUT"

# --- bundle -------------------------------------------------------------------------------------------------
git -C "$R" bundle create -q "$EX/work-repo.bundle" --all || die "cannot bundle the work repo"
git -C "$T" bundle create -q "$EX/topic-repo.bundle" --all || die "cannot bundle the record repo"
printf '%s\n' "$C1" >"$EX/FINAL_SHA"
printf '%s\n' "$(git -C "$T" symbolic-ref --short HEAD)" >"$EX/TOPIC_BRANCH"
printf '%s\n' "$BRANCH" >"$EX/WORK_BRANCH"
cat >"$EX/PATHS.env" <<ENV
ROOT='$ROOT'
R='$R'
W='$W'
T='$T'
ENV

# The SHIPPED artifacts are the bundles. The live directories are removed so the first rehydration
# starts from nothing: rehydrate.sh refuses to delete a directory without its ownership marker, and
# leaving unmarked leftovers here would wedge every later run behind that guard.
case "$ROOT" in
  /tmp/ap-v2-example.?*) rm -rf "$R" "$T" "$W" ;;
  *) die "refusing to clean $ROOT" ;;
esac

printf 'built %s -> CLOSED\n' "$TOPIC_ID"
printf '  final accepted sha: %s\n' "$C1"
printf '  root:               %s\n' "$ROOT"
