# Opus review: Agent-pairing protocol v2

## Review boundary

The initial request to give Opus direct read access to the internal pairing record, scratchpad, installed manuals, and repository was denied by the execution policy. The completed review instead used a sanitized, tools-disabled brief containing anonymous timing measurements, current protocol properties, and the proposed state machine. No repository paths, source code, project identifiers, UUIDs, commit SHAs, or filesystem access were exposed.

Model: Opus, xhigh effort. Review verdict: `APPROVE_WITH_CHANGES`.

## Review findings

The following is a faithful structured summary of the returned review; the primary disposition preserves disagreements and architecture-specific corrections separately below.

### Verdict and framing

**VERDICT: APPROVE_WITH_CHANGES**

Approach A is correctly scoped. Taking the two latency lists as index-aligned and the expired deadline as belonging to the 32,736-second turn: that assignment's budget was intent plus 4,996 seconds, and the work itself took 957 seconds—roughly 19% of budget. The failure was delivery rather than execution. Relative, acknowledgement-anchored clocks target that; transport-only receipts and a dispatcher daemon do not.

### Blocking findings

#### B1 — Versioning: absent `protocol_version` is fail-open

A dropped or misspelled field silently degrades a v2 topic into weaker legacy mode. Opus proposed a cutover commit whose descendants must declare a version and cross-version field-mixing must be rejected.

#### B2 — Fencing: prefer a structural fencing token

Owner/manual termination is an assertion and can permit split-brain if wrong. Opus proposed attempt-scoped write targets so stale writers are structurally rejected, making termination confirmation a tidiness concern rather than the primary safety barrier.

#### B3 — Committed visibility/report capture: participant bytes must be opaque

Verbatim ACK and report bytes must not be allowed to inject control syntax or duplicate byte-span sentinels. Control fields must be primary-stamped, and opaque content must have an unambiguous encoding/length boundary.

#### B4 — ACK ordering: unordered channels can deliver result before ACK

Strictly rejecting any result observed before an ACK can discard good work. Opus recommends ordering durable records by primary capture, buffering an early result, and requiring an explicit owner disposition when the acknowledgement never arrives. It explicitly rejects fabricating an “implied-at-result” acknowledgement.

#### B5 — Committed receipt wait must be bounded

The wake prompt must carry the expected dispatch reference and a bound. The participant polls committed record HEAD only until that bound, then exits with zero writes if no committed receipt appears.

#### B6 — Both timeout paths need a durable fence boundary

Work-timeout expiry needs the same fence ladder as ACK timeout. The primary must commit a `fence-initiated` record before requesting termination so a racing ACK/result is classified against a replay-visible boundary. A primary crash during the foreground wait must not turn lack of ACK into automatic proof that the participant died.

#### B7 — Report hash must be author-side and finalize-anchored

The reporting side computes byte count and SHA-256 when it finalizes immutable bytes. The primary compares the captured bytes with that supplied manifest. A primary-generated hash of its own stale copy would detect nothing.

### Should-fix findings

- Make epoch seconds normative and ISO timestamps display-only; validator arithmetic uses only epochs.
- Allow equal timestamps and record ordering through durable sequence, because multiple events legitimately occur within one second.
- All budget timestamps are primary-stamped; participant times remain untrusted claims.
- Size acknowledgement budgets per transport profile rather than one global default.
- Trim machine admission to the fields that affect behavior; ACK echoes the exact admission reference.
- Bind ACK to the durable job/session identifier and validate its observed worktree HEAD.
- Make report byte spans nonce/attempt-bound, reject nested/repeated sentinels, and specify encoding and trailing-newline rules.
- Keep owner questions and answers durable and render an explicitly untimed owner-blocked state.

### Direct answer on manual relay

Under manual relay, ACK does not cryptographically prove delivery to a particular agent. It is a liveness observation that bounds the unobserved-delivery window. Opus recommends `ack_evidence_class: transport-attested | human-relayed` so the record does not overstate the source of the observation.

