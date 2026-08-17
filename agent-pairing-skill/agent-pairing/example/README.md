# The shipped v2 example

Two Git bundles that rehydrate into a complete agent-pairing topic ending in exact `CLOSED`.

```bash
RT="$(/bin/bash example/rehydrate.sh --print-topic)"   # prints the restored topic dir
/bin/bash scripts/validate.sh --check "$RT"            # → classification: CLOSED
/bin/bash example/rehydrate.sh --clean                 # removes only its own marked directories
```

## What it contains, and why

It is deliberately not a happy path. A protocol is only legible once you can see what it does when
delivery fails, so the example carries the hard cases:

| Turn | Kind | What it shows |
| --- | --- | --- |
| 1 | `NORMAL` | dispatch → committed receipt → ACK → exact capture → `VERIFIED`; the accepted SHA advances |
| 2 | `REVIEW` | a stationary turn: it reviews turn 1's commit and may not move it |
| 3 | `NORMAL` | the ACK never arrives, the attempt is **fenced**, and a late ACK arrives after the boundary |
| — | close | every postcondition proved: THREAD.md says `CLOSED`, the worktree is gone, the branch stands at the final accepted SHA |

Turn 3 is the point of the example. Record `0017` is the `fence-initiated` boundary, committed
**before** the transport was asked to terminate the job. Record `0018` is the participant's
acknowledgement arriving *after* that boundary — correctly formed, binding the right attempt, and
changing nothing. It is preserved as a `late` observation because a late ACK does not mean the fence
was wrong; it means the acknowledgement arrived after the boundary. The attempt does not reopen.

The terminal result `0019` carries `ack_ref: null`, and that null is the evidence: no acknowledgement
was ever captured, which is the trigger rather than an omission.

## Regenerating

```bash
/bin/bash example/build.sh
```

The builder pins identity, timestamps and epochs, so two builds produce byte-identical commits and
`FINAL_SHA` is a stable artifact rather than a per-run accident. It validates the result and refuses
to bundle anything that is not `CLOSED`, then removes its live directories — the shipped artifacts
are the bundles.

`rehydrate.sh` never recreates the session worktree. The close postcondition requires that path to be
**absent and deregistered**, so restoring it would break the very state the example demonstrates.
