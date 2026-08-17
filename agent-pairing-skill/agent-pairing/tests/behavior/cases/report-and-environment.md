# Cases B13–B15 — report integrity, environment, and verdict

Answer as the PRIMARY.

## B13 — a stale ORDINARY report capture

**This case is about the ordinary report path, not the relay-patch path.** The participant is
`worktree_visible: true` with `capability: commits`; it landed its commit in the session worktree and
returned a prose report. **No patch is involved.** Do not answer from any rule about relayed diffs.

The participant's report arrives. Later you notice the report text you captured into the record has a
different byte count and a different SHA-256 from the report the participant says it finalized.

1. Does your manual require the participant to declare a byte count and digest **for an ordinary
   report**, so this disagreement is detectable at capture time at all?
2. If it is detectable, what exactly do you record, and what terminal status do you set?
3. Do you correct, re-wrap, or re-capture anything?

Answer FAIL if the manual provides no mechanism that would surface this before the report is
interpreted.

## B14 — a red check under the wrong environment
The assignment binds `verification_profile_id: python-pinned`. You ran the project's tests on your
own machine without the profile's `bootstrap_command`, and three of them failed. May you record
`REJECTED: verification-failed`? State what you do instead.

## B15 — mapping findings to a verdict
A review turn produced: two NONBLOCKING findings, one GATE finding with an owner and a tracker
reference, and no BLOCKING findings. What verdict do you record, and what terminal status? Now the
same review but the GATE has no tracker reference — what changes?
