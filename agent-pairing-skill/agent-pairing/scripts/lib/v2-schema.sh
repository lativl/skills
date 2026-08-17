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

# --- topic-level participant selection -----------------------------------------------------------------
# Resolved at OPEN, before any admission exists. The pair is not constrained: an owner may answer the
# selection question with either mode, and either mode may be unambiguous in the opening request.
# What IS constrained is that both values exist and are drawn from their enumerations, so replay can
# tell an inferred choice from an answered one instead of guessing which happened.
V2_START_MODES="primary-spawn owner-manual"
V2_SELECTION_SOURCES="initial-prompt owner-answer"

v2_require_participant_selection() { # <staged TOPIC.md> <subject>
  v2_ps_f="$1" v2_ps_n="$2"
  v2_ps_mode="$(v2_fm_get "$v2_ps_f" participant_start_mode)"
  v2_ps_src="$(v2_fm_get "$v2_ps_f" participant_selection_source)"
  if [ -z "$v2_ps_mode" ]; then
    v2_fail PARTICIPANT_START_MODE "$v2_ps_n" "TOPIC.md declares no participant_start_mode"
  elif ! v2_in_list "$v2_ps_mode" "$V2_START_MODES"; then
    v2_fail PARTICIPANT_START_MODE "$v2_ps_n" "participant_start_mode=$v2_ps_mode is not one of: $V2_START_MODES"
  fi
  if [ -z "$v2_ps_src" ]; then
    v2_fail PARTICIPANT_SELECTION "$v2_ps_n" "TOPIC.md declares no participant_selection_source"
  elif ! v2_in_list "$v2_ps_src" "$V2_SELECTION_SOURCES"; then
    v2_fail PARTICIPANT_SELECTION "$v2_ps_n" "participant_selection_source=$v2_ps_src is not one of: $V2_SELECTION_SOURCES"
  fi
  V2_START_MODE="$v2_ps_mode"
}

# --- admission ---------------------------------------------------------------------------------------------
V2_CAPABILITIES="commits writes-repo-only read-only"
V2_ADDRESS_KINDS="session-id job-id human-relay"
V2_SEARCHABILITIES="searchable unsearchable"
V2_REPORT_CHANNELS="transport-output human-relay"
V2_ACK_EVIDENCE_CLASSES="transport-attested human-relayed"
V2_ADMISSION_KEYS="admission_id agent_id join_mode transport capability worktree_visible \
durable_address_kind durable_address searchability token_search_recipe_ref report_channel \
ack_evidence_class receipt_commit_timeout_seconds default_ack_timeout_seconds"
# The fields that make up the transport CONTRACT. Any change to one of these is a different contract
# and requires a new admission_id — an assignment binds one exact admission_ref, so silently editing
# the contract under a stable id would retroactively change what past assignments agreed to.
V2_ADMISSION_CONTRACT_KEYS="transport capability worktree_visible durable_address_kind \
durable_address searchability token_search_recipe_ref report_channel ack_evidence_class"

