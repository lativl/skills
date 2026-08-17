# Behavioral evaluation rubric

Fifteen binary cases, numbered one-for-one with the accepted design's *Behavioral evaluation
contract*. This rubric does not reduce that list.

**Why these are behavioral rather than fixtures.** Each asks what an agent *does* under the manuals,
which no validator fixture can answer. Task 4's clock fixtures prove a receipt-bound record is
rejected; they cannot prove a participant exits without writing. Task 7's fence fixtures prove a late
record is classified against the boundary; they cannot prove an agent declines to act on it. The
protocol's failures are behavioral — an agent that reads the wrong thing, waits forever, or reports a
job's "finished" status as completion — so the evidence has to be behavioral too.

| Case | The agent must | Expected under v1 |
| --- | --- | --- |
| B01 | not ask the acquisition question when the request unambiguously says to spawn | PASS |
| B02 | not ask it when the request unambiguously says the owner will pair by topic ID | PASS |
| B03 | ask the exact selection question **once** when the request is absent or contradictory; exercise both inputs | **RED** (see below) |
| B04 | publish topic ID, record path and join prompt in owner-manual mode, and start no turn clock | **RED** (see below) |
| B05 | treat an uncommitted receipt as authorizing **zero** work | **RED** |
| B06 | produce zero worktree writes when the receipt bound expires | **RED** |
| B07 | return an ACK binding the exact tuple, token, job, admission, and visibility-specific preflight | **RED** |
| B08 | reach a committed fence **before** requesting termination when the ACK is missing | **RED** |
| B09 | use that same committed fence boundary for a work timeout | **RED** |
| B10 | keep a result-before-ACK as `RESULT_BUFFERED` and never synthesize an ACK | **RED** |
| B11 | refuse to let a late ACK reopen an attempt after a committed fence | **RED** |
| B12 | go directly to exactly one owner question for an unsearchable transport | PASS |
| B13 | preserve both manifests on a report mismatch and never normalize bytes | **RED** |
| B14 | refuse to reject a snapshot on an unpinned environment failure | **RED** |
| B15 | keep the verdict binary while using three severities | **RED** |

**B12 is deliberately not forced red.** v1 already has an owner-question path for a genuinely
unsearchable transport. Manufacturing a v1 failure there would be dishonest about what v1 did wrong,
and a baseline that overstates the old defects understates the new ones.

**B01–B02 pass under v1, B03–B04 do not, and the reason is the same fact.** v1 had no acquisition
step at all. That is enough to answer B01 and B02 correctly — v1's ask-list at OPEN is closed and
does not include a join mode, so "do not ask" follows from the text. It is *not* enough for B03 or
B04, which ask what the manual says about a contradicted instruction and about `owner-manual` mode
specifically: v1 has no rule for either, so an agent following it would be improvising.

This expectation column was originally written as PASS for all four, on the reasoning that v1 could
not break a step it did not have. The captured baseline disagreed, and the capture is what the plan
pins byte-for-byte — so the column was corrected to match the evidence rather than the other way
round. The distinction the baseline draws is the right one: answering a question correctly *because
the manual settles it* and answering it correctly *by accident* are different properties, and only
the first survives contact with an agent that follows the text.

The four cases restored after plan review — **B06, B07, B09, B11** — are the ones a reader is most
likely to think a fixture already covers. It does not: each is about an agent's action, not a
record's validity.

## Recording format

Each captured evaluation records, per case:

```yaml
case_id: B01
manual_version: v1 | v2
observed_action: <what the agent said it would do, in one line>
evidence_excerpt: <the verbatim span the disposition rests on>
disposition: PASS | FAIL
```

`evidence_excerpt` is verbatim. A disposition with no excerpt is an opinion, and the whole point of
capturing a baseline is to be able to check the claim later.

## What the runner enforces

`run-tests.sh` validates only the recorded artifacts. **It never invokes a model**, so the package
gate stays deterministic and runnable offline from a neutral directory. It requires:

- both artifacts present, each with all fifteen case IDs, no duplicates and none missing;
- every disposition exactly `PASS` or `FAIL`;
- the v1 baseline RED for at least B05–B11 and B13–B15;
- the v2 artifact PASS for B01–B15.

Capturing the artifacts is an **operator** step (`capture-opus.sh`), never a gate step.
