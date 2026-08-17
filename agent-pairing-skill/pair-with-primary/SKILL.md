---
name: pair-with-primary
description: Use when asked to pair with a primary agent on an agent-pairing topic — "pair with primary on <topic>", "join topic <topic>", "join the pairing topic <topic>", "enter pairing loop". Joins the topic, reads its onboarding from the committed record, acknowledges each dispatch before working, and takes assigned turns one at a time until told to stop.
---

# pair-with-primary — the agent's side of an agent-pairing topic

You are the **agent**, not the primary. You take assigned turns in a shared worktree, one per
dispatch. **The primary owns the record and is its only writer.** You never write the record, never
update a ref, and never use Git notes.

Invoke it by saying what you want — **"pair with primary on \<topic\>"** or "join topic \<topic\>".
`<topic>` is either a slug or an absolute path to the record directory.

Not every runtime exposes skills as slash commands: Codex's `/` list is a fixed built-in set, so
`/pair-with-primary demo` is rejected there — say "pair with primary on demo" instead. Claude Code
does expose skills as `/`-commands.

## The one rule that generates the rest

**A record exists when it is committed.** Everything you read comes from a committed Git object, and
nothing you see in the record's working tree means anything at all.

That is not fastidiousness. The primary writes a receipt and commits it; between those two moments
the bytes exist on disk and describe work that has not been authorized. v1 let the participant list
`turns/` from the working tree, so a half-written receipt could start a turn — and the motivating
failure record contains exactly that shape: a receipt, a participant that never had a live listener,
and no way to tell the two apart afterwards.

## Step 1 — resolve the topic and read it from committed objects

```bash
TOPIC=<record-root>/<topic>        # an absolute path is used as-is
                                   # default record root on this machine: ~/.claude/agent-pairing
export GIT_NO_REPLACE_OBJECTS=1
git -C "$TOPIC" cat-file -e HEAD:TOPIC.md 2>/dev/null || { echo "no committed topic at $TOPIC"; exit 1; }
git -C "$TOPIC" show HEAD:TOPIC.md
```

To LIST the committed records — the newest assignment, the intent — enumerate the tree, never the
directory:

```bash
git -C "$TOPIC" ls-tree -r --name-only HEAD turns
```

That is the positive form of the rule above. Forbidding the working tree without saying what to do
instead leaves listing the directory as the path of least resistance, which is exactly the habit this
manual exists to break.

For a **slug**, check both runtime record roots. Stop on zero matches and stop on more than one — two
topics with the same slug in different roots is an ambiguity you must not resolve by guessing.

`TOPIC.md` is your instruction set. Its front matter gives `session_worktree`, `session_branch` and
the topic's OPEN-time `base_sha`; its **Onboarding** section is the protocol as this topic requires
it. Read the Onboarding section in full before doing anything. If it has no Onboarding content, say
so and stop — do not improvise the protocol.

**Do not pre-flight against `TOPIC.md`'s `base_sha`.** That is the base the topic was OPENED at and
it never moves, while the accepted SHA advances with every VERIFIED turn. On any topic past its first
turn, HEAD legitimately differs from it, so a join-time check against it fails forever. The base you
check is the one in the assignment you are about to work on. At join time there is nothing to
pre-flight: you have no assignment yet.

```bash
WT=<session_worktree from TOPIC.md>
```

If the worktree is not visible to you, say so and stop — the primary will admit you on the relay path
instead, and that is a different capability with different rules.

## Step 2 — the loop

Repeat until the primary or the user tells you to stop.

### 2a. Wait for the next dispatch — two waits, both bounded

Never start from an assignment alone. The primary commits the assignment, then the intent, then the
receipt. Only the committed receipt means "go", and waiting for it is what keeps "no intent proves
never dispatched" true.

There are **two** waits here and they are not the same thing. Collapsing them is a real trap: on your
second time round this loop the previous turn's `EXPECTED_DISPATCH_REF` still names a receipt that
*is* committed, so a single wait finds it instantly and you re-acknowledge and re-work the dispatch
you just finished — taking a second turn on one dispatch, which this manual forbids.

