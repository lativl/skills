# Investigation: Agent-pairing delivery and protocol gaps

## Hand-off Brief

1. **What happened.** The committed record confirms intent-to-receipt gaps of 22m43s and 9h05m36s; the latter receipt arrived 7h42m20s after its absolute deadline. The dead-listener explanation is preserved as participant prose but never became a structured delivery-failure transition.
2. **Where the case stands.** Concluded: the protocol root cause is a conflation of primary-authored dispatch receipt with participant-observed delivery, compounded by unbounded dispatch latency, working-tree polling, and no durable fence boundary.
3. **What's needed next.** Approve or revise the reviewed v2 direction, then write an implementation plan for a versioned ACK handshake, two clocks, committed-only receipt consumption, transport admission, and author-finalized report manifests.

## Case Info

| Field | Value |
| --- | --- |
| Ticket | Work-2kwj |
| Date opened | 2026-08-14 |
| Status | Concluded |
| System | macOS Darwin 25.5.0 arm64; git 2.50.1; bash 3.2.57; Claude Code 2.1.232 |
| Evidence sources | Pairing record, validator classification, agent-side retrospective, installed protocol packages, repository history |

## Problem Statement

The user reports that ten otherwise successful sequential pairing turns hid two delivery stalls, one lasting more than nine hours, because a dispatch receipt proves only that the primary recorded an attempted dispatch—not that the participant received it. The proposed protocol should make delivery observable, prevent effective deadlines from expiring before receipt, admit only transports whose limitations are explicit, bind verification to the project environment, and close secondary report-integrity and review-tracking gaps without weakening the existing safety gates.

## Evidence Inventory

| Source | Status | Notes |
| --- | --- | --- |
| `~/.claude/agent-pairing/invoicing-platform-integration-implementation-review/turns/` | Available | 40 committed records across ten turns; independently inventoried and timestamp-reconciled. |
| Pairing validator at record HEAD `9c343ed` | Available | Read-only check reports accepted SHA `be35652`, no open attempt, and `classification: IDLE`. |
| Agent-side retrospective in Claude scratchpad | Partial | Contains record-derived arithmetic and session-transcript observations; transcript itself is not yet available as a durable source. |
| `~/.codex/skills/agent-pairing` and `~/.claude/skills/agent-pairing` | Available | Both roots contain 100 regular files and are path/byte/mode equivalent; exact v2 change surfaces are mapped. |
| Final and captured t0008 report byte streams | Available | Captured: 15,233 bytes; final: 16,225 bytes; differing SHA-256 values mechanically confirm stale capture. |
| Sanitized Opus review | Available | Tools-disabled external design review returned `APPROVE_WITH_CHANGES`; findings and dispositions are recorded separately. |
| Durable transport delivery log | Missing | The pairing record does not contain one. |
| Persistent monitor lifecycle log | Partial | The committed t0008 report says the monitor was killed, but no independent lifecycle event or structured pairing record confirms the process state. |

## Investigation Backlog

| # | Path to Explore | Priority | Status | Notes |
| - | --- | --- | --- | --- |
| 1 | Recalculate all assignment, intent, receipt, and result intervals | High | Done | Record timestamps independently confirm every reported interval. |
| 2 | Verify record-kind counts and absence of owner/late/abort records | High | Done | Exactly ten of each core kind; no structured failure transition. |
| 3 | Map current validator/state-machine changes needed for `ack` | High | Done | Schema, linkage, replay, resume, rendering, templates, tests, and participant instructions mapped. |
| 4 | Test deadline alternatives for append-only and legacy compatibility | High | Done | Receipt starts ACK budget; ACK starts work budget; epochs are normative; v1 is explicit legacy. |
| 5 | Grade secondary proposals and identify minimum coherent release | Medium | Done | Report integrity/channel and severity policy join v2.0; durable findings ledger is v2.1. |
| 6 | Obtain independent Opus review of the proposed design | High | Done | `APPROVE_WITH_CHANGES`; each finding accepted, revised, or rejected with rationale. |

## Timeline of Events

