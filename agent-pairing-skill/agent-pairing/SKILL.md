---
name: agent-pairing
description: Use when coordinating strict sequential turns between multiple coding agents in one shared worktree, especially for interrupted sessions, cross-runtime handoffs, or auditable pairing topics.
---

# agent-pairing — the primary's manual

**The baton is the working tree. A turn is exclusive write access to the repo. The handoff is a
commit.** You are the *primary*: the only writer of the record, the dispatcher of every turn, and
the judge of every result. Another agent works only inside the session worktree, only when it holds
an open assignment, and only for one turn.

Read `RUNBOOK.md` (in this package, at `<skills-root>/agent-pairing/` — `~/.claude/skills` for
Claude, `~/.codex/skills` for Codex) for anything environment-specific: how to dispatch on each
transport, how to search for a lost job id, poll cadence, commit hooks, and install/update. Nothing
in this manual is runtime-specific; where a mechanism differs per runtime, `RUNBOOK.md` says so.

## The two repos

| Thing | Where | Who writes it |
|---|---|---|
| The **record** | `<record-root>/<topic-slug>/` — its own git repo, no remote | You, only |
| The **session worktree** | `<worktree-root>/<topic-slug>/` on branch `pair/<topic-slug>` | Whoever holds the open turn |
| Everything else | — | Nobody |

Both roots are absolute paths of your choosing, written into the topic's `TOPIC.md` at open and
authoritative from then on. They are **per topic, not per runtime**: every agent working a topic —
whatever runtime it runs in — uses the same record repo and the same worktree, because there is one
record and one baton. `RUNBOOK.md` carries the defaults for this machine (`~/.claude/agent-pairing/`
and `~/.claude/agent-pairing-worktrees/`); that directory is just a location that already exists,
not a statement about which runtime may use it.

The record lives outside the work repo so that record commits never pollute
`git diff base..result`, which is the evidence a turn is judged on.

Record layout: `TOPIC.md` (charter, registry, DECISIONS, onboarding), `turns/` (the append-only
record), `THREAD.md` (generated — never hand-authored).

## Standing rules

- One agent in the worktree at a time; the open attempt is the lease.
- The handoff is a commit; the next turn starts from it. Never review a SHA you were not given.
- Verify worktree identity, tip, ancestry, trailers, scope and diff — never a summary alone.
- VERIFIED means a command plus its captured output. Anything else is INFERRED; label it so.
- Every objection carries its fix: file, symbol (never a line number), the change, the failure it
  prevents. Never reject bare.
- Completion is your verification passing — never a transport's "finished".
- Fence before re-dispatch, and commit the intent before dispatching.
- Record verbatim; provenance goes in the record *and* in the commit trailers.
- The record and the branch are append-only. Undo is `git revert` as a new turn, never a reset or
  force-push. A correction is a new entry, never an edit.
- Attribute commits by trailers, never by committer identity.
- Every assignment gets exactly one linked terminal result.
- `result_sha` is always agent-reported, never observed by you.
- An owner authorization is not progress: it must materialize a receipt or a result record.
- A close record means *closing*; only the postconditions mean *closed*.

All git commands take the form `git -C <absolute-path>` (never `cd`, never `--git-dir`) and run
with `GIT_NO_REPLACE_OBJECTS=1`.

## The validator

One script, two modes:

```bash
/bin/bash scripts/validate.sh --check  <topic-dir>    # read-only: schema, linkage, classification
/bin/bash scripts/validate.sh --render <topic-dir>    # writes exactly one file: THREAD.md, atomically
```

Exit codes:

| Exit | Meaning | What you do |
|---|---|---|
| 0 | No violations; a `classification:` line was printed | Read the classification — it may still be a stop |
| 2 | `VIOLATION …` lines on stderr (record corruption, schema, linkage), or a failed render | **STOP.** Do not dispatch, do not write another record. Fix or ask the owner |
| 3 | Usage error (bad mode, or a topic path containing whitespace) | Fix the invocation |

**Exit 0 does not mean "proceed."** `AWAITING_OWNER`, `DISPATCH_UNKNOWN` and `UNRECORDED_DRIFT` are
all exit 0 and all mean stop. A `(unverified: …)` suffix is not a verdict either — it means the
validator could not *read* something (the worktree list, the branch tip, the commit range). Restore
the read, then classify again; never act on a classification carrying `unverified`.

`--render` never publishes a partial `THREAD.md`: on failure it exits 2 and leaves the previous
file intact.

**The validator reads `turns/` from the working tree, but `THREAD.md` from `HEAD`.** So an
assignment that was written but never committed classifies exactly as if it had been committed —
`OPEN (never-dispatched)` — and the fail-closed rule "if the commit fails, there is no dispatch"
would rest on you noticing the failed commit. It does not: **every gate that precedes a dispatch
first requires the record repo to be clean.**

