# bash 3.2 compatible. Sourced by scripts/validate.sh — never executed directly.
#
# Replay: what a VALID record set MEANS. This file runs only after every schema and linkage check has
# passed, so it never has to reason about malformed input — a record set with a violation has no
# trustworthy state to report and the run has already exited 2.
#
# The one rule that governs everything here: THE VALIDATOR HAS NO CLOCK. It reads stored epochs and
# prints them; it never converts elapsed wall time into a state. Only a committed `fence-initiated`
# record performs that transition. Without this rule the same records would classify differently on
# two machines, and a timeout would take effect with nothing in the history saying so.

# Count records of one kind belonging to one attempt.
v2_attempt_count() { # <turn_id> <attempt_id> <kind>
  v2_ac_t="$1" v2_ac_a="$2" v2_ac_k="$3" v2_ac_n=0
  while read -r v2_ac_seq v2_ac_kind v2_ac_name v2_ac_file; do
    [ -n "${v2_ac_seq:-}" ] || continue
    [ "$v2_ac_kind" = "$v2_ac_k" ] || continue
    [ "$(v2_fm_get "$v2_ac_file" turn_id)" = "$v2_ac_t" ] || continue
    [ "$(v2_fm_get "$v2_ac_file" attempt_id)" = "$v2_ac_a" ] || continue
    v2_ac_n=$((v2_ac_n + 1))
  done <"$V2_SORTED"
  printf '%s\n' "$v2_ac_n"
}

# The newest assignment with no terminal result for its attempt. One open attempt is the exclusive
# worktree lease, so there is at most one.
v2_open_attempt() { # -> "turn_id attempt_id" or empty
  v2_oa_out=""
  while read -r v2_oa_seq v2_oa_kind v2_oa_name v2_oa_file; do
    [ -n "${v2_oa_seq:-}" ] || continue
    [ "$v2_oa_kind" = assignment ] || continue
    v2_oa_t="$(v2_fm_get "$v2_oa_file" turn_id)"
    v2_oa_a="$(v2_fm_get "$v2_oa_file" attempt_id)"
    [ "$(v2_attempt_count "$v2_oa_t" "$v2_oa_a" result)" -eq 0 ] && v2_oa_out="$v2_oa_t $v2_oa_a"
  done <"$V2_SORTED"
  printf '%s\n' "$v2_oa_out"
}

v2_count_kind() { # <kind>
  awk -v k="$1" '$2 == k' "$V2_SORTED" | grep -c . || true
}

# The open attempt's state, in the design's precedence order.
#
# The ordering is the substance, not the syntax:
#   FENCING first — a committed fence is a durable boundary, and no later evidence reopens what it
#     closed. Checking ACK or capture first would let a late ACK arriving after the fence flip the
#     state back to WORKING, which is exactly the reopening the fence exists to forbid.
#   RESULT_BUFFERED next — a capture with no ACK. This is the ONLY capture-derived state.
#   AWAITING_ACK then WORKING — anchored on the ACK, because the ACK is what proves delivery.
#
# WORKING is ACK-anchored and CAPTURE-INSENSITIVE: a valid ACK with no terminal result is WORKING
# whether or not a capture exists. A capture changes the primary's next ACTION — re-run verification
# and materialize the result rather than observe progress — never the classification. Deriving a
# separate state from the capture would give one situation two names depending on arrival order.
v2_classify_open_attempt() { # <turn_id> <attempt_id>
  v2_co_t="$1" v2_co_a="$2"
  if [ "$(v2_attempt_count "$v2_co_t" "$v2_co_a" intent)" -eq 0 ]; then
    printf 'OPEN (never-dispatched)\n'; return
  fi
  if [ "$(v2_attempt_count "$v2_co_t" "$v2_co_a" dispatch)" -eq 0 ]; then
    printf 'DISPATCH_UNKNOWN\n'; return
  fi
  if [ "$(v2_attempt_count "$v2_co_t" "$v2_co_a" fence-initiated)" -ge 1 ]; then
    printf 'FENCING\n'; return
  fi
  v2_co_ack="$(v2_attempt_count "$v2_co_t" "$v2_co_a" ack)"
  v2_co_cap="$(v2_attempt_count "$v2_co_t" "$v2_co_a" result-capture)"
  if [ "$v2_co_ack" -eq 0 ] && [ "$v2_co_cap" -ge 1 ]; then
    printf 'RESULT_BUFFERED\n'; return
  fi
  if [ "$v2_co_ack" -eq 0 ]; then
    printf 'AWAITING_ACK\n'; return
  fi
  printf 'WORKING\n'
}
