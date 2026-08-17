# The worked example — one topic, seventeen records, real captured output

This directory is the package's conformance fixture (spec §7): *one fully worked topic — open →
turn 1 → verbatim verification transcript → a rejected retry with a bumped attempt → close.* It is
also the only place in the package where SKILL.md's checklists have actually been followed end to
end rather than described.

## Provenance — how this was produced

Every byte in `topic/turns/` came out of a real mini-session run under `/tmp` on 2026-08-12 with
git 2.50.1: a real seed repo, a real `git worktree`, real commits carrying real trailers, and the
validator gating every step. **Every verification block's output is captured command output.** The
`cap` helper that built them printed the command, ran it, and appended its real stdout+stderr and
exit status directly into the record — nothing was retyped, reconstructed or composed. Composed
transcripts are forbidden here: the whole value of this artifact is that it is evidence.

One command *line* is a reference rather than a literal invocation: check 7 in
`topic/turns/0008-t0002-a01-result.md` reads `$ SCOPE="src/"; <SKILL.md check-7 block>`, standing
for the multi-line block in SKILL.md. Its output — `OUT OF SCOPE: config.txt` — is genuine, and
`tests/run-tests.sh` executes that same block, extracted from SKILL.md, against a real repo.
Everything else in `topic/turns/` is verbatim, command line included.

Two honest caveats, stated rather than hidden:

1. **Both roles are played by one primary.** The registry in `topic/TOPIC.md` says so. The
   "agent" is the same session acting under the agent's constraints; `result_sha` values are
   nonetheless *reported* by the agent role and never substituted by an observation the primary
   made itself (check 0), and every check was run for real against the resulting commits.
2. **The close finalizer's own output is not in `turns/`.** The close record is committed *before*
   the finalizer runs, and after a close no record may follow except its linked owner question and
   answer — so `worktree remove`, the step-4 branch re-read and the render have nowhere to be
   recorded. Their durable trace is the `postcondition` block in `topic/THREAD.md`, and the
   pre-close half of the gate *is* captured, inside `topic/turns/0017-close.md`.

## The seventeen records

| seq | file | spec | what it demonstrates |
|---|---|---|---|
| — | `TOPIC.md` | §3.0, §2.1 | the pinned `base_sha` + explicit `base_ref`, the registry, DECISIONS accumulating one line per settled decision, the pasteable onboarding |
| 0001 | `0001-t0001-a01-assignment.md` | §3.2, §3.3 | assignment: scope as space-separated prefixes, DON'Ts, the literal trailer block |
| 0002 | `0002-t0001-a01-intent.md` | §3.3 | the intent commit that strictly precedes dispatch — "no intent" proves "never dispatched" |
| 0003 | `0003-t0001-a01-dispatch.md` | §3.3 | the receipt with a real `job_id` and `receipt_source: direct` |
| 0004 | `0004-t0001-a01-result.md` | §3.4 | `VERIFIED` — checks 0–8 all run and all captured, including the check-8 spot-check in a **disposable detached worktree**. Accepted SHA advances to c1 |
| 0005–0007 | `t0002-a01` assignment/intent/dispatch | §3.3 | turn 2, scope `src/` only |
| 0008 | `0008-t0002-a01-result.md` | §3.4 check 7 | **`REJECTED: out-of-scope-changes`, for real.** The agent also edited `config.txt`; SKILL.md's check-7 command printed `OUT OF SCOPE: config.txt`. The commit landed, so the branch is **quarantined** and the next `--check` says `REMEDIATION_REQUIRED` |
| 0009–0011 | `t0003-a01` assignment/intent/dispatch | §3.3, §6.3 | a `REMEDIATION` turn based on the **quarantined tip**, authorised by that classification, self-dispatched (`agent_id: primary` — you write yourself an assignment for your own turns too) |
| 0012 | `0012-t0003-a01-result.md` | §3.7 | `VERIFIED`: `git revert` restores the accepted content **append-only** — never a reset, never a force-push. Accepted SHA advances to c3; the quarantine lifts and the topic is `IDLE` again |
| 0013–0015 | `t0002-a02` assignment/intent/dispatch | §4 | the **bumped attempt**: the same turn retried with a new attempt id, which is the fencing token |
| 0016 | `0016-t0002-a02-result.md` | §3.4 check 5 | `VERIFIED`: check 5 shows the range carrying attempt `02`; a stale `01` here would be a zombie. Accepted SHA advances to c4 |
| 0017 | `0017-close.md` | §3.8 | the close record: a disposition for **every** charter item, the follow-ups line, and the pre-close gate evidence. This record is the durable transition to `CLOSING:c-0001` — it is **not** `CLOSED` |
| — | `THREAD.md` | §3.8 step 5 | generated, never hand-authored; carries `status: CLOSED` and the three postconditions |

The SHAs, for cross-reference: base `59da6216…`, c1 `3be12c84…`, c2 (quarantined, never accepted)
`f0bd7d5b…`, c3 (the revert) `21863f26…`, c4 (final) `68b832a8…`.

## Why the shipped `topic/` says `CLOSING` and not `CLOSED`

The snapshot in `topic/` is a `git archive` of the record repo's tracked tree: **it has no `.git` of
its own**, and the `/tmp` work repo it names is not there either. So in place it honestly reports

```
postcondition thread-header: UNAVAILABLE
classification: CLOSING:c-0001 (unverified: …)
```

That is not a defect and it is not the topic's real state — `UNAVAILABLE` means *the validator could
not read something*, exactly as SKILL.md says. `--check` reads the **committed** `THREAD.md` via
`git show HEAD:THREAD.md`, and a directory with no repository has no `HEAD`.

`rehydrate.sh` restores both repos from the two bundles into the absolute paths pinned in
`PATHS.env` (the same paths the records name — records are not rewritable, so the paths cannot
move), and the very same records then classify:

```
postcondition thread-header: PASS
postcondition worktree-absent: PASS
postcondition branch-at-final: PASS
classification: CLOSED
```

Both readings are asserted by `tests/run-tests.sh`, together with render-stability: regenerating
`THREAD.md` from the rehydrated record reproduces the committed file byte for byte.

```bash
RT="$(/bin/bash example/rehydrate.sh --print-topic)"   # prints the restored topic dir
/bin/bash scripts/validate.sh --check "$RT"            # → classification: CLOSED
/bin/bash example/rehydrate.sh --clean                 # removes only its own marked directories
```

`rehydrate.sh` never recreates the session worktree: the close postcondition requires that path
absent. It refuses to delete anything outside `$ROOT` or anything missing the
`.agent-pairing-example` ownership marker, and it restores into staging directories that are
verified before they are swapped in, so a corrupt bundle can never replace a good restore.

It runs from **any** working directory, including one that is not inside a git repository — such as
the installed package at `<skills-root>/agent-pairing/` (`~/.claude/skills` for Claude,
`~/.codex/skills` for Codex). `git bundle verify` needs a repository, so the script gives it one
explicitly (the staging repo it has just created) rather than borrowing the caller's cwd.
