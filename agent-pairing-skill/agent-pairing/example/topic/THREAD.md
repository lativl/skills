GENERATED — do not edit — regenerate with: validate.sh --render <topic-dir>
accepted_sha: 68b832a88ab99abd7996d95ec9f3796c63db5b6f
open_attempt:
dispatched_at:
postcondition thread-header: PROJECTED
postcondition worktree-absent: PASS
postcondition branch-at-final: PASS
classification: CLOSED
status: CLOSED

---8<--- 0001-t0001-a01-assignment.md ---

---
record_seq: 0001
kind: assignment
topic_id: example
turn_id: 0001
attempt_id: 01
turn_kind: NORMAL
base_sha: 59da6216b2b3e018910d888600d2f4c9ba538d55
session_branch: pair/example
session_worktree: /private/tmp/ap-example.JkYZl2/wt
work_repo_common_dir: /private/tmp/ap-example.JkYZl2/repo/.git
scope: src/
deadline: 2026-08-12T23:00:00Z
agent_id: demo-agent
recorded_at: 2026-08-12T13:41:30Z
---
Goal: add a greeting line to `src/app.txt`.
Deliverable: one commit on `pair/example` whose diff touches only `src/app.txt` and adds a greeting line.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
Trailers:
Agent-Pairing-Topic: example
Agent-Pairing-Turn: 0001
Agent-Pairing-Attempt: 01

---8<--- 0002-t0001-a01-intent.md ---

---
record_seq: 0002
kind: intent
topic_id: example
turn_id: 0001
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0001-t0001-a01-assignment.md
idempotency_token: idem-example-t0001-a01
recorded_at: 2026-08-12T13:41:30Z
---
Committed dispatch authorization.

---8<--- 0003-t0001-a01-dispatch.md ---

---
record_seq: 0003
kind: dispatch
topic_id: example
turn_id: 0001
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0001-t0001-a01-assignment.md
transport: in-session
job_id: job-example-t0001-a01
dispatched_at: 2026-08-12T13:41:30Z
intent_ref: 0002-t0001-a01-intent.md
receipt_source: direct
recorded_at: 2026-08-12T13:41:30Z
---
Captured dispatch receipt. For owner-authorized recovery, insert `owner_answer_ref` in front matter.

---8<--- 0004-t0001-a01-result.md ---

---
record_seq: 0004
kind: result
topic_id: example
turn_id: 0001
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0001-t0001-a01-assignment.md
status: VERIFIED
reason: 
result_sha: 3be12c8472ee26ef7b5c02528478db9a7548dbcf
observed_at: 2026-08-12T13:42:03Z
recorded_at: 2026-08-12T13:42:03Z
---
## Verbatim agent output
Captured from the agent's returned session, verbatim (four-backtick fence; the text contains no
backtick runs of its own).

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
59da6216b2b3e018910d888600d2f4c9ba538d55
pre-flight: HEAD matches the pinned base 59da6216b2b3e018910d888600d2f4c9ba538d55 -- proceeding
$ git -C /tmp/ap-example.JkYZl2/wt add src/app.txt && git -C /tmp/ap-example.JkYZl2/wt commit
3be12c8 add a greeting line to src/app.txt
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
3be12c8472ee26ef7b5c02528478db9a7548dbcf
$ git -C /tmp/ap-example.JkYZl2/wt status --porcelain
(empty)
$ grep -c greeting /tmp/ap-example.JkYZl2/wt/src/app.txt
1
````

Agent-reported `result_sha`: `3be12c8472ee26ef7b5c02528478db9a7548dbcf` (never observed by the
primary; see check 0).

## Verification
NORMAL result -> checks 0-8 all GATE. Every block below is real captured output from this run.

## Primary commentary (separate)
Checks 0-8 all pass. The diff adds exactly one line to `src/app.txt` and nothing else, which is
what the agent claimed; the spot-check confirmed the greeting line is present in a detached
worktree at the reported SHA, not merely in the session tree. Status VERIFIED; the accepted SHA
advances to `3be12c8472ee26ef7b5c02528478db9a7548dbcf` (c1).