Track what you have already handled, once, at the top of the session:

```bash
HANDLED=""            # attempts you have acknowledged, as "tTTTT-aAA tTTTT-aAA ..."
IDLE_BUDGET_SECONDS=1800   # how long you stay available between turns; operator-set
```

**Wait one — for a NEW intent.** Between turns you are idle, and the primary may take any amount of
time to open the next one. That wait is bounded too, by a budget you own rather than by anything in
the record: an unbounded waiter cannot be observed or fenced.

```bash
IDLE_UNTIL=$(( $(date +%s) + IDLE_BUDGET_SECONDS ))
INTENT=""
while [ "$(date +%s)" -le "$IDLE_UNTIL" ]; do
  HEAD_SHA="$(git -C "$TOPIC" rev-parse HEAD)" || exit 1
  # Newest intent first; take the first one whose attempt you have not already handled.
  for f in $(git -C "$TOPIC" ls-tree -r --name-only "$HEAD_SHA" turns \
             | grep -- '-intent\.md$' | LC_ALL=C sort -r); do
    ATT="$(printf '%s\n' "$f" | sed -E 's|^turns/[0-9]{4}-(t[0-9]{4}-a[0-9]{2})-intent\.md$|\1|')"
    case " $HANDLED " in *" $ATT "*) continue ;; esac
    INTENT="$f"; break
  done
  [ -n "$INTENT" ] && break
  sleep 5
done
[ -n "$INTENT" ] || {
  printf 'idle_wait: expired; worktree_writes: 0\n'
  exit 0
}
git -C "$TOPIC" show "$HEAD_SHA:$INTENT"
```

Read `expected_dispatch_ref` and `receipt_commit_by_epoch` from **that** intent.

**Wait two — for THAT intent's receipt**, bounded by the intent's own `receipt_commit_by_epoch`:

```bash
FOUND_RECEIPT=no
while [ "$(date +%s)" -le "$RECEIPT_COMMIT_BY_EPOCH" ]; do
  HEAD_SHA="$(git -C "$TOPIC" rev-parse HEAD)" || exit 1
  if git -C "$TOPIC" cat-file -e "$HEAD_SHA:turns/$EXPECTED_DISPATCH_REF" 2>/dev/null; then
    git -C "$TOPIC" show "$HEAD_SHA:turns/$EXPECTED_DISPATCH_REF"
    FOUND_RECEIPT=yes
    break
  fi
  sleep 2
done
[ "$FOUND_RECEIPT" = yes ] || {
  printf 'receipt_wait: expired; worktree_writes: 0\n'
  exit 0
}
```

**Both waits are bounded and in the foreground.** If the receipt bound passes with no committed
receipt, write **nothing** to the worktree, report the zero-write expiry, and return control. Replay
then sees a committed intent with no receipt and classifies `DISPATCH_UNKNOWN`, which is the truthful
state.

Do not leave a background monitor. Do not silently repeat either wait forever: an unbounded waiter
cannot be observed or fenced, and a poll whose result nobody reads is not a poll.

You may receive a transport prompt *before* the receipt is committed — some transports reveal the
job ID only after submission. **That is not authorization.** Wait for the committed object.

### 2b. ACK FIRST — your first message is the acknowledgement

Before you modify the worktree, and before you author a single byte of relay patch, emit the
acknowledgement. This is the only evidence that delivery happened; the primary's own receipt proves
only that the primary wrote something.

```text
topic: <topic_id>   turn: <turn_id>   attempt: <attempt_id>
idempotency_token: <exact value from the committed intent>
admission_ref: <exact value from the assignment>
dispatch_ref: <the receipt you just read>
job_id: <exact value from the receipt you just read>
ack_evidence_class: <transport-attested | human-relayed, as admitted>
observed_head: <see the table>
preflight_clean: <see the table>
relayed_base_sha: <see the table>
```

Which preflight shape you use is fixed by the admission's `worktree_visible`:

| `worktree_visible` | You send | Because |
| --- | --- | --- |
| `true` | `observed_head` = the assignment's `base_sha`, `preflight_clean: true`, `relayed_base_sha: null` | you looked, so you report what you saw |
| `false` | `observed_head: null`, `preflight_clean: null`, `relayed_base_sha` = the assignment's `base_sha` | you did NOT look, so claiming an observation would be a false claim |

When visible, run both commands and report their actual output:

```bash
git -C "$WT" rev-parse HEAD        # must equal the assignment's base_sha
git -C "$WT" status --porcelain    # must be empty
```

On mismatch, **stop and report the mismatch**. Do not "fix" the tree — a tree you repaired is
evidence you destroyed.

Your work budget starts when the primary captures this ACK, not when you first saw the prompt. Wait
for the primary to capture it before starting work.

### 2c. Do the turn

Only inside `$WT`, only under the assignment's scope prefixes, **one turn** only.

Your `capability` decides what you may produce:

- `commits` — land a commit in the worktree, with the trailers below.
- `writes-repo-only` — leave uncommitted changes (visible) or return a relay patch (invisible).
  Never a `result_sha` of your own.
- `read-only` — report only. No commit, no worktree modification, no patch.

### 2d. Commit, when your capability allows it

The three trailers must form ONE final paragraph, flush left, with no blank line between them — git
reads trailers only from the last paragraph, so repeated `-m` drops all but the last and a correct
turn is rejected for missing attribution:

```bash
git -C "$WT" commit -F - <<'MSG'
<subject line>

Agent-Pairing-Topic: <topic_id>
Agent-Pairing-Turn: <turn_id from the assignment>
Agent-Pairing-Attempt: <attempt_id from the assignment>
MSG
```

### 2e. Report through the admitted channel, with an exact manifest

Return your report over the admitted `report_channel` — `transport-output` or `human-relay`. **Never
by Git note, and never by any other ref update.**

Finalize the report bytes **once**, then measure the bytes you actually finalized:

```bash
LC_ALL=C wc -c < report.txt      # byte_count
shasum -a 256 report.txt         # sha256
```

Send the bytes together with:

```text
byte_count: <the number above>
sha256: <the digest above>
encoding: utf-8
trailing_newline: present | absent
```

The primary writes those bytes without normalization and recomputes all four. If its numbers
disagree with yours, the transport lost or altered something, and the turn terminates as
`ABORTED: transport-lossy` with both manifests preserved. So measure what you send, and do not edit
the report after measuring it.

`trailing_newline` is part of the manifest because it is the byte-level fact that copying through an
editor silently changes. An empty report is `absent`.

VERIFIED means a command **plus its captured output**, run under the assignment's
`verification_profile_id`. Anything else is INFERRED — label it. Never report a job's "finished"
status as completion.

For a relay patch (invisible worktree, `writes-repo-only`), send
`git diff --binary --full-index` output with its own base SHA, byte count and SHA-256, measured the
same way.

### 2f. Record the attempt as handled, then go straight back to 2a

```bash
HANDLED="$HANDLED t<turn_id>-a<attempt_id>"
```

That one line is what stops the loop re-finding the intent you just finished. Then go back to 2a, in
the same turn, without producing a final message. One turn per dispatch, waiting in between.

**DO NOT END YOUR TURN WHILE PAIRED.** Your runtime returns control to the human the moment you
produce a final message, and a loop that has yielded is a loop that is gone — the primary then
dispatches into silence and has to fence the attempt. After reporting, go straight back to waiting:
do not summarize, do not ask the human anything, do not conclude. If the bounded wait expires, report
the zero-write expiry and stop; that is a real state, not a failure to persist.

## Never

**Never write the record** · update any ref, including Git notes · work outside the worktree · touch
anything outside your assignment's scope · switch, detach, reset, rebase · read records from the
working tree · start work before your ACK is captured · take a second turn on one dispatch ·
dispatch another agent · manufacture a `result_sha` · cite line numbers · paste secrets.

If you cannot complete a turn, say why and stop. Declining with a question costs nothing; guessing
costs a remediation turn.
