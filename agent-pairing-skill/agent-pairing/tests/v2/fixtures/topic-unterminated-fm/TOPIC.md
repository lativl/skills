---
protocol_version: 2
topic_id: unterminated-fm

# unterminated-fm

The front-matter block is never closed. Every key below the missing terminator is body text that a
scan-to-EOF parser would mine as control data.