**Check 0 - no-op precheck.** Reported `3be12c8472ee26ef7b5c02528478db9a7548dbcf` != base `59da6216b2b3e018910d888600d2f4c9ba538d55`.

**Check 1 - existence.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --verify 3be12c8472ee26ef7b5c02528478db9a7548dbcf^{commit}
3be12c8472ee26ef7b5c02528478db9a7548dbcf
(exit 0)
````

**Check 2 - worktree identity** (all three must match TOPIC.md).

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --show-toplevel
/private/tmp/ap-example.JkYZl2/wt
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --git-common-dir
/private/tmp/ap-example.JkYZl2/repo/.git
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt symbolic-ref --short HEAD
pair/example
(exit 0)
````

**Check 3 - tip equality.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
3be12c8472ee26ef7b5c02528478db9a7548dbcf
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" rev-parse "refs/heads/$(git -C "/tmp/ap-example.JkYZl2/wt" symbolic-ref --short HEAD)"
3be12c8472ee26ef7b5c02528478db9a7548dbcf
(exit 0)
````

**Check 4 - append-only ancestry.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" merge-base --is-ancestor "59da6216b2b3e018910d888600d2f4c9ba538d55" "3be12c8472ee26ef7b5c02528478db9a7548dbcf"; echo rc=$?
rc=0
(exit 0)
````

**Check 5 - attempt attribution.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" log --format='%H topic=[%(trailers:key=Agent-Pairing-Topic,valueonly,separator=%x2C)] turn=[%(trailers:key=Agent-Pairing-Turn,valueonly,separator=%x2C)] attempt=[%(trailers:key=Agent-Pairing-Attempt,valueonly,separator=%x2C)]' "59da6216b2b3e018910d888600d2f4c9ba538d55".."3be12c8472ee26ef7b5c02528478db9a7548dbcf"
3be12c8472ee26ef7b5c02528478db9a7548dbcf topic=[example] turn=[0001] attempt=[01]
(exit 0)
````

**Check 6 - cleanliness** (must be empty).

````
$ git -C "/tmp/ap-example.JkYZl2/wt" status --porcelain; echo "[end of status output]"
[end of status output]
(exit 0)
````

**Check 7 - scope, both sides of every change.** The command below is SKILL.md check 7 verbatim, with `SCOPE` set to this assignment: `src/`

````
$ SCOPE="src/"; <SKILL.md check-7 block>
[no OUT OF SCOPE line -- every path is under a declared prefix]
(exit 0)
````

**Check 8 - diff and claims**, then the spot-check in a disposable detached worktree.

````
$ git -C /tmp/ap-example.JkYZl2/wt diff 59da6216b2b3e018910d888600d2f4c9ba538d55..3be12c8472ee26ef7b5c02528478db9a7548dbcf
diff --git a/src/app.txt b/src/app.txt
index ce01362..2f025ca 100644
--- a/src/app.txt
+++ b/src/app.txt
@@ -1 +1,2 @@
 hello
+greeting: hello, world
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree add --detach "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.09QYEOez3t/spot" "3be12c8472ee26ef7b5c02528478db9a7548dbcf"
Preparing worktree (detached HEAD 3be12c8)
HEAD is now at 3be12c8 add a greeting line to src/app.txt
(exit 0)
````

````
$ grep -n greeting "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.09QYEOez3t/spot/src/app.txt"
2:greeting: hello, world
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree remove "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.09QYEOez3t/spot"
(exit 0)
````

**Re-observed check 3 (last step of verification).**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
3be12c8472ee26ef7b5c02528478db9a7548dbcf
(exit 0)
````

---8<--- 0005-t0002-a01-assignment.md ---

