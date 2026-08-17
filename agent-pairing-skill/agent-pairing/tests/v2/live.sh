#!/bin/bash
# bash 3.2 compatible. Sourced by tests/v2/run-tests.sh — never executed directly.
#
# Builds LIVE v2 topics: a real work repo, a real session worktree, and a real record repository,
# all at absolute paths that only exist at run time.
#
# Static fixture directories cannot express these cases. `session_worktree` and
# `work_repo_common_dir` are absolute paths pinned in the committed TOPIC.md, and the checks Task 8
# ports from v1 — worktree registration, branch identity, tree cleanliness, commit trailers, scope,
# accepted-SHA advance, close equivalence — all read the actual repository. A fixture whose paths
# point nowhere exercises the "unavailable evidence" branch and nothing else.

# Commit with a fixed identity so nothing depends on the machine's git config.
v2_gc() { git -C "$1" -c user.email=v2@test -c user.name=v2-test commit -qm "$2"; }
v2_gcf() { git -C "$1" -c user.email=v2@test -c user.name=v2-test commit -q -F "$2"; }

V2_LIVE_T=""   # record repo of the most recent build
V2_LIVE_W=""   # session worktree
V2_LIVE_R=""   # work repo
V2_LIVE_B0=""  # pinned base
V2_LIVE_C1=""  # the first turn's commit

# Append one record to the live topic, given its full front-matter body on stdin.
v2_rec() { # <topic-dir> <basename>
  cat >"$1/turns/$2"
}

v2_live_topic_md() { # <topic-dir> <topic-id> <base-sha> <base-ref> <branch> <worktree> <common-dir>
  cat >"$1/TOPIC.md" <<EOF
---
protocol_version: 2
topic_id: $2
participant_start_mode: owner-manual
participant_selection_source: initial-prompt
base_sha: $3
base_ref: $4
session_branch: $5
session_worktree: $6
work_repo_common_dir: $7
---

# $2

## Charter
## Preconditions
## Registry
## DECISIONS
## Onboarding
EOF
}

v2_live_admission() { # <topic-dir> <topic-id> <seq> <epoch>
  v2_rec "$1" "$3-admission.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: admission
topic_id: $2
recorded_epoch: $4
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
Participant admitted.
EOF
}

v2_live_assignment() { # <topic-dir> <topic-id> <seq> <epoch> <turn> <attempt> <kind> <base> <branch> <wt> <cdir> <scope>
  v2_rec "$1" "$3-t$5-a$6-assignment.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: assignment
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
base_sha: $8
session_branch: $9
session_worktree: ${10}
work_repo_common_dir: ${11}
scope: ${12}
agent_id: participant-a
admission_ref: 0001-admission.md
ack_timeout_seconds: 600
work_timeout_seconds: 3600
verification_profile_id: null
recorded_epoch: $4
recorded_at: 2026-08-14T10:00:10Z
---
Goal: the assigned outcome.
EOF
}

v2_live_intent() { # <topic-dir> <topic-id> <seq> <epoch> <turn> <attempt> <kind> <assignment-ref> <token> <expected-dispatch>
  v2_rec "$1" "$3-t$5-a$6-intent.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: intent
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
assignment_ref: $8
idempotency_token: $9
admission_ref: 0001-admission.md
expected_dispatch_ref: ${10}
receipt_commit_timeout_seconds: 300
receipt_commit_by_epoch: $(( $4 + 300 ))
recorded_epoch: $4
recorded_at: 2026-08-14T10:00:20Z
---
Committed dispatch authorization.
EOF
}

v2_live_dispatch() { # <topic-dir> <topic-id> <seq> <epoch> <turn> <attempt> <kind> <assignment-ref> <intent-ref> <job>
  v2_rec "$1" "$3-t$5-a$6-dispatch.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: dispatch
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
assignment_ref: $8
transport: human-relay
job_id: ${10}
intent_ref: $9
admission_ref: 0001-admission.md
dispatched_epoch: $4
ack_due_epoch: $(( $4 + 600 ))
receipt_source: direct
recorded_epoch: $4
recorded_at: 2026-08-14T10:00:30Z
---
Captured dispatch receipt.
EOF
}

v2_live_ack() { # <topic-dir> <topic-id> <seq> <epoch> <turn> <attempt> <kind> <a-ref> <i-ref> <d-ref> <job> <token> <base>
  v2_rec "$1" "$3-t$5-a$6-ack.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: ack
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
assignment_ref: $8
intent_ref: $9
dispatch_ref: ${10}
admission_ref: 0001-admission.md
job_id: ${11}
idempotency_token: ${12}
observed_head: ${13}
preflight_clean: true
relayed_base_sha: null
ack_evidence_class: human-relayed
ack_captured_epoch: $4
work_due_epoch: $(( $4 + 3600 ))
recorded_epoch: $4
recorded_at: 2026-08-14T10:00:40Z
---
Acknowledgement captured.
EOF
}

