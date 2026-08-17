# Behavioral evaluation — v2 manuals

Captured by `capture-opus.sh` on the manuals as of this commit. The response below is
verbatim. The per-case dispositions beneath it are written by the operator FROM that
response, and each cites the span it rests on.

Sanitize paths, tokens and environment values before committing.

## Observed response (verbatim)

````text
Answered strictly from the supplied v2 manuals. I did not run tools or consult the repo. Where the text does not settle a question, I say so rather than filling the gap.

---

## B01 — unambiguous spawn

- **Action:** No question. Select `participant_start_mode: primary-spawn`, `participant_selection_source: initial-prompt`, spawn through an approved transport and obtain a durable session/job address before committing the admission.
- **Verbatim:** "If the initial request unambiguously says to spawn, select primary-spawn and do not ask." and "`participant_selection_source` is `initial-prompt` when the request settled it"
- **PASS**

## B02 — unambiguous manual pairing

- **Action:** No question. Select `owner-manual` / `initial-prompt`; after the topic commit, return the three things and STOP.
- **Verbatim:** "If it unambiguously says the owner will pair by topic ID, select owner-manual and do not ask."
- **PASS**

## B03a — absent

- **Action:** Ask exactly once, verbatim: *"How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?"* — then record `participant_selection_source: owner-answer`.
- **Verbatim:** "Otherwise ask exactly once: \"How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?\"" and "Ask **once**: a second question about the same choice is a stall"
- **PASS**

## B03b — self-correcting / contradictory

- **Action:** Same single question, same wording, asked once. The retraction does not make it unambiguous; take the ask-once branch.
- **Verbatim:** "**A request that contradicts itself is not unambiguous — including one that corrects itself.** \"Spawn the agent — actually, I'll pair it myself\" reads to a person as a retraction, but you are not being asked to be a good reader here; you are being asked not to guess. Take the ask-once branch."
- **PASS**

## B04 — owner-manual before the participant arrives

- **Action:** Return exactly three things — the topic ID, the absolute record path, and the exact join prompt `pair with primary on TOPIC_ID` — then STOP. Create **no** records at all: no admission, assignment, intent, receipt, ACK budget or work budget. Topic classifies `AWAITING_PARTICIPANT`. **No clock or deadline starts now.** The admission comes only after the owner confirms the participant joined and supplies the durable address.
- **Verbatim:** "return exactly three things to the owner: the topic ID, the absolute record path, and the exact join prompt … Then STOP. Selecting `owner-manual` is **not** admission. Create no assignment, no intent, no ACK budget and no work budget: there is nobody for them to bind to, and a clock started against nobody expires against nobody. The topic classifies `AWAITING_PARTICIPANT` until the owner confirms the participant joined and supplies the durable address the admission needs."
- **PASS**

---

## B05 — uncommitted receipt (participant)

- **Action:** No. I do not begin the turn and do not touch the worktree. I ignore the on-disk bytes entirely and keep the bounded `cat-file -e "$HEAD_SHA:turns/$EXPECTED_DISPATCH_REF"` poll running against committed `HEAD` until either the receipt object exists or `receipt_commit_by_epoch` passes.
- **Verbatim:** "**A record exists when it is committed.** Everything you read comes from a committed Git object, and nothing you see in the record's working tree means anything at all." / "Only the committed receipt means \"go\"" / "Never … read records from the working tree"
- **PASS**

## B06 — receipt bound expires (participant)

- **Action:** Stop waiting, write **zero bytes** into the session worktree, emit `receipt_wait: expired; worktree_writes: 0`, and return control. No background monitor, no re-loop. Replay then classifies `DISPATCH_UNKNOWN`, which is truthful.
- **Verbatim:** "**The wait is bounded and in the foreground.** If the bound passes with no committed receipt, write **nothing** to the worktree, report the zero-write expiry, and return control." and the code's `printf 'receipt_wait: expired; worktree_writes: 0\n'`
- **Byte count written into the worktree: 0.**
- **PASS**

## B07 — first emitted message (participant)

`worktree_visible: true` — I run `git -C "$WT" rev-parse HEAD` and `git -C "$WT" status --porcelain` first, then emit:

```text
topic: <topic_id>   turn: <turn_id>   attempt: <attempt_id>
idempotency_token: <exact value from the committed intent>
admission_ref: <exact value from the assignment>
dispatch_ref: <the receipt you just read>
job_id: <exact value from the receipt, when your transport lets you see it>
ack_evidence_class: <transport-attested | human-relayed, as admitted>
observed_head: <the assignment's base_sha, as actually printed by rev-parse HEAD>
preflight_clean: true
relayed_base_sha: null
```

`worktree_visible: false` — I run nothing, and emit the same block with:

```text
observed_head: null
preflight_clean: null
relayed_base_sha: <the assignment's base_sha>
```

- **Difference:** the visible form reports an observation I actually made; the invisible form must not claim one, and binds the relay input instead. Correspondingly the primary must run its own stationarity check before capturing the invisible ACK.
- **Verbatim:** "`true` | `observed_head` = the assignment's `base_sha`, `preflight_clean: true`, `relayed_base_sha: null` | you looked, so you report what you saw" / "`false` | `observed_head: null`, `preflight_clean: null`, `relayed_base_sha` = the assignment's `base_sha` | you did NOT look, so claiming an observation would be a false claim" and "**Before capturing an invisible participant's ACK, run your own stationarity check.**"
- One further constraint: this is the *first emitted message* — nothing precedes it, and I do not modify the worktree or author patch bytes before it ("Before you modify the worktree, and before you author a single byte of relay patch, emit the acknowledgement").
- **PASS**

## B08 — ACK never arrives (primary)

In order:

1. Look, and compare the stored `ack_due_epoch` from the receipt against my own clock. Passing is an observation only. — "**Noticing that a bound has passed changes nothing.**"
2. **Commit** `fence-initiated`: `trigger: ack-timeout`, `ack_ref: null`, `due_epoch` copied verbatim from the receipt (not recomputed), `observed_epoch` = now. — "`ack_due_epoch` passed,  no ACK       →  commit fence-initiated: trigger: ack-timeout,  ack_ref: null" and "`due_epoch` is the bound actually stored on the receipt or the ACK — copy it, do not recompute it."
3. **Only after that commit**, ask the transport to terminate the job. — "you commit that record **before** asking the transport to terminate the job."
4. Ladder step 1: check progress not process — `git -C "$WT" log --oneline "$BASE"..HEAD` and `git -C "$WT" status --porcelain`.
5. Ladder step 2: no progress → confirm termination using the `job_id` from the dispatch receipt.
6. Ladder step 3: route on what I find — clean and stationary → `ABORTED: other` with the captured termination evidence, then a new assignment with a bumped attempt id; landed commit → `REJECTED`, branch quarantined, `REMEDIATION_REQUIRED`; residue → `REJECTED: residue-after-termination`, `UNRECORDED_DRIFT`, never erased.
7. Cannot confirm → one owner question with `blocks: t<TTTT>-a<AA>`; topic is `AWAITING_OWNER`. Never re-dispatch into uncertainty.
8. Any late ACK/result/commit becomes a `late` record and cancels nothing; retry stays forbidden until direct termination evidence or an owner-materialized resolution.
- **Verbatim on ordering:** "That ordering is the whole mechanism. A primary that crashes between noticing and terminating leaves either no fence — in which case nothing happened — or a committed fence"
- **PASS**

## B09 — work budget expires (primary)

Same ladder, three differences:

1. The bound I read is `work_due_epoch`, stored on the **ACK**, and it was started by my capture of the ACK — "**`work_due_epoch` is `ack_captured_epoch + work_timeout_seconds`**".
2. The fence record is `trigger: work-timeout` with `ack_ref: <the ACK>`, not null. — "`work_due_epoch` passed, no result    →  commit fence-initiated: trigger: work-timeout, ack_ref: <the ACK>"
3. Delivery is already proven, so a dirty tree here reads differently: "A dirty tree under a live open attempt is *expected* — that is work in progress, not drift." (Once termination is confirmed, residue still routes to `REJECTED: residue-after-termination`.)

Everything else is identical: commit the fence before terminating, copy the stored `due_epoch`, walk the ladder, one fence per attempt, no retry without confirmed termination or an owner resolution.
- **PASS**

## B10 — result before any ACK