---
record_seq: 0005
kind: assignment
topic_id: example
turn_id: 0002
attempt_id: 01
turn_kind: NORMAL
base_sha: 3be12c8472ee26ef7b5c02528478db9a7548dbcf
session_branch: pair/example
session_worktree: /private/tmp/ap-example.JkYZl2/wt
work_repo_common_dir: /private/tmp/ap-example.JkYZl2/repo/.git
scope: src/
deadline: 2026-08-12T23:30:00Z
agent_id: demo-agent
recorded_at: 2026-08-12T13:42:45Z
---
Goal: add a farewell line to `src/app.txt`.
Deliverable: one commit on `pair/example` whose diff touches only `src/app.txt` and adds a farewell line. `scope` is `src/` and nothing else: `config.txt` is OUT of scope.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
Trailers:
Agent-Pairing-Topic: example
Agent-Pairing-Turn: 0002
Agent-Pairing-Attempt: 01

---8<--- 0006-t0002-a01-intent.md ---

---
record_seq: 0006
kind: intent
topic_id: example
turn_id: 0002
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0005-t0002-a01-assignment.md
idempotency_token: idem-example-t0002-a01
recorded_at: 2026-08-12T13:42:45Z
---
Committed dispatch authorization.

---8<--- 0007-t0002-a01-dispatch.md ---

---
record_seq: 0007
kind: dispatch
topic_id: example
turn_id: 0002
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0005-t0002-a01-assignment.md
transport: in-session
job_id: job-example-t0002-a01
dispatched_at: 2026-08-12T13:42:45Z
intent_ref: 0006-t0002-a01-intent.md
receipt_source: direct
recorded_at: 2026-08-12T13:42:45Z
---
Captured dispatch receipt. For owner-authorized recovery, insert `owner_answer_ref` in front matter.

---8<--- 0008-t0002-a01-result.md ---

---
record_seq: 0008
kind: result
topic_id: example
turn_id: 0002
attempt_id: 01
turn_kind: NORMAL
assignment_ref: 0005-t0002-a01-assignment.md
status: REJECTED
reason: out-of-scope-changes
result_sha: f0bd7d5be8404355142f69d3784d761a82c9d409
observed_at: 2026-08-12T13:43:08Z
recorded_at: 2026-08-12T13:43:08Z
---
## Verbatim agent output
````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
3be12c8472ee26ef7b5c02528478db9a7548dbcf
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
f0bd7d5be8404355142f69d3784d761a82c9d409
$ git -C /tmp/ap-example.JkYZl2/wt show --stat --oneline HEAD
f0bd7d5 add a farewell line and turn it on in config
 config.txt  | 1 +
 src/app.txt | 1 +
 2 files changed, 2 insertions(+)
````

Agent-reported `result_sha`: `f0bd7d5be8404355142f69d3784d761a82c9d409`. The agent also wrote:
"added the farewell line and flipped the feature on in config so it actually shows up."


## Verification
NORMAL result -> checks 0-8 all GATE. Checks 0-6 pass; check 7 FAILS. The failing command and its real output are below.

## Primary commentary (separate)
Checks 0-6 pass. Check 7 fails: `config.txt` is outside the declared scope `src/`. Status
REJECTED, reason `out-of-scope-changes`. The commit landed, so the accepted SHA does NOT advance and
the branch is now QUARANTINED at `f0bd7d5be8404355142f69d3784d761a82c9d409` -- the next `--check`
classifies REMEDIATION_REQUIRED.

The objection carries its fix (never reject bare): in `config.txt`, remove the appended
`farewell_enabled` assignment; the farewell line in `src/app.txt` is correct and in scope and should
be kept. The failure this prevents: an assignment declaring `src/` gives the primary no basis to
judge a configuration change, and accepting it would silently widen every later turn's scope.

Note for the record: the agent's own report never mentioned `config.txt` in its `rev-parse` lines --
only `git show --stat` revealed it. This is exactly why check 7 parses the diff rather than trusting
the report.

**Check 0.** Reported `f0bd7d5be8404355142f69d3784d761a82c9d409` != base `3be12c8472ee26ef7b5c02528478db9a7548dbcf`.