# Writes the artifact AND the capture record, computing the manifest from the bytes it just wrote.
v2_live_capture() { # <topic-dir> <topic-id> <seq> <epoch> <turn> <attempt> <kind> <a-ref> <d-ref> <ack-ref> <text>
  mkdir -p "$1/artifacts/t$5-a$6"
  printf '%s\n' "${11}" >"$1/artifacts/t$5-a$6/report.md"
  v2_lc_a="$1/artifacts/t$5-a$6/report.md"
  v2_lc_bc="$(LC_ALL=C wc -c <"$v2_lc_a" | tr -d ' ')"
  v2_lc_sh="$(shasum -a 256 "$v2_lc_a" | awk '{print $1}')"
  v2_rec "$1" "$3-t$5-a$6-result-capture.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: result-capture
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
assignment_ref: $8
dispatch_ref: $9
ack_ref: ${10}
artifact_ref: artifacts/t$5-a$6/report.md
author_byte_count: $v2_lc_bc
author_sha256: $v2_lc_sh
observed_byte_count: $v2_lc_bc
observed_sha256: $v2_lc_sh
encoding: utf-8
trailing_newline: present
captured_epoch: $4
recorded_epoch: $4
recorded_at: 2026-08-14T10:00:50Z
---
Exact participant bytes.
EOF
}

v2_live_result() { # <topic> <id> <seq> <epoch> <turn> <attempt> <kind> <a-ref> <d-ref> <ack-ref> <cap-ref> <status> <reason> <sha>
  v2_lr_reason=""
  [ -n "${13}" ] && v2_lr_reason="reason: ${13}
"
  v2_rec "$1" "$3-t$5-a$6-result.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: result
topic_id: $2
turn_id: $5
attempt_id: $6
turn_kind: $7
assignment_ref: $8
dispatch_ref: $9
ack_ref: ${10}
result_capture_ref: ${11}
status: ${12}
${v2_lr_reason}result_sha: ${14}
observed_at: 2026-08-14T10:01:00Z
recorded_epoch: $4
recorded_at: 2026-08-14T10:01:00Z
---
Result.
EOF
}

v2_live_question() { # <topic> <id> <seq> <epoch> <question-id> <blocks>
  v2_rec "$1" "$3-owner-question.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: owner-question
topic_id: $2
recorded_epoch: $4
recorded_at: 2026-08-14T11:00:00Z
question_id: $5
blocks: $6
---
The evidence, the uncertainty, and the exact decision required.
EOF
}

v2_live_answer() { # <topic> <id> <seq> <epoch> <question-ref> <action> [extra]
  v2_la_extra=""
  [ -n "${7:-}" ] && v2_la_extra="$7
"
  v2_rec "$1" "$3-owner-answer.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: owner-answer
topic_id: $2
recorded_epoch: $4
recorded_at: 2026-08-14T11:05:00Z
question_ref: $5
action: $6
${v2_la_extra}---
Verbatim owner answer.
EOF
}

v2_live_close() { # <topic> <id> <seq> <epoch> <close-id> <final-sha>
  v2_rec "$1" "$3-close.md" <<EOF
---
protocol_version: 2
record_seq: $3
kind: close
topic_id: $2
recorded_epoch: $4
recorded_at: 2026-08-14T12:00:00Z
close_id: $5
final_accepted_sha: $6
---
Every charter item disposition and every follow-up.
EOF
}