| Time | Event | Source | Confidence |
| --- | --- | --- | --- |
| 2026-08-13T13:36:30Z | First assignment in the reviewed ten-turn sequence was created. | Pairing record `turns/0001-t0001-a01-assignment.md:15` | Confirmed |
| 2026-08-13T15:05:37Z | t0006 intent was created. | Pairing record `turns/0022-t0006-a01-intent.md:10` | Confirmed |
| 2026-08-13T15:28:20Z | t0006 receipt was created 22m43s after intent. | Pairing record `turns/0023-t0006-a01-dispatch.md:11` | Confirmed |
| 2026-08-13T18:36:44Z | t0008 intent was created. | Pairing record `turns/0030-t0008-a01-intent.md:10` | Confirmed |
| 2026-08-13T20:00:00Z | t0008's absolute assignment deadline expired. | Pairing record `turns/0029-t0008-a01-assignment.md:13` | Confirmed |
| 2026-08-14T03:42:20Z | t0008 dispatch receipt was created, 9h05m36s after intent and 7h42m20s after deadline. | Pairing record `turns/0031-t0008-a01-dispatch.md:11` | Confirmed |
| 2026-08-14T03:58:17Z | t0008 result preserved the expired-deadline/dead-listener account as participant prose. | Pairing record `turns/0032-t0008-a01-result.md:34` | Confirmed |
| 2026-08-14T05:26:43Z | Final result in the reviewed sequence was created. | Pairing record `turns/0040-t0010-a01-result.md:13` | Confirmed |
| 2026-08-14 | Validator reports the topic clean and `IDLE` at accepted SHA `be35652`. | Local read-only validator run | Confirmed |

## Turn Metrics

All durations below are independently calculated from record fields. “Dispatch latency” is intent `recorded_at` to receipt `dispatched_at`; “work duration” is receipt `dispatched_at` to result `recorded_at`.

| Turn | Kind | Intent | Receipt | Result | Dispatch latency | Work duration | Deadline relation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| t0001 | NORMAL | 2026-08-13 13:36:30Z | 13:37:28Z | 13:38:49Z | 58s | 1m21s | Receipt 22m32s early |
| t0002 | REVIEW | 2026-08-13 14:06:13Z | 14:06:13Z | 14:28:43Z | 0s | 22m30s | Receipt 53m47s early |
| t0003 | NORMAL | 2026-08-13 14:40:04Z | 14:40:04Z | 14:41:21Z | 0s | 1m17s | Receipt 19m56s early |
| t0004 | REVIEW | 2026-08-13 14:42:03Z | 14:42:03Z | 14:49:14Z | 0s | 7m11s | Receipt 32m57s early |
| t0005 | NORMAL | 2026-08-13 15:02:52Z | 15:02:52Z | 15:05:30Z | 0s | 2m38s | Receipt 57m08s early |
| t0006 | REVIEW | 2026-08-13 15:05:37Z | 15:28:20Z | 15:32:37Z | 22m43s | 4m17s | Receipt 31m40s early |
| t0007 | NORMAL | 2026-08-13 18:34:09Z | 18:34:09Z | 18:36:30Z | 0s | 2m21s | Receipt 55m51s early |
| t0008 | REVIEW | 2026-08-13 18:36:44Z | 2026-08-14 03:42:20Z | 03:58:17Z | 9h05m36s | 15m57s | Receipt 7h42m20s late |
| t0009 | NORMAL | 2026-08-14 05:11:23Z | 05:11:23Z | 05:13:31Z | 0s | 2m08s | Receipt 48m37s early |
| t0010 | REVIEW | 2026-08-14 05:14:19Z | 05:16:10Z | 05:26:43Z | 1m51s | 10m33s | Receipt 2h43m50s early |

## Confirmed Findings

### Finding 1: Intent-to-receipt latency is not bounded by the current record grammar

**Evidence:** `turns/0022-t0006-a01-intent.md:10`, `turns/0023-t0006-a01-dispatch.md:11`, `turns/0030-t0008-a01-intent.md:10`, and `turns/0031-t0008-a01-dispatch.md:11`.

**Detail:** The record admits an intent followed by a dispatch receipt hours later. The assignment's absolute deadline is fixed before that unbounded interval.

### Finding 2: The state machine reconstructs no delivery failure even though result prose mentions one

**Evidence:** Kind inventory is ten assignments, ten intents, ten dispatch receipts, and ten results; `turns/0032-t0008-a01-result.md:34` contains the dead-listener account; validator output is `classification: IDLE`.

**Detail:** The retrospective overstates the silence: a turns-only reader can see both the timestamp gap and the participant's account. What replay cannot see is a structured `DISPATCH_UNKNOWN`, owner question, acknowledgement, listener-death, or fence transition.

