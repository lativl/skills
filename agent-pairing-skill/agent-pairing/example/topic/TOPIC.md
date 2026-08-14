---
topic_id: example
base_sha: 59da6216b2b3e018910d888600d2f4c9ba538d55
base_ref: refs/heads/main
session_branch: pair/example
session_worktree: /private/tmp/ap-example.JkYZl2/wt
work_repo_common_dir: /private/tmp/ap-example.JkYZl2/repo/.git
---
<!-- base_sha is the pinned base (§3.0 step 3); base_ref is the EXPLICIT ref it was cut from
     (§2.2, "never guessed"). The validator seeds accepted_sha from base_sha and presence-checks
     base_ref — it cannot resolve a remote ref in a rehydrated repo and does not claim to. -->
# example
## Charter
Goal: give `src/app.txt` a greeting line and a farewell line, one per turn, without touching
anything outside `src/`.
Done-criteria:
1. `src/app.txt` contains a greeting line.  2. `src/app.txt` contains a farewell line.
3. Every accepted commit carries this topic's three trailers and touches only declared scope.
## Preconditions
One machine, one shared filesystem. All paths absolute. Commit hooks: none active in the work repo
(`ls .git/hooks` shows only `*.sample`), so nothing rewrites messages or blocks the trailers.
This example runs entirely under /tmp; it is a fixture, not a real engagement.
## Registry
| agent_id | transport | capability class | worktree visible? |
|---|---|---|---|
| `demo-agent` | in-session (the primary plays the agent role for this fixture) | `commits` | yes |
| `primary` | n/a — self-assigned turns (the revert) | `commits` | yes |
## DECISIONS
- t0002-a01 rejected `out-of-scope-changes`: `config.txt` is not in scope for this topic; a
  feature flag is a separate turn with its own declared scope, never a rider on a source edit.
- The quarantined tip is restored by `git revert` as a new REMEDIATION turn -- never a reset or a
  force-push (the branch is append-only).
- A rejected turn is retried as a BUMPED ATTEMPT of the same turn (t0002-a02), never as a new turn:
  the turn id names the piece of work and the attempt id is the fencing token.
## Onboarding
Instantiated from `templates/onboarding.md`; the pasteable text below goes into every dispatch
payload verbatim, together with the digest.

### Absolute paths
work repo `/private/tmp/ap-example.JkYZl2/repo`, session worktree
`/private/tmp/ap-example.JkYZl2/wt`, branch `pair/example`. Never leave the worktree.

### One-machine pre-flight
This protocol is single-machine. Before touching anything, verify HEAD equals the pinned base named
in your assignment; on mismatch, stop and report.

### Settled DECISIONS
Projected one line each from the DECISIONS section above.

### Current accepted SHA and branch
Named in the assignment as `base_sha`, on branch `pair/example`.

### Turn, attempt, scope, and deadline
Named in the assignment. `scope` is a space-separated list of path prefixes; both sides of a rename
must fall inside it.

### Verification and VERIFIED result contract
VERIFIED means a command plus its captured output; anything else is INFERRED and must be labelled.
Report the exact output of `git rev-parse HEAD` after your final commit. Commit with these trailers:

    Agent-Pairing-Topic: example
    Agent-Pairing-Turn: <TTTT>
    Agent-Pairing-Attempt: <AA>

### RELAY-THIS fallback
If you cannot see the worktree, return a fenced `RELAY-THIS` report plus a fenced
`git diff --binary --full-index`, its base SHA, byte count and SHA-256.

### DON'T list
Nothing outside the worktree; nothing outside scope; no record edits; no
switch/detach/reset/rebase/ref updates; no line numbers; job status is not completion; one turn
only; never paste secrets.

### Digest and truncation
Each digest section has a 4 KiB budget. Use `[TRUNCATED n bytes - see turns/SSSS]` when exceeded.
