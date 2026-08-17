---
protocol_version: 2
record_seq: {{RECORD_SEQ}}
kind: result-capture
topic_id: {{TOPIC_ID}}
turn_id: {{TURN_ID}}
attempt_id: {{ATTEMPT_ID}}
turn_kind: {{TURN_KIND}}
assignment_ref: {{ASSIGNMENT_REF}}
dispatch_ref: {{DISPATCH_REF}}
ack_ref: {{ACK_REF}}
artifact_ref: {{ARTIFACT_REF}}
author_byte_count: {{AUTHOR_BYTE_COUNT}}
author_sha256: {{AUTHOR_SHA256}}
observed_byte_count: {{OBSERVED_BYTE_COUNT}}
observed_sha256: {{OBSERVED_SHA256}}
encoding: utf-8
trailing_newline: {{TRAILING_NEWLINE}}
report_channel: {{REPORT_CHANNEL}}
captured_epoch: {{CAPTURED_EPOCH}}
recorded_epoch: {{RECORDED_EPOCH}}
recorded_at: {{RECORDED_AT}}
---
A NONTERMINAL record: the participant's exact report bytes are now committed, and nothing has yet
been decided about them.

The motivating v1 failure was a stale capture — the captured report and the final report had
different byte counts and different SHA-256 values, and no rule in the protocol noticed. The fix is
two independent manifests over the same bytes:

- `author_*` is what the participant finalized and declared.
- `observed_*` is what the primary recomputed from the bytes it actually wrote.

They must agree. When they do not, **preserve both and never repair, normalize, truncate, or
reinterpret the bytes.** With a clean stationary worktree that is `ABORTED: transport-lossy`; with a
landed commit or residue it is `REJECTED` with the branch quarantined.

`artifact_ref` is always `artifacts/tTTTT-aAA/report.md` for THIS attempt. The separate artifact file
is an opaque byte boundary: report text can contain `---`, front matter, or record framing and none
of it is ever parsed as control data. `THREAD.md` renders it as quoted content only.

`report_channel` is the channel the bytes actually arrived through, and it must equal the admitted
one. Be honest about it: no Git record can physically prove which pipe carried a string, so this
field is the primary's own report. Recording it is what lets a mismatch be a visible defect rather
than an unbacked claim — and if you find yourself writing a value that is not the admitted one, the
answer is a new admission, not a different value here.

`trailing_newline` is `present` or `absent` and is part of the manifest because it is a byte-level
fact that line-oriented handling silently changes. An empty report is `absent`.

`ack_ref` is normally this attempt's ACK. It is `null` only for a result-before-ACK capture — the
`RESULT_BUFFERED` path — where the bytes arrived before any acknowledgement did. A null here never
implies an ACK and never becomes one.

For a relay patch, add alongside the report manifest:

```yaml
patch_ref: artifacts/tTTTT-aAA/patch.diff
patch_base_sha: <the base the patch was cut from>
patch_byte_count: <LC_ALL=C wc -c>
patch_sha256: <shasum -a 256>
```

A patch is admissible only under `capability: writes-repo-only`. `read-only` is report-only by
contract and `commits` lands its own commit instead. When the primary applies a verified relay patch,
the resulting `result_sha` names the primary's application commit and carries `On-behalf-of` and
`Applied-by: primary`.
