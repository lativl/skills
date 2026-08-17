# RUNBOOK — environment notes

> **Edit per setup.** Everything in this file is environment-specific: transports, CLI flags,
> timeouts, job-id formats, poll cadence and paths all change without warning, and none of it is
> part of the protocol. The protocol lives in `SKILL.md`; if the two ever disagree about *what*
> must happen, `SKILL.md` wins — this file only says *how*, here, today.
>
> When you find something in here that is no longer true, fix it in place. A stale runbook is worse
> than an empty one, because it gets believed.

## Paths on this machine

| What | Default | Notes |
|---|---|---|
| Record repos (`<record-root>`) | `~/.claude/agent-pairing/<topic-slug>/` | One git repo per topic, no remote. Shared by every runtime working that topic |
| Session worktrees (`<worktree-root>`) | `~/.claude/agent-pairing-worktrees/<topic-slug>/` | One per topic; branch `pair/<topic-slug>`. Also shared |
| This package | `<skills-root>/agent-pairing/` | `SKILL.md`, `RUNBOOK.md`, `templates/`, `scripts/validate.sh` |
| — `<skills-root>` for Claude | `~/.claude/skills` | so the package is at `~/.claude/skills/agent-pairing/` |
| — `<skills-root>` for Codex | `~/.codex/skills` | so the package is at `~/.codex/skills/agent-pairing/`. Codex's own skills live under `~/.codex/skills/.system/`; user skills sit alongside it |

The record and worktree roots are overridable per topic; whatever you choose is recorded as an
absolute path in the topic's `TOPIC.md` and is authoritative from then on. They are **per topic, not
per runtime** — a Codex agent and a Claude agent on the same topic use the *same* record repo and
the *same* worktree. The `~/.claude/agent-pairing/` default above is a directory that happened to
exist on this machine; nothing in the protocol requires it, and it does not mean "Claude's records".

The package itself is the one thing that is installed **per runtime**, because each runtime only
loads skills from its own `<skills-root>` — hence the two rows above and the two-root install in
*Installing and updating this package*.

The validator refuses a topic path containing whitespace (it exits 3). Keep slugs to
`[a-z0-9-]`.

**Keep record roots out of `/tmp`.** Measured by experiment on this machine (2026-08-12, see
*What `workspace-write` does and does not enforce* under Transports): a codex agent dispatched
`workspace-write` can write into any path under `/tmp`, not just its own worktree — a write to
`/tmp/pairtest/topic/turns/AGENT_WROTE.md` succeeded, while the same write aimed at
`$HOME/.claude/agent-pairing/...` was blocked (`operation not permitted`). So a record root chosen
under `/tmp` is writable by any `workspace-write` participant, and the protocol's "record written by
the primary only" rule loses its sandbox backing there — it falls back to instruction alone, same as
a runtime with no sandbox at all. Use the documented default
(`~/.claude/agent-pairing/<topic-slug>/`) or any other path outside `/tmp`; do not park a topic's
record repo in `/tmp` for convenience.

---

## Transport admission

Under protocol v2 the transport contract is a **committed record**, not a registry note. Before any
assignment exists, commit `templates/admission.md` describing the transport you actually used. Every
assignment then binds one exact `admission_ref`, and the validator re-checks the capability and
visibility rules at assignment binding and again at ACK — so an illegal transition fails closed
instead of surfacing three turns later as unexplained drift.

The `TOPIC.md` Registry section stays as human-readable context, but it is no longer the authority:
if the registry and the admission disagree, the admission is what the protocol enforces.

Fill each admission field from the table below. Every one of them is validated:

| Field | What it must say |
| --- | --- |
| `join_mode` | `primary-spawn` or `owner-manual` — and it must match `TOPIC.md`'s `participant_start_mode` |
| `capability` | `commits`, `writes-repo-only`, or `read-only` |
| `worktree_visible` | `true` or `false`; `commits` requires `true` |
| `durable_address_kind` | `session-id`, `job-id`, or `human-relay` — never a monitor or waiter handle |
| `durable_address` | the address itself, never a credential |
| `searchability` | `searchable` (with a recipe below) or `unsearchable` (with `token_search_recipe_ref: null`) |
| `report_channel` | `transport-output` or `human-relay` |
| `ack_evidence_class` | `transport-attested` or `human-relayed` |
| `receipt_commit_timeout_seconds` | positive integer — how long the participant waits for the committed receipt |
| `default_ack_timeout_seconds` | positive integer — the default each assignment materializes explicitly |

