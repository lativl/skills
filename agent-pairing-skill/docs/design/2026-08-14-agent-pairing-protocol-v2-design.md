# Agent-Pairing Protocol v2 Design

**Status:** Accepted 2026-08-14 after specification review; implementation may begin. Five review
findings were resolved inline (see `Review disposition`).

**Date:** 2026-08-14

**Scope:** `agent-pairing` primary package, `pair-with-primary` participant package, and their dual-runtime deployment

## Source evidence

This design implements the conclusions of:

- `../investigation/agent-pairing-delivery-protocol-investigation.md`
- `../investigation/agent-pairing-opus-review.md`

The motivating record showed intent-to-receipt delays of 22m43s and 9h05m36s. In the longer case,
the receipt was committed 7h42m20s after the assignment deadline. The participant later reported a
dead listener, but the replayable record contained no delivery acknowledgement, fence boundary, or
structured delivery failure. A separate report capture was also stale: the captured and final
reports had different byte counts and SHA-256 values.

## Problem

Protocol v1 treats a primary-authored dispatch receipt as if it proves delivery. It also starts with
an absolute work deadline before delivery latency is bounded. A participant can observe an
uncommitted receipt through the record working tree, and report transport is contradictory: the
participant manual requires a Git note while also forbidding ref updates. Verification is not bound
to a project environment, so an unpinned dependency mismatch can appear to be a snapshot defect.

The design must make delivery observable without weakening the existing exclusive-worktree baton,
append-only history, accepted-SHA model, or verification gates.

## Goals

1. Distinguish primary dispatch from participant-observed delivery.
2. Bound receipt visibility and ACK latency independently from work duration.
3. Make ACK and work timeout handling replay-visible before termination begins.
4. Admit transports explicitly, including durable addressing, searchability, report channel, and
   evidence class.
5. Support both primary-spawned and owner-manually-paired participants without ambiguous prompting.
6. Consume record data only from committed Git objects.
7. Preserve exact participant report bytes with an author-supplied integrity manifest.
8. Bind verification claims to a declared project environment.
9. Define BLOCKING, GATE, and NONBLOCKING findings while retaining a binary verdict.
10. Keep v1 records auditable while making the default v2 path fail closed.
11. Deploy the primary and participant packages to Claude and Codex as one release transaction.

## Non-goals

- Attempt-scoped worktrees or refs; that is a separate v3 architecture.
- A generated durable `FINDINGS.md` ledger; that is deferred to v2.1.
- Background daemons, monitors, timers, or notification services.
- Parallel turns, multiple primaries, voting, or consensus.
- Cross-machine pairing.
- Cryptographic authentication of participant reports.
- Automatic tracker integration beyond requiring durable references for GATE findings.

## Repository architecture

The repository is the source of truth for both packages:

```text
agent-pairing-skill/
├── agent-pairing/
│   ├── SKILL.md
│   ├── RUNBOOK.md
│   ├── scripts/
│   ├── templates/
│   ├── tests/
│   └── example/
├── pair-with-primary/
│   └── SKILL.md
├── scripts/
│   └── install.sh
├── tests/
│   └── install-smoke.sh
└── docs/
    ├── investigation/
    ├── design/
    └── implementation/
```

The installed copies under `~/.claude/skills` and `~/.codex/skills` are deployment outputs. They
are never edited in place.

Responsibility remains separated:

- `agent-pairing` defines topic creation, record grammar, replay, verification, fencing, rendering,
  and close.
- `pair-with-primary` defines participant join, committed receipt waiting, ACK emission, one-turn
  work discipline, and reporting.
- The project-level installer stages, verifies, swaps, and if necessary restores both packages in
  both runtime roots.

## Compatibility boundary

`protocol_version: 2` is required in `TOPIC.md` and every v2 record. The default
`scripts/validate.sh` accepts only v2. A missing, malformed, or mixed version is a violation; it
never silently selects legacy behavior.

The current v1 validator is frozen as `scripts/validate-v1.sh`. Its existing fixtures and 360-test
suite remain a regression gate for historical topics. Historical v1 records are inspected only by
an explicit v1 command. The v2 participant package does not join an open v1 topic.