```bash
git -C <topic-dir> status --porcelain      # must be empty before you trust a classification
```

A non-empty result means the classification describes a record that does not durably exist. Commit
it (or resolve it by kind — **RESUME** step 0) before acting.

---

## OPEN — opening a topic

### Step 0 — resolve how the participant will join

Before anything else, decide `participant_start_mode` and record where that decision came from.
Read the request for **meaning**, not keywords:

```text
If the initial request unambiguously says to spawn, select primary-spawn and do not ask.
If it unambiguously says the owner will pair by topic ID, select owner-manual and do not ask.
Otherwise ask exactly once: "How should the secondary agent join this topic: should I spawn it, or will you pair it manually using the topic ID?"
```

`participant_selection_source` is `initial-prompt` when the request settled it and `owner-answer`
when you had to ask. Ask **once**: a second question about the same choice is a stall, and a
question asked when the request already answered it is noise. Both values go into `TOPIC.md` at
step 4 and are never edited afterwards.

**`owner-manual`** — after the topic is committed, return exactly three things to the owner: the
topic ID, the absolute record path, and the exact join prompt

```text
pair with primary on TOPIC_ID
```

Then STOP. Selecting `owner-manual` is **not** admission. Create no assignment, no intent, no ACK
budget and no work budget: there is nobody for them to bind to, and a clock started against nobody
expires against nobody. The topic classifies `AWAITING_PARTICIPANT` until the owner confirms the
participant joined and supplies the durable address the admission needs. Only then commit the
admission record, after which the topic classifies `IDLE`.

**`primary-spawn`** — spawn the participant through an approved transport and obtain a **durable**
session or job address before committing the admission. A monitor, waiter, or foreground polling
handle is never a durable address: it names the watcher, not the job, so after a crash it finds
nothing — which is exactly when the address is needed. If the spawn fails, stop and ask the owner
for direction; never silently fall back to `owner-manual`, because the two modes produce different
admission evidence and the record would then describe a pairing that did not happen.

### Steps 1-10 — creating the topic

1. Get from the caller, explicitly: the work repo path, the **base ref** (e.g. `origin/dev` — never
   guessed), and the topic slug. Stop and ask if any is missing.
2. Refuse to open if the topic dir, the branch `pair/<slug>`, or the worktree path already exists.
   An existing topic is a **RESUME**, not an open.
3. Resolve and pin the base:

   ```bash
   git -C <repo> rev-parse <base_ref>^{commit}
   ```

4. Create the record repo first — `TOPIC.md` has nowhere to live until it exists:

   ```bash
   mkdir -p <topic-dir>/turns && git -C <topic-dir> init
   ```

   Then write `TOPIC.md` from `templates/TOPIC.md` and fill every front-matter key **except**
   `session_worktree` and `work_repo_common_dir` — `protocol_version` (the exact scalar `2`),
   `topic_id`, `participant_start_mode` and `participant_selection_source` from step 0, `base_sha`,
   `base_ref`, `session_branch`. `base_sha` is the pinned commit; `base_ref` is the explicit ref it
   was cut from. The validator seeds the accepted SHA from `base_sha` and presence-checks
   `base_ref`; a topic missing either is rejected before any record is read.

   The two path keys are filled in step 8 from the worktree itself, which does not exist yet.
   **Never guess them:** the canonical values are realpaths (`/private/tmp/…`, not `/tmp/…`, on
   macOS), and a wrong value fails check 2's worktree identity on every turn of the topic, forever.

5. Fill `TOPIC.md`'s body sections: **Charter** (goal + done-criteria), **Preconditions** (one
   machine, one shared filesystem), **Registry** (per agent: `agent_id`, transport, capability
   class `commits` | `writes-repo-only` | `read-only`, and whether the worktree path is visible to
   it), **DECISIONS** (empty at open; one line per settled decision from here on), **Onboarding**
   (from `templates/onboarding.md`).
6. Check the work repo for commit hooks that rewrite messages or block commits — they fight the
   required trailers and the cleanliness check. Note what you find in `TOPIC.md`'s Preconditions
   and see `RUNBOOK.md`.
7. Create the dedicated worktree:

   ```bash
   git -C <repo> worktree add <worktree-path> -b pair/<slug> <base_sha>
   ```

8. Record the canonical paths in `TOPIC.md`, taken from the worktree itself:

   ```bash
   git -C <worktree-path> rev-parse --show-toplevel
   git -C <worktree-path> rev-parse --git-common-dir
   ```

