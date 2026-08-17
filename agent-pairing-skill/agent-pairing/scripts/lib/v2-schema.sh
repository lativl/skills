# bash 3.2 compatible. Sourced by scripts/validate.sh — never executed directly.
#
# Per-kind schemas, linkage, admission/capability constraints, and arithmetic checks.
#
# This file owns what a record must SAY. lib/v2-record.sh owns where the bytes come from and how a
# scalar is spelled; lib/v2-replay.sh owns what a valid record set MEANS. Keeping the three apart is
# what lets a schema defect report one code instead of surfacing later as an unexplained state.

# Require every common v2 field, with its exact shape. A record missing a common field is not
# partially valid: `record_seq` is the ordering authority and `recorded_epoch` is normative for
# arithmetic, so a record without them cannot be placed in the history at all.
v2_require_common() { # <staged-file> <display-name>
  v2_rc_f="$1" v2_rc_n="$2"
  v2_rc_ok=0

  # `protocol_version` owns ONE code for both of its failures. Routing an absent version through the
  # generic missing-key loop would report the compatibility boundary as an ordinary schema gap, and
  # the boundary is the whole point of this validator: absent and wrong must be the same answer.
  v2_rc_pv="$(v2_fm_get "$v2_rc_f" protocol_version)"
  case "$v2_rc_pv" in
    2) ;;
    '') v2_fail RECORD_PROTOCOL_VERSION "$v2_rc_n" "no protocol_version; every v2 record declares the exact scalar 2"; v2_rc_ok=1 ;;
    *)  v2_fail RECORD_PROTOCOL_VERSION "$v2_rc_n" "protocol_version '$v2_rc_pv' is not the exact scalar 2"; v2_rc_ok=1 ;;
  esac

  for v2_rc_k in record_seq kind topic_id recorded_epoch recorded_at; do
    v2_fm_has "$v2_rc_f" "$v2_rc_k" || { v2_fail MISSING_KEY "$v2_rc_n" "missing $v2_rc_k"; v2_rc_ok=1; }
  done
  [ "$v2_rc_ok" -eq 0 ] || return 1

  # `record_seq` is four decimal digits. The width is not decoration: it is what makes the filename
  # prefix, the LC_ALL=C sort order, and the durable cross-references agree with one another.
  v2_rc_seq="$(v2_fm_get "$v2_rc_f" record_seq)"
  case "$v2_rc_seq" in
    [0-9][0-9][0-9][0-9]) ;;
    *) v2_fail RECORD_SEQ "$v2_rc_n" "record_seq '$v2_rc_seq' is not exactly four decimal digits"; v2_rc_ok=1 ;;
  esac

  v2_rc_kind="$(v2_fm_get "$v2_rc_f" kind)"
  v2_in_list "$v2_rc_kind" "$V2_KINDS" \
    || { v2_fail UNKNOWN_KIND "$v2_rc_n" "kind=$v2_rc_kind is not a v2 record kind"; v2_rc_ok=1; }

  v2_rc_tid="$(v2_fm_get "$v2_rc_f" topic_id)"
  [ "$v2_rc_tid" = "$V2_TOPIC_ID" ] \
    || { v2_fail TOPIC_ID_MISMATCH "$v2_rc_n" "topic_id '$v2_rc_tid' is not the topic's validated identity '$V2_TOPIC_ID'"; v2_rc_ok=1; }

  # The epoch is a primary-stamped non-negative integer and is the ONLY value the validator does
  # arithmetic on. `recorded_at` beside it is display-only and is never consulted for ordering: two
  # records may carry the same epoch, and `record_seq` breaks the tie.
  v2_rc_ep="$(v2_fm_get "$v2_rc_f" recorded_epoch)"
  if ! v2_is_uint "$v2_rc_ep"; then
    v2_fail RECORDED_EPOCH "$v2_rc_n" "recorded_epoch '$v2_rc_ep' is not a non-negative decimal integer"
    v2_rc_ok=1
  elif ! v2_uint_value "$v2_rc_ep" >/dev/null; then
    v2_fail EPOCH_RANGE "$v2_rc_n" "recorded_epoch '$v2_rc_ep' exceeds the exact integer range ($V2_EPOCH_MAX)"
    v2_rc_ok=1
  fi

  v2_is_iso8601 "$(v2_fm_get "$v2_rc_f" recorded_at)" \
    || { v2_fail BAD_TIMESTAMP "$v2_rc_n" "recorded_at is not an ISO-8601 display value"; v2_rc_ok=1; }

  [ "$v2_rc_ok" -eq 0 ]
}

# Attempt-linked records additionally carry the turn tuple. This is checked before the filename
# agreement below, so a malformed width reports its own code once instead of twice.
v2_require_attempt_tuple() { # <staged-file> <display-name>
  v2_at_f="$1" v2_at_n="$2"
  v2_at_ok=0
  for v2_at_k in turn_id attempt_id turn_kind; do
    v2_fm_has "$v2_at_f" "$v2_at_k" || { v2_fail MISSING_KEY "$v2_at_n" "missing $v2_at_k"; v2_at_ok=1; }
  done
  [ "$v2_at_ok" -eq 0 ] || return 1
  case "$(v2_fm_get "$v2_at_f" turn_id)" in
    [0-9][0-9][0-9][0-9]) ;;
    *) v2_fail WIDTH "$v2_at_n" "turn_id is not exactly four decimal digits"; v2_at_ok=1 ;;
  esac
  case "$(v2_fm_get "$v2_at_f" attempt_id)" in
    [0-9][0-9]) ;;
    *) v2_fail WIDTH "$v2_at_n" "attempt_id is not exactly two decimal digits"; v2_at_ok=1 ;;
  esac
  v2_at_tk="$(v2_fm_get "$v2_at_f" turn_kind)"
  v2_in_list "$v2_at_tk" "NORMAL REVIEW REMEDIATION" \
    || { v2_fail BAD_TURN_KIND "$v2_at_n" "turn_kind=$v2_at_tk"; v2_at_ok=1; }
  [ "$v2_at_ok" -eq 0 ]
}

