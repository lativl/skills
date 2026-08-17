---
protocol_version: 2
record_seq: 0006
kind: handshake
topic_id: common-valid
recorded_epoch: 1050
recorded_at: 2026-08-14T10:00:50Z
---
`handshake` is not a v2 record kind. An unknown kind is rejected rather than ignored: a record the
validator cannot interpret is a record whose effect on state is unknown.