### Finding 3: The live package cannot be edited safely while this topic remains open

**Evidence:** `RUNBOOK.md`, “Installing and updating this package”; retrospective `scratchpad/pairing-retrospective-and-proposals.md:257`.

**Detail:** Both runtime roots must remain on one coherent manual; this investigation and design do not modify either installed package.

### Finding 4: The participant consumed uncommitted record-working-tree state

**Evidence:** `turns/0024-t0006-a01-result.md:34` says receipt 0023 was untracked at participant start; `pair-with-primary/SKILL.md:57`–`63` polls with `ls` rather than reading record `HEAD`.

**Detail:** “Receipt means go” is not durable if the participant discovers the file before the receipt commit. The participant loop must poll and read committed Git objects.

### Finding 5: t0008's recorded report is mechanically stale

**Evidence:** Embedded report bytes are 15,233 with SHA-256 `69606590e0a22df69798049a8228c5fe5cea7d846289c40ae4187e2e248b8881`; the final report is 16,225 bytes with SHA-256 `db4bfba22c5c4ac8b3d14f53fd2efaf61498eea49138bca4c0df5c32ba322d60`.

**Detail:** The final report adds completeness evidence and two accuracy qualifications. Verdict and blocking status did not change, but “complete verbatim relay” is false.

### Finding 6: The monitor was not the durable job ID

**Evidence:** `turns/0023-t0006-a01-dispatch.md:9` names a monitor-based transport, line 10 stores the durable session UUID, and line 16 names the ephemeral monitor handle.

**Detail:** The proposal should forbid using ephemeral listeners as the delivery mechanism or durable address, but it should not claim the existing `job_id` field held the monitor ID.

### Finding 7: Participant reporting instructions contradict themselves

**Evidence:** `pair-with-primary/SKILL.md:105`–`113` mandates git notes; its lines 121–125 and live `TOPIC.md:95` forbid ref updates.

**Detail:** The report channel must be admitted per transport and projected into participant instructions from one source.

## Deduced Conclusions

### Deduction 1: Receipt and delivery must be modeled as separate events

**Based on:** Findings 1 and 2.

**Reasoning:** A receipt is written by the primary, while delivery is observable only when the participant returns evidence. Treating those events as one erases the exact failure mode under investigation.

**Conclusion:** Any coherent fix needs a participant-originated delivery acknowledgement or an equivalent transport-level proof that the primary can record.

### Deduction 2: ACK timeout is a fence trigger, not a fence

**Based on:** Finding 2 and the existing never-re-dispatch-into-uncertainty invariant.

**Reasoning:** Missing acknowledgement proves no participant liveness observation; it does not prove the job is dead. Retry still requires a terminal result after direct termination evidence or an owner-mediated resolution.

**Conclusion:** v2 needs a replay-visible `fence-initiated` boundary and the existing termination/owner ladder for both ACK and work expiry.

### Deduction 3: Work time must start at ACK

**Based on:** Finding 1 and the independently measured 4m17s–22m30s review durations.

**Reasoning:** Receipt-anchoring prevents pre-dispatch expiry but still charges undelivered time against work. ACK-anchoring separates the short delivery budget from the actual execution budget.

**Conclusion:** Dispatch starts `ack_timeout_seconds`; primary receipt of ACK starts `work_timeout_seconds`.

## Hypothesized Paths

### Hypothesis 1: A dead persistent monitor caused the nine-hour t0008 gap

**Status:** Open

**Theory:** The primary addressed the turn through an ephemeral monitor that was killed during idle; delivery resumed only after the owner reactivated the terminal.

**Supporting indicators:** The retrospective identifies task `bwxl318e3`, `status: killed`, and a later `manual-fable-terminal-resume` receipt.

**Would confirm:** A durable session transcript or task lifecycle log linking that monitor death, the attempted dispatch, and the later resume.

**Would refute:** Evidence that the monitor remained live and received the dispatch during the gap.

**Resolution:** The explanation is durably present at `turns/0032-t0008-a01-result.md:34`; no independent monitor lifecycle record exists, so it cannot be promoted beyond participant-reported evidence.

### Hypothesis 2: A receipt-derived work deadline is sufficient

**Status:** Refuted

**Theory:** Storing relative budgets on assignment and deriving the work deadline from the dispatch receipt is sufficient.

**Supporting indicators:** A committed receipt already supplies a protocol timestamp before participant work should begin.

