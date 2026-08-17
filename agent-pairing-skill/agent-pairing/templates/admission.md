---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: admission
topic_id: {{TOPIC_ID}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
admission_id: {{ADMISSION_ID}}
agent_id: {{AGENT_ID}}
join_mode: {{JOIN_MODE}}
transport: {{TRANSPORT}}
capability: {{CAPABILITY}}
worktree_visible: {{WORKTREE_VISIBLE}}
durable_address_kind: {{DURABLE_ADDRESS_KIND}}
durable_address: {{DURABLE_ADDRESS}}
searchability: {{SEARCHABILITY}}
token_search_recipe_ref: {{TOKEN_SEARCH_RECIPE_REF}}
report_channel: {{REPORT_CHANNEL}}
ack_evidence_class: {{ACK_EVIDENCE_CLASS}}
receipt_commit_timeout_seconds: {{RECEIPT_COMMIT_TIMEOUT_SECONDS}}
default_ack_timeout_seconds: {{DEFAULT_ACK_TIMEOUT_SECONDS}}
---
Participant readiness and the transport contract this topic's assignments bind to.

An admission is the ONLY proof that a participant exists. Selecting `owner-manual` at OPEN is not
admission: the topic stays `AWAITING_PARTICIPANT`, with no assignment, no intent, no ACK budget and
no work budget, until the owner confirms the participant joined and supplies the durable address.

Field notes — each of these is validated, not documentation:

- `join_mode`: `primary-spawn` or `owner-manual`, matching how the participant actually arrived.
- `capability`: `commits`, `writes-repo-only`, or `read-only`.
  `commits` is the only value that admits a participant-authored landed commit, and it requires
  `worktree_visible: true`. `writes-repo-only` admits visible uncommitted changes or a relay
  `patch.diff`, never a participant-authored `result_sha`. `read-only` is report-only: no landed
  commit, no worktree modification, no relay patch.
- `worktree_visible`: `true` requires every ACK to carry `observed_head` and `preflight_clean: true`.
  `false` requires both to be null and binds the ACK with `relayed_base_sha` instead.
- `durable_address_kind`: `session-id`, `job-id`, or `human-relay`. A monitor, waiter, or foreground
  polling handle is NEVER a durable address — it names a watcher, not the job, and cannot be used to
  find the job again after a crash.
- `durable_address`: never contains a credential.
- `searchability`: `searchable` requires a concrete token-search recipe in `RUNBOOK.md` and a
  non-null `token_search_recipe_ref`. `unsearchable` requires the recipe reference to be the literal
  `null`, and means replay goes directly to one owner question rather than pretending a search
  happened.
- `report_channel`: `transport-output` or `human-relay`. Participant reporting never updates Git
  refs and never uses Git notes.
- `ack_evidence_class`: `transport-attested` or `human-relayed`. Manual pairing normally declares
  `human-relayed`; it does not weaken the per-turn ACK requirement.
- `receipt_commit_timeout_seconds` / `default_ack_timeout_seconds`: positive integers. The ACK
  timeout is a DEFAULT — each assignment materializes its own value so replay never depends on
  mutable configuration.

Any change to transport, address, capability, visibility, searchability, report channel, or evidence
class requires a NEW admission record with a new `admission_id`. Editing an admission in place is
not append-only, and an assignment binds one exact `admission_ref`.