Every v1 topic that the frozen validator can classify must reach exact `CLOSED` before either live
runtime installation is replaced. `IDLE` is intentionally insufficient: it has no in-flight turn,
but it can still accept a later v1 turn after the manuals have been swapped, leaving a v1 record
under v2 operating instructions. Source work and testing in this repository may proceed before that
gate; deployment may not.

A historical v1 record that the frozen validator cannot classify is not silently treated as closed,
and its committed bytes are never rewritten to make it pass. The only release path for such a
record is the explicit legacy-invalid acknowledgement defined under *Deployment transaction*. The
acknowledgement is an owner-audited quarantine decision for exact immutable evidence, not an
override for a validating non-`CLOSED` topic.

## Participant acquisition

### Required topic metadata

Before opening the topic, the primary resolves:

```yaml
participant_start_mode: primary-spawn | owner-manual
participant_selection_source: initial-prompt | owner-answer
```

Resolution is semantic, not tied to exact keywords:

1. An unambiguous initial instruction to spawn selects `primary-spawn` without a question.
2. An unambiguous instruction that the owner will pair by topic ID selects `owner-manual` without
   a question.
3. An absent or contradictory instruction causes exactly one question:

   > How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?

The selected value and its source are written into `TOPIC.md` at open.

### Primary-spawn mode

The primary spawns the participant through an approved transport, obtains a durable session or job
address, and commits an admission record. A monitor, waiter, or foreground polling handle is never
a durable address. Spawn failure stops for owner direction; it does not silently switch modes.

### Owner-manual mode

The primary creates the topic, returns its topic ID and record path, and gives the owner the exact
join prompt:

```text
pair with primary on TOPIC_ID
```

The topic classifies `AWAITING_PARTICIPANT`. No assignment, intent, receipt, ACK budget, or work
budget exists yet. After the owner confirms the participant joined, the primary commits the
admission record and the topic becomes `IDLE`.

Manual pairing does not weaken per-turn ACK requirements. Its admission normally declares
`ack_evidence_class: human-relayed`. If its transport is unsearchable, a later
`DISPATCH_UNKNOWN` state goes directly to one owner question.

## Common v2 record fields

Every record contains:

```yaml
protocol_version: 2
record_seq: INTEGER
kind: RECORD_KIND
topic_id: TOPIC_ID
recorded_epoch: INTEGER
recorded_at: ISO_8601_DISPLAY_VALUE
```

`recorded_epoch` is a primary-stamped non-negative integer and is normative for arithmetic.
`recorded_at` is display-only. Epochs must be non-decreasing but may be equal; `record_seq` is the
ordering authority.

The validator never reads wall-clock time. It validates stored arithmetic and prints due epochs.
The primary compares those epochs with its clock and materializes any timeout as a record.

## Transport admission

An append-only `admission` record proves participant readiness and defines the transport contract:

```yaml
kind: admission
admission_id: UNIQUE_ID
agent_id: STABLE_AGENT_ID
join_mode: primary-spawn | owner-manual
transport: TRANSPORT_NAME
capability: commits | writes-repo-only | read-only
worktree_visible: true | false
durable_address_kind: session-id | job-id | human-relay
durable_address: NON_SECRET_ADDRESS
searchability: searchable | unsearchable
token_search_recipe_ref: RUNBOOK_SECTION | null
report_channel: transport-output | human-relay
ack_evidence_class: transport-attested | human-relayed
receipt_commit_timeout_seconds: POSITIVE_INTEGER
default_ack_timeout_seconds: POSITIVE_INTEGER
```

An assignment binds one exact `admission_ref`. Any change in transport, address, capability,
visibility, searchability, report channel, or evidence class requires a new admission record. A
durable address must never contain a credential.

`searchability: searchable` requires a concrete token-search recipe in `RUNBOOK.md` and a
non-null reference. `searchability: unsearchable` requires a null recipe and means replay skips
token search rather than pretending a search happened.

`capability` and `worktree_visible` are validated fields, not documentation:

- `capability: commits` is the only value that admits a participant-authored landed-commit handoff,
  and it requires `worktree_visible: true`.
- `capability: writes-repo-only` admits either uncommitted worktree changes when the worktree is
  visible or a relay `patch.diff` when it is not. It does not admit a participant-authored
  `result_sha`. If the primary applies a verified relay patch, the resulting `result_sha` names the
  primary-authored application commit and retains the existing `On-behalf-of` and `Applied-by`
  provenance.