**A monitor ID is inadmissible.** A watcher handle, a foreground poll loop, a wrapper PID: none of
these is a durable address. They name the thing observing the job, so they stop resolving at exactly
the moment the address is needed — after a crash, when replay has to find the job again.

**Capability is a permission rule, not a physical claim.** `read-only` forbids a landed commit,
worktree modifications, and a relay `patch.diff` by contract; it is not an assertion that emitting
patch bytes requires filesystem writes. `writes-repo-only` admits visible uncommitted changes or an
invisible relay patch, but never a participant-authored `result_sha` — when the primary applies a
verified relay patch, the resulting `result_sha` names the primary's own application commit and
keeps the existing `On-behalf-of` / `Applied-by: primary` provenance.

Get the capability class right at open — an agent that cannot see the worktree needs the relay path
from the first turn, and one participant crossing classes mid-session has already happened. Crossing
classes now requires a new admission record with a new `admission_id`.

### Per-transport admission values

| Transport | address kind | searchability | report channel | evidence class | visibility | capability |
| --- | --- | --- | --- | --- | --- | --- |
| In-runtime subagent | `session-id` | `unsearchable` | `transport-output` | `transport-attested` | `true` | `commits` |
| codex CLI | `job-id` | `searchable` (see below) | `transport-output` | `transport-attested` | `true` | `commits` |
| Owner-relayed agent | `human-relay` | `unsearchable` | `human-relay` | `human-relayed` | `false` | `writes-repo-only` or `read-only` |

`searchable` for the codex CLI means the recipe in *Finding a lost job* below is real and runnable.
If it is not runnable in your environment, declare `unsearchable` with `token_search_recipe_ref:
null` — an honest `unsearchable` sends replay to one owner question, while a `searchable` claim with
no recipe records a search that never happened.

### In-runtime subagents (same machine, same filesystem)

An agent dispatched by the runtime you are already in, on this filesystem. Claude Code calls this
the Task tool; other runtimes name it differently or do not offer it at all. **Edit per setup:**
write down the dispatch call your runtime actually uses, and if it has none, delete this section for
that runtime and use the codex CLI or relay paths below.

- **Visibility:** the worktree path is visible; capability class is normally `commits`.
- **Job id:** subagents dispatched this way do not always surface a durable external id. Record the
  most specific handle the runtime gives you (agent name plus dispatch timestamp at minimum) as
  `job_id` — a receipt with a weak `job_id` still proves *dispatched*, which is the property the
  resume path depends on.
- **Dispatch payload:** paste the onboarding text, the digest and the assignment verbatim into the
  prompt, including the idempotency token. Do not summarize; do not "improve" the DON'T list.
- **Liveness:** the runtime reports whether an agent is still running. That is process liveness,
  never completion — check progress in the worktree (new commits, advancing output) before
  concluding anything.
- **Caveat:** a subagent that finishes without reporting a SHA has not delivered a result. Do not
  read the tip yourself and call it the result; that is the substitution the protocol forbids.

### codex CLI

- **Visibility:** runs on the same machine, so the worktree is usually visible; capability class
  depends on how the job is invoked.
- **A pairing turn needs `--write`.** The companion's default dispatch (no `--write`) maps to
  `sandbox: "read-only"`. Read-only is correct for review jobs, but it cannot run a turn: there is
  no commit, and `mktemp` itself is blocked, so neither the validator nor the suite can run inside
  the job either — an observed read-only dispatch failed at `mktemp ... failed / Operation not
  permitted` before it could do anything. For a turn, dispatch with `--write` and `--cwd` set to the
  session worktree:
  `node <companion> task --cwd <worktree> --write --prompt-file <file>`.
  `--write` maps to `sandbox: "workspace-write"`, not unrestricted filesystem access — see *What the
  sandbox does and does not enforce* below for exactly what that buys and does not buy.