# --- the builder ---------------------------------------------------------------------------------------
#
# v2_make_live <mode> -> prints the topic directory
#
# Every mode shares the same spine: a seeded work repo, a registered session worktree on
# `pair/live`, an admitted participant, and turn 1 carrying assignment -> intent -> dispatch -> ack
# -> capture -> VERIFIED result whose `result_sha` is a real commit with real trailers. Modes then
# diverge to produce exactly one classification.
v2_make_live() { # <mode>
  v2_ml_mode="$1"
  v2_ml_b="$(mktemp -d "$V2_TMP/live.XXXXXX")" || { echo "FATAL: temp allocation failed" >&2; return 1; }
  [ -n "$v2_ml_b" ] && [ -d "$v2_ml_b" ] || { echo "FATAL: temp allocation produced no directory" >&2; return 1; }
  case "$v2_ml_b" in "$V2_TMP"/live.?*) ;; *) echo "FATAL: $v2_ml_b escaped $V2_TMP" >&2; return 1 ;; esac

  R="$v2_ml_b/repo"; W="$v2_ml_b/wt"; T="$v2_ml_b/topic"
  mkdir -p "$R" && git -C "$R" init -q || return 1
  ( cd "$R" && printf 'a\n' >a.txt && git add -A ) && v2_gc "$R" seed || return 1
  B0="$(git -C "$R" rev-parse HEAD)" || return 1
  BREF="refs/heads/$(git -C "$R" symbolic-ref --short HEAD)"
  git -C "$R" worktree add -q "$W" -b pair/live "$B0" || return 1

  # Turn 1's real commit, carrying the three attribution trailers as ONE final paragraph.
  ( cd "$W" && mkdir -p src && printf 'x\n' >src/x.txt && git add -A ) || return 1
  printf 'work\n\nAgent-Pairing-Topic: live\nAgent-Pairing-Turn: 0001\nAgent-Pairing-Attempt: 01\n' \
    >"$v2_ml_b/msg1"
  v2_gcf "$W" "$v2_ml_b/msg1" || return 1
  C1="$(git -C "$W" rev-parse HEAD)" || return 1

  mkdir -p "$T/turns" && git -C "$T" init -q || return 1
  v2_live_topic_md "$T" live "$B0" "$BREF" pair/live "$W" "$R/.git"
  v2_live_admission "$T" live 0001 1000

  v2_ml_A=0002-t0001-a01-assignment.md
  v2_ml_I=0003-t0001-a01-intent.md
  v2_ml_D=0004-t0001-a01-dispatch.md
  v2_ml_K=0005-t0001-a01-ack.md
  v2_ml_P=0006-t0001-a01-result-capture.md

  case "$v2_ml_mode" in
    never-dispatched)
      v2_live_assignment "$T" live 0002 1010 0001 01 NORMAL "$B0" pair/live "$W" "$R/.git" "src/" ;;
    dispatch-unknown|owner-action-pending|awaiting-owner-attempt)
      v2_live_assignment "$T" live 0002 1010 0001 01 NORMAL "$B0" pair/live "$W" "$R/.git" "src/"
      v2_live_intent "$T" live 0003 1020 0001 01 NORMAL "$v2_ml_A" tok-1 "$v2_ml_D" ;;
    *)
      v2_live_assignment "$T" live 0002 1010 0001 01 NORMAL "$B0" pair/live "$W" "$R/.git" "src/"
      v2_live_intent "$T" live 0003 1020 0001 01 NORMAL "$v2_ml_A" tok-1 "$v2_ml_D"
      v2_live_dispatch "$T" live 0004 1030 0001 01 NORMAL "$v2_ml_A" "$v2_ml_I" job-1
      v2_live_ack "$T" live 0005 1040 0001 01 NORMAL "$v2_ml_A" "$v2_ml_I" "$v2_ml_D" job-1 tok-1 "$B0"
      v2_live_capture "$T" live 0006 1050 0001 01 NORMAL "$v2_ml_A" "$v2_ml_D" "$v2_ml_K" 'All checks passed.'
      v2_live_result "$T" live 0007 1060 0001 01 NORMAL "$v2_ml_A" "$v2_ml_D" "$v2_ml_K" "$v2_ml_P" VERIFIED '' "$C1" ;;
  esac

  case "$v2_ml_mode" in
    idle) : ;;
    working)
      # A second turn, acknowledged and still running. A dirty tree under a live open attempt is
      # EXPECTED — that is work in progress, not drift.
      v2_live_assignment "$T" live 0008 1100 0002 01 NORMAL "$C1" pair/live "$W" "$R/.git" "src/"
      v2_live_intent "$T" live 0009 1110 0002 01 NORMAL 0008-t0002-a01-assignment.md tok-2 0010-t0002-a01-dispatch.md
      v2_live_dispatch "$T" live 0010 1120 0002 01 NORMAL 0008-t0002-a01-assignment.md 0009-t0002-a01-intent.md job-2
      v2_live_ack "$T" live 0011 1130 0002 01 NORMAL 0008-t0002-a01-assignment.md 0009-t0002-a01-intent.md 0010-t0002-a01-dispatch.md job-2 tok-2 "$C1"
      printf 'in progress\n' >"$W/src/wip.txt" ;;
    awaiting-owner)
      v2_live_question "$T" live 0008 1100 q-1 general ;;
    awaiting-owner-attempt)
      v2_live_question "$T" live 0004 1100 q-1 t0001-a01 ;;
    owner-action-pending)
      v2_live_question "$T" live 0004 1100 q-1 t0001-a01
      v2_live_answer "$T" live 0005 1110 q-1 dispatch-job-found "transport: human-relay