- `capability: read-only` is report-only by contract. It may use either report channel but cannot
  produce a landed commit, uncommitted worktree changes, or a relay `patch.diff`. This is a protocol
  permission rule, not a claim that emitting patch bytes physically requires filesystem writes.
- `worktree_visible: true` requires the ACK to carry `observed_head` and `preflight_clean: true`.
  `worktree_visible: false` requires those fields to be null and instead binds the ACK to the
  assignment with `relayed_base_sha`. An invisible participant cannot use `capability: commits`, but
  may take a report-only assignment or use the existing relay-patch path under
  `capability: writes-repo-only`.

These constraints are checked at admission, at assignment binding, and again at ACK, so an illegal
capability transition fails closed instead of surfacing later as an unexplained drift.

## Assignment and timing model

An assignment replaces the absolute deadline with two durations:

```yaml
admission_ref: ADMISSION_RECORD
ack_timeout_seconds: POSITIVE_INTEGER
work_timeout_seconds: POSITIVE_INTEGER
verification_profile_id: PROFILE_ID | null
```

The assignment ACK timeout defaults from admission but is materialized explicitly so replay never
depends on mutable configuration. Work duration is task-specific.

The intent adds:

```yaml
admission_ref: ADMISSION_RECORD
idempotency_token: UNIQUE_TOKEN
expected_dispatch_ref: DISPATCH_FILENAME
receipt_commit_timeout_seconds: POSITIVE_INTEGER
receipt_commit_by_epoch: INTEGER
```

`receipt_commit_by_epoch` equals the intent epoch plus `receipt_commit_timeout_seconds`. The intent
materializes that addend and repeats its assignment's `admission_ref` for the same reason the ACK
timeout is materialized on the assignment: the validator must be able to assert
`receipt_commit_by_epoch == recorded_epoch + receipt_commit_timeout_seconds` from the record alone,
without reading a mutable admission default. The materialized value must equal the admitted
`receipt_commit_timeout_seconds`, and the intent's `admission_ref` must equal the assignment's. The
dispatch payload includes the expected filename and bound.

The participant may receive an initial transport prompt before the receipt is committed because
some transports reveal the job ID only after submission. This does not authorize work. The
participant polls committed record `HEAD` for `expected_dispatch_ref`, never the record working
tree. Any separate wake notification is sent only after the receipt commit.

If the bound expires without a committed receipt, the participant exits with zero worktree writes.
Replay then sees the committed intent without a receipt and classifies `DISPATCH_UNKNOWN`.

## Dispatch and ACK

The dispatch receipt contains:

```yaml
kind: dispatch
assignment_ref: ASSIGNMENT_RECORD
intent_ref: INTENT_RECORD
admission_ref: ADMISSION_RECORD
job_id: DURABLE_JOB_OR_SESSION_ID
dispatched_epoch: INTEGER
ack_due_epoch: INTEGER
receipt_source: direct | token-search | owner-answer | validated-uncommitted
```

`ack_due_epoch` must equal `dispatched_epoch + ack_timeout_seconds` from the assignment.

After observing the committed receipt, the participant's first emitted message contains:

- Exact topic, turn, and attempt tuple.
- Exact idempotency token.
- Exact admission and dispatch references.
- Exact job/session binding when visible to the participant.
- Declared ACK evidence class.

The preflight evidence is conditional on the admitted visibility:

- With `worktree_visible: true`, the participant includes
  `git -C SESSION_WORKTREE rev-parse HEAD` and
  `git -C SESSION_WORKTREE status --porcelain` output.
- With `worktree_visible: false`, the participant explicitly reports `observed_head: null` and
  `preflight_clean: null`, and echoes the assigned base as `relayed_base_sha`. This binds the relay
  input but does not claim direct observation of worktree state; the primary separately verifies
  that the shared worktree remains stationary before accepting the ACK.

The participant emits this before modifying the worktree or authoring relay patch bytes. The
primary accepts it as an `ack` record only when the tuple and all bindings match and the
visibility-specific preflight contract is satisfied:

```yaml
kind: ack
assignment_ref: ASSIGNMENT_RECORD
intent_ref: INTENT_RECORD
dispatch_ref: DISPATCH_RECORD
admission_ref: ADMISSION_RECORD
job_id: EXACT_RECEIPT_VALUE
idempotency_token: EXACT_INTENT_VALUE
observed_head: EXACT_ASSIGNMENT_BASE_SHA | null
preflight_clean: true | null
relayed_base_sha: EXACT_ASSIGNMENT_BASE_SHA | null
ack_evidence_class: transport-attested | human-relayed
ack_captured_epoch: INTEGER
work_due_epoch: INTEGER
```

For a visible admission, `observed_head` must equal the assignment `base_sha`,
`preflight_clean` must be true, and `relayed_base_sha` must be null. For an invisible admission,
`observed_head` and `preflight_clean` must be null, `relayed_base_sha` must equal the assignment
`base_sha`, and the primary's own pre-ACK worktree check must be clean and stationary.

`work_due_epoch` must equal `ack_captured_epoch + work_timeout_seconds`.

An invalid first response is preserved verbatim but is not fabricated into a valid ACK. Under a
clean stationary worktree it terminates as `REJECTED: ack-preflight-failed`. A moved tip or residue
uses the existing quarantine and drift rules.

After emitting a valid ACK, the participant may perform the assigned turn. The work clock starts
when the primary captures the ACK, not when the receipt was written and not when the participant
first saw the prompt.

## Report capture and integrity

Git notes are removed from `pair-with-primary`; participant reporting never updates refs. The
admitted `report_channel` is authoritative.

The participant finalizes immutable UTF-8 report bytes and supplies this author manifest:

```yaml
byte_count: NON_NEGATIVE_INTEGER
sha256: LOWERCASE_HEX_DIGEST
encoding: utf-8
trailing_newline: present | absent
```

The primary captures the bytes without normalization into:

```text
artifacts/tTTTT-aAA/report.md
```

Relay patches continue using their existing manifest discipline and, when present, are stored as:

```text
artifacts/tTTTT-aAA/patch.diff
```

The primary recomputes the report byte count and SHA-256. Matching bytes are committed with a
nonterminal `result-capture` record:

```yaml
kind: result-capture
assignment_ref: ASSIGNMENT_RECORD
dispatch_ref: DISPATCH_RECORD
ack_ref: ACK_RECORD | null
artifact_ref: artifacts/tTTTT-aAA/report.md
author_byte_count: INTEGER
author_sha256: HEX_DIGEST
observed_byte_count: INTEGER
observed_sha256: HEX_DIGEST
encoding: utf-8
trailing_newline: present | absent
captured_epoch: INTEGER
```

The separate artifact is an opaque byte boundary: report text cannot inject front matter or record
framing. `THREAD.md` renders the committed artifact as quoted report content but never parses it as
control data.

A terminal result references `result_capture_ref`. A VERIFIED result requires a valid ACK. Failure
results may carry `ack_ref: null` only for explicit preflight decline, transport loss, or a fenced
result-before-ACK path.

If author and observed manifests differ:

- With a clean stationary worktree, terminate `ABORTED: transport-lossy` and record both manifests.
- With a landed commit or residue, terminate `REJECTED`, quarantine the branch, and preserve both
  manifests as evidence.
- Never repair, normalize, truncate, or reinterpret participant bytes.

## Result before ACK

An out-of-order result is not discarded and does not imply an ACK:

1. Capture the exact artifact and commit `result-capture` with `ack_ref: null`.
2. Classify `RESULT_BUFFERED` while the ACK due epoch remains active.
3. If a valid ACK arrives before fencing, bind it and continue normal verification.
4. If no ACK arrives, initiate the ACK-timeout fence.
5. After termination or owner resolution, a landed commit is `REJECTED: result-before-ack` and is
   quarantined for an explicit remediation decision.

The protocol never synthesizes an “implied-at-result” ACK.

## Durable fencing

ACK and work expiry use the same durable boundary:

```yaml
kind: fence-initiated
trigger: ack-timeout | work-timeout
assignment_ref: ASSIGNMENT_RECORD
dispatch_ref: DISPATCH_RECORD
ack_ref: ACK_RECORD | null
job_id: EXACT_RECEIPT_VALUE
due_epoch: INTEGER
observed_epoch: INTEGER
```