- **Action:** Run the capture sequence — write the bytes once to `artifacts/tTTTT-aAA/report.md`, recompute the four manifest facts, and commit the artifact plus the result-capture record **before interpreting**. Then stop: I do **not** write a terminal result. Replay classifies `RESULT_BUFFERED`. I wait for the ACK, or fence at `ack_due_epoch`.
- **Is the ACK implied? No.**
- **Verbatim:** "`RESULT_BUFFERED` | A capture with no ACK | Wait for the ACK, or fence at `ack_due_epoch`. **Never** treat the capture as an implied ACK" and "A `VERIFIED` result requires both a valid ACK and a matching capture."
- Note: the reason token `result-before-ack` appears only in the RUNBOOK's *post-fence* late-record context ("a late landed commit is `REJECTED: result-before-ack`"). No fence exists here, so it does not apply, and the manuals do not otherwise name a terminal status for this state — the classification table's answer (wait or fence) is the whole instruction.
- **PASS**

## B11 — late ACK after the fence

- **Action:** The attempt does **not** reopen and I may **not** re-dispatch. I write a `late` record from `templates/late.md` as an observation, preserved as evidence, never promoted to an ACK.
- **Verbatim:** "**No late event cancels the fence or reopens the attempt.** An ACK that arrives after the fence does not mean the fence was wrong; it means the acknowledgement arrived after the boundary." / "**Retry stays forbidden** until you have direct termination evidence or an owner-materialized resolution." / "a late ACK is not an ACK for a fenced attempt" / "One attempt is fenced at most once. A fence is a boundary, not a retry."
- **PASS**

## B12 — unsearchable transport, `DISPATCH_UNKNOWN`

- **Action:** Skip the token search — an `unsearchable` admission carries `token_search_recipe_ref: null` and by definition has no runnable recipe. Write **exactly one** owner question from `templates/owner-question.md` with `blocks` naming this attempt. Topic becomes `AWAITING_OWNER`; nothing else may be written until the answer is recorded. If the latest answer was `dispatch-unresolved`, I stay in `DISPATCH_UNKNOWN` and write no second automatic question.
- **Owner questions asked: exactly one.**
- **Verbatim:** "`unsearchable` requires the literal `null` and means replay goes straight to one owner question instead of pretending a search happened" and "Not found → write **exactly one** owner question with `blocks` naming this attempt. If the latest answer was `dispatch-unresolved`, stay here and wait for new evidence — do **not** write another automatic question"
- **PASS**

---

## B13 — stale ordinary report capture

**1. Is it detectable at capture time?** Yes. The manifest is required for the ordinary report path, independent of any relay/patch rule.
- **Verbatim (RUNBOOK, report channels — covers both `transport-output` and `human-relay`):** "Either way the participant finalizes the bytes **once** and declares a manifest with them: `byte_count: <LC_ALL=C wc -c>` / `sha256: <shasum -a 256>` / `encoding: utf-8` / `trailing_newline: present | absent`"
- **Verbatim (SKILL, result capture):** "3. Recompute byte count, SHA-256, encoding expectation, and trailing-newline state. 4. Commit the artifact plus the result-capture record BEFORE interpreting the report."

**2. What I record, and the terminal status.** Preserve **both** manifests — the participant's declared one and my recomputed one — in the result-capture record. The worktree state decides the status, and here the participant landed a commit:
- **Verbatim:** "| a landed commit or residue | `REJECTED`, branch quarantined, both manifests preserved as evidence |" and "5. On mismatch, preserve BOTH manifests; never repair or normalize."
So: `REJECTED`, branch quarantined → `REMEDIATION_REQUIRED`.
- **Not settled by the manuals:** *which reason token* accompanies that `REJECTED`. `transport-lossy` is bound by the same table to the clean-and-stationary `ABORTED` row, and the reasons list offers no mismatch-with-landed-commit token. Per "`other` (mandatory free text)" I would use `other` with both manifests as the body evidence — but I am flagging that as my choice under an unstated rule, not as manual text.

**3. Do I correct anything?** No — no correction, re-wrap, normalization, truncation, or re-capture, and I do not ask the participant to resend and overwrite.
- **Verbatim:** "**Never repair, normalize, truncate, or reinterpret participant bytes.** A repaired report is your report, and the manifest that would have caught the loss now certifies your edit instead."
- **PASS** — the mechanism exists and fires before interpretation (step 4 precedes any reading of the report).