- **Wrapper timeout is not job completion.** The wrapper around the CLI times out on its own
  schedule — a ten-minute wrapper timeout on a thirty-five-minute job is a normal, observed event.
  When the wrapper returns "timed out", the job is very often **still running**. Treat this as *no
  information about completion* and go to the fence ladder: check progress in the worktree, then
  confirm termination by `job_id`.
- **Zombies are real.** A codex job can outlive the agent that dispatched it — this happened twice
  while this package was being built, and one job sat "running" for one hour forty-seven minutes
  having produced nothing. A job that is "running" with no output and no commits is dead in every
  sense the protocol cares about, but it is **not** confirmed terminated. Confirm, or ask the owner.
  Never re-dispatch into that uncertainty.
- **Polling:** drive the companion/poll loop yourself rather than waiting on a nested job to poll on
  its own behalf; a nested poller cannot observe the job it is part of. Match completion on the
  result/duration line the CLI prints at the end, not on the "running" row, which is also printed
  while nothing is happening.
- **Never let it dispatch anything.** One primary, one open turn.

### What `workspace-write` does and does not enforce

Measured by dispatching a real `--write` codex CLI job against a scratch session worktree (2026-08-12):

- **Writes inside the dispatched worktree:** allowed — the job made a real commit with all three
  `Agent-Pairing-*` trailers parsing correctly (`git commit -F -` heredoc form), and only the
  in-scope file changed.
- **Writes into a temp path under `/tmp`, even outside the worktree:** allowed —
  `echo probe > /tmp/pairtest/topic/turns/AGENT_WROTE.md` succeeded and the file was verified
  present afterward.
- **Writes into a non-`/tmp` path outside the worktree** (the documented default record root,
  `$HOME/.claude/agent-pairing/<topic>/...`): **blocked** — `zsh:1: operation not permitted`, and
  the file was verified absent afterward.
- **Reads outside the worktree:** allowed in both locations (temp and non-temp).
- **Scope (which files an agent may touch) is NOT sandbox-enforced at all.** `workspace-write` says
  nothing about *which* file inside the worktree gets written — it only gates *where* on the
  filesystem a write can land. An out-of-scope edit inside the declared worktree succeeds at write
  time exactly like an in-scope one; it is caught **after the fact**, at verification, by CYCLE
  check 7 (the `--name-status -M -C -z` scope parse). That is exactly why an out-of-scope change is
  a **REJECTED** result with a **quarantined branch**, not a failed write — nothing in the sandbox
  stopped the write from happening.
- **Consequence for the sole-scribe rule:** the protocol's "the record is written by the primary
  only" rule gets sandbox backing *only* when the record root is outside `/tmp`. Put a topic's
  record root under `/tmp` and a `workspace-write` participant can write into it too — the rule then
  rests on instruction alone, with no sandbox backstop. See *Keep record roots out of `/tmp`* below.

### Any transport that cannot see the filesystem

Use the relay path (`SKILL.md`, CYCLE): a fenced `RELAY-THIS` report, and for code a fenced
`git diff --binary --full-index` plus its base SHA, byte count and SHA-256. Verify all three, apply
with `git apply --3way`, commit with the attempt trailers plus `On-behalf-of` and
`Applied-by: primary`. Never repair a patch that fails to apply.

---

## Report channels and relay

Participant reporting **never updates a Git ref and never uses Git notes.** v1's participant manual
required a Git note while simultaneously forbidding ref updates; the admitted `report_channel` is now
the only authority.

| `report_channel` | The participant returns bytes by | The primary captures them from |
| --- | --- | --- |
| `transport-output` | its transport's own output stream | that stream, verbatim |
| `human-relay` | a fenced `RELAY-THIS` block the owner passes along | the fenced block, verbatim |

Either way the participant finalizes the bytes **once** and declares a manifest with them:

```yaml
byte_count: <LC_ALL=C wc -c>
sha256: <shasum -a 256>
encoding: utf-8
trailing_newline: present | absent
```

The primary writes those bytes to `artifacts/tTTTT-aAA/report.md` without normalization, recomputes
the same four facts, and commits the artifact together with the `result-capture` record before
interpreting anything. Both manifests are stored. A disagreement is `ABORTED: transport-lossy` under
a clean stationary worktree, or `REJECTED` with a quarantined branch if something landed — never a
repair.