The primary commits `fence-initiated` before asking the transport to terminate the job. A timeout
comparison without this record is only an observation and changes no state.

After the fence commit:

- A late ACK or result is an observation against the fence boundary.
- No late event automatically cancels the fence or reopens the attempt.
- Retry remains forbidden until direct termination evidence or an owner-materialized resolution
  closes the attempt.
- A clean stationary attempt may terminate `ABORTED: ack-timeout` or
  `ABORTED: work-timeout` after termination is confirmed.
- A landed commit is rejected and quarantined; residue enters `UNRECORDED_DRIFT`.

Missing ACK proves only that no acknowledgement was captured. It never proves that the participant
is dead or that redispatch is safe.

## Replay classification and precedence

The default v2 validator derives these states:

| Classification | Durable condition | Primary action |
| --- | --- | --- |
| `AWAITING_PARTICIPANT` | Topic open, no admission | Wait for spawn or owner confirmation |
| `IDLE` | Admission present, no open attempt, stationary tree | Dispatch or close |
| `OPEN (never-dispatched)` | Assignment without intent | Abort mechanically and retry with a new attempt |
| `DISPATCH_UNKNOWN` | Intent without receipt | Token search or one owner question |
| `AWAITING_ACK` | Receipt without ACK or result capture | Wait or fence at ACK due epoch |
| `RESULT_BUFFERED` | Result capture without ACK | Wait for ACK or fence |
| `WORKING` | Valid ACK, no terminal result | Observe progress or fence at work due epoch |
| `FENCING` | `fence-initiated` without terminal result | Confirm termination or ask owner |
| `AWAITING_OWNER` | Unanswered owner question | Stop |
| `OWNER_ACTION_PENDING` | Actionable answer not materialized | Materialize idempotently |
| `REMEDIATION_REQUIRED` | Quarantined commit | Run an assigned remediation turn |
| `UNRECORDED_DRIFT` | Unexplained tip, residue, or identity failure | Stop and ask owner |
| `CLOSING:ID` | Close postconditions incomplete | Continue finalizer |
| `CLOSED` | All close postconditions satisfied | Terminal |

Precedence is fail-closed:

1. Record corruption or schema violation stops validation.
2. An active close boundary is evaluated before ordinary turn states.
3. An unanswered owner question blocks all automatic action.
4. A fence record takes precedence over ACK, capture, or work states.
5. A result capture without ACK takes precedence over ordinary `AWAITING_ACK`.
6. Worktree drift and quarantine prevent `IDLE`.

`WORKING` is ACK-anchored and capture-insensitive: a valid ACK with no terminal result is `WORKING`
whether or not a `result-capture` record exists. A capture only changes the primary's next action —
re-run verification and materialize the terminal result rather than observe progress — and never a
capture-only classification. `RESULT_BUFFERED` is therefore the single capture-derived state and
applies only when the ACK is absent.

The validator emits stored due epochs but never converts elapsed wall time into a state. Only a
committed `fence-initiated` record performs that transition.

## Failure and crash recovery

| Last durable boundary | Replayed state | Recovery |
| --- | --- | --- |
| No intent | Never dispatched | Safe to create a new attempt |
| Intent, no receipt | `DISPATCH_UNKNOWN` | Search token when admitted; otherwise ask owner |
| Receipt, no ACK | `AWAITING_ACK` | Wait or commit fence after due epoch |
| ACK, no result capture | `WORKING` | Observe progress or commit work-timeout fence |
| Capture, no ACK | `RESULT_BUFFERED` | Wait for ACK or commit ACK-timeout fence |
| Capture and ACK, no result | `WORKING` with captured output | Re-run verification and materialize result |
| Fence committed | `FENCING` | Confirm termination or ask owner |
| Terminal result | Existing terminal state | Continue, remediate, or close |

An uncommitted v2 receipt follows the existing partial-receipt discipline: validate exact tuple and
required fields, then commit as `validated-uncommitted`; otherwise hash its exact bytes into one
owner question before removal.