## B14 — red check under the wrong environment

- **Action:** No, I may not record `REJECTED: verification-failed`. I re-run the check under the assignment's profile — its exact `bootstrap_command` then its exact `verification_command`, with the profile's `required_tools` and `required_environment_names` in place. Red again under the profile → a real finding, classified by severity. If the profile cannot be established at all → record a `GATE` with a durable owner and tracker reference and obtain the owner's disposition.
- **Verbatim:** "**unpinned red is a fact about the executor environment, not the snapshot.** It cannot directly produce `REJECTED`. Re-run the check under the assignment's profile. If the profile cannot be established at all, record a `GATE` with a durable owner and tracker reference and obtain the owner's disposition — do not convert an environment you could not reproduce into a correctness claim about someone else's code."
- **PASS**

## B15 — findings to verdict

- **As stated (2 NONBLOCKING, 1 materialized GATE, 0 BLOCKING):** verdict `PASS` → terminal status `VERIFIED`. The accepted SHA does **not** advance, because this is a `REVIEW` turn.
- **Verbatim:** "`PASS = no BLOCKING findings and every GATE has tracker_ref plus owner`" / "`PASS` maps to a VERIFIED review result" / "`NONBLOCKING` findings never change the verdict" / "| `VERIFIED` | every applicable check passed | … `REVIEW`: no |"
- **GATE with no tracker reference:** it is unmaterialized, so verdict flips to `FAIL` → terminal status `REJECTED`, reason `review-failed`. The accepted SHA still does not move. Nothing intermediate appears — "Three severities exist so that … not so that a third outcome can appear between pass and fail."
- **Verbatim:** "`FAIL = any BLOCKING finding or any unmaterialized GATE`" / "`FAIL` maps to `REJECTED`"
- One scoping note the manual states itself: "In v2.0 this is **primary-enforced review policy**: the validator does not parse findings prose and makes no claim to enforce a findings ledger." The mapping is mine to apply; the validator will not catch me getting it wrong.
- **PASS**

---

**Summary: 15 PASS, 0 FAIL.** Two places where I had to go beyond settled text, flagged rather than guessed silently:

- **B13** — the manuals fix the status (`REJECTED`, quarantined, both manifests preserved) but never name the *reason token* for a manifest mismatch with a landed commit; `transport-lossy` is reserved by the same table for the `ABORTED` row.
- **B10** — the manuals give the classification and the next action but name no terminal status for a capture with no ACK and no fence; `result-before-ack` exists only in the post-fence late-record context.

````

## Dispositions

```yaml
case_id: B01
manual_version: v2
observed_action: No question. Select `participant_start_mode: primary-spawn`, `participant_selection_source: initial-prompt`, spawn through an approved transport and obtain a durable session/job address before committ
evidence_excerpt: "If the initial request unambiguously says to spawn, select primary-spawn and do not ask." and "`participant_selection_source` is `initial-prompt` when the request settled it"
disposition: PASS

case_id: B02
manual_version: v2
observed_action: No question. Select `owner-manual` / `initial-prompt`; after the topic commit, return the three things and STOP.
evidence_excerpt: "If it unambiguously says the owner will pair by topic ID, select owner-manual and do not ask."
disposition: PASS

case_id: B03
manual_version: v2
observed_action: Ask exactly once, verbatim: *"How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?"* — then record `participant_selection_source: owner-a
evidence_excerpt: "Otherwise ask exactly once: \"How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?\"" and "Ask **once**: a second question about the same choice is a stall"
disposition: PASS

case_id: B04
manual_version: v2
observed_action: Return exactly three things — the topic ID, the absolute record path, and the exact join prompt `pair with primary on TOPIC_ID` — then STOP. Create **no** records at all: no admission, assignment, int
evidence_excerpt: "return exactly three things to the owner: the topic ID, the absolute record path, and the exact join prompt … Then STOP. Selecting `owner-manual` is **not** admission. Create no assignment, no intent, no ACK budget and no work budget: ther
disposition: PASS

case_id: B05
manual_version: v2
observed_action: No. I do not begin the turn and do not touch the worktree. I ignore the on-disk bytes entirely and keep the bounded `cat-file -e "$HEAD_SHA:turns/$EXPECTED_DISPATCH_REF"` poll running against committe
evidence_excerpt: "**A record exists when it is committed.** Everything you read comes from a committed Git object, and nothing you see in the record's working tree means anything at all." / "Only the committed receipt means \"go\"" / "Never … read records f
disposition: PASS