Getting the byte count right is a real trap on a relayed report: `wc -c` under a UTF-8 locale still
counts bytes, but a report copied through an editor that strips or adds a final newline changes both
the count and the digest. That is the failure the manifest exists to catch, so do not "fix" a
mismatch by recounting — record it.

For a relay patch, store it as `artifacts/tTTTT-aAA/patch.diff` with its own `patch_base_sha`,
`patch_byte_count` and `patch_sha256`. A patch is admissible only under
`capability: writes-repo-only`; `read-only` is report-only by contract and `commits` lands its own
commit instead.

---

## Finding a lost job (the `DISPATCH_UNKNOWN` path)

When replay finds an intent with no dispatch receipt, the *first* move is a token search, because a
found job produces a receipt mechanically and needs no human. Every dispatch payload carries the
attempt's `idempotency_token`, which is what makes this search possible at all.

Recipes, per transport — **fill these in for your setup**:

| Transport | Search | Notes |
|---|---|---|
| codex CLI | Search the CLI's session/log directory for the token: `grep -rl '<token>' <codex-log-dir>` | Then read the job id out of the matching session's metadata |
| In-runtime subagents | Search the runtime's transcript/session store for the token | **Edit per setup** — the store's location differs per runtime, and some keep no searchable store at all; then this path is unavailable |
| Anything else | — | Write it down here the first time you work it out |

If the transport genuinely cannot be searched, say so and write the owner question. That is a
supported outcome, not a failure: some transports simply cannot be interrogated, and the protocol
records the uncertainty rather than guessing past it. A `dispatch-unresolved` answer keeps the topic
waiting for new evidence; if evidence later arrives, the token search can still produce a receipt.

---

## Poll cadence and clocks

There are no daemons, timers or watchers. Bounds are checked when you look, so "how often you look"
is an operator setting, not a protocol rule.

