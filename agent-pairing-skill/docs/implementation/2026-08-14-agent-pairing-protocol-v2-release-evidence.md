# Agent-Pairing Protocol v2 — Release Evidence

**Released:** 2026-08-17 · **Source commit:** `dc72ca6363166ccc3e49e2a17576a51f9f91bbfe`
**Branch:** `feat/agent-pairing-protocol-v2` (pushed to `origin`; integration into `main` is the
owner's decision and is not part of this plan)

## Live topic inventory and disposition

The gate refuses deployment unless every valid topic classifies exactly `CLOSED`. The inventory
below was refreshed immediately before the swap; it is **not** the four-row table the plan carried
from review time, which had gone stale — nine topics existed, not four.

| Topic | State before | Disposition | State after |
| --- | --- | --- | --- |
| `agent-pairing-v2-plan-review-round-2` | `CLOSED` | none needed | `CLOSED` |
| `demo` | `OPEN (dispatched)` | closed under owner-confirmed termination (records 0028–0031) | `CLOSED` |
| `invoicing-dual-mode-architecture-options-review` | `CLOSED` | none needed | `CLOSED` |
| `invoicing-platform-integration-implementation-review` | `IDLE` | closed (record 0041) | `CLOSED` |
| `invoicing-platform-onboarding-design-review-v2` | `CLOSED` | none needed | `CLOSED` |
| `invoicing-platform-onboarding-design-review` | frozen-v1 **exit 2** | **archived** outside the live root | not enumerated |
| `invoicing-platform-onboarding-final-design-approval` | `CLOSED` | none needed | `CLOSED` |
| `invoicing-platform-onboarding-plan-review` | `CLOSED` | none needed | `CLOSED` |
| `invoicing-platform-onboarding-revised-design-review` | `CLOSED` | none needed | `CLOSED` |

Owner: Vitaliy L. All dispositions were directed by the owner in-session.

### `demo` — closed under owner-confirmed termination

Attempt `t0006-a01` (REVIEW) was dispatched 2026-08-13T06:45:30Z on transport `live-session-loop`,
job `codex-terminal-pair-loop-4`, and never returned. Observed at close: the session worktree was
clean and stationary at `eeae73eaefb56d2467b7a2ae4252da43ae0a704d` — tip = HEAD = accepted SHA — and
the record repository was clean. Nothing had landed and there was no residue.

Closed through the v1 protocol rather than by editing: owner question `0028` → owner answer `0029`
(`dispatch-termination-confirmed`, with the evidence recorded) → result `0030`
(`ABORTED: terminated-before-result`, `result_sha: null`, citing the answer) → close `0031` →
`THREAD.md` rendered and committed with the postconditions satisfied.

**Note on ordering:** the first render produced a `THREAD.md` without `status: CLOSED`, because the
worktree was still registered and the topic still classified `CLOSING`. The postconditions have to be
*satisfied* before the render that proves them. Worktree retired, then re-rendered.

### `invoicing-platform-integration-implementation-review` — closed from `IDLE`

Ten turns, each with a terminal result, no unanswered owner question, branch already at the accepted
SHA `be35652ff38d1a7b76c40bc970a60979e84f00b4`. Close record `0041`, worktree retired, rendered.

`IDLE` is not deployment-safe: it has no in-flight turn, but it can still accept a later v1 turn,
which would leave a v1 record being worked under v2 manuals.

The host repository (`~/Work/Projects/invoicing_system`) was **not** otherwise touched: it remains on
`dev`, and `pair/invoicing-platform-integration-implementation-review` still stands at the same
commit. Only the pairing worktree was retired.

### `invoicing-platform-onboarding-design-review` — archived, not rewritten

The frozen validator cannot classify it: its records carry `record_seq: 1` where the grammar requires
`0001`, producing `SEQ_FILENAME_MISMATCH` and `WIDTH` on every record.

Such a topic can never reach `CLOSED`, and the protocol forbids rewriting committed records to make
them pass. The design names two remaining options — an owner-authorized acknowledgement, or archival
outside the live roots. **Archival was chosen**, because an acknowledgement asserts
`no_live_participant: true` with durable liveness evidence, and that is an owner's assertion to make
rather than an implementer's.

Moved intact to `~/.claude/agent-pairing-archive/`:

```
HEAD before / after:  871c8b18d22104e547820a1c45b0c6ecadc54bc7
tree before / after:  98529c364e2790c5c3d5387a2b205247d340fdc6
```

Not one committed byte changed. Its session worktree was deliberately **left in place**: removing it
would destroy residue evidence, and archival is about removing the topic from a gate it can never
satisfy, not about tidying up.

**No legacy-invalid acknowledgement was created or used in this release.** The
`--legacy-invalid-ack` path is implemented and smoke-tested but was not exercised against live data.

## Installation

```
install.sh --source /Users/vlysovych/Personal/projects/skills/agent-pairing-skill \
           --claude-root /Users/vlysovych/.claude \
           --codex-root  /Users/vlysovych/.codex
```

Result: `release installed to all four destinations`.

- Topic gate: 8 topics inspected under `~/.claude/agent-pairing`, all `CLOSED`.
  `~/.codex/agent-pairing` does not exist and was **reported and skipped** — a configured default
  that is absent is skipped, while an explicitly passed `--record-root` that is absent is an error.
- Source gate, staged gate, and both installed gates: all passed.
- Cross-root parity verified for both packages.

### Manifest digests (SHA-256 over the sorted per-file digests)

| Package | Source | Claude | Codex |
| --- | --- | --- | --- |
| `agent-pairing` | `150c8f53c0ef…8ffa` | `150c8f53c0ef…8ffa` | `150c8f53c0ef…8ffa` |
| `pair-with-primary` | `6e19b48d2b12…b072` | `6e19b48d2b12…b072` | `6e19b48d2b12…b072` |

Full values:

```
agent-pairing      150c8f53c0efbd8296e27d1764fb32413cf8be527dbd8ab07671c1d9c0028ffa
pair-with-primary  6e19b48d2b12f3de34a97d221dfd022842071ce3f5f4881e2b469f7f5079b072
```

## Gate results at the released commit

| Suite | Result |
| --- | --- |
| Frozen v1 regression | `360 passed, 0 failed` |
| v2 validator | `136 passed, 0 failed` |
| Manual contract | `19 passed, 0 failed` |
| Behavioral artifacts | `36 passed, 0 failed` |
| Participant contract | `30 passed, 0 failed` |
| Example replay | `CLOSED`, with a fenced attempt and its late evidence |
| Installer smoke | `29 passed, 0 failed` |

All run from `/private/tmp`, a neutral non-repository directory.

### On the frozen v1 count

The plan's Global Constraints froze this gate at `360 passed, 0 failed`. That number is not constant:
a handful of v1 cases are derived from shared, non-frozen inputs — one `referenced path exists:`
assertion per template path named in `SKILL.md`. It is now pinned by exact count in
`agent-pairing/tests/run-tests.sh` with a per-increment ledger, so a **lost** v1 case is as loud as
an added one. "0 failed" alone would have hidden a deletion. The ledger currently reads:

```
360  the frozen baseline
 +1  Task 3  templates/admission.md referenced by SKILL.md
 -2  Task 4  record-template instantiation MOVED to tests/v2
 +1  Task 5  templates/ack.md referenced by SKILL.md
```

The `-2` is the one deviation worth reading twice: v2 templates cannot produce a valid *v1* topic by
construction, so validating them with the frozen validator asserted the opposite of the compatibility
boundary. Those two cases moved to the v2 suite, which validates them against the validator that owns
the grammar.

## Plan deviations

| # | Deviation | Why |
| --- | --- | --- |
| D1 | The v1 harness's D27/D28 structural guards were retargeted from `$HERE/run-tests.sh` to `$0` | The freeze renamed the harness, so that path silently resolved to the new v2 runner and the guards stopped inspecting the 1955-line harness they exist to protect |
| D2 | Two record-template instantiation cases moved from the v1 harness to the v2 suite | See above |
| D3 | The frozen gate is pinned by exact count rather than by the literal number `360` | See above |
| D4 | **The plan's participant wait-loop snippet is wrong** and was not transcribed | The plan probes `"$HEAD_SHA:$EXPECTED_DISPATCH_REF"`, but `expected_dispatch_ref` holds a **basename**, so that probe can never resolve. `pair-with-primary/SKILL.md` uses `"$HEAD_SHA:turns/$EXPECTED_DISPATCH_REF"`, and the participant contract extracts and executes that line against two fixtures differing only in committedness |
| D5 | `AP_INSTALL_SKIP_SUITES` added to the installer | The installer runs the full gate four times per release; the smoke harness drives it a dozen times to exercise guards, gate, swap and rollback, none of which the suites affect. One smoke case deliberately runs the full path. A release must never set it |
| D6 | The example build root is a pinned path, not `mktemp` | A per-run root was embedded in `TOPIC.md` and every assignment, so the topic bundle changed on every build while the README claimed byte-identical commits |
| D7 | `tests/behavior/rubric.md`'s expected-v1 column corrected for B03/B04 from PASS to RED | The captured baseline disagreed with the rubric, and the plan pins the capture byte-for-byte. Answering correctly *because the manual settles it* and answering correctly *by accident* are different properties |
| D8 | Behavioral case B13 was sharpened after a first capture | The evaluator answered from v1's relay-patch manifest rule, which v1 genuinely has; the defect the investigation recorded was on the **ordinary report** path, where v1 had no manifest at all. The case was ambiguous between the two |

## Defects found by review, and closed

Twenty-two demonstrated fail-opens were found across the branch, each reproduced before being fixed
and each now carrying a regression fixture. The ones worth remembering:

1. **`ls-tree | sort` reported sort's status** — a repository with committed records and a deleted
   tree object exited 0 as `AWAITING_PARTICIPANT`: a corrupt topic classified as a clean one.
2. **Committed record paths were glob-expanded** — a record named `turns/000[6]-close.md` was
   replaced by whichever real file matched the *current directory*. From `/tmp` it was rejected; from
   inside the topic it exited 0, never parsed. Same records, opposite verdicts depending on cwd.
3. **`git status --porcelain` never reports ignored files** — one `.gitignore` line hid a
   half-written receipt entirely.
4. **`rev-parse --git-dir` walks upward** — a directory of record files inside *any* other repository
   was accepted, and every `HEAD:` read resolved against that repository's tree.
5. **A close written over a live open attempt reached `CLOSED`**, silently ending a running agent's
   lease.
6. **A close naming an unexplained tip as `final_accepted_sha` reached `CLOSED`**, laundering drift
   into the one state this gate trusts.
7. **`ABORTED: ack-timeout` was unrecordable** — a fail-*closed* defect. The design authorizes it for
   a clean stationary fenced attempt; such an attempt has no ACK by definition, so its result must
   carry `ack_ref: null`, which the reason list forbade.
8. **A fence could skip its due-epoch check entirely** by naming a receipt that did not resolve — the
   durable boundary's only checkable temporal claim, bypassable.
9. **A committed `patch.diff` with no manifest was accepted unverified** — the stale-capture hole,
   reopened for the bytes about to be applied to the work repo.

Three recurring causes are worth naming, because they produced most of the rest:

- **Subshell state loss.** A helper that returns a value must be called as `$(...)`, and every
  `v2_fail` it makes there increments a counter that dies with the subshell — the check printed to
  stderr and the run still exited 0. This happened three times: `v2_stage_committed`'s slot counter,
  `v2_resolve_attempt_ref`'s violation reporting, and the smoke harness's own `new_env`.
- **Presence instead of exclusivity.** Assertions that checked "the expected code appears" rather
  than "the expected code is the only code" masked a real blocker for several commits. Tightening
  that one assertion surfaced it immediately.
- **Guards matching their own source.** Two structural scans had to have their search terms assembled
  from fragments, because written literally they matched the very lines that forbid the defect.

## Fresh-session discovery

Both prompts run in fresh non-interactive sessions against the **installed** packages, with tools
disabled so the answers come from the manuals rather than from reading the repository.

### Primary

> Use agent-pairing. I will pair the secondary manually by topic ID. Explain only how participant
> selection is resolved before OPEN.

**PASS.** Selected `owner-manual` without asking, and stated the whole owner-manual contract
unprompted: return the topic ID, the absolute record path, and the literal join prompt, then stop;
create no assignment, intent, or ACK budget because there is no participant to bind them to; the
topic sits at `AWAITING_PARTICIPANT` until the admission commits, which is what moves it to `IDLE`.

**This check earned its place.** On the first run the primary answered correctly in every respect
*except* that it recorded `participant_selection_source: owner-answer`, reasoning that the owner had
told it the mode. Every request comes from the owner, so "the owner told me" does not distinguish the
two cases — the field records **whether you had to ask**. The manual was ambiguous, not the agent.
Clarified, redeployed, and re-run: the second run selects `initial-prompt` and states the test
explicitly ("records only whether I had to ask").

A validator fixture could not have caught this. Both values are legal scalars and both produce a
valid topic; only an agent reading the manual and choosing could expose it.

### Participant

> Use pair-with-primary. Explain only whether you read an uncommitted dispatch receipt or update Git
> notes.

**PASS.** "I read committed dispatch receipts only — never the uncommitted working tree — and I never
write or update Git notes; the primary is the record's sole writer." Both v1 defects named and
refused, unprompted.

## Whole-branch review

Two independent reviews ran against the finished branch.

**Codex — reject**, four findings, all reproduced and fixed: two installer rollback flaws (a
space-containing path split by word-splitting so rollback ran `rm -rf` on a path nobody named; backup
slots derived from a root's basename colliding when two roots shared one), a fence able to precede
the receipt whose timeout it claimed, and `AP_INSTALL_SKIP_SUITES` being an unrestricted production
bypass. It also correctly flagged that acceptance criterion 12 was overclaimed — see below.

**Fable — accept with fixes**, and its blocker was the most serious defect found in the whole
project: **a `VERIFIED` result committed after a fence dissolved the boundary**, advanced the
accepted SHA past it, and — because `CLOSE_SHA_MISMATCH` compares a close against the same fold that
result had just moved — could carry a fenced attempt all the way to `CLOSED`. The same laundering
pattern this branch had already closed twice, arriving through the one seam left open. Fixed: after a
fence commits, an `ack` or `result-capture` for that attempt is a violation (post-fence evidence
belongs in a `late` record), and the terminal status is restricted to `ABORTED` or `REJECTED`.

Fable also found that the RUNBOOK's install section had never been reconciled with the Task 13
installer — it still documented a hand-rolled, ungated, single-package procedure that an agent would
have followed literally, performing exactly the deploy the design's criterion 16 exists to prevent.
Rewritten.

Its mutation testing found the real gap behind these: deleting `LINK_TUPLE_MISMATCH` left the entire
v2 suite green. That rule now has a fixture, and the sweep of unasserted codes is recorded as
follow-up work below.

## Follow-up work, not done in this release

- **Violation-code coverage sweep.** Of 94 `v2_fail` codes, roughly 37 are never asserted by name.
  Not all are uncovered — several fire through sibling assertions — but at least one
  (`LINK_TUPLE_MISMATCH`) was provably uncovered and is now fixed. The rest should be swept: add a
  one-defect fixture per reachable code, and delete any that are provably unreachable.
- **`tests/v2/live.sh`** appears in no plan task or file-responsibility map. It is sound and keeps the
  gate offline, but it is an unrecorded structural addition.
- **Unknown front-matter keys** on records are tolerated. Required-key lists make dangerous
  misspellings fail closed, so this is a nit rather than a hole.

## Known limits of what the records can prove

Two acceptance criteria are worth stating precisely, because the honest scope is narrower than a
casual reading suggests.

**Criterion 12 — "Participant reports use the admitted channel and never Git notes."** The
*never Git notes* half is genuinely enforced: the participant never updates a ref, and the contract
suite refuses any Git-note idiom in the manual's code. The *admitted channel* half is **not
physically verifiable from records** — nothing in a Git repository can prove which pipe carried a
string. The capture record now carries `report_channel` and the validator binds it to the admission,
so a mismatch is a visible record-level defect rather than an unbacked claim; but it remains the
primary's own report. Anyone relying on this should read it as "the record states the channel and
cannot contradict the admission", not as proof of transport.

**Criterion 15 — review verdict mapping.** Primary-enforced in v2.0 by design. The validator does not
parse findings prose and makes no claim to. What is testable is that the manual states the mapping
exactly, which `manual-contract.sh` pins verbatim against the design's own words.

## Backup

Every live record repository was copied before any disposition, to
`/private/tmp/agent-pairing-live-backup-20260817-154200` (9 topics, 5.4 MB). This is a temporary
path and will not survive a reboot; the durable copies are the topics themselves and the archive.
