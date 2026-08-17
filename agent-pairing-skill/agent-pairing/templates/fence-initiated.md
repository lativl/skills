---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: fence-initiated
topic_id: {{TOPIC_ID}}
turn_id: {{TURN_ID}}
attempt_id: {{ATTEMPT_ID}}
turn_kind: {{TURN_KIND}}
trigger: {{TRIGGER}}
assignment_ref: {{ASSIGNMENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
ack_ref: {{ACK_REF}}
job_id: {{JOB_ID}}
due_epoch: {{DUE_EPOCH}}
observed_epoch: {{OBSERVED_EPOCH}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
---
The durable timeout boundary. **Commit this record BEFORE asking the transport to terminate the
job.**

A timeout comparison on its own changes nothing. Noticing that a due epoch has passed is an
observation; this record is the only thing that turns it into a state. That ordering is what makes a
timeout replayable: a primary that crashes between "noticed" and "terminated" leaves either no fence
(nothing happened) or a committed fence (the boundary is in the history), never an unrecorded
termination.

`trigger` is exactly `ack-timeout` or `work-timeout`. **`reason` is not an accepted alias.** Two
spellings of one field is how one of them stops being checked.

| `trigger` | `due_epoch` must be | `ack_ref` |
| --- | --- | --- |
| `ack-timeout` | the receipt's `ack_due_epoch` | `null` — there is no ACK; that is why the fence exists |
| `work-timeout` | the ACK's `work_due_epoch` | the ACK whose budget expired |

`observed_epoch` is when you looked, and it may not precede `due_epoch` — a fence claiming it
observed an expiry before the expiry could have happened is a fence that fired early.

After this record commits:

- A late ACK, capture, result, or landed commit is an **observation against the boundary**, recorded
  as a `late` record. It is preserved as evidence.
- No late event cancels the fence or reopens the attempt.
- **Retry stays forbidden** until direct termination evidence or an owner-materialized resolution
  ends the attempt. Missing ACK proves only that no acknowledgement was captured — never that the
  participant is dead, and never that redispatch is safe.
- A clean stationary attempt may then terminate `ABORTED: ack-timeout` or `ABORTED: work-timeout`
  once termination is confirmed. A landed commit is rejected and quarantined; residue enters
  `UNRECORDED_DRIFT`.