- **Current default: poll every 3 minutes** for a long-running dispatched job. (An older note in
  this environment says 4; the owner's stated preference is 3. Confirm before relying on either.)
- v2 has **three** bounds, not one deadline. Size each to the job and write it into the record:

  | Bound | Starts at | Stored on | Sized for |
  | --- | --- | --- | --- |
  | `receipt_commit_by_epoch` | the committed **intent** | intent | how long the participant should wait for a receipt to appear — seconds to a few minutes |
  | `ack_due_epoch` | the committed **receipt** | receipt | delivery latency: submit-to-first-response, not the work |
  | `work_due_epoch` | the captured **ACK** | ack | the task itself |

  The admission's `default_ack_timeout_seconds` and `receipt_commit_timeout_seconds` are defaults;
  the assignment and intent materialize their own copies, and the validator checks the arithmetic
  against those copies. Never leave a bound to be inferred from configuration.
- Poll in the **foreground**. Background waiters get killed, and their notifications can be routed
  to a session that no longer exists; a poll whose result nobody reads is not a poll.
- A poll that shows no new commits and no advancing output is evidence for the fence ladder, not a
  reason to re-dispatch.
- **A bound that has passed is an observation, not a state change.** `validate.sh` prints the stored
  due epochs and never compares them with the clock. Nothing changes until you commit a
  `fence-initiated` record — see *FENCE — durable timeout boundary* in `SKILL.md`.

### Fencing an expired bound

```text
1. Read the stored bound from the record (ack_due_epoch on the receipt, work_due_epoch on the ACK).
2. Compare it with your own clock. If it has not passed, stop — there is nothing to do.
3. Commit fence-initiated, copying that exact due_epoch and stamping observed_epoch = now.
4. ONLY NOW ask the transport to terminate the job.
5. Confirm termination by job_id (per-transport commands above).
6. Record any late arrival as a `late` record. It cancels nothing.
```

Step 3 before step 4 is not a style preference. Terminating first and recording afterwards means a
crash in between leaves a killed job and a history that never mentions it — and the next primary,
seeing an open attempt with no fence, has no way to distinguish that from a job still running.

The `late` record is where a post-fence ACK, report, or landed commit goes. It is preserved as
evidence and never promoted: a late ACK is not an ACK for a fenced attempt, and a late landed commit
is `REJECTED: result-before-ack` with the branch quarantined.

**Retry remains forbidden** after a fence until termination is directly confirmed or the owner
materializes a resolution. This is the rule the whole fence exists to protect: a missing ACK is
missing evidence, not evidence of death.

### Recovering an uncommitted receipt

Found a `dispatch` record in the record working tree that was never committed? Validate its exact
tuple and required fields, then **re-stamp** it: fresh `dispatched_epoch` (now), `ack_due_epoch`
recomputed from that, and the epoch from the original bytes preserved as
`pre_crash_dispatched_epoch` with `receipt_source: validated-uncommitted`. That field is evidence
only; the validator rejects a receipt whose `ack_due_epoch` was computed from it. Restoring the
pre-crash epoch would hand the participant a budget that had already expired before it could see the
receipt. If the bytes do not validate, hash them into one owner question before removing them.

---

## Commit hooks in the work repo

Check at open, and record what you find in the topic's Preconditions. Hooks fight two things the
verification depends on:

- **Trailers.** A `commit-msg` or `prepare-commit-msg` hook that rewrites, reorders or strips
  message content can drop or mangle the three attempt trailers, which breaks attribution for every
  commit in the range.
- **Cleanliness.** A `pre-commit` hook that reformats files, regenerates artifacts, or writes into
  the tree can leave the worktree dirty after the agent's final commit, failing the cleanliness
  check through no fault of the agent.

Practical options, in preference order: fix the hook; or record the interference in the topic's
Preconditions and in the assignment so the agent knows to re-check its tree after committing. Do
**not** disable hooks silently, and do not accept an unclean tree "because the hook did it" —
capture what happened as evidence and route it like any other observation.

Also worth checking at open: a `gc`/`prune` running from another checkout can invalidate the
worktree admin entry. Resume re-confirms it with `git worktree list`, which is why that check exists.

---

## Installing and updating this package

Install is a copy. There is nothing to build and no state outside the package.

**There are TWO installation roots on this machine**, because two runtimes must be able to load the
skill and each reads its own directory:

| Runtime | `<skills-root>` | Package installed at |
|---|---|---|
| Claude | `$HOME/.claude/skills` | `$HOME/.claude/skills/agent-pairing` |
| Codex | `$HOME/.codex/skills` | `$HOME/.codex/skills/agent-pairing` |

**Any change to this package means re-running the block below for BOTH roots.** Updating one leaves
the other on the old version, and the two runtimes will then be following different manuals for the
same topic — the failure mode is silent, because each side's copy looks internally consistent.

**Update must be atomic**, because a half-copied package is a manual with missing steps that an
agent will still try to follow. Stage the new version beside the live one, verify it there, and swap
by rename — with the previous installation kept aside until the installed copy has proven itself:

```bash
set -eu
SRC=<absolute path to the new skills/agent-pairing>
# A cwd unrelated to the source repo, so a repo-relative assumption cannot pass unnoticed.
# It must NOT be a git repo (see the note below): a git-repo cwd is exactly what once hid a
# cwd-dependent bug in example/rehydrate.sh from this smoke. So: NEUTRAL="$(mktemp -d)" — no init.
NEUTRAL=<scratch non-repo dir>

require_root() { # <name> <value>   — `set -u` does NOT reject a set-but-EMPTY variable, and an
  case "${2:-}" in                  #   empty root would put the install at /skills/agent-pairing,
    "")  echo "$1 is empty — refusing to derive install paths" >&2; exit 3 ;;   # which this block
    /)   echo "$1 is / — refusing to install at the filesystem root" >&2; exit 3 ;; # then creates,
    /*)  ;;                                                                    #   swaps and later
    *)   echo "$1 is not absolute ($2) — refusing" >&2; exit 3 ;;              #   deletes -rf.
  esac; }

install_one() { # <root>   — run it twice: install_one "$HOME/.claude"; install_one "$HOME/.codex"
  require_root HOME "${HOME:-}"; require_root ROOTDIR "${1:-}"
  DEST="$1/skills/agent-pairing"; PARENT="$1/skills"
  mkdir -p "$PARENT"
  # Unchecked, STAGE="" makes NEW="/agent-pairing", BACKUP="/previous", and the success branch's
  # `rm -rf "$BACKUP" "$STAGE"` a delete at the filesystem root.
  STAGE="$(mktemp -d "$PARENT/.agent-pairing.install.XXXXXX")" || { echo "mktemp -d under $PARENT failed" >&2; exit 3; }
  [ -n "$STAGE" ] && [ -d "$STAGE" ] || { echo "mktemp produced no directory" >&2; exit 3; }
  case "$STAGE" in "$PARENT"/.agent-pairing.install.?*) ;; *) echo "refusing to stage in $STAGE" >&2; exit 3;; esac
  NEW="$STAGE/agent-pairing"; mkdir "$NEW"
  ( cd "$SRC" && tar --exclude='./pressure' -cf - . ) | ( cd "$NEW" && tar -xf - )
  [ ! -d "$NEW/pressure" ] || { echo "pressure tree leaked into install" >&2; exit 1; }
  ( cd "$NEUTRAL" && /bin/bash "$NEW/tests/run-tests.sh" ) || { echo "staged suite failed; nothing swapped" >&2; exit 1; }

  BACKUP="$STAGE/previous"
  [ ! -e "$DEST" ] || mv "$DEST" "$BACKUP"
  if mv "$NEW" "$DEST" && ( cd "$NEUTRAL" && /bin/bash "$DEST/tests/run-tests.sh" ) && [ ! -d "$DEST/pressure" ]; then
    rm -rf "$BACKUP" "$STAGE"
  else
    [ ! -e "$DEST" ] || mv "$DEST" "$STAGE/failed"
    [ ! -e "$BACKUP" ] || mv "$BACKUP" "$DEST"
    echo "install smoke failed; previous installation restored" >&2
    exit 1
  fi; }
```

Notes:

- **Do the roots one at a time and verify each before starting the next.** They are independent: if
  the second fails, say "the first is installed and the second is not" rather than unwinding a good
  installation. The rollback inside the block is per-root and only ever restores *that* root.
- **On a first install there is nothing to roll back.** With no previous installation, `BACKUP` is
  never created and the restore branch never runs. Do not report that as "rollback verified".
- The stage and the destination must be on the **same filesystem**, or the final `mv` is a copy and
  stops being atomic. `mktemp -d` under `$PARENT` guarantees this.
- The tests **do** ship, because the second smoke runs them from the installed path — that is what
  catches a path assumption that only holds inside the source repo. `pressure/` does not ship (and
  is not present in the built package at all); the assertions stay as a guard.
- **`$NEUTRAL` must NOT be a git repo, and the suite must be green from it.** The suite is
  cwd-independent: `example/rehydrate.sh` gives `git bundle verify` an explicit repository context
  (`git -C <staging repo>`) instead of relying on the caller's cwd. Measured on this host after that
  fix: **360 passed, 0 failed** from the source tree, from an installed `<skills-root>/agent-pairing`
  and from `/` alike. Running the smoke from inside a git repo is what let the earlier cwd-dependent
  version pass here while failing for a reader who did the obvious thing — `cd` into the installed
  skill and run its tests — and got **355 passed, 5 failed** with the misleading message
  `work-repo.bundle is corrupt` about a byte-identical bundle. Use a plain `mktemp -d`, and if the
  count is not 360/0, stop: something is cwd-dependent again.
- After installing, verify per root: `head -5 <root>/skills/agent-pairing/SKILL.md` (front matter),
  the suite count from the installed path, `find . -type f | sort` matching the source, and
  `example/rehydrate.sh --print-topic` → `scripts/validate.sh --check <topic>` classifying `CLOSED`
  → `--clean`. The example pins **absolute** `/tmp` paths, which both roots share, so run that last
  check sequentially with `--clean` in between.
- Whether the runtime actually *lists* the skill can only be confirmed on the **next** session start
  of that runtime — a live listing cannot be checked from inside the session that installed it.
- Never edit the live package in place while a topic is open.
- Updating this package never touches an open topic: record repos and worktrees live outside it, and
  their absolute paths are pinned in each `TOPIC.md`.
- If you want a rollback copy that outlives a successful install, take one yourself before running
  the block (`cp -R "$DEST" "$DEST.old.$$"`); the block deletes its own backup once the installed
  copy passes its smoke.

### Who can load this skill, and who still needs the onboarding text

`SKILL.md` says the onboarding text is "the **only** carrier of this protocol for agents that never
read this package". With the package installed under both `<skills-root>`s that is **partly**
superseded, and the precise version matters:

- A **Codex** agent can now load this skill directly from `~/.codex/skills/agent-pairing/`, the same
  way a Claude agent loads it from `~/.claude/skills/agent-pairing/`.
- **Every other agent** — any other runtime, any relay transport, anything that cannot see this
  filesystem — still has the onboarding text as its **only** carrier of the protocol.
- So does a **Codex agent dispatched without the skill loaded**. Having the files on disk is not the
  same as having read them: unless the skill is actually loaded into that session, the dispatched
  agent knows nothing about turn discipline, trailers or receipts, and the onboarding text is what
  it will be working from.

Do not shorten the onboarding text on the strength of "Codex has the skill now". Paste it in full,
verbatim, on every dispatch, exactly as before — the rationale in `SKILL.md`'s *The onboarding text
and the digest* is unchanged for the majority of dispatch paths.

**Confirmed by experiment (2026-08-12), the first cross-runtime evidence for this:** a codex CLI
agent dispatched `--write` against a scratch session worktree, with the package installed at
`~/.codex/skills/agent-pairing/` and nothing pasted into the prompt, loaded `SKILL.md` on its own
and visibly followed it — used `git -C`, exported `GIT_NO_REPLACE_OBJECTS=1`, ran a preflight before
writing, and committed with the `git commit -F -` heredoc form so all three trailers parsed. That is
one data point for one job, not a guarantee for every dispatch shape; the onboarding text stays
mandatory, verbatim, for every agent that cannot or does not load the package (see the three bullets
above).

---

## Preflight checklist for a new environment

1. `bash --version` — the validator and these snippets are written for bash 3.2; do not assume
   newer builtins.
2. `git --version`, and confirm `git worktree` behaves (add, list, remove).
3. Confirm the record root and the worktree root are writable and on a **local** shared
   filesystem — one machine is a stated precondition, and a network mount that drops a lock will
   corrupt evidence rather than fail loudly.
4. `/bin/bash scripts/validate.sh` with no arguments — expect the usage message and exit 3.
5. Confirm a **writable temp directory** and a working `mktemp`: `validate.sh` uses one for its
   read-only checkouts, `tests/run-tests.sh` builds every fixture under one, and the example's
   rehydration additionally needs a working `git`. See *Sandboxed agents* below.
6. Work out the token-search recipe for each transport you intend to use, and write it into the
   table above **before** you need it. The moment you need it is the moment you cannot afford to
   experiment.

### Sandboxed agents: read the manual, don't run the validator

An agent whose sandbox has **no writable `/tmp` and no `mktemp`** cannot run this package's tooling.
Observed on a real Codex run: `tests/run-tests.sh` aborted with exit 3 at its very first line — it
builds every fixture under `mktemp -d /tmp/agent-pairing-tests.XXXXXX` — and `--check` over the
worked example reported `UNRECORDED_DRIFT (unverified: work-repo)`, because the example's work repo
is rehydrated into `/tmp` and, with no writable `/tmp`, it was simply not there. That is a
**constraint of that sandbox**, not a defect in the package, and no amount of retrying inside it
will change the result. The example's rehydration additionally needs a working `git`.

What still works, and what to do:

- A sandboxed agent can read `SKILL.md`, `RUNBOOK.md` and the templates, and can follow the protocol
  as a **participant**: take an assignment, work in the worktree if it can see it, commit with the
  trailers, report the SHA. None of that needs a temp directory.
- The **primary runs `--check`**, as it always does. The validator is the primary's instrument;
  a sandboxed agent's `UNRECORDED_DRIFT (unverified: …)` is evidence about its sandbox and must
  never be recorded as evidence about the topic.
- If the *primary itself* is sandboxed this way, it cannot gate turns. Say so to the owner and stop:
  a classification you could not run is not a classification.