job_id: job-recovered" ;;
    remediation)
      # A REJECTED commit left at the branch tip: the accepted SHA did not advance to it, so the
      # tree must be brought back append-only rather than reset.
      ( cd "$W" && printf 'bad\n' >src/bad.txt && git add -A ) || return 1
      printf 'rejected\n\nAgent-Pairing-Topic: live\nAgent-Pairing-Turn: 0002\nAgent-Pairing-Attempt: 01\n' \
        >"$v2_ml_b/msg2"
      v2_gcf "$W" "$v2_ml_b/msg2" || return 1
      C2="$(git -C "$W" rev-parse HEAD)" || return 1
      v2_live_assignment "$T" live 0008 1100 0002 01 NORMAL "$C1" pair/live "$W" "$R/.git" "src/"
      v2_live_intent "$T" live 0009 1110 0002 01 NORMAL 0008-t0002-a01-assignment.md tok-2 0010-t0002-a01-dispatch.md
      v2_live_dispatch "$T" live 0010 1120 0002 01 NORMAL 0008-t0002-a01-assignment.md 0009-t0002-a01-intent.md job-2
      v2_live_ack "$T" live 0011 1130 0002 01 NORMAL 0008-t0002-a01-assignment.md 0009-t0002-a01-intent.md 0010-t0002-a01-dispatch.md job-2 tok-2 "$C1"
      v2_live_capture "$T" live 0012 1140 0002 01 NORMAL 0008-t0002-a01-assignment.md 0010-t0002-a01-dispatch.md 0011-t0002-a01-ack.md 'Out of scope.'
      v2_live_result "$T" live 0013 1150 0002 01 NORMAL 0008-t0002-a01-assignment.md 0010-t0002-a01-dispatch.md 0011-t0002-a01-ack.md 0012-t0002-a01-result-capture.md REJECTED out-of-scope-changes "$C2" ;;
    drift)
      # A commit at the tip that NO record explains. Not remediation — nothing in the history says
      # where it came from, so the only safe move is to stop and ask.
      ( cd "$W" && printf 'mystery\n' >src/mystery.txt && git add -A ) || return 1
      v2_gc "$W" "unexplained" || return 1 ;;
    residue)
      printf 'residue\n' >"$W/src/residue.txt" ;;
    closing)
      # The close record exists but the worktree is still registered, so the postconditions are not
      # yet satisfied.
      v2_live_close "$T" live 0008 1200 close-0001 "$C1" ;;
    closed)
      v2_live_close "$T" live 0008 1200 close-0001 "$C1" ;;
  esac

  git -C "$T" add -A && v2_gc "$T" records || return 1

  if [ "$v2_ml_mode" = closed ]; then
    # The close postconditions, performed for real: the worktree is removed and deregistered, the
    # branch stands at the final accepted SHA, and THREAD.md is committed saying so.
    git -C "$R" worktree remove --force "$W" >/dev/null 2>&1 || return 1
    printf 'GENERATED — do not edit\nstatus: CLOSED\n\n' >"$T/THREAD.md"
    git -C "$T" add -A && v2_gc "$T" thread || return 1
  fi

  V2_LIVE_T="$T"; V2_LIVE_W="$W"; V2_LIVE_R="$R"; V2_LIVE_B0="$B0"; V2_LIVE_C1="$C1"
  printf '%s\n' "$T"
}

# Assert a live mode's exact classification.
v2_expect_live() { # <name> <mode> <classification>
  v2_el_n="$1" v2_el_m="$2" v2_el_c="$3"
  : >"$V2_OUT"
  v2_el_t="$(v2_make_live "$v2_el_m")" || { v2_nok "$v2_el_n" "cannot build live mode '$v2_el_m'"; return; }
  "$V2_VALIDATE" --check "$v2_el_t" >"$V2_OUT" 2>&1
  v2_el_rc=$?
  if grep -Fx "classification: $v2_el_c" "$V2_OUT" >/dev/null; then
    v2_ok "$v2_el_n"
  else
    v2_nok "$v2_el_n" "expected 'classification: $v2_el_c' (rc $v2_el_rc); got: $(grep -m1 -E '^(classification|VIOLATION|FATAL)' "$V2_OUT")"
  fi
}
