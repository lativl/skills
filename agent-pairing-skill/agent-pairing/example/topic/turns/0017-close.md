---
record_seq: 0017
kind: close
topic_id: example
close_id: c-0001
final_accepted_sha: 68b832a88ab99abd7996d95ec9f3796c63db5b6f
recorded_at: 2026-08-12T13:46:05Z
---
## Charter dispositions (every item, no silent drops)

| # | Charter item | Disposition |
|---|---|---|
| 1 | `src/app.txt` contains a greeting line | **met** -- t0001-a01, accepted at c1 `3be12c8` |
| 2 | `src/app.txt` contains a farewell line | **met** -- t0002-a02, accepted at c4 `68b832a` |
| 3 | every accepted commit carries the three trailers and touches only declared scope | **met** -- check 5 and check 7 evidence in turns/0004, 0012 and 0016; the one commit that violated it (c2 `f0bd7d5`) was rejected and reverted, never accepted |

## Follow-ups

Durable follow-ups belong in the project's own tracker, not in this record. One is filed there: the
`farewell_enabled` flag that t0002-a01 tried to smuggle into `config.txt` was never re-proposed as
its own turn; if it is wanted, it needs an assignment declaring `config.txt` in scope.

## Pre-close evidence (§3.8 step 1 and the step-3 gate, captured BEFORE this record was written)


Precondition: `--check` classifies IDLE.

````
$ /bin/bash "/private/tmp/claude-501/-Users-vlysovych-Work-Projects-platform/64dfb8b6-d468-48e2-a9c3-1d0b3e6f8570/scratchpad/skill-design/skills/agent-pairing/scripts/validate.sh" --check "/tmp/ap-example.JkYZl2/topic"
accepted_sha: 68b832a88ab99abd7996d95ec9f3796c63db5b6f
open_attempt:
dispatched_at:
postcondition thread-header: FAIL
postcondition worktree-absent: FAIL
postcondition branch-at-final: PASS
classification: CLOSING:c-0001
(exit 0)
````

Step-3 gate: clean tree, symbolic branch, HEAD = branch tip = final_accepted_sha.

````
$ git -C "/tmp/ap-example.JkYZl2/wt" status --porcelain; echo "[end of status output]"
[end of status output]
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt symbolic-ref --short HEAD
pair/example
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/repo rev-parse refs/heads/pair/example
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/repo" worktree list --porcelain
worktree /private/tmp/ap-example.JkYZl2/repo
HEAD 59da6216b2b3e018910d888600d2f4c9ba538d55
branch refs/heads/main

worktree /private/tmp/ap-example.JkYZl2/wt
HEAD 68b832a88ab99abd7996d95ec9f3796c63db5b6f
branch refs/heads/pair/example

(exit 0)
````

The worktree removal itself, the step-4 re-read and the render happen AFTER this record is
committed; no record may follow a close except its own linked owner question and answer, so their
evidence lives in `THREAD.md`'s postcondition lines and in `example/README.md`, not here.