9. Commit the record repo. **The topic exists only when this commit exists.**
10. Gate: run `git -C <topic-dir> status --porcelain -- turns TOPIC.md` — it **must be empty** — then
    `scripts/validate.sh --check <topic-dir>`, and STOP on exit 2. A freshly opened topic
    classifies `AWAITING_PARTICIPANT`: it has a charter and a pinned base, but no admitted
    participant yet.

### Step 11 — admit the participant

Write `templates/admission.md`, fill every field from the transport you actually used, and commit
it. The admission is the only durable proof that a participant exists, and every later assignment
binds one exact `admission_ref`.

The fields are validated, not documentation. `capability: commits` requires
`worktree_visible: true`; `searchability: searchable` requires a real token-search recipe in
`RUNBOOK.md` and a non-null `token_search_recipe_ref`, while `unsearchable` requires the literal
`null` and means replay goes straight to one owner question instead of pretending a search happened.
`durable_address` never contains a credential. Any later change to transport, address, capability,
visibility, searchability, report channel, or evidence class is a **new admission record with a new
`admission_id`** — editing one in place would retroactively change what past assignments agreed to.

After the admission commits, re-run the gate. The topic now classifies `IDLE` and a turn may begin.

The worktree is protection against *accidental* interference — git refuses to check out its branch
twice, and another session's branch switching cannot move this HEAD. It is not a security boundary:
a raw ref update, `--ignore-other-worktrees`, or a prune-and-recreate at the same path all defeat
it, and a recreate destroys uncommitted-residue evidence.

---

## CYCLE — running one turn

### Dispatch half

1. **Pin the base.** For a `NORMAL` or `REVIEW` turn, `base_sha` = the accepted SHA = the branch
   tip; confirm all three agree before writing anything. If they do not, stop and run **RESUME**.
   For a `REMEDIATION` turn the base is the quarantined tip, and the turn is authorised only from a
   `REMEDIATION_REQUIRED` classification, or from `UNRECORDED_DRIFT` with a linked owner answer;
   its done-criteria must include restoring the accepted content append-only.
2. **Write and commit the assignment** from `templates/assignment.md`. `scope` is a
   **space-separated list of path prefixes**. Include goal, deliverable, the DON'Ts, and the
   literal trailer block. If the commit fails, there is no dispatch — fail closed.
3. **Write and commit the intent** from `templates/intent.md` with a fresh `idempotency_token`,
   unique across the whole topic. This commit strictly precedes dispatch, so "no intent" proves
   "never dispatched".
4. **Dispatch.** The payload is the onboarding text plus the digest plus the assignment, verbatim,
   plus the idempotency token. Stateless transports get the full payload on every re-dispatch.
   Mechanics per transport: `RUNBOOK.md`.
5. **Write and commit the dispatch receipt** from `templates/dispatch.md` with the real `job_id`,
   the `intent_ref`, and `receipt_source: direct`.
6. Gate: run `git -C <topic-dir> status --porcelain` — it **must be empty** — then
   `scripts/validate.sh --check <topic-dir>`, and STOP on exit 2. Expect `OPEN (dispatched)`.
   The cleanliness check is not decoration: `--check` reads `turns/` from the working tree, so an
   uncommitted record classifies as if it were committed.

You write yourself an assignment for your own turns too — reverts, remediation, applying a relayed
patch. No commit exists without an assigned turn.

### Result half

7. **Capture the returned output verbatim** into `templates/result.md`'s first section. Fence it
   with one more backtick than the longest run in the captured text, minimum four. Keep your own
   commentary in the separate section — never blended into the agent's words.
8. **Run the checks below**, then set exactly one terminal status and one reason:

   | Status | When | Advances the accepted SHA? |
   |---|---|---|
   | `VERIFIED` | every applicable check passed | `NORMAL`/`REMEDIATION`: yes, to `result_sha`. `REVIEW`: no |
   | `REJECTED` | a check or the review failed | No. A landed commit quarantines the branch |
   | `SUPERSEDED` | the open attempt was made obsolete by a replacement or a collision | No; landed commits are quarantined |
   | `ABORTED` | confirmed termination before an acceptable result | No; requires tip = HEAD = `base_sha`, a clean tree, and captured termination evidence |

9. **Commit the result, then regenerate and commit `THREAD.md`.** `--render` writes the file; it
   does not commit it, and leaving it uncommitted trips the record-repo gate on the next resume:

   ```bash
   /bin/bash scripts/validate.sh --render <topic-dir>
   git -C <topic-dir> add THREAD.md && git -C <topic-dir> commit -m '<record_seq>: result'
   ```

10. Gate: run `git -C <topic-dir> status --porcelain` — it **must be empty**, which also proves the
    result and the regenerated `THREAD.md` are committed — then
    `scripts/validate.sh --check <topic-dir>`, and STOP on exit 2.