A `validated-uncommitted` receipt is re-stamped, never restored. `dispatched_epoch` is the epoch at
which the primary commits the recovered receipt, and `ack_due_epoch` is recomputed from that value;
any pre-crash epoch found in the uncommitted bytes is preserved as `pre_crash_dispatched_epoch`
evidence only and is never used in arithmetic. Restoring the pre-crash epoch would let
`ack_due_epoch` be already past at the moment the receipt first becomes visible to the participant,
recreating the v1 pre-expired-deadline defect inside the recovery path. Because the ACK budget is
delivery latency and the participant cannot observe an uncommitted receipt, the budget must start
when visibility starts. Uncommitted ACK, capture, fence, or result files are revalidated by
kind before any commit. Unknown residue stops replay.

## Environment parity

Each verification-capable assignment binds `verification_profile_id`. `TOPIC.md` defines every
profile used by the topic with:

- Lockfile or environment-manifest identity.
- Exact bootstrap command.
- Exact verification command.
- Required runtime and tool versions.
- Required environment variable names, never secret values.

The participant reports the profile ID, resolved tool versions, exact command, and captured output.

An unpinned failure is a fact about the executor's machine, not the assigned snapshot. It cannot
directly produce `REJECTED`. The check must be rerun under the assignment profile. If the profile
cannot be established, the reviewer records a GATE and obtains owner disposition rather than
claiming a correctness failure.

## Review severity and verdict

Review findings use exactly three severities:

- `BLOCKING`: correctness, safety, scope, or acceptance failure.
- `GATE`: must have an owner and durable tracker reference before its named lifecycle gate.
- `NONBLOCKING`: improvement that does not affect acceptance.

The binary verdict is:

```text
PASS = no BLOCKING findings and every GATE has tracker_ref plus owner
FAIL = any BLOCKING finding or any unmaterialized GATE
```

PASS maps to a VERIFIED review result. FAIL maps to REJECTED. NONBLOCKING findings do not affect
the verdict. In v2.0 this is primary-enforced review policy; the validator does not parse findings
prose or claim ledger enforcement.

## Preserved v1 safety properties

The following remain unchanged:

- One open attempt is the exclusive worktree lease.
- The handoff is a commit and the accepted SHA advances only after primary verification.
- REVIEW turns are stationary and cannot move the accepted SHA.
- Sync and close operations prove tree and branch equivalence.
- Base SHA pinning and append-only remediation remain mandatory.
- Primary and participant test claims are evidence only when accompanied by captured output.
- The record and branch remain append-only.
- Retry into uncertain liveness remains forbidden.
- The primary remains the sole record scribe.

## Behavioral evaluation contract

The historical v1 stall and stale capture are the observed RED baseline. Before changing protocol
instructions, behavioral evaluations cover:

1. Explicit `primary-spawn` does not ask the acquisition question.
2. Explicit `owner-manual` does not ask the acquisition question.
3. An unspecified or contradictory prompt asks exactly once.
4. Manual mode creates no turn or deadline before admission.
5. A participant ignores an uncommitted receipt.
6. Receipt-bound expiry produces zero worktree writes.
7. ACK returns and binds the exact tuple, token, job, admission, and preflight HEAD.
8. Missing ACK causes a fence record before termination.
9. Work timeout uses the same fence boundary.
10. Result-before-ACK becomes `RESULT_BUFFERED` without an implied ACK.
11. Late ACK after fencing cannot reopen the attempt.
12. Unsearchable transport goes directly to exactly one owner question.
13. Report-manifest mismatch is detected and preserves both manifests.
14. An unpinned environment failure cannot cause rejection.
15. Severity mapping retains a binary verdict.

Evaluations run first against the current v1 manuals to preserve the failing baseline, then against
the v2 manuals to demonstrate the intended behavior.

## Automated validation contract

The package test entry point runs all of:

- Frozen v1 validator suite, retaining its 360/0 baseline.
- Independent v2 fixtures for every valid classification.
- One-defect fixtures for each new violation code.
- Missing, malformed, and mixed protocol version cases.
- Admission binding and illegal capability transitions.
- Visible and invisible ACK preflight variants, including relay-base binding and relay-patch
  capability compatibility.
- Receipt commit bound, intent addend identity, and committed-object consumption.
- `validated-uncommitted` recovery re-stamping, including a case whose pre-crash epoch would have
  produced an already-expired ACK budget.