# The filename is a durable cross-reference — every `*_ref` in this protocol is one — so a name that
# disagrees with its own front matter is a record that lies about its own identity.
v2_require_filename() { # <staged-file> <display-name>
  v2_fn_f="$1" v2_fn_n="$2"
  v2_fn_kind="$(v2_fm_get "$v2_fn_f" kind)"
  v2_fn_pfx="$(v2_seq_of "$v2_fn_n")"
  v2_fn_seq="$(v2_fm_get "$v2_fn_f" record_seq)"

  # Owned by RECORD_SEQ above: a malformed width is not re-reported here as a name mismatch.
  case "$v2_fn_seq" in [0-9][0-9][0-9][0-9]) ;; *) return 0 ;; esac
  if [ "$v2_fn_pfx" != "$v2_fn_seq" ]; then
    v2_fail SEQ_FILENAME_MISMATCH "$v2_fn_n" "filename prefix $v2_fn_pfx != record_seq $v2_fn_seq"
    return 1
  fi

  if v2_in_list "$v2_fn_kind" "$V2_ATTEMPT_KINDS"; then
    v2_fn_t="$(v2_fm_get "$v2_fn_f" turn_id)"
    v2_fn_a="$(v2_fm_get "$v2_fn_f" attempt_id)"
    case "$v2_fn_t" in [0-9][0-9][0-9][0-9]) ;; *) return 0 ;; esac   # WIDTH owns this defect
    case "$v2_fn_a" in [0-9][0-9]) ;; *) return 0 ;; esac
    case "$v2_fn_kind" in
      late) v2_fn_want="${v2_fn_pfx}-t${v2_fn_t}-a${v2_fn_a}-late-[0-9][0-9].md"
            v2_fn_msg="${v2_fn_pfx}-t${v2_fn_t}-a${v2_fn_a}-late-KK.md" ;;
      *)    v2_fn_want="${v2_fn_pfx}-t${v2_fn_t}-a${v2_fn_a}-${v2_fn_kind}.md"
            v2_fn_msg="$v2_fn_want" ;;
    esac
    case "$v2_fn_n" in
      $v2_fn_want) ;;
      *) v2_fail FILENAME_SHAPE "$v2_fn_n" "basename does not match $v2_fn_msg"; return 1 ;;
    esac
  else
    v2_fn_want="${v2_fn_pfx}-${v2_fn_kind}.md"
    [ "$v2_fn_n" = "$v2_fn_want" ] \
      || { v2_fail FILENAME_SHAPE "$v2_fn_n" "basename does not match $v2_fn_want"; return 1; }
  fi
}

# Per-kind schema dispatch. Every kind lands in exactly one branch — there is no silent default,
# because a kind that validates by falling through is a kind nobody wrote a rule for.
#
# Tasks 3-7 fill these in: admission (Task 3), assignment/intent/dispatch clocks (Task 4), ack
# (Task 5), result-capture and result (Task 6), fence-initiated and late (Task 7).
v2_validate_kind() { # <staged-file> <display-name>
  case "$(v2_fm_get "$1" kind)" in
    admission)       v2_schema_admission "$1" "$2" ;;
    assignment)      v2_schema_assignment "$1" "$2" ;;
    intent)          v2_schema_intent "$1" "$2" ;;
    dispatch)        v2_schema_dispatch "$1" "$2" ;;
    ack)             v2_schema_ack "$1" "$2" ;;
    result-capture)  v2_schema_result_capture "$1" "$2" ;;
    fence-initiated) v2_schema_fence "$1" "$2" ;;
    result)          v2_schema_result "$1" "$2" ;;
    late)            v2_schema_late "$1" "$2" ;;
    owner-question)  v2_schema_owner_question "$1" "$2" ;;
    owner-answer)    v2_schema_owner_answer "$1" "$2" ;;
    close)           v2_schema_close "$1" "$2" ;;
    *) return 0 ;;   # UNKNOWN_KIND is v2_require_common's own code, already reported
  esac
}

v2_schema_admission()      { :; }   # Task 3
v2_schema_assignment()     { :; }   # Task 4
v2_schema_intent()         { :; }   # Task 4
v2_schema_dispatch()       { :; }   # Task 4
v2_schema_ack()            { :; }   # Task 5
v2_schema_result_capture() { :; }   # Task 6
v2_schema_result()         { :; }   # Task 6
v2_schema_fence()          { :; }   # Task 7
v2_schema_late()           { :; }   # Task 7
v2_schema_owner_question() { :; }   # Task 8
v2_schema_owner_answer()   { :; }   # Task 8
v2_schema_close()          { :; }   # Task 8
