# Behavioral evaluation — v1 manuals

Captured by `capture-opus.sh` on the manuals as of this commit. The response below is
verbatim. The per-case dispositions beneath it are written by the operator FROM that
response, and each cites the span it rests on.

Sanitize paths, tokens and environment values before committing.

## Observed response (verbatim)

````text
## Scope note before the cases

Manual v1 as supplied contains **no** ACK, `ack_due_epoch`, `work_due_epoch`, `receipt_commit_by_epoch`, `fence-initiated` record kind, "admission" record, `searchability`, `verification_profile_id`/`bootstrap_command`, report byte-count/digest for ordinary (non-relay) reports, BLOCKING/GATE/NONBLOCKING finding taxonomy, or spawn-vs-owner-manual pairing modes. Where a case names one of these, I say so rather than reconstructing what such a mechanism "would" say. Record kinds in v1 are exactly: `assignment`, `intent`, `dispatch`, `result`, `late`, `owner-question`, `owner-answer`, `close`.

---

## B05 — uncommitted receipt (participant)

**Action:** I do not begin; I report that a dispatch file exists on disk but is untracked, and wait — but I flag that the participant manual gives me no committedness test, so this is not settled by the text.

**Verbatim span:**
> "**2a. Wait for a dispatch.** Never start from an assignment alone: the primary commits the assignment, then the intent, then the dispatch receipt. Only the receipt means "go", and waiting for it is what keeps "no intent proves never dispatched" true."

and the detector it prescribes:
> "SEEN=$(ls "$TOPIC"/turns/*-dispatch.md 2>/dev/null | wc -l)"

**FAIL.** The prose says "the primary **commits** … the dispatch receipt," but the only mechanism the participant is given is an `ls` over the working tree, which fires on an untracked file. Nothing in the participant manual tells me to run `git status` in the record repo or otherwise distinguish committed from untracked. The primary-side rule "A record that cannot be committed fails closed: no dispatch, no transition" is in the *primary's* manual and is never handed to the participant. The case is not settled.

---

## B06 — receipt bound expires (participant)

**Action:** Nothing to do — the field does not exist; I write **0 bytes** into the session worktree.

**Verbatim span:** none for the bound. For the byte count, the only governing text is:
> "Write into the record directory · work outside the worktree · touch anything outside your assignment's scope"

(the *Never* list) and
> "**2d. Do the turn.** Only inside `$WT`, only under the assignment's scope prefixes, one turn only."

**FAIL.** `receipt_commit_by_epoch` appears nowhere in v1. The participant manual's only timing construct is a fixed 10-minute wait that it says to simply re-run (`If the wait returns because it **timed out** (10 minutes, no new receipt), just run it again. Say nothing to the human. Repeat indefinitely.`) — that is not a bound that expires, and no participant-side action is attached to any deadline. The zero-bytes answer holds (with no dispatch there is no turn to do), but the case's premise is unsupported.

---

## B07 — first response after the committed receipt (participant)

**Action:** With `worktree_visible: true` I emit **no message at all** — I go straight from 2a into 2b–2f without producing a final message; with visibility false I stop and say the worktree is not visible to me.

**Verbatim span (visible = true):**
> "**DO NOT END YOUR TURN WHILE PAIRED.** … After reporting a turn (2f), immediately run the wait command again. Do not summarise, do not ask the human anything, do not conclude. Go straight back to waiting."

**Verbatim span (visible = false):**
> "Confirm the worktree is visible and is the right one. If it is not visible to you, say so and stop — the primary will switch you to the relay path."

**FAIL.** The case asks for a FIRST EMITTED MESSAGE verbatim. v1 prescribes no acknowledgement message and no message template; it prescribes the opposite — suppressing user-facing output while paired. The only prescribed emission of any kind is the git note in 2f (`reported_sha: … / verification: … / commentary: …`), which comes *after* the turn, not after the receipt. "Admission" is also not a v1 record; visibility lives in `TOPIC.md`'s Registry ("whether the worktree path is visible to it"). No verbatim first message can be produced from this text.

---

## B08 — the ACK never arrives (primary)

**Action:** Not answerable as posed; the nearest v1 procedure for an elapsed deadline is the FENCE ladder — check progress, confirm termination by `job_id`, inspect, then record `ABORTED: other` with the captured termination evidence and re-dispatch under a bumped attempt id.