### Validated decisions

- Relative acknowledgement/work budgets fix the pre-expired absolute-deadline defect.
- Work clock starts at ACK, not receipt.
- Validator emits due epochs but never reads wall clock; the primary performs operational comparisons.
- Commit receipt before separate wake notification; participants consume committed Git objects only.
- Missing ACK starts fencing but proves neither termination nor permission to retry.
- Preserve the no-daemon design.
- Report hashes make no authentication claim.
- Defer the durable findings ledger and avoid a hand-edited root ledger.

### Opus's proposed minimum v2.0

ACK with evidence class, job binding, and validated observed HEAD; two relative epoch clocks; committed receipt visibility with bounded polling; durable fencing boundary; finalize-anchored author report manifest; trimmed admission; fail-closed version cutover; durable owner disposition; and coherent updates to both primary and participant manuals, templates, validator, tests, and examples.

Opus recommended deferring the findings taxonomy with the ledger, keeping environment parity as review policy plus an opaque profile id, cutting git-note reporting entirely, and generating participant instructions from admission rather than maintaining contradictory prose.

## Primary disposition

| Finding | Disposition | Rationale |
| --- | --- | --- |
| B1 | Accept principle; revise mechanism | Separate topic repos do not share an ancestry chain with a package cutover commit. Default v2 validation will reject an absent version; legacy topics use an explicitly invoked frozen v1 validator. |
| B2 | Defer structural alternative | Attempt-scoped worktrees/refs replace the one-shared-worktree baton and accepted-branch handoff. v2 retains termination/owner fencing and never retries uncertainty; attempt-scoped isolation is a possible v3 redesign. |
| B3 | Accept narrowly | Front matter already isolates body bytes from state fields, but report-span parsing still needs opaque encoding or strict non-nestable framing. |
| B4 | Accept | Buffer out-of-order result transport data; never materialize a v2 terminal result before ACK without an owner disposition. Never synthesize ACK from result existence. |
| B5 | Accept | Add `receipt_commit_by_epoch` to the dispatch payload and committed-only bounded polling to participant instructions. |
| B6 | Accept | Add `fence-initiated`, cover both ACK and work expiry, and define crash/resume races. |
| B7 | Accept with correction | Author-side finalize manifest is required. A read-only relay cannot provide a committed source object without violating its capability; primary capture plus author hash is the enforceable boundary. |
| S1–S4 | Accept | Epoch arithmetic, non-decreasing timestamps, primary clock authority, and per-transport defaults fit Bash 3.2 and deterministic replay. |
| S5 | Accept partially | Trim admission, but retain capability because it governs commit permission and report-channel compatibility. |
| S6 | Accept job binding; reject proposed ancestry check | Worktree HEAD and pairing-record receipt live in different Git repositories. The enforceable check is `observed_head == assignment.base_sha` at preflight, plus exact job/admission binding. |
| S7 | Accept | Hash contract needs exact bytes, encoding, trailing newline, unique framing, and a pre-result retry rule. |
| S8 | Already present / preserve | Owner questions and answers already exist as durable record kinds and `AWAITING_OWNER`; v2 extends rather than reinvents them. The live-package update prohibition remains until the current topic closes. |
| Taxonomy deferral | Reject full deferral; narrow scope | Define BLOCKING/GATE/NONBLOCKING as review policy in v2.0, but do not claim validator enforcement until the v2.1 ledger. Every GATE must name and materialize a project-tracker owner. |

## Resulting recommendation

Proceed with Approach A as a versioned, acknowledgement-based delivery handshake. Add committed-only receipt consumption, two primary-stamped epoch clocks, explicit evidence class, a replay-visible fence boundary, author-finalized report manifests, a small transport admission record, and a frozen explicit legacy validator. Preserve the existing shared-worktree safety model in v2.0 and treat attempt-scoped isolation as a separate architecture proposal.
