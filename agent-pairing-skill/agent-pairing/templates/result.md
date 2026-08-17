---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: result
topic_id: {{TOPIC_ID}}
turn_id: {{TURN_ID}}
attempt_id: {{ATTEMPT_ID}}
turn_kind: {{TURN_KIND}}
assignment_ref: {{ASSIGNMENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
ack_ref: {{ACK_REF}}
result_capture_ref: {{RESULT_CAPTURE_REF}}
status: {{STATUS}}
reason: {{REASON}}
result_sha: {{RESULT_SHA}}
observed_at: {{OBSERVED_AT}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
---
`ack_ref` and `result_capture_ref` are what make a terminal status accountable to evidence rather
than to the primary's memory of the turn.

A **VERIFIED** result requires a valid ACK and a matching capture. There is no VERIFIED without
proof that the work was delivered and that the report bytes are the ones the participant finalized.

`ack_ref: null` is legal only for a failure result in one of three situations, each of which is a
case where no acknowledgement could exist:

- an explicit preflight decline,
- transport loss,
- a fenced result-before-ACK.

It never implies an ACK and never becomes one. The protocol does not synthesize an
"implied-at-result" acknowledgement.

## Verbatim agent output
The participant's report bytes live in `artifacts/tTTTT-aAA/report.md`, committed with the
`result-capture` record, and are referenced here rather than pasted. That file is an opaque byte
boundary; this section holds only what the primary needs inline. Fence any inline excerpt with one
more backtick than the longest run in it, with a minimum fence of four.

## Verification
Record commands and captured output, including failed commands.

## Primary commentary (separate)
Keep interpretation separate from the verbatim report and verification evidence.