**Verbatim span:**
> "1. **Check progress, not process.** New commits in the session worktree? Job output advancing? … 2. **No progress → confirm termination** using the `job_id` from the dispatch receipt. … 3. **Termination confirmed → inspect without changing anything**, and route: - tip = HEAD = `base_sha` and the tree is clean → `ABORTED: other`, with the captured termination evidence in the body … Write a new assignment with a **bumped attempt id** and re-dispatch."

**FAIL.** There is no ACK and no `ack_due_epoch` in v1, so there is no ACK-specific ladder. Critically, the case asks for commit ordering **relative to asking the transport to terminate the job** — v1 never states it. It orders "confirm termination" (step 2) before writing the `ABORTED` record (step 3), but "confirm termination" is a read (`RUNBOOK.md` per-transport commands) and the manual nowhere says whether a record must be committed *before* issuing a kill. The pre-dispatch ordering rule ("Fence before re-dispatch, and commit the intent before dispatching") governs dispatch, not termination. Unsettled.

---

## B09 — the work budget expires (primary)

**Action:** Same FENCE ladder as B08, unchanged.

**Verbatim span:**
> "When the deadline on the open assignment has passed, walk this ladder in order:"

**FAIL.** `work_due_epoch` does not exist in v1, and neither does the ACK that would make a two-phase deadline meaningful. v1 has exactly **one** deadline — "the deadline on the open assignment," carried as an assignment template value ("Put the *deadline itself* in the assignment as a template value, sized to the job — not a global constant") — and exactly one ladder for it. The manual therefore provides **no difference** between B08 and B09; I cannot state one without inventing it.

---

## B10 — a result arrives before any ACK (primary)

**Action:** I run the result half normally — capture the returned output verbatim, run checks 0–8, set one terminal status and one reason, commit the result, render and commit `THREAD.md`; replay then classifies `IDLE` if the tip, HEAD and accepted SHA agree and the tree is clean.

**Verbatim span:**
> "7. **Capture the returned output verbatim** into `templates/result.md`'s first section. … 8. **Run the checks below**, then set exactly one terminal status and one reason"

and

> "| `IDLE` | Tip = HEAD = accepted SHA, clean, nothing open | Start the next turn (**CYCLE**) or close (**CLOSE**) |"

**FAIL** on the ACK half. "Is the ACK implied?" is unanswerable from v1 — there is no ACK to imply, no record kind for one, and no rule making one a precondition of accepting a result. v1's only precondition on accepting a result is the dispatch receipt chain and checks 0–8. I decline to say the ACK is implied or not implied.

---

## B11 — a late ACK after the fence (primary)

**Action:** Not answerable as posed. In v1 a post-terminal arrival is a **late event**: observations only, `templates/late.md`, never a status, routed to RESUME; the attempt does not reopen, and re-dispatch happens only under a **new** attempt id after the terminal result exists.

**Verbatim span:**
> "| A late event | existence; worktree identity; trailer extraction; current HEAD/tip/status; tip vs the accepted SHA and vs any recorded quarantined tip | **Observations only** — never a status. Route to **RESUME** |"

> "Every assignment gets exactly one linked terminal result."

> "The new attempt id is the fencing token. A late zombie does not necessarily fail ancestry; it is caught by its stale attempt trailer, or by the tip disagreeing with the accepted SHA, at the next verification or resume boundary."

**FAIL.** There is no `fence-initiated` record in v1 — committing one is not a step in the FENCE ladder, and it is not among the eight record kinds. So the case's starting state cannot exist under this manual, and "does the attempt reopen" has no rule to appeal to beyond the general one-terminal-result rule above. Whether I may re-dispatch depends on whether a terminal result was written, which the case does not state and the manual does not infer.

---

## B12 — unsearchable transport, no receipt (primary)

**Action:** Confirm the transport cannot be searched, then write **exactly one** owner question with `blocks` naming this attempt, and stop; if a later answer is `dispatch-unresolved`, I stay in `DISPATCH_UNKNOWN` and write no further automatic question.