- `WORKING` derived identically with and without a preceding `result-capture`.
- Multi-record-root open-v1 gating, including an open topic present only in the non-default root.
- ACK binding, same-second epochs, and due-epoch arithmetic.
- Primary crashes at every durable boundary.
- ACK and work-timeout fencing.
- Result capture before ACK and late events after fence.
- Author/observed report manifest mismatch.
- Manual and primary-spawn acquisition.
- Template instantiation with no unresolved tokens.
- Historical v1 replay and a rehydrated v2 example ending in `CLOSED`.
- Neutral-CWD execution with Bash 3.2 compatibility.
- Source, staged, and installed file/byte/mode manifests.

The v2 suite must preserve the harness's destructive-path guards, fail-closed Git read behavior,
deterministic rendering, and exact violation-code assertions.

## Deployment transaction

Deployment is one release across four destinations:

- Claude `agent-pairing`
- Claude `pair-with-primary`
- Codex `agent-pairing`
- Codex `pair-with-primary`

The installer accepts repeatable `--record-root ABSOLUTE_PATH` arguments. When none are provided it
defaults to the record root of every runtime it is about to write — `~/.claude/agent-pairing` and
`~/.codex/agent-pairing` — because a release that replaces both runtimes must gate on the open
topics of both. A default covering only one runtime would let an open Codex v1 topic pass a check it
was never enumerated by, which is fail-open on a stated safety precondition. A configured default
root that does not exist is reported and skipped; an explicitly passed `--record-root` that does not
exist is an error. Before deployment the installer enumerates every topic directly under each record
root and selects the validator named by that topic's declared protocol version. Demonstration and
fixture topics live under repository test data or temporary roots, never directly under a live
runtime record root. Existing demonstrations already under a live root remain ordinary discovered
topics until explicitly dispositioned; topic names never create an implicit exclusion.

The v1 gate has exactly three record outcomes:

1. A successful validation whose exact classification is `CLOSED` permits deployment.
2. A successful validation with any other classification refuses deployment. No acknowledgement
   can override this outcome.
3. A frozen-v1 `--check` that successfully runs but exits 2 with deterministic violation output
   refuses deployment unless one explicit `--legacy-invalid-ack ABSOLUTE_FILE` exactly matches the
   topic and evidence. Validator execution failure, unavailable Git/worktree evidence, malformed
   acknowledgement, v2 validation failure, and every unrecognized outcome refuse deployment and
   cannot be acknowledged.

The repeatable legacy-invalid acknowledgement is machine-readable and contains:

```yaml
ack_version: 1
topic_path: CANONICAL_ABSOLUTE_PATH
record_head: FULL_GIT_OBJECT_ID
record_tree: FULL_GIT_OBJECT_ID
validator_exit: 2
validator_output_sha256: LOWERCASE_SHA256
owner: OWNER_ID
tracker_ref: DURABLE_TRACKER_ID
reason: ONE_LINE_REASON
acknowledged_at: RFC3339_UTC
```

The installer accepts it only when the record repository is clean, its current `HEAD` and
`HEAD^{tree}` equal the file, a second frozen-v1 read reproduces exit 2 and the exact output digest,
and no other acknowledgement names that topic. It prints the topic, owner, tracker, reason, pinned
object IDs, validator-output digest, and acknowledgement-file digest before staging anything. The
same facts and file digest are committed to the release-evidence document. A stale acknowledgement
therefore fails closed after any record change, and an acknowledgement can never convert a valid
open or idle topic into a permitted one.

The installer:

1. Refuses empty, relative, or filesystem-root source and destination paths.
2. Refuses deployment while any discovered classifiable v1 topic is not `CLOSED`, or while an
   invalid legacy topic lacks an exact owner-authorized acknowledgement.
3. Validates both source skills and runs the full neutral-CWD suite.
4. Stages all four packages beside their live destinations.
5. Verifies every staged package before changing either runtime.
6. Saves all four previous installations.
7. Swaps all four staged packages by same-filesystem rename as one release operation.
8. Runs post-install skill validation, package tests, example replay, and cross-root byte/mode parity.
9. Restores all four previous installations if any post-install check fails.
10. Removes backups only after all four destinations pass.

Each individual rename is atomic. The cross-root operation is transaction-like rather than
filesystem-atomic, so the installer minimizes the swap window and guarantees that any detected
failure restores a coherent old version instead of leaving a mixed steady state.