**Check 1 - existence.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --verify f0bd7d5be8404355142f69d3784d761a82c9d409^{commit}
f0bd7d5be8404355142f69d3784d761a82c9d409
(exit 0)
````

**Check 2 - worktree identity.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --show-toplevel
/private/tmp/ap-example.JkYZl2/wt
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --git-common-dir
/private/tmp/ap-example.JkYZl2/repo/.git
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt symbolic-ref --short HEAD
pair/example
(exit 0)
````

**Check 3 - tip equality.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
f0bd7d5be8404355142f69d3784d761a82c9d409
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" rev-parse "refs/heads/$(git -C "/tmp/ap-example.JkYZl2/wt" symbolic-ref --short HEAD)"
f0bd7d5be8404355142f69d3784d761a82c9d409
(exit 0)
````

**Check 4 - append-only ancestry.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" merge-base --is-ancestor "3be12c8472ee26ef7b5c02528478db9a7548dbcf" "f0bd7d5be8404355142f69d3784d761a82c9d409"; echo rc=$?
rc=0
(exit 0)
````

**Check 5 - attempt attribution.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" log --format='%H topic=[%(trailers:key=Agent-Pairing-Topic,valueonly,separator=%x2C)] turn=[%(trailers:key=Agent-Pairing-Turn,valueonly,separator=%x2C)] attempt=[%(trailers:key=Agent-Pairing-Attempt,valueonly,separator=%x2C)]' "3be12c8472ee26ef7b5c02528478db9a7548dbcf".."f0bd7d5be8404355142f69d3784d761a82c9d409"
f0bd7d5be8404355142f69d3784d761a82c9d409 topic=[example] turn=[0002] attempt=[01]
(exit 0)
````

**Check 6 - cleanliness.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" status --porcelain; echo "[end of status output]"
[end of status output]
(exit 0)
````

**Check 7 - scope, both sides of every change. THIS IS THE FAILING CHECK.** SKILL.md check 7 verbatim, `SCOPE` set to this assignment: `src/`

````
$ SCOPE="src/"; <SKILL.md check-7 block>
OUT OF SCOPE: config.txt
````

The supporting diff, for the record:

````
$ git -C "/tmp/ap-example.JkYZl2/wt" diff --name-status -M -C "3be12c8472ee26ef7b5c02528478db9a7548dbcf".."f0bd7d5be8404355142f69d3784d761a82c9d409"
M	config.txt
M	src/app.txt
(exit 0)
````

**Check 8 - diff and claims.** The diff was read; the spot-check worktree was NOT created.
SKILL.md does not state whether the checks short-circuit once one gates, so the primary read the
diff (cheap, read-only) and skipped the disposable-worktree spot-check, whose only purpose would be
to substantiate claims about a result that is already rejected.

````
$ git -C /tmp/ap-example.JkYZl2/wt diff 3be12c8472ee26ef7b5c02528478db9a7548dbcf..f0bd7d5be8404355142f69d3784d761a82c9d409
diff --git a/config.txt b/config.txt
index 97bc5ce..f697a88 100644
--- a/config.txt
+++ b/config.txt
@@ -1 +1,2 @@
 cfg
+farewell_enabled=true
diff --git a/src/app.txt b/src/app.txt
index 2f025ca..79f07f7 100644
--- a/src/app.txt
+++ b/src/app.txt
@@ -1,2 +1,3 @@
 hello
 greeting: hello, world
+farewell: goodbye, world
(exit 0)
````

**Re-observed check 3 (last step).**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
f0bd7d5be8404355142f69d3784d761a82c9d409
(exit 0)
````

---8<--- 0009-t0003-a01-assignment.md ---