v2_schema_admission() { # <staged-file> <display-name>
  v2_ad_f="$1" v2_ad_n="$2"
  for v2_ad_k in $V2_ADMISSION_KEYS; do
    v2_fm_has "$v2_ad_f" "$v2_ad_k" || { v2_fail MISSING_KEY "$v2_ad_n" "missing $v2_ad_k"; return 1; }
  done

  v2_ad_join="$(v2_fm_get "$v2_ad_f" join_mode)"
  if ! v2_in_list "$v2_ad_join" "$V2_START_MODES"; then
    v2_fail JOIN_MODE "$v2_ad_n" "join_mode=$v2_ad_join is not one of: $V2_START_MODES"
  elif [ -n "${V2_START_MODE:-}" ] && [ "$v2_ad_join" != "$V2_START_MODE" ]; then
    # How the participant ARRIVED must match how the topic said it would. A mismatch means either the
    # record or the topic is describing a different pairing than the one that happened.
    v2_fail JOIN_MODE "$v2_ad_n" "join_mode=$v2_ad_join contradicts the topic's participant_start_mode=$V2_START_MODE"
  fi

  v2_ad_cap="$(v2_fm_get "$v2_ad_f" capability)"
  v2_in_list "$v2_ad_cap" "$V2_CAPABILITIES" \
    || v2_fail CAPABILITY "$v2_ad_n" "capability=$v2_ad_cap is not one of: $V2_CAPABILITIES"

  v2_ad_vis="$(v2_fm_get "$v2_ad_f" worktree_visible)"
  case "$v2_ad_vis" in
    true|false) ;;
    *) v2_fail WORKTREE_VISIBLE "$v2_ad_n" "worktree_visible=$v2_ad_vis is not true or false" ;;
  esac

  # `commits` is the ONLY capability that admits a participant-authored landed commit, and a
  # participant that cannot see the worktree cannot have authored one in it. This is checked at
  # admission, again at assignment binding, and again at ACK, so an illegal capability cannot arrive
  # later disguised as unexplained drift.
  if [ "$v2_ad_cap" = commits ] && [ "$v2_ad_vis" = false ]; then
    v2_fail CAPABILITY_VISIBILITY "$v2_ad_n" "capability: commits requires worktree_visible: true"
  fi

  v2_ad_akind="$(v2_fm_get "$v2_ad_f" durable_address_kind)"
  # A monitor, waiter, or foreground polling handle names a WATCHER, not the job. After a crash the
  # watcher is gone and the handle finds nothing, which is precisely when a durable address is needed.
  v2_in_list "$v2_ad_akind" "$V2_ADDRESS_KINDS" \
    || v2_fail DURABLE_ADDRESS_KIND "$v2_ad_n" "durable_address_kind=$v2_ad_akind is not one of: $V2_ADDRESS_KINDS (a monitor or waiter handle is never durable)"
  [ -n "$(v2_fm_get "$v2_ad_f" durable_address)" ] \
    || v2_fail DURABLE_ADDRESS "$v2_ad_n" "durable_address is empty"

  v2_ad_search="$(v2_fm_get "$v2_ad_f" searchability)"
  v2_ad_recipe="$(v2_fm_get "$v2_ad_f" token_search_recipe_ref)"
  case "$v2_ad_search" in
    searchable)
      [ "$v2_ad_recipe" != null ] && [ -n "$v2_ad_recipe" ] \
        || v2_fail SEARCHABILITY "$v2_ad_n" "searchability: searchable requires a non-null token_search_recipe_ref" ;;
    unsearchable)
      # A null recipe is the honest encoding: replay SKIPS token search and goes to one owner
      # question, rather than recording that a search happened when none could.
      [ "$v2_ad_recipe" = null ] \
        || v2_fail SEARCHABILITY "$v2_ad_n" "searchability: unsearchable requires token_search_recipe_ref: null (got $v2_ad_recipe)" ;;
    *)
      v2_fail SEARCHABILITY "$v2_ad_n" "searchability=$v2_ad_search is not one of: $V2_SEARCHABILITIES" ;;
  esac

  v2_ad_chan="$(v2_fm_get "$v2_ad_f" report_channel)"
  v2_in_list "$v2_ad_chan" "$V2_REPORT_CHANNELS" \
    || v2_fail REPORT_CHANNEL "$v2_ad_n" "report_channel=$v2_ad_chan is not one of: $V2_REPORT_CHANNELS"

  v2_ad_cls="$(v2_fm_get "$v2_ad_f" ack_evidence_class)"
  v2_in_list "$v2_ad_cls" "$V2_ACK_EVIDENCE_CLASSES" \
    || v2_fail ACK_EVIDENCE_CLASS "$v2_ad_n" "ack_evidence_class=$v2_ad_cls is not one of: $V2_ACK_EVIDENCE_CLASSES"

  for v2_ad_k in receipt_commit_timeout_seconds default_ack_timeout_seconds; do
    v2_ad_v="$(v2_fm_get "$v2_ad_f" "$v2_ad_k")"
    if ! v2_is_uint "$v2_ad_v" || [ "$v2_ad_v" -eq 0 ]; then
      v2_fail ADMISSION_TIMEOUT "$v2_ad_n" "$v2_ad_k='$v2_ad_v' is not a positive decimal integer"
    fi
  done
}
# Cross-record admission rules. Run after every admission has passed its own schema, over the
# ordered record index.
#
# An `admission_id` names ONE transport contract. Two records may not share it:
#   - sharing it with DIFFERENT contract fields silently rewrites what past assignments agreed to,
#     because an assignment binds one exact admission_ref and the id is how it is named;
#   - sharing it with IDENTICAL fields is a redundant record whose only effect is to make the id
#     ambiguous as a reference.
# The two get different codes because they are different mistakes: the first is a contract change
# that skipped its new id, the second is a duplicate.
v2_check_admissions() { # <ordered record index>
  v2_ca_idx="$1"
  v2_ca_list="$V2_WORK/admissions"
  awk '$2 == "admission" { print $3 " " $4 }' "$v2_ca_idx" >"$v2_ca_list" || return 1
  while read -r v2_ca_name v2_ca_file; do
    [ -n "${v2_ca_name:-}" ] || continue
    v2_ca_id="$(v2_fm_get "$v2_ca_file" admission_id)"
    while read -r v2_ca_name2 v2_ca_file2; do
      [ -n "${v2_ca_name2:-}" ] || continue
      # Ordered index, so comparing only forward pairs reports each collision once.
      [ "$v2_ca_name2" \> "$v2_ca_name" ] || continue
      [ "$(v2_fm_get "$v2_ca_file2" admission_id)" = "$v2_ca_id" ] || continue
      v2_ca_changed=""
      for v2_ca_k in $V2_ADMISSION_CONTRACT_KEYS; do
        [ "$(v2_fm_get "$v2_ca_file" "$v2_ca_k")" = "$(v2_fm_get "$v2_ca_file2" "$v2_ca_k")" ] \
          || v2_ca_changed="$v2_ca_changed $v2_ca_k"
      done
      if [ -n "$v2_ca_changed" ]; then
        v2_fail ADMISSION_MUTATED "$v2_ca_name2" "changes${v2_ca_changed} but reuses admission_id $v2_ca_id from $v2_ca_name; a changed transport contract needs a new admission_id"
      else
        v2_fail ADMISSION_ID_DUP "$v2_ca_name2" "admission_id $v2_ca_id is already used by $v2_ca_name"
      fi
    done <"$v2_ca_list"
  done <"$v2_ca_list"
}

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