11. **Decide the next move**: another assignment · a remediation turn · an owner question · close.
    Append each settled decision to `TOPIC.md`'s DECISIONS as one line.

### The verification matrix

| Context | What runs | Gates or observations? |
|---|---|---|
| `NORMAL` / `REMEDIATION` result | checks 0–8 | **Gates** — any failure is `REJECTED` or `SUPERSEDED` |
| `REVIEW` result | checks 2 and 6; the stationary gate (HEAD = tip = `base_sha` = reported `result_sha`); check 8 against the report, with the spot-check worktree detached at `base_sha` | **Gates** |
| A result with no commit | worktree identity; HEAD and tip vs `base_sha`; cleanliness; fencing/termination evidence | Observations |
| A late event | existence; worktree identity; trailer extraction; current HEAD/tip/status; tip vs the accepted SHA and vs any recorded quarantined tip | **Observations only** — never a status. Route to **RESUME** |

Checks are **gates, not a pipeline**: once one fails the status is decided, and the remaining checks
are optional. Run the ones that add evidence, skip the rest, and state in the result which checks
you did not run and why.

Set these once per turn and use them in every command below:

```bash
WT=<session_worktree>; BASE=<base_sha>; RES=<agent-reported result_sha>
export GIT_NO_REPLACE_OBJECTS=1
```

**Check 0 — no-op precheck.** The agent reported a `result_sha` and it differs from `BASE`. A
`NORMAL` turn that reports `BASE` is `REJECTED: no-op-result` — an empty range makes the ancestry
and trailer checks pass vacuously. A `NORMAL` result with no reported SHA while the tip moved is
`REJECTED`. Never substitute a SHA you observed yourself: that collapses check 3 to `x == x == x`.

**Check 1 — existence.**

```bash
git -C "$WT" rev-parse --verify "$RES^{commit}"
```

**Check 2 — worktree identity.** All three must match `TOPIC.md`:

```bash
git -C "$WT" rev-parse --show-toplevel
git -C "$WT" rev-parse --git-common-dir
git -C "$WT" symbolic-ref --short HEAD          # = session_branch; a detached HEAD fails here
```

**Check 3 — tip equality.** HEAD, the branch ref, and the agent-reported SHA are all equal:

```bash
git -C "$WT" rev-parse HEAD
git -C "$WT" rev-parse "refs/heads/$(git -C "$WT" symbolic-ref --short HEAD)"
```

**Check 4 — append-only ancestry.**

```bash
git -C "$WT" merge-base --is-ancestor "$BASE" "$RES"    # exit 0 required
```

**Check 5 — attempt attribution.** Every commit in the range carries this attempt's exact three
trailers. Committer identity is never attribution — a zombie and its retry share a committer. One
line per commit, each trailer labelled and bracketed, so an **empty** bracket names exactly which
trailer is missing:

```bash
git -C "$WT" log --format='%H topic=[%(trailers:key=Agent-Pairing-Topic,valueonly,separator=%x2C)] turn=[%(trailers:key=Agent-Pairing-Turn,valueonly,separator=%x2C)] attempt=[%(trailers:key=Agent-Pairing-Attempt,valueonly,separator=%x2C)]' "$BASE".."$RES"
```

Every line must show all three brackets filled with **this** attempt's exact values. An empty
bracket, a wrong value, or a bracket holding two comma-separated values (a repeated trailer) all
fail the check.

**How the trailers must be written.** Git's trailer parser — both `git interpret-trailers` and the
`%(trailers:…)` format this check uses — reads **only the last paragraph** of the message. The three
trailers must therefore form **one final paragraph**, each on its own line, with **no blank line
between them**, separated from the subject by exactly one blank line. Repeated `-m` puts each
argument in its **own paragraph**, so only the last one is seen: the commit then reports
`topic=[] turn=[] attempt=[01]` and a correct, in-scope turn fails check 5 as
`REJECTED: verification-failed`. Use `git commit -F -`:

```bash
git -C "$WT" commit -F - <<'MSG'
<subject line>

Agent-Pairing-Topic: <topic_id>
Agent-Pairing-Turn: <TTTT>
Agent-Pairing-Attempt: <AA>
MSG
```

Never `git commit -m 'subj' -m 'Agent-Pairing-Topic: …' -m …`. The lines must also be **flush left**:
git folds a whitespace-led line into the previous trailer, and an indented block reports all three
brackets empty. The same rule applies to the relay
path's `On-behalf-of:` and `Applied-by:` lines — they join that one final paragraph too.

**Check 6 — cleanliness.**

```bash
git -C "$WT" status --porcelain      # must be empty
```

