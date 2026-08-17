---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: ack
topic_id: {{TOPIC_ID}}
turn_id: {{TURN_ID}}
attempt_id: {{ATTEMPT_ID}}
turn_kind: {{TURN_KIND}}
assignment_ref: {{ASSIGNMENT_REF}}
intent_ref: {{INTENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
admission_ref: {{ADMISSION_REF}}
job_id: {{JOB_ID}}
idempotency_token: {{IDEMPOTENCY_TOKEN}}
observed_head: {{OBSERVED_HEAD}}
preflight_clean: {{PREFLIGHT_CLEAN}}
relayed_base_sha: {{RELAYED_BASE_SHA}}
ack_evidence_class: {{ACK_EVIDENCE_CLASS}}
ack_captured_epoch: {{ACK_CAPTURED_EPOCH}}
work_due_epoch: {{WORK_DUE_EPOCH}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
---
The participant's acknowledgement, captured by the primary after the participant observed the
COMMITTED dispatch receipt.

This record is the protocol's only evidence that the work was actually delivered. A primary-authored
receipt proves that the primary wrote something; it proves nothing about receipt. The motivating v1
record contained a receipt, a dead listener, and no way to tell the two apart.

**The work budget starts here** — at `ack_captured_epoch`, not when the receipt was written and not
when the participant first saw a prompt. `work_due_epoch` must equal
`ack_captured_epoch + work_timeout_seconds` from the assignment.

Every reference must match the exact committed predecessor: the assignment, its intent, that
attempt's receipt, and the admission the assignment binds. `job_id` is the receipt's value verbatim
and `idempotency_token` is the intent's.

The preflight evidence depends on the admitted visibility, and the two shapes are mutually exclusive:

| `worktree_visible` | `observed_head` | `preflight_clean` | `relayed_base_sha` |
| --- | --- | --- | --- |
| `true` | the assignment's `base_sha` | `true` | `null` |
| `false` | `null` | `null` | the assignment's `base_sha` |

A visible participant ran `git -C SESSION_WORKTREE rev-parse HEAD` and
`git -C SESSION_WORKTREE status --porcelain` and reports what it saw. An invisible participant did
not look, so claiming an observation would be a false claim; it echoes the assigned base to bind the
relay input, and the primary separately verifies that the shared worktree is clean and stationary
before capturing the ACK.

Null values are the literal scalar `null`, never an empty value.

An invalid first response is preserved verbatim and is **never rewritten into a valid ACK**. Under a
clean stationary worktree it terminates as `REJECTED: ack-preflight-failed`; a moved tip or residue
uses the quarantine and drift rules instead.