**Would confirm:** A state-machine design with deterministic replay, crash recovery, legacy handling, and no notification-before-commit race.

**Would refute:** A race in which transport notification necessarily precedes the durable receipt or the participant cannot bind its acknowledgement to the receipt clock.

**Resolution:** It prevents pre-dispatch expiry but charges missing-delivery time to work. The reviewed design uses receipt for ACK due and ACK receipt for work due.

## Missing Evidence

| Gap | Impact | How to Obtain |
| --- | --- | --- |
| Durable lifecycle evidence for the persistent monitor | Determines whether the claimed transport root cause is Confirmed or remains Hypothesized | Preserve/export the original Claude task transcript or notification log. |
| Durable owner “check again” messages | Determines the exact out-of-band recovery sequence | Export the primary and participant session transcripts. |
| Package source-of-truth location | Needed before eventual implementation | Identify the editable source package; installed roots are deployment targets, not safe working copies. |

## Source Code Trace

| Element | Detail |
| --- | --- |
| Error origin | Protocol transition from committed intent to primary-authored dispatch receipt immediately becomes `OPEN (dispatched)` with no participant-originated liveness state. |
| Trigger | A transport accepts or appears to accept a dispatch while the participant/listener is not actually reachable. |
| Condition | Unbounded intent-to-receipt or receipt-to-delivery latency combined with absolute assignment deadlines and no durable acknowledgement. |
| Related files | Primary `SKILL.md`/`RUNBOOK.md`; TOPIC, assignment, admission, dispatch, ACK, fence, result, and onboarding templates; `scripts/validate.sh`; tests/fixtures/examples; participant `pair-with-primary/SKILL.md`. |

## Conclusion

**Confidence:** High for the protocol defect; Medium for the dead-monitor causal event

The protocol defect is Confirmed: a primary-authored receipt is treated as dispatched state without participant acknowledgement, absolute deadlines precede an unbounded gap, and the participant loop can see uncommitted receipts. The dead-monitor cause is preserved as participant evidence but not independently corroborated. A sanitized, tools-disabled Opus review approved the ACK/two-clock direction with changes: bounded committed-receipt polling, explicit ACK evidence class, author-side report manifests, and a durable fence boundary.

## Recommended Next Steps

### Fix direction

Adopt a v2 protocol with explicit versioning, append-only transport admission, `ack` and `fence-initiated` records, primary-stamped epoch clocks, committed-only participant reads, and author-finalized report integrity. Missing ACK initiates fencing but never authorizes retry. Manual relay ACK is labeled `human-relayed`, not claimed as transport proof. Keep capability in admission; bind ACK to admission/job/idempotency token and require `observed_head == assignment.base_sha`.

Legacy topics must not silently enter v2 because a version field is absent. Since separate topic repos share no cutover ancestry, the default v2 validator should reject missing version; a frozen, explicitly invoked v1 validator handles historical records. The current topic closes under v1 before either installed package changes.

Define BLOCKING/GATE/NONBLOCKING as review policy in v2.0 while keeping verdict binary; require every GATE to materialize in the project tracker. Add durable finding/disposition records and generated `FINDINGS.md` in v2.1.

### Diagnostic

The only remaining diagnostic gap is independent monitor lifecycle evidence. It is not required to justify the protocol fix because the timing, stale capture, uncommitted receipt consumption, and missing ACK state are already Confirmed.

## Reproduction Plan

Keep the historical v1 topic as a compatibility fixture. Add a v2 fixture with `ack_timeout_seconds: 600` and `work_timeout_seconds: 5400`: raw dispatch prompt at T0; receipt committed at T0+5s; ACK absent through due time; `fence-initiated` committed before termination request; no retry until terminal result. Twin fixtures cover ACK at T0+30s with work due anchored from ACK, result-before-ACK buffering, primary crash/resume, late ACK after fence, human-relayed evidence class, unsearchable transport owner question, stale report hash mismatch, and same-second non-decreasing epochs.

## Side Findings

- The main invoicing checkout already contains unrelated user changes; this investigation preserves them and will stage only its own artifacts.
- Opus's proposed cross-repository ancestry check for `observed_head` is invalid because worktree and pairing record are separate Git repositories; equality with assignment `base_sha` is the correct preflight gate.
- Opus's attempt-scoped worktree/ref fencing is a valid alternative architecture but not a v2 patch: it replaces the shared-baton model and is deferred to a separate v3 investigation.