**Check 7 — scope, both sides of every change.** `--name-only` reports only a rename's
*destination*, so a rename out of an out-of-scope directory passes it while touching a path it must
not. Parse `--name-status -M -C -z` and validate the source *and* destination of every `R`/`C`
entry. Every path must fall under a declared prefix at a path-segment boundary (`src/` matches
`src/a.c`, never `src2/a.c`). Run under bash:

```bash
SCOPE="<the assignment's space-separated scope prefixes>"
bad=""
while IFS= read -r -d '' st; do
  case "$st" in R*|C*) n=2;; *) n=1;; esac
  i=0
  while [ "$i" -lt "$n" ]; do
    IFS= read -r -d '' p || break 2
    hit=no
    for pre in $SCOPE; do
      case "$pre" in */) ;; *) pre="$pre/";; esac
      case "$p/" in "$pre"*) hit=yes;; esac
    done
    [ "$hit" = yes ] || bad="$bad $p"
    i=$((i+1))
  done
done < <(git -C "$WT" diff --name-status -M -C -z "$BASE".."$RES")
[ -z "$bad" ] || echo "OUT OF SCOPE:$bad"
```

Any out-of-scope path is `REJECTED: out-of-scope-changes`, unless a linked owner answer accepts it.

**Check 8 — diff and claims (the one judgment call).** Read `git diff "$BASE".."$RES"` against the
prose and reject claims the diff does not support. Then spot-check at least one claimed
verification **in a disposable detached worktree** — never in the session worktree:

```bash
SPOT="$(mktemp -d)/spot"
git -C "$WT" worktree add --detach "$SPOT" "$RES"      # for a REVIEW turn, use "$BASE"
# … run the claimed verification command here and capture its output …
git -C "$WT" worktree remove "$SPOT"                   # always remove it; never rm -rf
```

Re-observe check 3's tip equality as the **last** step of verification, to shrink the window
between checking and accepting.

### Turn kinds

- `NORMAL` — delivers commits. `result_sha` required and must differ from `base_sha`.
- `REVIEW` — delivers a report. Commits are forbidden; `result_sha` is required and must **equal**
  `base_sha` (reporting it proves the agent observed its own tree). The accepted SHA does not move.
- `REMEDIATION` — restores a quarantined branch, append-only.
- A `null` `result_sha` is reserved for no-commit failure results (`ABORTED`, declined). Write it as
  the literal four-character token `null` (`result_sha: null`) — not an empty value, not omitted.

Reasons: `verification-failed`, `review-failed`, `no-op-result`, `out-of-scope-changes`,
`patch-apply-failed`, `agent-declined-with-question`, `residue-after-termination`,
`replaced-by-retry`, `collision`, `never-dispatched`, `dispatch-confirmed-absent`,
`terminated-before-result`, `transport-lossy`, `other` (mandatory free text). An agent that declines
with a question costs nothing: route it to a fresh assignment or an owner question.

Two of those reasons are **owner-materialized only**: `dispatch-confirmed-absent` and
`terminated-before-result` each require an `owner_answer_ref` naming an answer with the matching
action (`dispatch-confirmed-absent` / `dispatch-termination-confirmed`), and the validator rejects
the record without one. A termination or an absence **you** confirmed yourself is `other`, with the
evidence in the body.

### When the agent cannot see the worktree

If the registry marks an agent `read-only`, or the worktree path is not visible to it, use the
relay path. The agent returns a fenced `RELAY-THIS` report and, for code, a fenced unified diff
(`git diff --binary --full-index`) **plus** its base SHA, its byte count, and its SHA-256. Verify
all three before applying. Then:

```bash
git -C "$WT" apply --3way <patch>
```

Commit with the attempt's trailers plus `On-behalf-of: <agent_id>` and `Applied-by: primary`, then
run checks 0–8 against that commit. A failed apply is `REJECTED: patch-apply-failed` with the
verbatim error — **never repair the patch**: repairing makes you the author and voids the
provenance the record depends on. A byte-count or hash mismatch is `ABORTED: transport-lossy`.

---

## FENCE — deadlines, liveness, and never re-dispatching into uncertainty

Completion and liveness are different questions, and a commit appears only at the end of a turn.
Deadlines are checked **when you look** — there are no daemons, timers, or background waiters here,
and "poll for N minutes" is a promise this protocol does not make. When the deadline on the open
assignment has passed, walk this ladder in order:

1. **Check progress, not process.** New commits in the session worktree? Job output advancing?

   ```bash
   git -C "$WT" log --oneline "$BASE"..HEAD
   git -C "$WT" status --porcelain
   ```

   A job "running" for hours with nothing produced is dead in every sense that matters. A dirty
   tree under a live open attempt is *expected* — that is work in progress, not drift.