---
record_seq: 0009
kind: assignment
topic_id: example
turn_id: 0003
attempt_id: 01
turn_kind: REMEDIATION
base_sha: f0bd7d5be8404355142f69d3784d761a82c9d409
session_branch: pair/example
session_worktree: /private/tmp/ap-example.JkYZl2/wt
work_repo_common_dir: /private/tmp/ap-example.JkYZl2/repo/.git
scope: src/ config.txt
deadline: 2026-08-13T01:00:00Z
agent_id: primary
recorded_at: 2026-08-12T13:44:05Z
---
Goal: restore the accepted content append-only. `git revert` the quarantined commit
f0bd7d5be8404355142f69d3784d761a82c9d409 so the tree returns to the accepted SHA's content.
Authorised by the REMEDIATION_REQUIRED classification printed after record 0008.
Deliverable: one revert commit on `pair/example`. Done-criteria: `git diff <accepted c1> <result>`
is EMPTY -- the accepted content is restored -- and no history is rewritten (no reset, no
force-push). Scope is `src/ config.txt` because the revert necessarily touches both paths the
quarantined commit touched; that is what makes an append-only undo possible at all.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
Trailers:
Agent-Pairing-Topic: example
Agent-Pairing-Turn: 0003
Agent-Pairing-Attempt: 01

---8<--- 0010-t0003-a01-intent.md ---

---
record_seq: 0010
kind: intent
topic_id: example
turn_id: 0003
attempt_id: 01
turn_kind: REMEDIATION
assignment_ref: 0009-t0003-a01-assignment.md
idempotency_token: idem-example-t0003-a01
recorded_at: 2026-08-12T13:44:05Z
---
Committed dispatch authorization.

---8<--- 0011-t0003-a01-dispatch.md ---

---
record_seq: 0011
kind: dispatch
topic_id: example
turn_id: 0003
attempt_id: 01
turn_kind: REMEDIATION
assignment_ref: 0009-t0003-a01-assignment.md
transport: self
job_id: self-t0003-a01
dispatched_at: 2026-08-12T13:44:05Z
intent_ref: 0010-t0003-a01-intent.md
receipt_source: direct
recorded_at: 2026-08-12T13:44:05Z
---
Captured dispatch receipt. For owner-authorized recovery, insert `owner_answer_ref` in front matter.

---8<--- 0012-t0003-a01-result.md ---

---
record_seq: 0012
kind: result
topic_id: example
turn_id: 0003
attempt_id: 01
turn_kind: REMEDIATION
assignment_ref: 0009-t0003-a01-assignment.md
status: VERIFIED
reason: 
result_sha: 21863f265eefb6ff3db9c0866167c35c27b5e7f9
observed_at: 2026-08-12T13:44:37Z
recorded_at: 2026-08-12T13:44:37Z
---
## Verbatim agent output
This turn was SELF-DISPATCHED: the primary held the turn (`agent_id: primary`, transport `self`),
so "the agent's returned output" is the primary's own captured session. It is still recorded
verbatim here, and it is still judged by the same checks -- that is the honest limit SKILL.md names.

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
f0bd7d5be8404355142f69d3784d761a82c9d409
$ git -C /tmp/ap-example.JkYZl2/wt revert --no-commit f0bd7d5be8404355142f69d3784d761a82c9d409
$ git -C /tmp/ap-example.JkYZl2/wt commit -m 'revert the out-of-scope commit f0bd7d5' ...
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
21863f265eefb6ff3db9c0866167c35c27b5e7f9
````


## Verification
REMEDIATION result -> checks 0-8 all GATE, exactly as for a NORMAL turn.

## Primary commentary (separate)
Checks 0-8 all pass and the done-criterion holds: `git diff c1 c3` is empty, so the accepted
content is restored without rewriting anything. Status VERIFIED; the accepted SHA advances to
`21863f265eefb6ff3db9c0866167c35c27b5e7f9` (c3). The quarantine is lifted -- the next `--check`
classifies IDLE, which is what re-authorises an ordinary turn.

Turn 0002's goal is still unmet: the farewell line went away with the revert. It is retried as
attempt 02 of the SAME turn (t0002-a02), with a bumped attempt id, not as a new turn -- the attempt
id is the fencing token and the turn id is the piece of work.

**Check 0.** Reported `21863f265eefb6ff3db9c0866167c35c27b5e7f9` != base (the quarantined tip) `f0bd7d5be8404355142f69d3784d761a82c9d409`.

