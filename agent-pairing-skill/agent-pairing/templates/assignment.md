---
record_seq: {{RECORD_SEQ}}
kind: assignment
topic_id: {{TOPIC_ID}}
turn_id: {{TURN_ID}}
attempt_id: {{ATTEMPT_ID}}
turn_kind: {{TURN_KIND}}
base_sha: {{BASE_SHA}}
session_branch: {{SESSION_BRANCH}}
session_worktree: {{SESSION_WORKTREE}}
work_repo_common_dir: {{WORK_REPO_COMMON_DIR}}
scope: {{SCOPE}}
deadline: {{DEADLINE}}
agent_id: {{AGENT_ID}}
recorded_at: {{RECORDED_AT}}
---
Goal: state the requested outcome.
Deliverable: state the observable artifact.
DON'Ts: do not leave the worktree, exceed scope, edit records, dispatch another agent, or omit evidence.
Trailers: these three lines are ONE final paragraph of the commit message — no blank line between
them, one blank line after the subject. Git's trailer parser reads only the last paragraph, so
repeated `-m` (each argument becomes its own paragraph) drops all but the last trailer and fails
attribution. A leading space breaks them too — git folds a whitespace-led line into the previous
trailer, and all three brackets come back empty. Commit with `git commit -F -`, never with repeated
`-m`, and keep the trailer lines flush left:

```bash
git -C {{SESSION_WORKTREE}} commit -F - <<'MSG'
<subject line>

Agent-Pairing-Topic: {{TOPIC_ID}}
Agent-Pairing-Turn: {{TURN_ID}}
Agent-Pairing-Attempt: {{ATTEMPT_ID}}
MSG
```