2. **No progress → confirm termination** using the `job_id` from the dispatch receipt. The receipt
   is what lets a *fresh* primary fence a job its crashed predecessor started. Per-transport
   commands: `RUNBOOK.md`.
3. **Termination confirmed → inspect without changing anything**, and route:
   - tip = HEAD = `base_sha` and the tree is clean → `ABORTED: other`, with the captured
     termination evidence in the body (`other` requires explanatory body text, and that evidence is
     it). Write a new assignment with a **bumped attempt id** and re-dispatch. Do **not** reach for
     `terminated-before-result` here: it is gated on an `owner_answer_ref` and is reserved for the
     owner-materialized path (an answer with `action: dispatch-termination-confirmed`). Steps 2–3
     are the self-service path — a termination *you* confirmed is recorded as `other`; step 4 is the
     only branch that goes to the owner.
   - a commit landed → `REJECTED`; the branch is quarantined → `REMEDIATION_REQUIRED`.
   - uncommitted residue → `REJECTED: residue-after-termination` with the residue captured as
     evidence → `UNRECORDED_DRIFT`. **Never erase residue merely to retry**; the only exit is an
     owner answer.
4. **Cannot confirm → write an owner question** from `templates/owner-question.md`, with `blocks`
   naming this attempt (`t<TTTT>-a<AA>`). The topic is now `AWAITING_OWNER`. **Never re-dispatch
   into uncertainty** — two agents in one tree is the failure this whole design exists to prevent.

The new attempt id is the fencing token. A late zombie does not necessarily fail ancestry; it is
caught by its stale attempt trailer, or by the tip disagreeing with the accepted SHA, at the next
verification or resume boundary. Landed zombie commits quarantine the branch until a revert or
remediation turn restores a verified tip. **A failed remediation attempt escalates to the owner —
it never auto-retries.**

---

## RESUME — a fresh primary reconstructs the state

You have the topic directory and the work repo, and nothing else. Do not dispatch, do not write a
record, and do not touch the worktree until you have finished step 2.

### Step 0 — the record-repo gate

```bash
git -C <topic-dir> status --porcelain
```

Uncommitted files mean the previous primary died mid-step. Resolve by *kind*:

| Uncommitted file | Why | What you do |
|---|---|---|
| `assignment` | Provably pre-dispatch — dispatch is strictly ordered after the intent commit | Discard it |
| `intent` | Same | Discard it |
| `dispatch` receipt | Post-dispatch evidence — but a crash can truncate it | See the partial-receipt path below |
| `result` | Verification is read-only and idempotent | Re-run the checks, complete the file, commit it |
| `THREAD.md`, or a `THREAD.md.tmp.*` render temp | Derived, never authored | Remove the temp, regenerate with `--render`, continue |
| Anything else | Unexplained | Stop, record what you observed, ask the owner |

**The partial-receipt path.** An uncommitted receipt is not automatically a valid record. Validate
it first: complete front matter; the exact topic/turn/attempt tuple matching the committed
assignment and intent; non-empty `transport`, `job_id` and timestamps; an allowed `receipt_source`.

- Complete and consistent → commit it with `receipt_source: validated-uncommitted`.
- Truncated or inconsistent → capture its **exact bytes, byte count and SHA-256** into a
  dispatch-unknown owner question. Remove the partial file **only after that question's commit
  succeeds**, then follow the durable-intent path (`DISPATCH_UNKNOWN`) below.

### Step 1 — replay

```bash
/bin/bash scripts/validate.sh --check <topic-dir>
```

STOP on exit 2. Exit 2 here means the record itself is broken — a sequence gap, a duplicate, a
dangling link, an unauthorized owner action. A gap can only mean deletion or tampering; it is never
something to write past. Ask the owner.

The validator replays the record in `record_seq` order, checks every linkage, derives the accepted
SHA, and prints a header (`accepted_sha`, `open_attempt`, `dispatched_at`) followed by one
`classification:` line.

### Step 2 — confirm the worktree is registered

Before trusting anything about the worktree path:

```bash
git -C <repo> worktree list --porcelain
```

Absence is expected only while finalizing a close, or after one. Otherwise it is drift.

### Step 3 — act on the classification

The validator **classifies**; it never writes a record and never touches the work repo. The write
half is yours. First match wins, and the validator already applied that precedence:

| `classification:` | What it means | What **you** write next |
|---|---|---|
| `IDLE` | Tip = HEAD = accepted SHA, clean, nothing open | Start the next turn (**CYCLE**) or close (**CLOSE**) |
| `OPEN (never-dispatched)` | An unmatched assignment with no intent — provably never dispatched | Write a mechanical `ABORTED: never-dispatched` result, then a new assignment with a bumped attempt, and re-dispatch. No human needed |
| `OPEN (dispatched)` | A receipt exists | Fence it (**FENCE**) by its `job_id` |
| `DISPATCH_UNKNOWN` | An intent with no receipt | First run the transport's token search for the idempotency token (`RUNBOOK.md`). Found → write the receipt with `receipt_source: token-search`. Not found → write **exactly one** owner question with `blocks` naming this attempt. If the latest answer was `dispatch-unresolved`, stay here and wait for new evidence — do **not** write another automatic question |
| `AWAITING_OWNER` | An unanswered owner question | **Stop.** Nothing else may be written until the answer is recorded |
| `OWNER_ACTION_PENDING` | An actionable dispatch authorization that has not materialized | Execute the authorized materialization idempotently (below). An answer alone never closes an assignment; never blind-retry |
| `REMEDIATION_REQUIRED` | The tip is a quarantined commit, or every commit above the accepted SHA carries a closed attempt's valid trailers | For the trailer case, first write the `late` record (`templates/late.md`, observation only). Then run a `REMEDIATION` turn from the quarantined tip |
| `UNRECORDED_DRIFT` | The tip, the tree, or the worktree cannot be explained by the record — including a missing worktree path before close | **Stop.** Write down every observation (tip, HEAD, status, worktree list) and open an owner question. Resume only under an owner answer authorizing cleanup or remediation |
| `CLOSING:<close_id>` | A close record exists with a postcondition still missing | Continue the finalizer (**CLOSE**, steps 3–5) |
| `CLOSED` | All postconditions proved | Terminal. Any new record in `turns/` after this is corruption |

A `(unverified: …)` suffix on any of these means a read failed, not that the state is true. Restore
the read first.

**Materializing an owner authorization.** The answer's `action` decides the record you write, and
each is safe to re-run until it commits:

- `dispatch-job-found` (carries `transport` + `job_id`) → append a dispatch receipt with
  `receipt_source: owner-answer` and the `owner_answer_ref`, then fence that job.
- `dispatch-confirmed-absent` (carries authoritative evidence) → inspect the worktree; append
  `ABORTED: dispatch-confirmed-absent` with the `owner_answer_ref` **only when** tip = HEAD =
  `base_sha` and the tree is clean.
- `dispatch-termination-confirmed` (carries termination evidence) → append `ABORTED:
  terminated-before-result` with the `owner_answer_ref`, under that same clean-and-stationary gate.
- `dispatch-unresolved` → nothing materializes; the state stays `DISPATCH_UNKNOWN`.

If the clean-and-stationary gate fails, write `REJECTED` naming the answer and the observed commit
or residue, then route normally to `REMEDIATION_REQUIRED` or `UNRECORDED_DRIFT`.

---

## CLOSE — closing a topic

1. **Preconditions.** `scripts/validate.sh --check <topic-dir>` must classify `IDLE`: no open
   attempt, no unanswered owner question, tip = HEAD = the accepted SHA, clean tree. STOP on exit 2.
   An owner answer may mark charter items withdrawn or authorize close after a resolved remediation
   decision. It may **not** waive a possibly-live attempt, a dirty tree, an identity mismatch, or an
   unexplained ref — those are fenced or resolved first.
2. **Write and commit the close record** from `templates/close.md`: a unique `close_id`, the
   `final_accepted_sha`, a disposition for **every** charter item (met / not met / withdrawn — no
   silent drops), and the follow-ups note: file durable follow-ups in the project's own tracker.
   This commit is the durable transition to `CLOSING:<close_id>`. It is **not** `CLOSED`.
3. **Run the idempotent finalizer.** If the session worktree is registered and its path exists,
   re-check clean tree, symbolic branch, and HEAD = branch tip = `final_accepted_sha`, then:

   ```bash
   git -C <repo> worktree remove <worktree-path>      # no --force, ever
   ```

   Removal is satisfied only when the path is absent **and** no `git worktree list` entry names it.
   A path/list disagreement, or content that does not match, is never erased: write **one** owner
   question with `blocks: CLOSING:<close_id>`.
4. **Re-read the branch ref** from the work repo and require it still equals `final_accepted_sha`:

   ```bash
   git -C <repo> rev-parse refs/heads/pair/<slug>
   ```

   A mismatch takes the same linked-question route as step 3.