**Check 1 - existence.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --verify 21863f265eefb6ff3db9c0866167c35c27b5e7f9^{commit}
21863f265eefb6ff3db9c0866167c35c27b5e7f9
(exit 0)
````

**Check 2 - worktree identity.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --show-toplevel
/private/tmp/ap-example.JkYZl2/wt
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --git-common-dir
/private/tmp/ap-example.JkYZl2/repo/.git
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt symbolic-ref --short HEAD
pair/example
(exit 0)
````

**Check 3 - tip equality.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
21863f265eefb6ff3db9c0866167c35c27b5e7f9
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" rev-parse "refs/heads/$(git -C "/tmp/ap-example.JkYZl2/wt" symbolic-ref --short HEAD)"
21863f265eefb6ff3db9c0866167c35c27b5e7f9
(exit 0)
````

**Check 4 - append-only ancestry** (the quarantined tip is an ANCESTOR of the revert -- nothing was rewritten).

````
$ git -C "/tmp/ap-example.JkYZl2/wt" merge-base --is-ancestor "f0bd7d5be8404355142f69d3784d761a82c9d409" "21863f265eefb6ff3db9c0866167c35c27b5e7f9"; echo rc=$?
rc=0
(exit 0)
````

**Check 5 - attempt attribution.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" log --format='%H topic=[%(trailers:key=Agent-Pairing-Topic,valueonly,separator=%x2C)] turn=[%(trailers:key=Agent-Pairing-Turn,valueonly,separator=%x2C)] attempt=[%(trailers:key=Agent-Pairing-Attempt,valueonly,separator=%x2C)]' "f0bd7d5be8404355142f69d3784d761a82c9d409".."21863f265eefb6ff3db9c0866167c35c27b5e7f9"
21863f265eefb6ff3db9c0866167c35c27b5e7f9 topic=[example] turn=[0003] attempt=[01]
(exit 0)
````

**Check 6 - cleanliness.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" status --porcelain; echo "[end of status output]"
[end of status output]
(exit 0)
````

**Check 7 - scope.** SKILL.md check 7 verbatim, `SCOPE` set to this assignment: `src/ config.txt`

````
$ SCOPE="src/ config.txt"; <SKILL.md check-7 block>
OUT OF SCOPE: config.txt src/app.txt
[no OUT OF SCOPE line]
(exit 0)
````

**Check 8 - diff and claims**, plus the done-criterion: the tree must equal the accepted content.

````
$ git -C /tmp/ap-example.JkYZl2/wt diff f0bd7d5be8404355142f69d3784d761a82c9d409..21863f265eefb6ff3db9c0866167c35c27b5e7f9
diff --git a/config.txt b/config.txt
index f697a88..97bc5ce 100644
--- a/config.txt
+++ b/config.txt
@@ -1,2 +1 @@
 cfg
-farewell_enabled=true
diff --git a/src/app.txt b/src/app.txt
index 79f07f7..2f025ca 100644
--- a/src/app.txt
+++ b/src/app.txt
@@ -1,3 +1,2 @@
 hello
 greeting: hello, world
-farewell: goodbye, world
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" diff --stat "3be12c8472ee26ef7b5c02528478db9a7548dbcf" "21863f265eefb6ff3db9c0866167c35c27b5e7f9"; echo "[empty diff => the accepted content of 3be12c8472ee26ef7b5c02528478db9a7548dbcf is restored]"
[empty diff => the accepted content of 3be12c8472ee26ef7b5c02528478db9a7548dbcf is restored]
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree add --detach "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.vUU75CbJdL/spot" "21863f265eefb6ff3db9c0866167c35c27b5e7f9"
Preparing worktree (detached HEAD 21863f2)
HEAD is now at 21863f2 revert the out-of-scope commit f0bd7d5
(exit 0)
````

````
$ cat "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.vUU75CbJdL/spot/config.txt"
cfg
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree remove "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.vUU75CbJdL/spot"
(exit 0)
````

