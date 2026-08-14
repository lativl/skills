# Agent-Pairing Protocol v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the accepted agent-pairing protocol v2 as repository-owned primary and participant skills, with acknowledgement-based delivery, replay-safe clocks and fencing, exact report capture, explicit legacy validation, and transactional dual-runtime installation.

**Architecture:** Preserve the one-shared-worktree baton and append-only record repository, but make protocol v2 a separate fail-closed grammar whose validator reads committed Git objects. Keep the current validator and its 360-case harness as an explicit v1 path; build v2 as focused Bash 3.2 libraries behind the default validator, then make both manuals, templates, examples, and the installer consume that contract.

**Tech Stack:** Markdown skill packages, POSIX utilities, Bash 3.2, Git plumbing commands, SHA-256 via `shasum -a 256`, and shell-based fixture/evaluation harnesses.

## Global Constraints

- `protocol_version: 2` is required in `TOPIC.md` and every v2 record; missing, malformed, mixed, or non-v2 input is rejected by the default validator.
- Historical records are accepted only by the explicit `scripts/validate-v1.sh` command.
- The frozen legacy gate remains `360 passed, 0 failed` from a neutral non-repository working directory.
- Bash code must run under macOS Bash 3.2: no associative arrays, `mapfile`, `readarray`, process substitution dependencies, or GNU-only flags.
- The primary is the sole record scribe; participants read records only from committed Git objects and never update record refs.
- A participant may begin work only after a committed dispatch receipt and a valid ACK bound to the attempt, token, admission, job, evidence class, and visibility-specific base evidence.
- `record_seq` is the ordering authority; primary-stamped integer epochs are normative for arithmetic, may be equal, and never cause the validator to consult wall-clock time.
- The committed receipt starts the ACK budget; the captured ACK starts the work budget.
- Timeout observation does not change state until a `fence-initiated` record is committed, and no late event reopens a fenced attempt.
- Exact report bytes are UTF-8 with explicit trailing-newline state, byte count, and lowercase SHA-256; the primary never normalizes participant bytes.
- `BLOCKING`, `GATE`, and `NONBLOCKING` are primary policy in v2.0; the verdict remains binary and the validator does not parse findings prose.
- No background daemon, persistent monitor, parallel turn, multiple primary, cross-machine protocol, cryptographic report authentication, or v2.1 findings ledger is introduced.
- Deployment treats Claude/Codex `agent-pairing` and Claude/Codex `pair-with-primary` as one four-destination release and restores all four on a detected failure.
- Deployment refuses while any discovered v1 topic under either runtime record root is not `CLOSED`.
- Installed copies are outputs. Implementation changes only this repository until the deployment task passes its open-topic gate.

## Source Specification

- Design: `agent-pairing-skill/docs/design/2026-08-14-agent-pairing-protocol-v2-design.md`
- Investigation: `agent-pairing-skill/docs/investigation/agent-pairing-delivery-protocol-investigation.md`
- Opus disposition: `agent-pairing-skill/docs/investigation/agent-pairing-opus-review.md`

## File Responsibility Map

| Path | Responsibility |
| --- | --- |
| `agent-pairing-skill/agent-pairing/scripts/validate-v1.sh` | Frozen explicit validator for historical v1 topics |
| `agent-pairing-skill/agent-pairing/scripts/validate.sh` | Default v2 CLI, argument checks, library loading, and final rendering |
| `agent-pairing-skill/agent-pairing/scripts/lib/v2-record.sh` | Committed-object enumeration, front-matter parsing, common fields, filenames, hashes, and epoch primitives |
| `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh` | Per-kind schemas, linkage, admission/capability constraints, and arithmetic checks |
| `agent-pairing-skill/agent-pairing/scripts/lib/v2-replay.sh` | Accepted-SHA replay, precedence, classifications, due-epoch output, drift, and close checks |
| `agent-pairing-skill/agent-pairing/templates/` | Canonical v2 topic and record bodies, including admission, ACK, capture, and fence records |
| `agent-pairing-skill/agent-pairing/SKILL.md` | Primary lifecycle: participant selection, OPEN, dispatch, ACK, capture, fence, replay, verification, and close |
| `agent-pairing-skill/agent-pairing/RUNBOOK.md` | Transport recipes, environment profiles, recovery, operator timing, and deployment procedure |
| `agent-pairing-skill/pair-with-primary/SKILL.md` | Participant join, committed receipt wait, ACK-first behavior, one-turn discipline, and exact reporting |
| `agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh` | Existing 360-case legacy harness, changed only to point at `validate-v1.sh` |
| `agent-pairing-skill/agent-pairing/tests/v1-example/` | Frozen historical example consumed only by the v1 harness |
| `agent-pairing-skill/agent-pairing/tests/v2/` | v2 fixture builder, one-defect tests, replay tests, and manual-contract checks |
| `agent-pairing-skill/agent-pairing/tests/behavior/` | Before/after behavioral cases and captured evaluation rubric |
| `agent-pairing-skill/agent-pairing/tests/run-tests.sh` | Neutral-CWD package gate that runs v1, v2, behavior-contract, and example suites |
| `agent-pairing-skill/agent-pairing/example/` | Rehydrated v2 record/work repositories that end in `CLOSED` |
| `agent-pairing-skill/scripts/install.sh` | Four-destination preflight, stage, verify, swap, rollback, and post-install parity |
| `agent-pairing-skill/tests/install-smoke.sh` | Temporary-root happy path, open-v1 refusal, injected rollback failures, and mode/byte parity |

---

### Task 1: Freeze v1 and establish the v2 test entry point

**Files:**
- Move: `agent-pairing-skill/agent-pairing/scripts/validate.sh` → `agent-pairing-skill/agent-pairing/scripts/validate-v1.sh`
- Move: `agent-pairing-skill/agent-pairing/tests/run-tests.sh` → `agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh`
- Move: `agent-pairing-skill/agent-pairing/example/` → `agent-pairing-skill/agent-pairing/tests/v1-example/`
- Create: `agent-pairing-skill/agent-pairing/scripts/validate.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/run-tests.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/lib.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/topic-empty-v2/TOPIC.md`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/topic-missing-version/TOPIC.md`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/topic-v1/TOPIC.md`

**Interfaces:**
- Consumes: the existing v1 validator and 360-case harness without semantic change.
- Produces: `/bin/bash scripts/validate-v1.sh --check TOPIC_DIR`, `/bin/bash scripts/validate.sh --check TOPIC_DIR`, and one package test command.

- [ ] **Step 1: Record the fresh legacy baseline before moving files**

Run from `/private/tmp`:

```bash
/Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected final line:

```text
360 passed, 0 failed
```

- [ ] **Step 2: Move the legacy files non-interactively and point the harness at the explicit validator**

Run:

```bash
mv -f agent-pairing-skill/agent-pairing/scripts/validate.sh agent-pairing-skill/agent-pairing/scripts/validate-v1.sh
mv -f agent-pairing-skill/agent-pairing/tests/run-tests.sh agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh
mv -f agent-pairing-skill/agent-pairing/example agent-pairing-skill/agent-pairing/tests/v1-example
```

Change only the legacy harness validator and example assignments:

```bash
VALIDATE="$HERE/../scripts/validate-v1.sh"
EX="$HERE/v1-example"
```

- [ ] **Step 3: Write the initial failing v2 protocol-version tests**

Create `tests/v2/lib.sh` with checked temp allocation and exact result helpers:

```bash
v2_ok() { V2_PASS=$((V2_PASS + 1)); printf 'ok   %s\n' "$1"; }
v2_nok() { V2_FAIL=$((V2_FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

v2_materialize() {
  source_dir="$1"
  target_dir="$(mktemp -d "$V2_TMP/topic.XXXXXX")" || return 1
  cp -rf "$source_dir"/. "$target_dir"/ || return 1
  git -C "$target_dir" init -q || return 1
  git -C "$target_dir" add -A || return 1
  git -C "$target_dir" -c user.name=v2-test -c user.email=v2@test commit -qm seed || return 1
  printf '%s\n' "$target_dir"
}

v2_run() {
  topic_dir="$(v2_materialize "$1")" || return 1
  "$V2_VALIDATE" --check "$topic_dir" >"$V2_OUT" 2>&1
}

v2_expect_violation() {
  name="$1" fixture="$2" code="$3"
  if v2_run "$V2_FIXTURES/$fixture"; then
    v2_nok "$name" "validator unexpectedly returned zero"
  elif grep -F "VIOLATION $code" "$V2_OUT" >/dev/null; then
    v2_ok "$name"
  else
    v2_nok "$name" "expected VIOLATION $code; got: $(sed -n '1p' "$V2_OUT")"
  fi
}
```

Create three topic fixtures. The valid empty topic begins with:

```yaml
---
protocol_version: 2
topic_id: empty-v2
participant_start_mode: owner-manual
participant_selection_source: initial-prompt
---
```

The missing-version fixture omits `protocol_version`; the v1 fixture carries
`protocol_version: 1`. Assert:

```bash
v2_expect_violation "missing version fails closed" topic-missing-version PROTOCOL_VERSION
v2_expect_violation "v1 is rejected by default" topic-v1 PROTOCOL_VERSION
```

- [ ] **Step 4: Run the v2 tests and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh
```

Expected: nonzero because the default v2 validator does not exist.

- [ ] **Step 5: Implement the smallest default validator and package runner**

The first `scripts/validate.sh` must check exact CLI shape, require a Git record repository with
`HEAD:TOPIC.md`, read the topic version from that committed object, reject anything except the exact
scalar `2`, and print `classification: AWAITING_PARTICIPANT` for the empty v2 fixture. It must never
fall back to the record working tree. Use exit `2` for a protocol violation and exit `3` for invalid
CLI usage.

Create the package runner:

```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$HERE/run-v1-tests.sh" || exit $?
/bin/bash "$HERE/v2/run-tests.sh" || exit $?
```

- [ ] **Step 6: Run legacy and v2 gates from a neutral directory**

Run:

```bash
cd /private/tmp
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh
```

Expected: legacy ends `360 passed, 0 failed`; v2 ends with zero failed.

- [ ] **Step 7: Commit the compatibility boundary**

```bash
git add agent-pairing-skill/agent-pairing/scripts/validate-v1.sh agent-pairing-skill/agent-pairing/scripts/validate.sh agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh agent-pairing-skill/agent-pairing/tests/run-tests.sh agent-pairing-skill/agent-pairing/tests/v1-example agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: establish agent-pairing v2 validation boundary"
```

---

### Task 2: Implement committed-object parsing and the common v2 grammar

**Files:**
- Create: `agent-pairing-skill/agent-pairing/scripts/lib/v2-record.sh`
- Create: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Modify: `agent-pairing-skill/agent-pairing/scripts/validate.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/common-valid/`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/common-defects/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: `validate.sh --check TOPIC_DIR` from Task 1.
- Produces: `v2_list_records TOPIC_DIR`, `v2_read_committed TOPIC_DIR PATH`, `v2_fm_get FILE KEY`, `v2_require_common FILE`, and `v2_validate_kind FILE`.

- [ ] **Step 1: Add one-defect tests for committed-only reads and common fields**

Reuse Task 1's `v2_materialize` helper so every ordinary fixture directory becomes a temporary Git
record repository before validation:

Add assertions for exact violation codes:

```bash
v2_expect_violation "record version is required" common-defects/missing-record-version RECORD_PROTOCOL_VERSION
v2_expect_violation "record sequence is decimal" common-defects/bad-record-seq RECORD_SEQ
v2_expect_violation "epoch is nonnegative" common-defects/negative-epoch RECORDED_EPOCH
v2_expect_violation "epochs do not decrease" common-defects/decreasing-epoch EPOCH_ORDER
v2_expect_violation "unknown kind is rejected" common-defects/unknown-kind UNKNOWN_KIND
v2_expect_violation "working-tree-only record is ignored then reported as residue" common-defects/uncommitted-record UNCOMMITTED_RESIDUE
```

- [ ] **Step 2: Run the common-grammar cases and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh
```

Expected: failures name the six not-yet-implemented common checks.

- [ ] **Step 3: Implement fail-closed committed readers**

In `v2-record.sh`, expose these exact functions:

```bash
v2_git() {
  topic="$1"
  shift
  GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 git -C "$topic" "$@"
}

v2_read_committed() {
  topic="$1" path="$2"
  v2_git "$topic" show "HEAD:$path"
}

v2_list_records() {
  v2_git "$1" ls-tree -r --name-only HEAD turns |
    LC_ALL=C sort
}
```

Copy each committed blob to a checked temporary file before parsing; never parse `turns/` from the
working tree. Compare `git status --porcelain --untracked-files=all` with the committed tree and
emit `UNCOMMITTED_RESIDUE` for record-tree residue.

- [ ] **Step 4: Implement strict front matter, filename, and common-field validation**

Require exactly one opening and one closing `---`, unique `key: value` entries, no blank lines in
front matter, and these common keys on every record:

```text
protocol_version record_seq kind topic_id recorded_epoch recorded_at
```

Enforce non-decreasing `recorded_epoch`, strict increasing `record_seq`, exact topic identity, and
filename tuple agreement. Accept only:

```text
admission assignment intent dispatch ack result-capture fence-initiated result late owner-question owner-answer close
```

- [ ] **Step 5: Run the focused suite and the full legacy gate**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh
/bin/bash agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh
```

Expected: v2 zero failed; legacy `360 passed, 0 failed`.

- [ ] **Step 6: Commit the common grammar**

```bash
git add agent-pairing-skill/agent-pairing/scripts/validate.sh agent-pairing-skill/agent-pairing/scripts/lib agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: validate committed agent-pairing v2 records"
```

---

### Task 3: Add participant selection and transport admission

**Files:**
- Modify: `agent-pairing-skill/agent-pairing/templates/TOPIC.md`
- Create: `agent-pairing-skill/agent-pairing/templates/admission.md`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:101`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:47`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/admission/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: common v2 topic/record parsing from Task 2.
- Produces: `participant_start_mode`, `participant_selection_source`, the `admission` schema, and `AWAITING_PARTICIPANT`/`IDLE` classification inputs.

- [ ] **Step 1: Write failing topic-selection and admission fixtures**

Cover these exact valid pairs:

```text
primary-spawn initial-prompt
primary-spawn owner-answer
owner-manual initial-prompt
owner-manual owner-answer
```

Add one-defect cases for contradictory source values, missing mode, duplicate `admission_id`, a
monitor ID used as a durable address, `searchable` without a recipe, `unsearchable` with a recipe,
`commits` with invisible worktree, read-only with a patch capture, and changed admission fields
without a new `admission_id`.

- [ ] **Step 2: Run the admission cases and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh admission
```

Expected: nonzero with the first missing admission-schema assertion.

- [ ] **Step 3: Update `TOPIC.md` and add the admission template**

The topic front matter must add:

```yaml
protocol_version: 2
participant_start_mode: {{PARTICIPANT_START_MODE}}
participant_selection_source: {{PARTICIPANT_SELECTION_SOURCE}}
```

The admission template must contain the accepted design fields exactly:

```yaml
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
```

- [ ] **Step 4: Encode selection behavior in the primary manual**

At OPEN, write these three branches without keyword-only parsing:

```text
If the initial request unambiguously says to spawn, select primary-spawn and do not ask.
If it unambiguously says the owner will pair by topic ID, select owner-manual and do not ask.
Otherwise ask exactly once: “How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?”
```

For owner-manual mode, return the topic ID, absolute record path, and exact prompt
`pair with primary on TOPIC_ID`; create no assignment or clock before admission. For primary-spawn,
require a durable session/job address and reject monitor/waiter handles.

Selecting `owner-manual` is not itself admission. Wait until the owner confirms that the secondary
joined and supplies the durable address/evidence needed by the admission; only then commit the
admission and allow `IDLE`.

- [ ] **Step 5: Implement admission validation and initial classification**

Validate the enumerations and conditional fields from the design. Classification is:

```bash
if [ "$admission_count" -eq 0 ]; then
  printf 'classification: AWAITING_PARTICIPANT\n'
else
  printf 'classification: IDLE\n'
fi
```

This shortcut is only for the no-attempt branch; later replay precedence replaces it when records
beyond admission exist.

- [ ] **Step 6: Run focused and regression suites**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh admission
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: all v2 admission cases pass; package gate ends with zero failed.

- [ ] **Step 7: Commit participant selection and admission**

```bash
git add agent-pairing-skill/agent-pairing/templates/TOPIC.md agent-pairing-skill/agent-pairing/templates/admission.md agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: admit agent-pairing participants explicitly"
```

---

### Task 4: Replace absolute deadlines with intent, receipt, and recovery clocks

**Files:**
- Modify: `agent-pairing-skill/agent-pairing/templates/assignment.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/intent.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/dispatch.md`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:162`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:139`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/clocks/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: an exact `admission_ref` from Task 3.
- Produces: materialized `ack_timeout_seconds`, `work_timeout_seconds`, `receipt_commit_timeout_seconds`, `receipt_commit_by_epoch`, `dispatched_epoch`, and `ack_due_epoch`.

- [ ] **Step 1: Write failing clock and linkage cases**

Add cases for:

```text
intent admission_ref differs from assignment
intent receipt timeout differs from admission
receipt_commit_by_epoch arithmetic mismatch
dispatch ack_due_epoch arithmetic mismatch
same-second recorded epochs accepted
absolute deadline key rejected in v2 assignment
validated-uncommitted missing pre_crash_dispatched_epoch
validated-uncommitted arithmetic based on the pre-crash epoch
participant-visible committed receipt whose ACK budget is positive
```

Use exact codes `ADMISSION_REF`, `RECEIPT_TIMEOUT`, `RECEIPT_COMMIT_DUE`, `ACK_DUE`,
`LEGACY_DEADLINE`, and `RECOVERY_EPOCH`.

- [ ] **Step 2: Run the clock fixtures and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh clocks
```

Expected: nonzero because v1 template fields and arithmetic are still present.

- [ ] **Step 3: Replace the assignment, intent, and dispatch fields**

Assignment adds:

```yaml
admission_ref: {{ADMISSION_REF}}
ack_timeout_seconds: {{ACK_TIMEOUT_SECONDS}}
work_timeout_seconds: {{WORK_TIMEOUT_SECONDS}}
verification_profile_id: {{VERIFICATION_PROFILE_ID}}
```

Intent adds:

```yaml
admission_ref: {{ADMISSION_REF}}
expected_dispatch_ref: {{EXPECTED_DISPATCH_REF}}
receipt_commit_timeout_seconds: {{RECEIPT_COMMIT_TIMEOUT_SECONDS}}
receipt_commit_by_epoch: {{RECEIPT_COMMIT_BY_EPOCH}}
```

Dispatch replaces `dispatched_at` with:

```yaml
admission_ref: {{ADMISSION_REF}}
job_id: {{JOB_ID}}
dispatched_epoch: {{DISPATCHED_EPOCH}}
ack_due_epoch: {{ACK_DUE_EPOCH}}
receipt_source: {{RECEIPT_SOURCE}}
```

All three also receive the common v2 fields.

- [ ] **Step 4: Implement integer arithmetic and recovery provenance**

Use decimal-only checks and remove leading-zero ambiguity before shell arithmetic:

```bash
v2_is_uint() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
v2_uint_value() {
  v2_is_uint "$1" || return 1
  awk -v n="$1" 'BEGIN { printf "%.0f\n", n + 0 }'
}
v2_sum_eq() {
  left="$(v2_uint_value "$1")" || return 1
  right="$(v2_uint_value "$2")" || return 1
  expected="$(v2_uint_value "$3")" || return 1
  [ "$((left + right))" -eq "$expected" ]
}
```

Epoch values must stay within the exact integer range supported by both the shell and `awk`; reject
larger values with `EPOCH_RANGE`. The validator must check:

```text
receipt_commit_by_epoch = intent.recorded_epoch + receipt_commit_timeout_seconds
ack_due_epoch = dispatched_epoch + assignment.ack_timeout_seconds
```

For `receipt_source: validated-uncommitted`, require `pre_crash_dispatched_epoch`, require it not to
exceed `dispatched_epoch`, and calculate only from the re-stamped `dispatched_epoch`.

- [ ] **Step 5: Update primary recovery instructions**

The manual must say that a recovered uncommitted receipt is rewritten and committed with a fresh
`dispatched_epoch`; original bytes contribute only `pre_crash_dispatched_epoch`. Commit the receipt
before any wake notification. If no committed receipt appears by `receipt_commit_by_epoch`, the
participant writes nothing and exits; replay remains `DISPATCH_UNKNOWN`.

- [ ] **Step 6: Run focused, full, and Bash syntax gates**

Run:

```bash
/bin/bash -n agent-pairing-skill/agent-pairing/scripts/validate.sh
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh clocks
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: syntax exits zero; all suites report zero failed.

- [ ] **Step 7: Commit the two-clock dispatch boundary**

```bash
git add agent-pairing-skill/agent-pairing/templates/assignment.md agent-pairing-skill/agent-pairing/templates/intent.md agent-pairing-skill/agent-pairing/templates/dispatch.md agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: add replayable dispatch and acknowledgement clocks"
```

---

### Task 5: Add visibility-aware acknowledgement and capability enforcement

**Files:**
- Create: `agent-pairing-skill/agent-pairing/templates/ack.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/onboarding.md`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:164`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:47`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/ack/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: assignment, intent, dispatch, and admission references from Tasks 3–4.
- Produces: a valid `ack` record and `work_due_epoch`; visible ACKs bind observed HEAD/cleanliness, invisible ACKs bind `relayed_base_sha`.

- [ ] **Step 1: Write the ACK matrix as failing one-defect tests**

Cover this full matrix:

| Visibility | Capability | Valid evidence |
| --- | --- | --- |
| true | commits | observed HEAD equals base, clean true, relay base null |
| true | writes-repo-only | observed HEAD equals base, clean true, relay base null |
| true | read-only | observed HEAD equals base, clean true, relay base null |
| false | writes-repo-only | observed HEAD null, clean null, relay base equals base |
| false | read-only | observed HEAD null, clean null, relay base equals base |

Reject invisible `commits`, wrong job/token/admission/evidence class, visible null HEAD, visible dirty
preflight, invisible observed HEAD, invisible null relay base, wrong relay base, and incorrect
`work_due_epoch`.

- [ ] **Step 2: Run the ACK cases and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh ack
```

Expected: nonzero with missing `ack` kind/schema failures.

- [ ] **Step 3: Add the ACK template**

Use these exact binding fields after the common v2 fields:

```yaml
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
```

Represent null values as the literal scalar `null`.

- [ ] **Step 4: Implement exact tuple, evidence, and capability checks**

The validator must compare every reference to the exact committed predecessor. It must enforce:

```text
visible: observed_head == assignment.base_sha; preflight_clean == true; relayed_base_sha == null
invisible: observed_head == null; preflight_clean == null; relayed_base_sha == assignment.base_sha
work_due_epoch == ack_captured_epoch + work_timeout_seconds
```

`commits` requires visibility. `writes-repo-only` permits visible uncommitted changes or an invisible
relay patch but never a participant-authored landed SHA. `read-only` is report-only and forbids a
landed SHA, worktree modifications, and relay patch capture.

- [ ] **Step 5: Update onboarding and primary instructions to make ACK the first response**

The participant's first emitted message after committed-receipt observation must include the exact
attempt tuple, token, admission/dispatch refs, visible job binding, evidence class, and one of the
two preflight shapes. The primary commits the ACK only after its own shared-worktree stationarity
check. Invalid evidence is preserved, never rewritten into a valid ACK.

- [ ] **Step 6: Run the ACK, package, and legacy gates**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh ack
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: zero v2 failures and legacy `360 passed, 0 failed` within the package output.

- [ ] **Step 7: Commit ACK enforcement**

```bash
git add agent-pairing-skill/agent-pairing/templates/ack.md agent-pairing-skill/agent-pairing/templates/onboarding.md agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: require visibility-aware participant acknowledgements"
```

---

### Task 6: Capture exact participant reports and relay patches

**Files:**
- Create: `agent-pairing-skill/agent-pairing/templates/result-capture.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/result.md`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-record.sh`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:190`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:130`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/capture/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: admitted `report_channel`, capability, and ACK reference from Tasks 3 and 5.
- Produces: immutable `artifacts/tTTTT-aAA/report.md`, optional `patch.diff`, a `result-capture` record, and a terminal result that references the capture.

- [ ] **Step 1: Write failing exact-byte capture tests**

Create fixture artifacts for these byte shapes:

```text
ASCII with trailing newline
ASCII without trailing newline
UTF-8 containing “Київ” and a trailing newline
report body containing --- and Markdown fences
author byte count mismatch
author SHA-256 mismatch
declared trailing-newline mismatch
capture path outside artifacts/tTTTT-aAA
read-only admission with patch.diff
writes-repo-only relay patch with matching byte manifest
```

Assert exact codes `CAPTURE_PATH`, `CAPTURE_BYTES`, `CAPTURE_SHA256`, `CAPTURE_NEWLINE`,
`CAPABILITY_PATCH`, and `RESULT_CAPTURE_REF`.

- [ ] **Step 2: Run capture tests and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh capture
```

Expected: nonzero because capture records and artifact validation are not implemented.

- [ ] **Step 3: Add exact hash and newline helpers**

Implement these interfaces in `v2-record.sh`:

```bash
v2_byte_count() { LC_ALL=C wc -c <"$1" | tr -d ' '; }
v2_sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
v2_has_trailing_newline() {
  [ ! -s "$1" ] && { printf 'absent\n'; return; }
  last="$(tail -c 1 "$1" | od -An -tuC | tr -d ' ')"
  [ "$last" = 10 ] && printf 'present\n' || printf 'absent\n'
}
```

Guard every file read and require lowercase 64-character hex for both hashes. An empty report has
`trailing_newline: absent`.

- [ ] **Step 4: Add the capture template and terminal linkage**

The capture template carries:

```yaml
assignment_ref: {{ASSIGNMENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
ack_ref: {{ACK_REF}}
artifact_ref: {{ARTIFACT_REF}}
author_byte_count: {{AUTHOR_BYTE_COUNT}}
author_sha256: {{AUTHOR_SHA256}}
observed_byte_count: {{OBSERVED_BYTE_COUNT}}
observed_sha256: {{OBSERVED_SHA256}}
encoding: utf-8
trailing_newline: {{TRAILING_NEWLINE}}
captured_epoch: {{CAPTURED_EPOCH}}
```

Add `ack_ref`, `dispatch_ref`, and `result_capture_ref` to terminal results. VERIFIED requires a
valid ACK and matching capture. Only preflight decline, transport loss, or fenced result-before-ACK
may terminate with `ack_ref: null`.

- [ ] **Step 5: Update the primary capture algorithm**

Specify this sequence in the manual:

```text
1. Receive finalized manifest and bytes over the admitted report channel.
2. Write bytes once to artifacts/tTTTT-aAA/report.md without line-oriented reconstruction.
3. Recompute byte count, SHA-256, encoding expectation, and trailing-newline state.
4. Commit artifact plus result-capture before interpreting the report.
5. On mismatch, preserve both manifests; never repair or normalize.
6. Re-run assigned verification and only then commit the terminal result.
```

For relay code, preserve the existing base SHA, byte-count, SHA-256, `git apply --3way`,
`On-behalf-of`, and `Applied-by: primary` discipline.

- [ ] **Step 6: Run capture and regression suites**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh capture
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: capture cases pass; package gate reports zero failed.

- [ ] **Step 7: Commit exact report capture**

```bash
git add agent-pairing-skill/agent-pairing/templates/result-capture.md agent-pairing-skill/agent-pairing/templates/result.md agent-pairing-skill/agent-pairing/scripts/lib agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: preserve exact agent-pairing report bytes"
```

---

### Task 7: Add durable ACK/work fencing and result-before-ACK handling

**Files:**
- Create: `agent-pairing-skill/agent-pairing/templates/fence-initiated.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/late.md`
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-schema.sh`
- Create: `agent-pairing-skill/agent-pairing/scripts/lib/v2-replay.sh`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:393`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:160`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/fence/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: ACK due epoch, work due epoch, capture record, and attempt bindings.
- Produces: `fence-initiated`, `RESULT_BUFFERED`, `FENCING`, and terminal timeout results that cannot be reopened by late records.

- [ ] **Step 1: Write the fence race matrix as failing tests**

Add fixtures for:

```text
receipt plus no ACK before fence
valid ACK plus no result before fence
capture before ACK without fence
capture before ACK followed by valid ACK
capture before ACK followed by fence
late ACK after fence
late capture after fence
late landed commit after fence
fence written before stored due epoch
timeout terminal result without a preceding fence
second fence for one attempt
```

The validator never compares due epochs with current time. It only checks that a committed fence's
`observed_epoch` is not earlier than its `due_epoch` and that the due epoch equals the bound stored
on the receipt or ACK.

- [ ] **Step 2: Run fence cases and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh fence
```

Expected: nonzero because `fence-initiated`, `RESULT_BUFFERED`, and `FENCING` are unknown.

- [ ] **Step 3: Add the durable fence template**

After common v2 fields, require:

```yaml
reason: ack-timeout | work-timeout
assignment_ref: {{ASSIGNMENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
ack_ref: {{ACK_REF}}
job_id: {{JOB_ID}}
due_epoch: {{DUE_EPOCH}}
observed_epoch: {{OBSERVED_EPOCH}}
```

`ack_ref` is `null` only for `ack-timeout`; it is mandatory for `work-timeout`.

- [ ] **Step 4: Implement fence precedence and out-of-order capture rules**

In `v2-replay.sh`, order the open-attempt branches so that:

```bash
if [ "$fence_count" -eq 1 ]; then
  printf 'classification: FENCING\n'
elif [ "$ack_count" -eq 0 ] && [ "$capture_count" -eq 1 ]; then
  printf 'classification: RESULT_BUFFERED\n'
elif [ "$ack_count" -eq 0 ]; then
  printf 'classification: AWAITING_ACK\n'
else
  printf 'classification: WORKING\n'
fi
```

This branch runs only after schema/linkage checks and before drift-free `IDLE`. A capture plus ACK
remains `WORKING`; capture affects the primary action, not classification.

- [ ] **Step 5: Update fence and late-event instructions**

Require the primary to commit the fence before requesting transport termination. After that commit,
ACK/capture/result data is preserved as a late observation and cannot cancel the fence. Retry is
forbidden until direct termination evidence or an owner-materialized resolution ends the attempt.

- [ ] **Step 6: Run fence, capture, ACK, and package gates**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh fence
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh capture
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh ack
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: all focused suites and the package gate report zero failed.

- [ ] **Step 7: Commit durable fencing**

```bash
git add agent-pairing-skill/agent-pairing/templates/fence-initiated.md agent-pairing-skill/agent-pairing/templates/late.md agent-pairing-skill/agent-pairing/scripts/lib agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: fence expired agent-pairing attempts durably"
```

---

### Task 8: Complete deterministic replay, precedence, rendering, and close

**Files:**
- Modify: `agent-pairing-skill/agent-pairing/scripts/lib/v2-replay.sh`
- Modify: `agent-pairing-skill/agent-pairing/scripts/validate.sh`
- Modify: `agent-pairing-skill/agent-pairing/templates/owner-question.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/owner-answer.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/close.md`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:436`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/classification/`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/fixtures/precedence/`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: all validated v2 record kinds from Tasks 2–7 plus existing branch/trailer safety rules.
- Produces: the full accepted classification set, deterministic `THREAD.md`, and idempotent owner-action/close replay.

- [ ] **Step 1: Write one valid fixture for every classification**

Require exact output for:

```text
AWAITING_PARTICIPANT
IDLE
OPEN (never-dispatched)
DISPATCH_UNKNOWN
AWAITING_ACK
RESULT_BUFFERED
WORKING
FENCING
AWAITING_OWNER
OWNER_ACTION_PENDING
REMEDIATION_REQUIRED
UNRECORDED_DRIFT
CLOSING:close-0001
CLOSED
```

Add paired `WORKING` fixtures with and without `result-capture`; both must print the identical
classification. Add precedence fixtures where unanswered owner question beats work state, fence
beats ACK/capture, quarantine beats IDLE, and active close beats ordinary turn state.

- [ ] **Step 2: Run classification tests and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh classification
```

Expected: nonzero for every not-yet-complete replay branch.

- [ ] **Step 3: Port preserved v1 safety checks into v2 replay without sharing mutable code**

Re-implement the accepted-SHA fold, one-open-attempt rule, commit trailer checks, scope checks using
`--name-status -M -C -z`, REVIEW stationarity, quarantined-commit handling, worktree registration,
branch identity, clean status, and close tree/branch equivalence. Do not source
`validate-v1.sh`; the legacy validator remains independently executable and frozen.

- [ ] **Step 4: Implement the exact precedence order**

The top-level order is:

```text
schema or record corruption → violation
active close boundary
unanswered owner question
fence
capture without ACK
ordinary open-attempt states
quarantine or drift
idle
```

`OPEN (never-dispatched)` requires assignment without intent. `DISPATCH_UNKNOWN` requires intent
without receipt. No automatic action follows an unsearchable transport; the replay action is one
owner question.

- [ ] **Step 5: Make `--render` deterministic and committed-only**

Render `THREAD.md` to a checked temporary file, quote artifact report bytes without parsing them as
front matter, compare before rename, and preserve the previous file on any read/write/rename
failure. `--check` must never modify the topic. Render ordering is `record_seq`, not timestamp.

- [ ] **Step 6: Run classification, render-stability, failure-injection, and full gates**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh classification
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh render
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: all v2 classifications match exactly; two consecutive renders are byte-identical; injected
read/rename failures preserve the old render; package gate reports zero failed.

- [ ] **Step 7: Commit complete v2 replay**

```bash
git add agent-pairing-skill/agent-pairing/scripts agent-pairing-skill/agent-pairing/templates/owner-question.md agent-pairing-skill/agent-pairing/templates/owner-answer.md agent-pairing-skill/agent-pairing/templates/close.md agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "feat: replay agent-pairing v2 topics deterministically"
```

---

### Task 9: Bind verification to environment profiles and review severity

**Files:**
- Modify: `agent-pairing-skill/agent-pairing/templates/TOPIC.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/assignment.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/result.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/onboarding.md`
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md:218`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:325`
- Create: `agent-pairing-skill/agent-pairing/tests/v2/manual-contract.sh`
- Modify: `agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh`

**Interfaces:**
- Consumes: `verification_profile_id` from assignments and terminal-result verification evidence.
- Produces: project-pinned verification disposition and the exact three-severity/binary-verdict policy.

- [ ] **Step 1: Write failing manual-contract checks**

The contract script must require all of these literal rules in the primary manual/onboarding:

```text
unpinned red is a fact about the executor environment, not the snapshot
BLOCKING
GATE
NONBLOCKING
PASS = no BLOCKING findings and every GATE has tracker_ref plus owner
FAIL = any BLOCKING finding or any unmaterialized GATE
```

It must also instantiate a topic containing one profile with lock identity, bootstrap command,
verification command, runtime/tool versions, and environment variable names, then assert no
`{{UPPER_SNAKE_CASE}}` token survives.

- [ ] **Step 2: Run the manual-contract test and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/manual-contract.sh
```

Expected: nonzero because v1 manuals contain neither environment profile nor severity contract.

- [ ] **Step 3: Add the verification-profile section to topic and onboarding templates**

Use this exact generic body shape for each profile in the topic template:

```yaml
profile_id: {{VERIFICATION_PROFILE_ID}}
lock_identity: {{LOCK_IDENTITY}}
bootstrap_command: {{BOOTSTRAP_COMMAND}}
verification_command: {{VERIFICATION_COMMAND}}
required_tools: {{REQUIRED_TOOLS}}
required_environment_names: {{REQUIRED_ENVIRONMENT_NAMES}}
```

The manual-contract fixture instantiates those fields with `python-pinned`, a recorded `uv.lock`
SHA-256, `uv sync --frozen`, `uv run pytest -q`, captured Python/uv versions, and the environment
names `TEST_APP_DATABASE_URL_PG TEST_SYSTEM_DATABASE_URL_PG`. Secret values never enter the record.
Assignments use the profile ID or literal `null` for a non-verification turn.

- [ ] **Step 4: Encode environment disposition and severity mapping**

Require exact command plus captured output and resolved tool versions in participant evidence. An
unpinned failure cannot directly produce REJECTED; rerun under the assignment profile. If the
profile cannot be established, create a GATE with durable owner/tracker reference instead of a
correctness claim.

Define the binary mapping exactly as the design and state explicitly that v2.0 enforcement belongs
to the primary, not record-prose parsing.

- [ ] **Step 5: Run manual contract and package gates**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/v2/manual-contract.sh
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: both exit zero; no template tokens remain in the instantiated profile case.

- [ ] **Step 6: Commit environment and review policy**

```bash
git add agent-pairing-skill/agent-pairing/templates agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/tests/v2
git commit -m "docs: bind pairing verification to project environments"
```

---

### Task 10: Make `pair-with-primary` repository-owned and ACK-first

**Files:**
- Create: `agent-pairing-skill/pair-with-primary/SKILL.md`
- Create: `agent-pairing-skill/pair-with-primary/tests/run-tests.sh`
- Create: `agent-pairing-skill/pair-with-primary/tests/fixtures/committed-receipt/`
- Create: `agent-pairing-skill/pair-with-primary/tests/fixtures/uncommitted-receipt/`
- Modify: `agent-pairing-skill/agent-pairing/tests/run-tests.sh`

**Interfaces:**
- Consumes: topic ID/absolute path, committed assignment/intent/receipt, admission visibility/capability/report channel, and exact templates from Tasks 3–9.
- Produces: participant join/admission evidence, bounded committed-receipt wait, ACK-first report, one assigned turn, and author-finalized report manifest.

- [ ] **Step 1: Seed the repository package from the installed participant skill**

Copy the identical installed source into the repository as the starting point:

```bash
mkdir -p agent-pairing-skill/pair-with-primary
cp -f /Users/vlysovych/.codex/skills/pair-with-primary/SKILL.md agent-pairing-skill/pair-with-primary/SKILL.md
```

Before editing, assert the Claude and Codex installed copies match:

```bash
cmp -s /Users/vlysovych/.claude/skills/pair-with-primary/SKILL.md /Users/vlysovych/.codex/skills/pair-with-primary/SKILL.md
```

- [ ] **Step 2: Write failing participant contract tests**

The test must reject these v1 behaviors if they remain in the repository skill:

```text
git notes
read turns from ls on the record working tree
an unbounded or indefinitely repeated wait
start work before emitting ACK
report without byte_count and sha256
```

It must require `git show HEAD:PATH` or equivalent committed-object access,
`receipt_commit_by_epoch`, the exact tuple/token/admission/dispatch binding, both visibility-specific
ACK shapes, `report_channel`, `shasum -a 256`, UTF-8, and trailing-newline state.

- [ ] **Step 3: Run participant tests and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/pair-with-primary/tests/run-tests.sh
```

Expected: nonzero because the seeded v1 skill reads working-tree receipts, loops indefinitely, and
uses Git notes.

- [ ] **Step 4: Rewrite join and committed receipt waiting**

Resolve an absolute topic path directly. For a slug, check both runtime record roots and stop on
zero or multiple matches. Read `TOPIC.md`, assignment, intent, and receipt only with
`git -C "$TOPIC" show "HEAD:$PATH"` after `git cat-file -e` confirms the object.

The wait loop must be foreground and bounded by the intent:

```bash
FOUND_RECEIPT=no
while [ "$(date +%s)" -le "$RECEIPT_COMMIT_BY_EPOCH" ]; do
  HEAD_SHA="$(git -C "$TOPIC" rev-parse HEAD)" || exit 1
  if git -C "$TOPIC" cat-file -e "$HEAD_SHA:$EXPECTED_DISPATCH_REF" 2>/dev/null; then
    git -C "$TOPIC" show "$HEAD_SHA:$EXPECTED_DISPATCH_REF"
    FOUND_RECEIPT=yes
    break
  fi
  sleep 2
done
[ "$FOUND_RECEIPT" = yes ] || {
  printf 'receipt_wait: expired; worktree_writes: 0\n'
  exit 0
}
```

If the committed receipt did not appear, emit a zero-write expiry report and return control. Do not
leave a background monitor or silently repeat the wait forever.

- [ ] **Step 5: Rewrite ACK, work, and report behavior**

The first response after receipt observation is the exact ACK evidence. Only after the primary
captures it may the participant work. A visible participant runs HEAD/status preflight; an invisible
participant reports null observed fields plus exact `relayed_base_sha`.

After one turn, finalize report bytes once and emit:

```text
byte_count: output of LC_ALL=C wc -c
sha256: output of shasum -a 256
encoding: utf-8
trailing_newline: present or absent
```

Return through the admitted channel. Never write the record, update Git notes, dispatch another
agent, or manufacture a result SHA.

- [ ] **Step 6: Run participant and combined package gates**

Run:

```bash
/bin/bash agent-pairing-skill/pair-with-primary/tests/run-tests.sh
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: participant contract zero failed; primary package gate zero failed.

- [ ] **Step 7: Commit the repository-owned participant package**

```bash
git add agent-pairing-skill/pair-with-primary agent-pairing-skill/agent-pairing/tests/run-tests.sh
git commit -m "feat: add ACK-first pair-with-primary skill"
```

---

### Task 11: Reconcile the primary manual and add behavioral evaluation artifacts

**Files:**
- Modify: `agent-pairing-skill/agent-pairing/SKILL.md`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md`
- Modify: `agent-pairing-skill/agent-pairing/templates/onboarding.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/rubric.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/cases/participant-selection.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/cases/delivery-and-fence.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/cases/report-and-environment.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/baseline-v1.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/accepted-v2.md`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/capture-opus.sh`
- Create: `agent-pairing-skill/agent-pairing/tests/behavior/run-tests.sh`
- Modify: `agent-pairing-skill/agent-pairing/tests/run-tests.sh`

**Interfaces:**
- Consumes: every implemented v2 mechanism and participant instruction from Tasks 3–10.
- Produces: one internally consistent primary manual, one self-contained onboarding projection, and durable before/after behavioral evidence.

- [ ] **Step 1: Write the evaluation rubric before rewriting the remaining v1 prose**

The rubric has eleven binary cases:

```text
B01 explicit primary-spawn does not ask
B02 explicit owner-manual does not ask
B03 absent mode asks the exact selection question once
B04 contradictory mode asks the exact selection question once
B05 owner-manual publishes topic ID/path/prompt and starts no turn clock
B06 uncommitted receipt authorizes zero work
B07 missing ACK reaches committed fence before termination request
B08 result before ACK remains RESULT_BUFFERED and never synthesizes ACK
B09 unsearchable dispatch goes directly to one owner question
B10 manifest mismatch preserves both manifests and never normalizes bytes
B11 unpinned red cannot reject; severity mapping remains binary
```

Each captured evaluation entry records `case_id`, `manual_version`, `observed_action`,
`evidence_excerpt`, and `PASS|FAIL`. The runner rejects duplicate/missing case IDs and requires v1
to retain its captured disposition byte-for-byte, with RED at least for B06, B07, B08, B10, and
B11, while v2 passes B01–B11. Do not force B09 red: v1 already has an owner-question path for a
genuinely unsearchable transport.

- [ ] **Step 2: Run the behavioral artifact runner and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/behavior/run-tests.sh
```

Expected: nonzero until all case, baseline, and accepted-v2 artifacts exist and the primary manual
contains the complete v2 actions.

- [ ] **Step 3: Rewrite the primary lifecycle end to end**

Remove v1-only `OPEN (dispatched)`, absolute deadline, working-tree record read, primary receipt as
delivery proof, persistent waiter, inline report capture, and Git-note language. Keep the stationary
REVIEW gate, tree-equivalence sync/close proof, base pinning, append-only remediation, trailer/scope
verification, sole-scribe rule, and the rule that test reports are claims until evidence is checked.

The v2 lifecycle order must be:

```text
resolve participant mode → OPEN → admission → assignment → intent → transport submit →
receipt commit → wake → committed receipt observation → ACK capture → work → exact capture →
verification → result → next turn or close
```

- [ ] **Step 4: Rewrite RUNBOOK transport and recovery recipes**

For every admitted transport, document durable address kind, searchability and exact token-search
recipe or `unsearchable`, report channel, evidence class, visibility, capability, receipt timeout,
and ACK timeout. State that a monitor/waiter ID is inadmissible. Add exact actions for
`DISPATCH_UNKNOWN`, recovered uncommitted receipt re-stamping, ACK/work fencing, late events,
environment reruns, and stale/lossy report capture.

- [ ] **Step 5: Make onboarding a complete participant carrier**

The onboarding projection must contain committed-object read commands, intent receipt bound, exact
ACK shape, work due semantics, capability/visibility rules, report manifest, relay patch discipline,
environment profile, one-turn scope, commit trailers, and the DON'T list. Instantiate the template
in tests and reject any unresolved `{{UPPER_SNAKE_CASE}}` token.

- [ ] **Step 6: Populate the durable evaluation results**

Implement `capture-opus.sh` with this CLI:

```text
capture-opus.sh --manual-version v1|v2 --primary-skill FILE --runbook FILE --participant-skill FILE --cases DIRECTORY --output FILE
```

The script concatenates the three manual inputs and sorted case files into a checked temporary
prompt, instructs the reviewer to return all eleven rubric fields without tools, and invokes:

```bash
claude --model opus --effort xhigh --permission-mode plan --tools "" --no-session-persistence --print "$(<"$PROMPT_FILE")"
```

Before rewriting the repository manuals, extract the accepted v1 primary files from commit
`f3f50f7` into checked temporary files. The installed Claude/Codex participant files are still
identical before Task 14 and supply the v1 participant input. Capture both evaluations:

```bash
git show f3f50f7:agent-pairing-skill/agent-pairing/SKILL.md > /private/tmp/agent-pairing-v1-SKILL.md
git show f3f50f7:agent-pairing-skill/agent-pairing/RUNBOOK.md > /private/tmp/agent-pairing-v1-RUNBOOK.md
/bin/bash agent-pairing-skill/agent-pairing/tests/behavior/capture-opus.sh --manual-version v1 --primary-skill /private/tmp/agent-pairing-v1-SKILL.md --runbook /private/tmp/agent-pairing-v1-RUNBOOK.md --participant-skill /Users/vlysovych/.codex/skills/pair-with-primary/SKILL.md --cases agent-pairing-skill/agent-pairing/tests/behavior/cases --output agent-pairing-skill/agent-pairing/tests/behavior/baseline-v1.md
/bin/bash agent-pairing-skill/agent-pairing/tests/behavior/capture-opus.sh --manual-version v2 --primary-skill agent-pairing-skill/agent-pairing/SKILL.md --runbook agent-pairing-skill/agent-pairing/RUNBOOK.md --participant-skill agent-pairing-skill/pair-with-primary/SKILL.md --cases agent-pairing-skill/agent-pairing/tests/behavior/cases --output agent-pairing-skill/agent-pairing/tests/behavior/accepted-v2.md
```

Preserve observed model output as fenced text and keep the deterministic rubric disposition
separate. Sanitize paths, tokens, and environment values before committing. Do not replace the
historical v1 failures with inferred prose.

- [ ] **Step 7: Run behavioral, participant, and package gates**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/tests/behavior/run-tests.sh
/bin/bash agent-pairing-skill/pair-with-primary/tests/run-tests.sh
/bin/bash agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: B01–B11 accepted for v2, recorded v1 RED cases preserved, all shell gates zero failed.

- [ ] **Step 8: Commit the reconciled manuals and evaluations**

```bash
git add agent-pairing-skill/agent-pairing/SKILL.md agent-pairing-skill/agent-pairing/RUNBOOK.md agent-pairing-skill/agent-pairing/templates/onboarding.md agent-pairing-skill/agent-pairing/tests/behavior agent-pairing-skill/agent-pairing/tests/run-tests.sh
git commit -m "docs: reconcile agent-pairing manuals with protocol v2"
```

---

### Task 12: Rebuild the example as a closed v2 replay

**Files:**
- Create: `agent-pairing-skill/agent-pairing/example/build.sh`
- Create: `agent-pairing-skill/agent-pairing/example/rehydrate.sh`
- Create: `agent-pairing-skill/agent-pairing/example/README.md`
- Generate: `agent-pairing-skill/agent-pairing/example/topic-repo.bundle`
- Generate: `agent-pairing-skill/agent-pairing/example/work-repo.bundle`
- Generate: `agent-pairing-skill/agent-pairing/example/TOPIC_BRANCH`
- Generate: `agent-pairing-skill/agent-pairing/example/FINAL_SHA`
- Modify: `agent-pairing-skill/agent-pairing/tests/run-tests.sh`

**Interfaces:**
- Consumes: default v2 validator, templates, participant report contract, and close postconditions.
- Produces: deterministic source bundles whose rehydrated topic validates, renders stably, and ends `CLOSED` with tree/branch equivalence.

- [ ] **Step 1: Add an integration assertion for the existing example and verify RED**

Add to the package runner:

```bash
EXAMPLE="$HERE/../example"
EXAMPLE_TOPIC="$(/bin/bash "$EXAMPLE/rehydrate.sh" --print-topic)" || exit $?
/bin/bash "$HERE/../scripts/validate.sh" --check "$EXAMPLE_TOPIC" |
  grep -Fx 'classification: CLOSED' >/dev/null || exit 1
/bin/bash "$EXAMPLE/rehydrate.sh" --clean || exit $?
```

The new v2 `rehydrate.sh` expectations require:

```text
protocol_version: 2
classification: CLOSED
one admission
one valid ACK
one matching result-capture
one fence race represented as late evidence
```

Run the package gate; expect failure because the committed bundles are v1.

- [ ] **Step 2: Write a deterministic example builder**

`build.sh` must allocate checked temporary record/work repositories, create a pinned base, open a
topic in `owner-manual` mode, commit admission, execute one commit-bearing turn with ACK/capture,
execute one REVIEW turn that stays stationary, materialize one fenced late observation, close the
topic, run `validate.sh --check` and `--render`, and finally create both bundles.

Set deterministic author/committer identity and timestamps inside the builder:

```bash
export GIT_AUTHOR_NAME=agent-pairing-example
export GIT_AUTHOR_EMAIL=example@invalid
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export TZ=UTC
```

Every recursive delete must use the existing checked prefix guard.

- [ ] **Step 3: Regenerate and rehydrate twice**

Run:

```bash
/bin/bash agent-pairing-skill/agent-pairing/example/build.sh
cd /private/tmp
EXAMPLE_TOPIC="$(/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/example/rehydrate.sh --print-topic)"
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate.sh --check "$EXAMPLE_TOPIC"
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate.sh --render "$EXAMPLE_TOPIC"
cp -f "$EXAMPLE_TOPIC/THREAD.md" /private/tmp/agent-pairing-v2-thread.first
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate.sh --render "$EXAMPLE_TOPIC"
cmp -s /private/tmp/agent-pairing-v2-thread.first "$EXAMPLE_TOPIC/THREAD.md"
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/example/rehydrate.sh --clean
```

Expected: `classification: CLOSED`; the second render is byte-identical to the first. The package
gate repeats rehydration independently.

- [ ] **Step 4: Run full package regression**

Run:

```bash
cd /private/tmp
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/run-tests.sh
```

Expected: legacy `360 passed, 0 failed`, v2 zero failed, behavior zero failed, example CLOSED.

- [ ] **Step 5: Commit the v2 example**

```bash
git add agent-pairing-skill/agent-pairing/example agent-pairing-skill/agent-pairing/tests/run-tests.sh
git commit -m "test: add closed agent-pairing v2 replay example"
```

---

### Task 13: Implement four-destination transactional installation

**Files:**
- Create: `agent-pairing-skill/scripts/install.sh`
- Create: `agent-pairing-skill/tests/install-smoke.sh`
- Modify: `agent-pairing-skill/agent-pairing/RUNBOOK.md:198`

**Interfaces:**
- Consumes: repository `agent-pairing` and `pair-with-primary` packages, both validators, package tests, and zero or more explicit record roots.
- Produces: byte/mode-identical Claude and Codex installations or a coherent rollback to the previous four-package release.

- [ ] **Step 1: Write installer smoke tests before the installer**

Allocate one checked temporary root containing fake Claude/Codex homes, old package sentinels, and
record roots. Cover:

```text
empty source refused
relative source refused
filesystem-root source refused
missing explicit record root refused
missing configured default root reported and skipped
open v1 topic only under Claude default refuses
open v1 topic only under Codex default refuses
closed v1 topics under both defaults permit install
v2 topic uses default v2 validator
source validation failure leaves all four old packages
failure after first swap restores all four old packages
failure during post-install validation restores all four old packages
success installs all four packages with source byte/mode parity
```

Use `AP_INSTALL_FAIL_AT=after-first-swap` and `AP_INSTALL_FAIL_AT=post-install-validation` as explicit
failure-injection points available only to the smoke harness.

- [ ] **Step 2: Run installer tests and verify RED**

Run:

```bash
/bin/bash agent-pairing-skill/tests/install-smoke.sh
```

Expected: nonzero because `scripts/install.sh` does not exist.

- [ ] **Step 3: Implement argument parsing and destructive-path guards**

Support:

```text
--source ABSOLUTE_REPO_AGENT_PAIRING_SKILL_DIR
--claude-root ABSOLUTE_CLAUDE_HOME
--codex-root ABSOLUTE_CODEX_HOME
--record-root ABSOLUTE_RECORD_ROOT
```

`--record-root` is repeatable. With none supplied, inspect both
`CLAUDE_ROOT/agent-pairing` and `CODEX_ROOT/agent-pairing`; report and skip a missing default. Refuse
empty, relative, `/`, whitespace-only, and `..`-escaping paths before `mkdir`, move, or removal.

- [ ] **Step 4: Implement the open-v1 deployment gate**

Enumerate direct child topic repositories under every selected record root. A missing
`protocol_version` is historical v1; explicit `1` is v1; exact `2` is v2; any other value blocks
deployment. Run the corresponding validator from the source package. A v1 topic permits deployment
only when its exact classification is `CLOSED`.

- [ ] **Step 5: Implement stage, manifest verification, swap, and rollback**

For each runtime root, stage both packages beside `ROOT/skills`. Build a sorted manifest containing
relative path, mode, byte count, and SHA-256, excluding `.DS_Store`. Validate source and every stage
from `/private/tmp` before changing a live destination.

Save all four old destinations, then swap in this order:

```text
Claude agent-pairing
Claude pair-with-primary
Codex agent-pairing
Codex pair-with-primary
```

Track each completed rename. A trap restores every saved destination in reverse order and removes a
new destination that previously had no installation. Delete backups only after all four
post-install validations and manifest comparisons pass.

- [ ] **Step 6: Make the smoke suite prove rollback and parity**

After every injected failure, assert all four old sentinel files and their hashes remain. After
success, compare source and installed manifests byte-for-byte and run:

```bash
/bin/bash "$CLAUDE_ROOT/skills/agent-pairing/tests/run-tests.sh"
/bin/bash "$CODEX_ROOT/skills/agent-pairing/tests/run-tests.sh"
/bin/bash "$CLAUDE_ROOT/skills/pair-with-primary/tests/run-tests.sh"
/bin/bash "$CODEX_ROOT/skills/pair-with-primary/tests/run-tests.sh"
```

- [ ] **Step 7: Run installer and source gates from a neutral directory**

Run:

```bash
cd /private/tmp
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/tests/install-smoke.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/run-tests.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/pair-with-primary/tests/run-tests.sh
```

Expected: installer failures are caught and rolled back; success has four-way parity; all source
gates report zero failed.

- [ ] **Step 8: Commit transactional installation**

```bash
git add agent-pairing-skill/scripts/install.sh agent-pairing-skill/tests/install-smoke.sh agent-pairing-skill/agent-pairing/RUNBOOK.md
git commit -m "feat: install agent-pairing skills transactionally"
```

---

### Task 14: Run the release gate, deploy only after topic safety, and capture discovery evidence

**Files:**
- Create: `agent-pairing-skill/docs/implementation/2026-08-14-agent-pairing-protocol-v2-release-evidence.md`
- Modify only if a gate exposes a defect: files owned by Tasks 1–13

**Interfaces:**
- Consumes: complete repository implementation and transactional installer.
- Produces: fresh verification evidence, a pushed implementation branch, four coherent installed packages, and fresh-session skill discovery evidence.

- [ ] **Step 1: Verify no unrelated files are staged**

Run:

```bash
git status --short
git diff --check
git diff --cached --check
```

Expected: only protocol-v2 implementation paths are modified/staged; `.DS_Store` remains untracked
and excluded.

- [ ] **Step 2: Run every source gate from `/private/tmp`**

Run:

```bash
cd /private/tmp
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/run-v1-tests.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/v2/run-tests.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/tests/behavior/run-tests.sh
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/pair-with-primary/tests/run-tests.sh
EXAMPLE_TOPIC="$(/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/example/rehydrate.sh --print-topic)"
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate.sh --check "$EXAMPLE_TOPIC"
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/example/rehydrate.sh --clean
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/tests/install-smoke.sh
```

Expected: v1 `360 passed, 0 failed`; every v2/behavior/participant/install suite zero failed; example
prints `classification: CLOSED`.

- [ ] **Step 3: Run Bash and placeholder checks**

Run:

```bash
/bin/bash -n /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate.sh
/bin/bash -n /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing/scripts/validate-v1.sh
/bin/bash -n /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/scripts/install.sh
rg -n 'TB''D|TO''DO|FIX''ME|{{[A-Z][A-Z0-9_]*}}' /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/agent-pairing /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/pair-with-primary /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/scripts
```

Expected: syntax commands exit zero. The token scan may match canonical templates; instantiate every
matched template in the test harness and require the rendered copies to have no token matches.

- [ ] **Step 4: Commit any gate-driven correction separately, then synchronize the repository**

If Step 2 or 3 required a correction, repeat the failing focused test, full relevant suite, and
then commit only that correction. When the tree is verified:

```bash
git pull --rebase
git push origin main
git status --short --branch
```

Expected: push succeeds and status reports `main...origin/main`, apart from known untracked
`.DS_Store` files.

- [ ] **Step 5: Run the live open-topic gate without bypass**

Run the installer in validation mode if implemented, or its normal preflight before swaps. It must
inspect both `~/.claude/agent-pairing` and `~/.codex/agent-pairing`. If any v1 topic is not CLOSED,
stop the deployment and close that topic under v1; never edit the live package to bypass the gate.

- [ ] **Step 6: Deploy the one verified release to both runtimes**

Run:

```bash
/bin/bash /Users/vlysovych/Personal/projects/skills/agent-pairing-skill/scripts/install.sh --source /Users/vlysovych/Personal/projects/skills/agent-pairing-skill --claude-root /Users/vlysovych/.claude --codex-root /Users/vlysovych/.codex
```

Expected: source validation, four stages, four swaps, four post-install validations, and cross-root
byte/mode parity all succeed. Any failure restores all four previous packages.

- [ ] **Step 7: Verify fresh-session discovery and record evidence**

Start one new Claude session and one new Codex session after deployment. In each, use these exact
prompts and capture the response plus resolved skill path:

```text
Use agent-pairing. I will pair the secondary manually by topic ID. Explain only how participant selection is resolved before OPEN.
```

```text
Use pair-with-primary. Explain only whether you read an uncommitted dispatch receipt or update Git notes.
```

The first answer must select `owner-manual` without asking. The second must say committed receipt
only and no Git notes. Record commands, output, installed paths, source commit, installer result,
and manifest hashes in the release-evidence document without secrets.

- [ ] **Step 8: Commit and push release evidence**

```bash
git add agent-pairing-skill/docs/implementation/2026-08-14-agent-pairing-protocol-v2-release-evidence.md
git commit -m "docs: record agent-pairing v2 release evidence"
git pull --rebase
git push origin main
git status --short --branch
```

Expected: local and remote main match; installed package manifests match the pushed source commit.

---

## Requirements Coverage

| Accepted design requirement | Implemented by |
| --- | --- |
| Explicit v2 and frozen v1 validator | Tasks 1–2 |
| Prompt-specified spawn/manual choice and one fallback question | Tasks 3 and 11 |
| Durable transport admission and searchability | Task 3 |
| Receipt commit bound and two clocks | Task 4 |
| Re-stamped validated-uncommitted receipt | Task 4 |
| ACK tuple/token/job/admission/evidence binding | Task 5 |
| Visibility-aware preflight and relay-base binding | Task 5 |
| Capability/report-channel compatibility | Tasks 5–6 |
| Exact report bytes and author/observed manifests | Task 6 |
| Result-before-ACK buffering | Task 7 |
| Durable ACK/work fence and late-event precedence | Tasks 7–8 |
| Full replay state set, owner actions, drift, and close | Task 8 |
| Environment parity and severity vocabulary | Task 9 |
| Repository-owned participant skill; no Git notes | Task 10 |
| Behavioral evaluation contract and preserved v1 safety | Task 11 |
| Rehydrated v2 example ending CLOSED | Task 12 |
| Four-destination transactional deployment and dual-root v1 gate | Task 13 |
| Neutral-CWD verification and fresh-session discovery | Task 14 |

## Plan Self-Review Checklist

- [x] Every design acceptance criterion maps to at least one task in Requirements Coverage.
- [x] Every created or modified file appears in the File Responsibility Map or a task file list.
- [x] Function names and record fields are spelled identically in producing and consuming tasks.
- [x] Every implementation task contains a RED command, a minimal implementation action, a GREEN command, and a focused commit.
- [x] The v1 `360 passed, 0 failed` gate runs after every validator-facing slice.
- [x] No task edits an installed package directly before the transactional deployment step.
- [x] No task introduces v2.1 ledger work, v3 worktrees, background monitors, or parallel turns.

## Execution Handoff

Plan complete and saved to `agent-pairing-skill/docs/implementation/2026-08-14-agent-pairing-protocol-v2-implementation-plan.md`. Two execution options:

1. **Subagent-Driven** — the primary spawns a fresh implementation worker per task and reviews between tasks. This requires an explicit `primary-spawn` choice before work begins.
2. **Inline Execution** — execute the tasks in this session with `superpowers:executing-plans`, in batches with review checkpoints.

If the owner prefers manual pairing, open an agent-pairing topic in `owner-manual` mode and return its topic ID instead of spawning a worker.