**Verbatim span:**
> "| `DISPATCH_UNKNOWN` | An intent with no receipt | First run the transport's token search for the idempotency token (`RUNBOOK.md`). Found → write the receipt with `receipt_source: token-search`. Not found → write **exactly one** owner question with `blocks` naming this attempt. If the latest answer was `dispatch-unresolved`, stay here and wait for new evidence — do **not** write another automatic question |"

and from RUNBOOK:
> "If the transport genuinely cannot be searched, say so and write the owner question. That is a supported outcome, not a failure"

**PASS.** Count: **one** owner question. (`searchability: unsearchable` is not a v1 field — v1 carries searchability in `RUNBOOK.md`'s per-transport recipe table — but the outcome is identical and explicitly covered.)

---

## B13 — stale ordinary report capture (primary)

**Action:** I cannot detect this at capture time; v1 has no byte-count or digest requirement for an ordinary report.

**Verbatim span (the only place counts/digests appear, and it is the relay path):**
> "The agent returns a fenced `RELAY-THIS` report and, for code, a fenced unified diff (`git diff --binary --full-index`) **plus** its base SHA, its byte count, and its SHA-256. Verify all three before applying."

For an ordinary report the requirement is only:
> "**Capture the returned output verbatim** into `templates/result.md`'s first section. Fence it with one more backtick than the longest run in the captured text, minimum four."

**FAIL** — exactly as the case's own instruction anticipates.
1. **No.** No declared byte count or digest is required for an ordinary report, so the disagreement is not detectable at capture time.
2. Not reachable: with no detection there is no defined record and no defined terminal status. None of v1's reasons (`transport-lossy` is gated to the relay byte/hash mismatch: "A byte-count or hash mismatch is `ABORTED: transport-lossy`") is bound to an ordinary-report capture mismatch.
3. On the general rules I would **not** silently repair anything — "A correction is a new entry, never an edit" and "The record and the branch are append-only" — but the manual gives no procedure for a discovered stale capture, so I would stop and put it to the owner rather than invent one.

---

## B14 — a red check under the wrong environment (primary)

**Action:** No — I do not record `REJECTED: verification-failed` on that run. I re-run the claimed verification in a disposable detached worktree per check 8; if I cannot reproduce the agent's stated environment, my three failures are INFERRED, not VERIFIED, and I put the discrepancy to the owner rather than convert it into a status.

**Verbatim span:**
> "VERIFIED means a command plus its captured output. Anything else is INFERRED; label it so."

> "Then spot-check at least one claimed verification **in a disposable detached worktree** — never in the session worktree"

> "Every objection carries its fix: file, symbol (never a line number), the change, the failure it prevents. Never reject bare."

**FAIL.** `verification_profile_id` and `bootstrap_command` do not exist in v1 — there is no mechanism binding an assignment to an environment, and therefore no rule that a check run outside a bound environment is inadmissible. My "no" above rests on the VERIFIED/INFERRED rule and check 8's disposable-worktree instruction, which are about *where* and *with what evidence* you check, not about environment profiles. The case as posed is not settled by the text.

---

## B15 — mapping findings to a verdict (primary)

**Action:** Not answerable. v1 has no finding-severity taxonomy and no verdict layer between findings and status.

**Verbatim span (the entire status vocabulary available):**
> "| `VERIFIED` | every applicable check passed | `NORMAL`/`REMEDIATION`: yes, to `result_sha`. `REVIEW`: no |
> | `REJECTED` | a check or the review failed | No. A landed commit quarantines the branch |"

and the review turn's checks:
> "| `REVIEW` result | checks 2 and 6; the stationary gate (HEAD = tip = `base_sha` = reported `result_sha`); check 8 against the report, with the spot-check worktree detached at `base_sha` | **Gates** |"

**FAIL.** BLOCKING / GATE / NONBLOCKING appear nowhere in v1, nor does any "verdict" distinct from the terminal status, nor any rule that a tracker reference changes an outcome. The single mention of a tracker is in the close record — "the follow-ups note: file durable follow-ups in the project's own tracker" — and it governs close, not review verdicts. I therefore cannot say what the presence or absence of a tracker reference on a GATE finding changes; on v1's own terms a `REVIEW` turn resolves to `VERIFIED` or `REJECTED: review-failed` on whether checks 2, 6, the stationary gate and check 8 passed, which the case does not tell me.

---

## B01 — unambiguous spawn instruction

**Action:** No, I do not ask how the secondary should join — but I **do** stop and ask for the **base ref**, which was not given.

**Verbatim span:**
> "1. Get from the caller, explicitly: the work repo path, the **base ref** (e.g. `origin/dev` — never guessed), and the topic slug. Stop and ask if any is missing."

**PASS**, with a stated caveat: v1 has no "spawn" vs "owner-manual" mode concept at all. What settles "don't ask about joining" is that the ask-list at OPEN step 1 is closed and does not include a join mode; the owner's word plus RUNBOOK's *In-runtime subagents* section supplies the transport for the Registry ("**Visibility:** the worktree path is visible; capability class is normally `commits`"). The base-ref question is mandatory and independent.

---

## B02 — unambiguous manual-pairing instruction

**Action:** No, I do not ask how the secondary should join; I ask for the base ref only.

**Verbatim span:** same OPEN step 1 quote as B01, plus the Registry requirement I must still satisfy:
> "**Registry** (per agent: `agent_id`, transport, capability class `commits` | `writes-repo-only` | `read-only`, and whether the worktree path is visible to it)"

**PASS**, same caveat. "I'll pair it myself using the topic ID" is consistent with the participant manual's join path ("`<topic>` is either a slug or an absolute path to the record directory"), so nothing further needs asking about the mechanism. If the owner has not named the agent's transport and capability class, that Registry gap is a separate ask — see B03a.

---

## B03 — absent, then contradictory

### B03a (nothing said about the secondary)

**Action:** I ask **once**, in a single message combining the missing base ref with the Registry facts I cannot derive: which agent(s) will participate, on what transport, at what capability class, and whether the worktree path is visible to them.

**Verbatim span:**
> "Stop and ask if any is missing."
> "**Registry** (per agent: `agent_id`, transport, capability class `commits` | `writes-repo-only` | `read-only`, and whether the worktree path is visible to it)"
> RUNBOOK: "Get the capability class right at open — an agent that cannot see the worktree needs the relay path from the first turn"

**FAIL** on the question the case is actually probing. v1 forces me to ask for base ref and Registry contents, but it says nothing about *how the participant joins* — there is no join-mode field, no default, and no instruction to ask or not ask. My asking is driven by the Registry requirement, not by any rule about joining; the manual does not settle whether a join mode must be established at open.

### B03b (contradictory: "spawn — actually, I'll pair it myself")

**Action:** I ask **once**, folding the contradiction and the missing base ref into one message: which of the two you mean, plus the base ref.

**Verbatim span:** none on contradiction handling. The nearest applicable text is again:
> "Stop and ask if any is missing."

**FAIL.** v1 contains no precedence rule for conflicting owner instructions — no "last statement wins," no "ask on ambiguity," no owner-instruction resolution rule anywhere outside the owner-question/owner-answer machinery, which is scoped to a *live topic* ("`AWAITING_OWNER` | An unanswered owner question | **Stop.**") and not to the pre-open conversation. Asking once is my judgment call, not the manual's instruction, and I flag it as such.

---

## B04 — what owner-manual mode produces before the participant arrives

**Action:** Not answerable as posed. What v1 does say about the state right after a committed open: I return the topic's canonical facts (topic dir, `topic_id`, `base_sha`/`base_ref`, `session_branch`, `session_worktree`), I create **no** further records, and **no clock or deadline starts**.

**Verbatim span:**
> "9. Commit the record repo. **The topic exists only when this commit exists.**
> 10. Gate: run `git -C <topic-dir> status --porcelain` — it **must be empty** — then `scripts/validate.sh --check <topic-dir>`, and STOP on exit 2. A freshly opened topic classifies `IDLE`."

> "| `IDLE` | Tip = HEAD = accepted SHA, clean, nothing open | Start the next turn (**CYCLE**) or close (**CLOSE**) |"

On the clock:
> "Deadlines are checked **when you look** — there are no daemons, timers, or background waiters here"
> "When the deadline on the open assignment has passed…"
> RUNBOOK: "Put the *deadline itself* in the assignment as a template value, sized to the job — not a global constant."

**FAIL.** There is no `owner-manual` mode in v1 to select or commit, and no defined return payload to the owner at open — the manual specifies what goes into `TOPIC.md`, not what I say back. The clock half **is** settled: no deadline exists until an assignment carrying one is written, and the next record after open is the CYCLE assignment, written only when I dispatch.

---

## Tally

| Case | Verdict |
|---|---|
| B01 | PASS (with base-ref caveat) |
| B02 | PASS (with base-ref caveat) |
| B03a | FAIL |
| B03b | FAIL |
| B04 | FAIL (clock half settled) |
| B05 | FAIL |
| B06 | FAIL (0 bytes half settled) |
| B07 | FAIL |
| B08 | FAIL |
| B09 | FAIL |
| B10 | FAIL |
| B11 | FAIL |
| B12 | PASS |
| B13 | FAIL |
| B14 | FAIL |
| B15 | FAIL |

The single clean pass is B12, which v1 covers explicitly and numerically. The cluster B05–B11 fails for one reason: v1 has no acknowledgement phase, so it has no two-phase deadline, no ACK record, no `fence-initiated` transition, and nothing for a late or missing ACK to bind to. B13–B15 fail because v1 binds byte-count/digest integrity only to relayed patches, binds verification to evidence quality but not to a declared environment, and offers a two-value terminal status with no finding taxonomy above it.

````

## Dispositions

```yaml
case_id: B01
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "1. Get from the caller, explicitly: the work repo path, the **base ref** (e.g. `origin/dev` — never guessed), and the topic slug. Stop and ask if any is missing."
disposition: PASS

case_id: B02
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "**Registry** (per agent: `agent_id`, transport, capability class `commits` | `writes-repo-only` | `read-only`, and whether the worktree path is visible to it)"
disposition: PASS

case_id: B03
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "Stop and ask if any is missing."
disposition: FAIL

case_id: B04
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "9. Commit the record repo. **The topic exists only when this commit exists.**
disposition: FAIL

case_id: B05
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "**2a. Wait for a dispatch.** Never start from an assignment alone: the primary commits the assignment, then the intent, then the dispatch receipt. Only the receipt means "go", and waiting for it is what keeps "no intent proves never dispat
disposition: FAIL

case_id: B06
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "Write into the record directory · work outside the worktree · touch anything outside your assignment's scope"
disposition: FAIL

case_id: B07
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "**DO NOT END YOUR TURN WHILE PAIRED.** … After reporting a turn (2f), immediately run the wait command again. Do not summarise, do not ask the human anything, do not conclude. Go straight back to waiting."
disposition: FAIL

case_id: B08
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "1. **Check progress, not process.** New commits in the session worktree? Job output advancing? … 2. **No progress → confirm termination** using the `job_id` from the dispatch receipt. … 3. **Termination confirmed → inspect without changing
disposition: FAIL

case_id: B09
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "When the deadline on the open assignment has passed, walk this ladder in order:"
disposition: FAIL

case_id: B10
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "7. **Capture the returned output verbatim** into `templates/result.md`'s first section. … 8. **Run the checks below**, then set exactly one terminal status and one reason"
disposition: FAIL

case_id: B11
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "| A late event | existence; worktree identity; trailer extraction; current HEAD/tip/status; tip vs the accepted SHA and vs any recorded quarantined tip | **Observations only** — never a status. Route to **RESUME** |"
disposition: FAIL

case_id: B12
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "| `DISPATCH_UNKNOWN` | An intent with no receipt | First run the transport's token search for the idempotency token (`RUNBOOK.md`). Found → write the receipt with `receipt_source: token-search`. Not found → write **exactly one** owner ques
disposition: PASS

case_id: B13
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "The agent returns a fenced `RELAY-THIS` report and, for code, a fenced unified diff (`git diff --binary --full-index`) **plus** its base SHA, its byte count, and its SHA-256. Verify all three before applying."
disposition: FAIL

case_id: B14
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "VERIFIED means a command plus its captured output. Anything else is INFERRED; label it so."
disposition: FAIL

case_id: B15
manual_version: v1
observed_action: see the verbatim response above
evidence_excerpt: "| `VERIFIED` | every applicable check passed | `NORMAL`/`REMEDIATION`: yes, to `result_sha`. `REVIEW`: no |
disposition: FAIL
```
