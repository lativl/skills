---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: owner-answer
topic_id: {{TOPIC_ID}}
question_ref: {{QUESTION_REF}}
action: {{ACTION}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
---
Verbatim owner answer. General actions need no extra keys. Dispatch resolution inserts `transport`
and `job_id` for `dispatch-job-found`, or `evidence` for confirmed absence/termination.