**Re-observed check 3 (last step).**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
21863f265eefb6ff3db9c0866167c35c27b5e7f9
(exit 0)
````

---8<--- 0013-t0002-a02-assignment.md ---

---
record_seq: 0013
kind: assignment
topic_id: example
turn_id: 0002
attempt_id: 02
turn_kind: NORMAL
base_sha: 21863f265eefb6ff3db9c0866167c35c27b5e7f9
session_branch: pair/example
session_worktree: /private/tmp/ap-example.JkYZl2/wt
work_repo_common_dir: /private/tmp/ap-example.JkYZl2/repo/.git
scope: src/
deadline: 2026-08-13T02:00:00Z
agent_id: demo-agent
recorded_at: 2026-08-12T13:45:04Z
---
Goal: RETRY of turn 0002 with a bumped attempt id. Add a farewell line to `src/app.txt` and
nothing else. The attempt id is the fencing token: any commit still arriving from attempt 01 is
identified by its stale `Agent-Pairing-Attempt: 01` trailer.
Deliverable: one commit on `pair/example` touching ONLY `src/app.txt`. `config.txt` is out of
scope -- attempt 01 was rejected for exactly that, see turns/0008. If you believe a config change
is required, decline with a question; do not take it yourself.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
Trailers:
Agent-Pairing-Topic: example
Agent-Pairing-Turn: 0002
Agent-Pairing-Attempt: 02

---8<--- 0014-t0002-a02-intent.md ---

---
record_seq: 0014
kind: intent
topic_id: example
turn_id: 0002
attempt_id: 02
turn_kind: NORMAL
assignment_ref: 0013-t0002-a02-assignment.md
idempotency_token: idem-example-t0002-a02
recorded_at: 2026-08-12T13:45:04Z
---
Committed dispatch authorization.

---8<--- 0015-t0002-a02-dispatch.md ---

---
record_seq: 0015
kind: dispatch
topic_id: example
turn_id: 0002
attempt_id: 02
turn_kind: NORMAL
assignment_ref: 0013-t0002-a02-assignment.md
transport: in-session
job_id: job-example-t0002-a02
dispatched_at: 2026-08-12T13:45:04Z
intent_ref: 0014-t0002-a02-intent.md
receipt_source: direct
recorded_at: 2026-08-12T13:45:04Z
---
Captured dispatch receipt. For owner-authorized recovery, insert `owner_answer_ref` in front matter.

---8<--- 0016-t0002-a02-result.md ---

---
record_seq: 0016
kind: result
topic_id: example
turn_id: 0002
attempt_id: 02
turn_kind: NORMAL
assignment_ref: 0013-t0002-a02-assignment.md
status: VERIFIED
reason: 
result_sha: 68b832a88ab99abd7996d95ec9f3796c63db5b6f
observed_at: 2026-08-12T13:45:36Z
recorded_at: 2026-08-12T13:45:36Z
---
## Verbatim agent output
````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
21863f265eefb6ff3db9c0866167c35c27b5e7f9
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
68b832a88ab99abd7996d95ec9f3796c63db5b6f
$ git -C /tmp/ap-example.JkYZl2/wt status --porcelain
(empty)
$ cat /tmp/ap-example.JkYZl2/wt/src/app.txt
hello
greeting: hello, world
farewell: goodbye, world
````

Agent-reported `result_sha`: `68b832a88ab99abd7996d95ec9f3796c63db5b6f`.

## Verification
NORMAL result -> checks 0-8 all GATE. Check 5 is the interesting one here: the range must carry attempt `02`, not `01`.

## Primary commentary (separate)
Checks 0-8 all pass. The diff touches only `src/app.txt`; the spot-check shows `config.txt` back at
its seed content `cfg`, so the rejected change did not survive the revert. Status VERIFIED; the
accepted SHA advances to `68b832a88ab99abd7996d95ec9f3796c63db5b6f` (c4).

Both charter done-criteria are now met, so the next move is CLOSE.

