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
