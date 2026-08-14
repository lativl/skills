# Onboarding
## Absolute paths
## One-machine pre-flight
## Settled DECISIONS
One line each, projected from TOPIC.md's DECISIONS section.
## Current accepted SHA and branch
## Turn, attempt, scope, and deadline
## Commit trailers — one final paragraph, `git commit -F -`
The three `Agent-Pairing-*` lines form ONE final paragraph: no blank line between them, one blank
line after the subject. Git reads trailers only from the last paragraph, so repeated `-m` (each
argument is its own paragraph) drops all but the last and your turn is rejected for missing
attribution. A leading space breaks them too — git folds a whitespace-led line into the previous
trailer and all three come back empty. Commit with a heredoc, never with repeated `-m`, and keep the
trailer lines flush left:

```bash
git -C <session_worktree> commit -F - <<'MSG'
<subject line>

Agent-Pairing-Topic: <topic_id>
Agent-Pairing-Turn: <TTTT>
Agent-Pairing-Attempt: <AA>
MSG
```
## Verification and VERIFIED result contract
## RELAY-THIS fallback
## DON'T list
## Digest and truncation
Each digest section has a 4 KiB budget. Use `[TRUNCATED n bytes — see turns/SSSS]` when exceeded.
