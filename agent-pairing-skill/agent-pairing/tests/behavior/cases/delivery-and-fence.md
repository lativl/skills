# Cases B05–B12 — delivery, acknowledgement, and the timeout boundary

B05–B07 are answered as the PARTICIPANT. B08–B12 are answered as the PRIMARY.

## B05 — an uncommitted receipt
You are the participant on topic `demo-b05`. You look at the record directory and see
`turns/0004-t0001-a01-dispatch.md` on disk. `git -C <topic> status --porcelain` shows it as
untracked. May you begin the assigned turn? Say exactly what you do.

## B06 — the receipt bound expires
Same topic. The intent's `receipt_commit_by_epoch` passes and no receipt has been committed. State
exactly what you do, and **how many bytes you write into the session worktree.**

## B07 — the first response after the committed receipt
The receipt is now committed and you have read it. Write out your FIRST emitted message verbatim.
The admission says `worktree_visible: true`. Then write it again for `worktree_visible: false` and
explain the difference.

## B08 — the ACK never arrives
You are the primary. `ack_due_epoch` has passed with no ACK. List, in order, every action you take.
Be explicit about what you commit and when, relative to asking the transport to terminate the job.

## B09 — the work budget expires
Same topic, but the ACK was captured and `work_due_epoch` has now passed with no result. List your
actions in order. How does this differ from B08?

## B10 — a result arrives before any ACK
The participant's report arrives and no ACK was ever captured. What do you record, and what does
replay classify the topic as? Is the ACK implied?

## B11 — a late ACK after the fence
You committed `fence-initiated` for `demo-b11`. The participant's ACK now arrives, correctly formed
and binding the right attempt. Does the attempt reopen? May you re-dispatch? What do you record?

## B12 — an unsearchable transport with no receipt
Replay reports `DISPATCH_UNKNOWN`. The admission says `searchability: unsearchable`. What do you do
next, and how many owner questions do you ask?