Skill discovery is verified in fresh Claude and Codex sessions after the filesystem transaction.

## Acceptance criteria

The v2 design is implemented only when all of these are true:

1. Both primary and participant packages live in this repository and are the deployment source.
2. Initial participant mode is inferred when explicit and asked exactly once when absent or
   contradictory.
3. Manual mode exposes topic ID and waits for admission without starting a turn deadline.
4. Default validation rejects absent or non-v2 protocol versions.
5. Historical v1 validation remains explicitly available and its suite remains green.
6. Participant work cannot start from an uncommitted receipt.
7. A committed receipt starts only the ACK budget; a valid ACK starts the work budget.
8. ACK binds attempt, token, admission, job, evidence class, and either an observed preflight HEAD
   or the explicit relay base required by the admission's visibility.
9. ACK and work expiry commit a fence before termination is requested.
10. Missing ACK never authorizes automatic retry.
11. Result-before-ACK is durably buffered and never treated as an implied ACK.
12. Participant reports use the admitted channel and never Git notes.
13. Author-supplied report manifests detect stale or lossy capture.
14. Verification failures cannot reject a snapshot until reproduced under the assigned profile.
15. Review verdict mapping follows the approved severity policy.
16. Both runtime roots receive the same verified package release or both are restored; the live v1
    gate permits exact `CLOSED` plus only exact owner-acknowledged invalid legacy evidence and never
    permits a validating non-`CLOSED` or unavailable topic.
17. All behavioral evaluations and automated suites pass from a neutral non-repository directory.

## Review disposition

Specification review on 2026-08-14 found no architectural objection: the two clocks, committed-only
receipt consumption, ACK evidence class, durable fence boundary, author-finalized manifest, and
frozen v1 validator each trace to a Confirmed finding in the investigation, and the deferrals match
the recorded Opus dispositions. Five defects were found in the written specification and resolved in
this revision:

| # | Defect | Resolution |
| --- | --- | --- |
| R1 | `WORKING` was defined incompatibly by the classification table ("no capture") and the recovery table ("with captured output") | `WORKING` is ACK-anchored and capture-insensitive; `RESULT_BUFFERED` is the only capture-derived state |
| R2 | `receipt_source: validated-uncommitted` left `dispatched_epoch` provenance unstated, allowing a recovered receipt to publish an already-expired ACK budget | Recovered receipts are re-stamped at commit; the pre-crash epoch is retained as evidence only |
| R3 | `capability` and `worktree_visible` were schema fields with no stated rule, and so were unvalidatable | Both are bound to explicit handoff, report-channel, and ACK-preflight constraints |
| R4 | `receipt_commit_by_epoch` was checkable only against a mutable admission default, unlike `ack_due_epoch` | The intent materializes `receipt_commit_timeout_seconds` and repeats `admission_ref` |
| R5 | The open-v1 deployment gate defaulted to one record root while the release replaced two runtimes | The default enumerates the record root of every runtime being written |

A second review round verified R1–R5, the v1 `360/0` baseline, and the rejected empty-`turns/`
guard against Apple Git 2.50.1. It found one deployment blocker and two specification gaps:

| # | Defect | Resolution |
| --- | --- | --- |
| R6 | A structurally invalid append-only v1 record could neither become `CLOSED` nor pass the strict gate | Added a narrowly scoped owner acknowledgement pinned to clean record HEAD/tree and reproducible validator-output digest; it cannot override valid non-`CLOSED`, v2, unavailable, or read-failure outcomes |
| R7 | Live deployment prerequisites, including the release topic itself, were not materialized before the final task | The plan now inventories every live topic with an owner, durable tracker, and explicit pre-swap disposition |
| R8 | `CLOSED`-rather-than-`IDLE` and treatment of demonstrations were underexplained | `IDLE` remains unsafe because it can accept a later v1 turn; examples live outside live record roots and names never create an exclusion |

No finding changed the v2 state machine's shape or task sequence. The acknowledgement changes only
the pre-deployment treatment of immutable, unclassifiable v1 evidence; the behavioral evaluation
contract stands as written.

## Deferred work

v2.1 may add structured finding and disposition records plus a generated `FINDINGS.md`. v3 may
evaluate attempt-scoped worktrees or refs as a structural stale-writer fence. Neither is part of
this implementation plan.