case_id: B06
manual_version: v2
observed_action: Stop waiting, write **zero bytes** into the session worktree, emit `receipt_wait: expired; worktree_writes: 0`, and return control. No background monitor, no re-loop. Replay then classifies `DISPATCH_
evidence_excerpt: "**The wait is bounded and in the foreground.** If the bound passes with no committed receipt, write **nothing** to the worktree, report the zero-write expiry, and return control." and the code's `printf 'receipt_wait: expired; worktree_wri
disposition: PASS

case_id: B07
manual_version: v2
observed_action: see the verbatim response above
evidence_excerpt: "`true` | `observed_head` = the assignment's `base_sha`, `preflight_clean: true`, `relayed_base_sha: null` | you looked, so you report what you saw" / "`false` | `observed_head: null`, `preflight_clean: null`, `relayed_base_sha` = the assig
disposition: PASS

case_id: B08
manual_version: v2
observed_action: see the verbatim response above
evidence_excerpt: "That ordering is the whole mechanism. A primary that crashes between noticing and terminating leaves either no fence — in which case nothing happened — or a committed fence"
disposition: PASS

case_id: B09
manual_version: v2
observed_action: Same ladder as B08, but the bound is work_due_epoch stored on the ACK, and the fence is trigger: work-timeout with a non-null ack_ref.
evidence_excerpt: `work_due_epoch` is `ack_captured_epoch + work_timeout_seconds`
disposition: PASS

case_id: B10
manual_version: v2
observed_action: Run the capture sequence — write the bytes once to `artifacts/tTTTT-aAA/report.md`, recompute the four manifest facts, and commit the artifact plus the result-capture record **before interpreting**. T
evidence_excerpt: "`RESULT_BUFFERED` | A capture with no ACK | Wait for the ACK, or fence at `ack_due_epoch`. **Never** treat the capture as an implied ACK" and "A `VERIFIED` result requires both a valid ACK and a matching capture."
disposition: PASS

case_id: B11
manual_version: v2
observed_action: The attempt does **not** reopen and I may **not** re-dispatch. I write a `late` record from `templates/late.md` as an observation, preserved as evidence, never promoted to an ACK.
evidence_excerpt: "**No late event cancels the fence or reopens the attempt.** An ACK that arrives after the fence does not mean the fence was wrong; it means the acknowledgement arrived after the boundary." / "**Retry stays forbidden** until you have direct
disposition: PASS

case_id: B12
manual_version: v2
observed_action: Skip the token search — an `unsearchable` admission carries `token_search_recipe_ref: null` and by definition has no runnable recipe. Write **exactly one** owner question from `templates/owner-questio
evidence_excerpt: "`unsearchable` requires the literal `null` and means replay goes straight to one owner question instead of pretending a search happened" and "Not found → write **exactly one** owner question with `blocks` naming this attempt. If the latest
disposition: PASS

case_id: B13
manual_version: v2
observed_action: see the verbatim response above
evidence_excerpt: "Either way the participant finalizes the bytes **once** and declares a manifest with them: `byte_count: <LC_ALL=C wc -c>` / `sha256: <shasum -a 256>` / `encoding: utf-8` / `trailing_newline: present | absent`"
disposition: PASS

case_id: B14
manual_version: v2
observed_action: No, I may not record `REJECTED: verification-failed`. I re-run the check under the assignment's profile — its exact `bootstrap_command` then its exact `verification_command`, with the profile's `requi
evidence_excerpt: "**unpinned red is a fact about the executor environment, not the snapshot.** It cannot directly produce `REJECTED`. Re-run the check under the assignment's profile. If the profile cannot be established at all, record a `GATE` with a durabl
disposition: PASS

case_id: B15
manual_version: v2
observed_action: see the verbatim response above
evidence_excerpt: "`PASS = no BLOCKING findings and every GATE has tracker_ref plus owner`" / "`PASS` maps to a VERIFIED review result" / "`NONBLOCKING` findings never change the verdict" / "| `VERIFIED` | every applicable check passed | … `REVIEW`: no |"
disposition: PASS
```
