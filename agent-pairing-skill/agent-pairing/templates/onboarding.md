# Onboarding
## Absolute paths
## One-machine pre-flight
## Settled DECISIONS
One line each, projected from TOPIC.md's DECISIONS section.
## Current accepted SHA and branch
## Wait for the COMMITTED receipt — never the working tree
Read every record with committed-object access only:

```bash
git -C {{TOPIC_DIR}} cat-file -e "HEAD:turns/{{EXPECTED_DISPATCH_REF}}" && \
  git -C {{TOPIC_DIR}} show "HEAD:turns/{{EXPECTED_DISPATCH_REF}}"
```

An uncommitted receipt authorizes **nothing**. You may receive a transport prompt before the receipt
exists — some transports reveal the job ID only after submission — and that is not authorization
either. Poll committed `HEAD` in the foreground until `{{EXPECTED_DISPATCH_REF}}` appears or the
bound `receipt_commit_by_epoch: {{RECEIPT_COMMIT_BY_EPOCH}}` passes. If the bound passes first,
**write nothing to the worktree**, report the zero-write expiry, and exit.

## ACK FIRST — your first message is the acknowledgement
Before you modify the worktree or author a single byte of relay patch, emit exactly this:

```text
topic: {{TOPIC_ID}}   turn: {{TURN_ID}}   attempt: {{ATTEMPT_ID}}
idempotency_token: {{IDEMPOTENCY_TOKEN}}
admission_ref: {{ADMISSION_REF}}
dispatch_ref: {{EXPECTED_DISPATCH_REF}}
job_id: {{JOB_ID}}
ack_evidence_class: {{ACK_EVIDENCE_CLASS}}
observed_head: {{OBSERVED_HEAD}}
preflight_clean: {{PREFLIGHT_CLEAN}}
relayed_base_sha: {{RELAYED_BASE_SHA}}
```

Which preflight shape you use is fixed by `worktree_visible: {{WORKTREE_VISIBLE}}`:

- **visible** — run `git -C {{SESSION_WORKTREE}} rev-parse HEAD` and
  `git -C {{SESSION_WORKTREE}} status --porcelain`. Report the HEAD you actually saw (it must be the
  assigned base) and `preflight_clean: true`; `relayed_base_sha` is the literal `null`.
- **invisible** — `observed_head: null` and `preflight_clean: null`, because you did not look and
  must not claim you did. Echo the assigned base as `relayed_base_sha`.

Your work budget starts when the primary captures this ACK, not when you first saw the prompt.

## Your capability — what you may and may not produce
`capability: {{CAPABILITY}}`

- `commits` — you may land a commit in the visible worktree, with the trailers below.
- `writes-repo-only` — visible: leave uncommitted changes for the primary. Invisible: return a relay
  patch. Never a `result_sha` of your own.
- `read-only` — report only. No commit, no worktree modification, no `patch.diff`.

## Turn, attempt, scope, and the three bounds
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
## Verification environment — run it under the assigned profile
`verification_profile_id: {{VERIFICATION_PROFILE_ID}}`

The profile is defined in `TOPIC.md`. Before claiming anything:

1. Run the profile's exact `bootstrap_command`.
2. Run the profile's exact `verification_command` — not your own variation of it.
3. Report the profile ID, the **resolved tool versions**, the exact command, and the **captured
   output**, including any failing command.

A claim without captured output is a claim, not evidence. If you cannot establish the profile at all,
say so plainly and stop — do not report a red result from a different environment as though it were a
finding about this snapshot. An unpinned failure is a fact about the machine you ran on.

## Verification and VERIFIED result contract
## RELAY-THIS fallback
## DON'T list
## Digest and truncation
Each digest section has a 4 KiB budget. Use `[TRUNCATED n bytes — see turns/SSSS]` when exceeded.
