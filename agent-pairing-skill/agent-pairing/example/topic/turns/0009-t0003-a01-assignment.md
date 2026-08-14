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