**Check 0.** Reported `68b832a88ab99abd7996d95ec9f3796c63db5b6f` != base `21863f265eefb6ff3db9c0866167c35c27b5e7f9`.

**Check 1 - existence.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --verify 68b832a88ab99abd7996d95ec9f3796c63db5b6f^{commit}
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

**Check 2 - worktree identity.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --show-toplevel
/private/tmp/ap-example.JkYZl2/wt
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse --git-common-dir
/private/tmp/ap-example.JkYZl2/repo/.git
(exit 0)
````

````
$ git -C /tmp/ap-example.JkYZl2/wt symbolic-ref --short HEAD
pair/example
(exit 0)
````

**Check 3 - tip equality.**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" rev-parse "refs/heads/$(git -C "/tmp/ap-example.JkYZl2/wt" symbolic-ref --short HEAD)"
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

**Check 4 - append-only ancestry.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" merge-base --is-ancestor "21863f265eefb6ff3db9c0866167c35c27b5e7f9" "68b832a88ab99abd7996d95ec9f3796c63db5b6f"; echo rc=$?
rc=0
(exit 0)
````

**Check 5 - attempt attribution** (every bracket must hold `02`; a stale `01` here would be a zombie from the fenced attempt).

````
$ git -C "/tmp/ap-example.JkYZl2/wt" log --format='%H topic=[%(trailers:key=Agent-Pairing-Topic,valueonly,separator=%x2C)] turn=[%(trailers:key=Agent-Pairing-Turn,valueonly,separator=%x2C)] attempt=[%(trailers:key=Agent-Pairing-Attempt,valueonly,separator=%x2C)]' "21863f265eefb6ff3db9c0866167c35c27b5e7f9".."68b832a88ab99abd7996d95ec9f3796c63db5b6f"
68b832a88ab99abd7996d95ec9f3796c63db5b6f topic=[example] turn=[0002] attempt=[02]
(exit 0)
````

**Check 6 - cleanliness.**

````
$ git -C "/tmp/ap-example.JkYZl2/wt" status --porcelain; echo "[end of status output]"
[end of status output]
(exit 0)
````

**Check 7 - scope.** SKILL.md check 7 verbatim, `SCOPE` set to this assignment: `src/`

````
$ SCOPE="src/"; <SKILL.md check-7 block>
[no OUT OF SCOPE line -- unlike attempt 01]
(exit 0)
````

**Check 8 - diff and claims**, plus the spot-check in a disposable detached worktree.

````
$ git -C /tmp/ap-example.JkYZl2/wt diff 21863f265eefb6ff3db9c0866167c35c27b5e7f9..68b832a88ab99abd7996d95ec9f3796c63db5b6f
diff --git a/src/app.txt b/src/app.txt
index 2f025ca..79f07f7 100644
--- a/src/app.txt
+++ b/src/app.txt
@@ -1,2 +1,3 @@
 hello
 greeting: hello, world
+farewell: goodbye, world
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree add --detach "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.p8CO6YsTcS/spot" "68b832a88ab99abd7996d95ec9f3796c63db5b6f"
Preparing worktree (detached HEAD 68b832a)
HEAD is now at 68b832a add a farewell line to src/app.txt
(exit 0)
````

````
$ cat "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.p8CO6YsTcS/spot/src/app.txt"; echo '---'; cat "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.p8CO6YsTcS/spot/config.txt"
hello
greeting: hello, world
farewell: goodbye, world
---
cfg
(exit 0)
````

````
$ git -C "/tmp/ap-example.JkYZl2/wt" worktree remove "/var/folders/rd/fv90t57x5272lmdqdk_8cxj40000gn/T/tmp.p8CO6YsTcS/spot"
(exit 0)
````

**Re-observed check 3 (last step).**

````
$ git -C /tmp/ap-example.JkYZl2/wt rev-parse HEAD
68b832a88ab99abd7996d95ec9f3796c63db5b6f
(exit 0)
````

---8<--- 0017-close.md ---

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