5. **Regenerate and commit `THREAD.md`.** `--render` projects the header and emits `status: CLOSED`
   only when the worktree-absent and branch-at-final postconditions pass. `--check` reads the
   **committed** `THREAD.md`, so an uncommitted or modified one fails the postcondition:

   ```bash
   /bin/bash scripts/validate.sh --render <topic-dir>
   git -C <topic-dir> add THREAD.md && git -C <topic-dir> commit -m 'close: <close_id>'
   /bin/bash scripts/validate.sh --check <topic-dir>      # must now print classification: CLOSED
   ```

   Run `scripts/validate.sh --check <topic-dir>` and STOP on exit 2. Anything other than
   `classification: CLOSED` means a postcondition is still missing — read which one from the
   `postcondition` lines and continue from step 3. Step 5 is safe to repeat and appends no record
   to `turns/`.

**Postconditions — a topic is `CLOSED` only when all of these hold:** the committed `THREAD.md`
header says `CLOSED`, the branch ref equals `final_accepted_sha`, the session worktree path is
absent, and its `git worktree list` entry is absent.

**The `cancel-close` route.** When the step-3 or step-4 safety gate fails, the linked owner question
has one safe resolution: an answer with `action: cancel-close`. It invalidates that close attempt
only. Replay then classifies the observed worktree normally — often `UNRECORDED_DRIFT` or
`REMEDIATION_REQUIRED` — normal records may resume, and a later close gets a **new** `close_id`.

**While a close is active**, only its linked owner question and answer may follow it in `turns/`;
anything else is corruption. After a topic is finally `CLOSED`, any new record is corruption, and a
late work-repo observation is an owner matter outside the record.

The branch survives, unmerged. Merging and upstream reconciliation are the owner's decisions,
outside this protocol. The record directory is retained, still with no remote.

---

## Record grammar (quick reference)

Filenames are `SSSS-tTTTT-aAA-<kind>[-KK].md`; owner and close records are `SSSS-<kind>.md`. The
front-matter `record_seq` is authoritative and the filename prefix is a zero-padded convenience.
`record_seq` = the highest committed one + 1, and the file is written **and committed in one
durable step**. A record that cannot be committed fails closed: no dispatch, no transition.

| Kind | Template |
|---|---|
| `assignment` | `templates/assignment.md` |
| `intent` | `templates/intent.md` |
| `dispatch` | `templates/dispatch.md` |
| `result` | `templates/result.md` |
| `late` | `templates/late.md` |
| `owner-question` | `templates/owner-question.md` |
| `owner-answer` | `templates/owner-answer.md` |
| `close` | `templates/close.md` |

`TOPIC.md` comes from `templates/TOPIC.md`; the pasteable onboarding text from
`templates/onboarding.md`.

Field widths are seq 4, turn 4, attempt 2, late 2. A topic that would exceed them closes, and a
successor topic opens.

## The onboarding text and the digest

The onboarding text is the **only** carrier of this protocol for agents that never read this
package. It is self-contained, pasteable, about one page, and it goes into every dispatch payload
verbatim, together with a digest: charter, DECISIONS, the last assignment, the last result, the
accepted SHA, the observed tip, and the current classification — each under a stated byte budget
(4 KiB by default) with explicit `[TRUNCATED n bytes — see turns/SSSS]` markers where it is cut.
Bounded means a budget, not a hope.

It must always carry: absolute paths and the one-machine precondition; the goal and done-criteria in
three sentences or fewer; the settled DECISIONS as one-liners so a newcomer does not re-litigate an
old round; the pinned base plus the pre-flight stop rule (*verify HEAD equals the pinned base before
touching anything; on mismatch, stop and report*); the scope, the literal trailer block, and the
mandatory instruction to **report the exact output of `git rev-parse HEAD` after the final commit**;
the difference between VERIFIED and INFERRED; the relay fallback; and the DON'T list — nothing
outside the worktree, nothing outside scope, no record edits, no switch/detach/reset/rebase/ref
updates, no line numbers, job status is not completion, one turn only, never paste secrets.

The first-turn failures to warn against, in the order they actually occur: summarizing instead of
working · editing outside scope · citing line numbers · reading job status as completion · taking a
second turn · "helpfully" editing the record.

## What this skill does not do

No parallel turns, no voting or consensus, no second primary, no cross-machine operation (it is a
stated precondition that fails loudly at onboarding), no daemons or timers or watchers, no tracker
integration beyond the one follow-ups line in the close record, and no transport mechanics — those
live in `RUNBOOK.md`.

A verbatim, append-only record will eventually capture a credential. The record repo has no remote
by default and the onboarding forbids pasting secrets. If a secret does land in the record: rotate
the credential and record an owner answer. **The record is not rewritten.**

## The honest limit

You are participant, judge and scribe — often for work you dispatched and sometimes for work you
did yourself. That conflict is mitigated by the mechanical checks, by agent-reported SHAs, by
verbatim capture, by an append-only history, and by the owner as arbiter. It is not eliminated.
Check 8 is judgment, and the worktree is safety, not security.
