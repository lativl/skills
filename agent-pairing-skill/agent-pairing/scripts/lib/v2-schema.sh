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

  # The identity scalars must be non-empty, not merely present. `admission_id` is the cross-reference
  # every assignment binds; an empty one is not a name, and two empty ones collide as a duplicate of
  # the empty string rather than being reported as the missing identity they are.
  for v2_ad_k in admission_id agent_id transport; do
    [ -n "$(v2_fm_get "$v2_ad_f" "$v2_ad_k")" ] \
      || v2_fail ADMISSION_IDENTITY "$v2_ad_n" "$v2_ad_k is empty"
  done

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

  # Routed through v2_uint_value, not just v2_is_uint: a value like 10^26 is all decimal digits, so
  # `v2_is_uint` accepts it and the very next `[ "$v" -eq 0 ]` fails with `integer expression
  # expected` on stderr — a false test result, no violation, and exit 0. Every arithmetic input in
  # this protocol has to be inside the range the shell and awk agree on before it is compared.
  for v2_ad_k in receipt_commit_timeout_seconds default_ack_timeout_seconds; do
    v2_ad_v="$(v2_fm_get "$v2_ad_f" "$v2_ad_k")"
    if ! v2_uint_value "$v2_ad_v" >/dev/null 2>&1; then
      v2_fail ADMISSION_TIMEOUT "$v2_ad_n" "$v2_ad_k='$v2_ad_v' is not a decimal integer within the exact range (1..$V2_EPOCH_MAX)"
    elif [ "$v2_ad_v" -eq 0 ]; then
      v2_fail ADMISSION_TIMEOUT "$v2_ad_n" "$v2_ad_k='$v2_ad_v' is not a POSITIVE integer"
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

# --- clocks: two durations, a receipt bound, and recovery provenance -------------------------------------
#
# v1 put ONE absolute deadline on the assignment, before delivery latency was bounded at all — so a
# receipt committed hours late published a deadline that had already passed. v2 replaces it with two
# DURATIONS and materializes every addend into the record, so the validator can assert the arithmetic
# from the records alone without consulting a mutable admission default or a wall clock.
#
# The keys v1 used for absolute time are forbidden outright rather than ignored. A v2 record carrying
# `deadline` or `dispatched_at` is a record whose author was following the v1 manual, and silently
# accepting it would let a v1 turn run under v2 instructions.
V2_LEGACY_TIME_KEYS_assignment="deadline"
V2_LEGACY_TIME_KEYS_dispatch="dispatched_at"
V2_RECEIPT_SOURCES="direct token-search owner-answer validated-uncommitted"

# Resolve a `*_ref` to the staged file of a record of the expected kind. Empty when it does not
# resolve, which each caller reports with its own code.
v2_resolve_ref() { # <ref-basename> <expected-kind>
  [ -n "$1" ] || return 1
  awk -v n="$1" -v k="$2" '$3 == n && $2 == k { print $4; found = 1; exit } END { exit !found }' "$V2_SORTED"
}

# Is this basename a COMMITTED record at all, whatever the state of its front matter?
v2_ref_committed() { # <ref-basename>
  [ -n "$1" ] || return 1
  grep -Fxq "turns/$1" "$V2_WORK/records.sorted"
}

# Did it survive common validation? Empty when it was dropped for its own defect.
v2_ref_validated_kind() { # <ref-basename>
  [ -n "$1" ] || return 1
  awk -v n="$1" '$3 == n { print $2; exit }' "$V2_SORTED"
}

# Resolve a `*_ref` that must name a record of THIS attempt, and report one exact code when it does
# not. Prints the staged path on success; returns 1 having already reported on failure.
#
# Resolving by (basename, kind) alone is not enough. Those two facts are topic-wide, so a fence on
# attempt a02 could cite a01's receipt and then validate its own `due_epoch` against a01's stored
# bound — the arithmetic would pass while describing a different attempt's timeout. Every reference
# that carries attempt semantics goes through here so the tuple is checked with it.
# The resolved path is returned in V2_REF_PATH, NOT on stdout. A helper that prints its result must
# be called as `$(...)`, which runs it in a subshell — and every v2_fail it makes there increments a
# violation counter that dies with that subshell. The check would report on stderr and the run would
# still exit 0. State that crosses a subshell boundary has to be a file or a caller-side variable.
V2_REF_PATH=""
v2_resolve_attempt_ref() { # <ref> <kind> <referring-staged-file> <referring-name> <code>
  v2_ra_ref="$1" v2_ra_kind="$2" v2_ra_from="$3" v2_ra_name="$4" v2_ra_code="$5"
  V2_REF_PATH=""
  v2_ra_p="$(v2_resolve_ref "$v2_ra_ref" "$v2_ra_kind")" || v2_ra_p=""
  if [ -z "$v2_ra_p" ]; then
    # A target dropped for its OWN defect already fails the run; do not also blame the referrer.
    v2_ref_target_already_faulted "$v2_ra_ref" && return 1
    v2_fail "$v2_ra_code" "$v2_ra_name" "$v2_ra_kind reference '$v2_ra_ref' resolves to no $v2_ra_kind record of this topic"
    return 1
  fi
  for v2_ra_k in turn_id attempt_id; do
    if [ "$(v2_fm_get "$v2_ra_from" "$v2_ra_k")" != "$(v2_fm_get "$v2_ra_p" "$v2_ra_k")" ]; then
      v2_fail "$v2_ra_code" "$v2_ra_name" "cites '$v2_ra_ref', which belongs to attempt t$(v2_fm_get "$v2_ra_p" turn_id)-a$(v2_fm_get "$v2_ra_p" attempt_id), not this record's t$(v2_fm_get "$v2_ra_from" turn_id)-a$(v2_fm_get "$v2_ra_from" attempt_id)"
      return 1
    fi
  done
  V2_REF_PATH="$v2_ra_p"
}

# A reference whose TARGET was dropped for its own schema defect is not a dangling reference. The
# target's own violation already fails the run; blaming the referring record too would report one
# mutation as several codes and point at files that are not wrong. Returns 0 when the caller should
# stay silent.
v2_ref_target_already_faulted() { # <ref-basename>
  v2_rt_ref="$1"
  v2_ref_committed "$v2_rt_ref" || return 1
  [ -z "$(v2_ref_validated_kind "$v2_rt_ref")" ]
}

v2_schema_assignment() { # <staged-file> <display-name>
  v2_as_f="$1" v2_as_n="$2"
  for v2_as_k in base_sha session_branch session_worktree work_repo_common_dir scope agent_id \
                 admission_ref ack_timeout_seconds work_timeout_seconds verification_profile_id; do
    v2_fm_has "$v2_as_f" "$v2_as_k" || { v2_fail MISSING_KEY "$v2_as_n" "missing $v2_as_k"; return 1; }
  done
  for v2_as_k in $V2_LEGACY_TIME_KEYS_assignment; do
    ! v2_fm_has "$v2_as_f" "$v2_as_k" \
      || v2_fail LEGACY_DEADLINE "$v2_as_n" "carries the v1 absolute-time key '$v2_as_k'; v2 assignments carry ack_timeout_seconds and work_timeout_seconds instead"
  done
  v2_is_sha "$(v2_fm_get "$v2_as_f" base_sha)" || v2_fail BAD_SHA "$v2_as_n" "base_sha"

  # Materialized explicitly so replay never depends on mutable configuration. The ACK timeout
  # DEFAULTS from the admission but is written here; the work duration is task-specific.
  for v2_as_k in ack_timeout_seconds work_timeout_seconds; do
    v2_as_v="$(v2_fm_get "$v2_as_f" "$v2_as_k")"
    if ! v2_uint_value "$v2_as_v" >/dev/null 2>&1; then
      v2_fail ASSIGNMENT_TIMEOUT "$v2_as_n" "$v2_as_k='$v2_as_v' is not a decimal integer within the exact range (1..$V2_EPOCH_MAX)"
    elif [ "$v2_as_v" -eq 0 ]; then
      v2_fail ASSIGNMENT_TIMEOUT "$v2_as_n" "$v2_as_k='$v2_as_v' is not a POSITIVE integer"
    fi
  done
}

v2_schema_intent() { # <staged-file> <display-name>
  v2_in_f="$1" v2_in_n="$2"
  for v2_in_k in assignment_ref idempotency_token admission_ref expected_dispatch_ref \
                 receipt_commit_timeout_seconds receipt_commit_by_epoch; do
    v2_fm_has "$v2_in_f" "$v2_in_k" || { v2_fail MISSING_KEY "$v2_in_n" "missing $v2_in_k"; return 1; }
  done
  [ -n "$(v2_fm_get "$v2_in_f" idempotency_token)" ] \
    || v2_fail INTENT_TOKEN "$v2_in_n" "idempotency_token is empty"

  v2_in_to="$(v2_fm_get "$v2_in_f" receipt_commit_timeout_seconds)"
  if ! v2_uint_value "$v2_in_to" >/dev/null 2>&1 || [ "$v2_in_to" -eq 0 ]; then
    v2_fail RECEIPT_TIMEOUT "$v2_in_n" "receipt_commit_timeout_seconds='$v2_in_to' is not a positive integer within the exact range"
    return 1
  fi

  # `receipt_commit_by_epoch == recorded_epoch + receipt_commit_timeout_seconds`, asserted from THIS
  # record alone. That is why the intent materializes the timeout instead of inheriting it: a bound
  # checkable only against a mutable admission default is not checkable at replay time at all.
  v2_in_ep="$(v2_fm_get "$v2_in_f" recorded_epoch)"
  v2_in_by="$(v2_fm_get "$v2_in_f" receipt_commit_by_epoch)"
  if ! v2_uint_value "$v2_in_by" >/dev/null 2>&1; then
    v2_fail EPOCH_RANGE "$v2_in_n" "receipt_commit_by_epoch='$v2_in_by' is not a decimal integer within the exact range"
  elif ! v2_sum_eq "$v2_in_ep" "$v2_in_to" "$v2_in_by"; then
    v2_fail RECEIPT_COMMIT_DUE "$v2_in_n" "receipt_commit_by_epoch $v2_in_by != recorded_epoch $v2_in_ep + receipt_commit_timeout_seconds $v2_in_to"
  fi
}

v2_schema_dispatch() { # <staged-file> <display-name>
  v2_dp_f="$1" v2_dp_n="$2"
  for v2_dp_k in assignment_ref intent_ref admission_ref transport job_id dispatched_epoch \
                 ack_due_epoch receipt_source; do
    v2_fm_has "$v2_dp_f" "$v2_dp_k" || { v2_fail MISSING_KEY "$v2_dp_n" "missing $v2_dp_k"; return 1; }
  done
  for v2_dp_k in $V2_LEGACY_TIME_KEYS_dispatch; do
    ! v2_fm_has "$v2_dp_f" "$v2_dp_k" \
      || v2_fail LEGACY_DEADLINE "$v2_dp_n" "carries the v1 absolute-time key '$v2_dp_k'; v2 receipts carry dispatched_epoch and ack_due_epoch instead"
  done
  [ -n "$(v2_fm_get "$v2_dp_f" job_id)" ] || v2_fail DISPATCH_JOB "$v2_dp_n" "job_id is empty"

  v2_dp_src="$(v2_fm_get "$v2_dp_f" receipt_source)"
  v2_in_list "$v2_dp_src" "$V2_RECEIPT_SOURCES" \
    || v2_fail BAD_RECEIPT_SOURCE "$v2_dp_n" "receipt_source=$v2_dp_src is not one of: $V2_RECEIPT_SOURCES"

  v2_dp_de="$(v2_fm_get "$v2_dp_f" dispatched_epoch)"
  v2_uint_value "$v2_dp_de" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_dp_n" "dispatched_epoch='$v2_dp_de' is not a decimal integer within the exact range"; return 1; }
  v2_dp_ad="$(v2_fm_get "$v2_dp_f" ack_due_epoch)"
  v2_uint_value "$v2_dp_ad" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_dp_n" "ack_due_epoch='$v2_dp_ad' is not a decimal integer within the exact range"; return 1; }

  # A recovered uncommitted receipt is RE-STAMPED, never restored. `dispatched_epoch` is the epoch at
  # which the primary commits the recovered receipt; the pre-crash epoch found in the uncommitted
  # bytes is evidence ONLY and never enters arithmetic. Restoring it would let `ack_due_epoch` be
  # already past at the moment the receipt first becomes visible to the participant — recreating the
  # v1 pre-expired-deadline defect inside the recovery path. The ACK budget measures delivery latency,
  # and the participant cannot observe an uncommitted receipt, so the budget starts when visibility
  # starts.
  if [ "$v2_dp_src" = validated-uncommitted ]; then
    if ! v2_fm_has "$v2_dp_f" pre_crash_dispatched_epoch; then
      v2_fail RECOVERY_EPOCH "$v2_dp_n" "receipt_source: validated-uncommitted requires pre_crash_dispatched_epoch as evidence of the epoch it replaced"
      return 1
    fi
    v2_dp_pc="$(v2_fm_get "$v2_dp_f" pre_crash_dispatched_epoch)"
    if ! v2_uint_value "$v2_dp_pc" >/dev/null 2>&1; then
      v2_fail RECOVERY_EPOCH "$v2_dp_n" "pre_crash_dispatched_epoch='$v2_dp_pc' is not a decimal integer within the exact range"
      return 1
    fi
    if [ "$v2_dp_pc" -gt "$v2_dp_de" ]; then
      v2_fail RECOVERY_EPOCH "$v2_dp_n" "pre_crash_dispatched_epoch $v2_dp_pc postdates the re-stamped dispatched_epoch $v2_dp_de; the recovered receipt is committed after the crash, never before it"
      return 1
    fi
  elif v2_fm_has "$v2_dp_f" pre_crash_dispatched_epoch; then
    v2_fail RECOVERY_EPOCH "$v2_dp_n" "pre_crash_dispatched_epoch is only meaningful for receipt_source: validated-uncommitted (got $v2_dp_src)"
  fi
}
# --- cross-record linkage -------------------------------------------------------------------------------
# Every attempt-linked record names its assignment, and the receipt additionally names its intent.
# A reference that does not resolve, or resolves to a record describing a DIFFERENT attempt, is a
# record whose place in the history is unknown.
v2_check_attempt_links() {
  while read -r v2_cl_seq v2_cl_kind v2_cl_name v2_cl_file; do
    [ -n "${v2_cl_seq:-}" ] || continue
    v2_in_list "$v2_cl_kind" "$V2_ATTEMPT_KINDS" || continue

    v2_cl_aref="$(v2_fm_get "$v2_cl_file" assignment_ref)"
    if [ "$v2_cl_kind" = assignment ]; then
      v2_cl_ap="$v2_cl_file"
    else
      v2_cl_ap="$(v2_resolve_ref "$v2_cl_aref" assignment)" || v2_cl_ap=""
      if [ -z "$v2_cl_ap" ]; then
        v2_ref_target_already_faulted "$v2_cl_aref" && continue
        v2_fail LINK_DANGLING "$v2_cl_name" "assignment_ref '$v2_cl_aref' resolves to no assignment record"
        continue
      fi
      for v2_cl_k in topic_id turn_id attempt_id turn_kind; do
        [ "$(v2_fm_get "$v2_cl_file" "$v2_cl_k")" = "$(v2_fm_get "$v2_cl_ap" "$v2_cl_k")" ] \
          || v2_fail LINK_TUPLE_MISMATCH "$v2_cl_name" "$v2_cl_k differs from $v2_cl_aref"
      done
      [ "$v2_cl_seq" \> "$(v2_fm_get "$v2_cl_ap" record_seq)" ] \
        || v2_fail LINK_ORDER "$v2_cl_name" "record precedes its own assignment"
    fi

    if [ "$v2_cl_kind" = dispatch ]; then
      v2_cl_iref="$(v2_fm_get "$v2_cl_file" intent_ref)"
      v2_cl_ip="$(v2_resolve_ref "$v2_cl_iref" intent)" || v2_cl_ip=""
      if [ -z "$v2_cl_ip" ]; then
        v2_ref_target_already_faulted "$v2_cl_iref" \
          || v2_fail LINK_DANGLING "$v2_cl_name" "intent_ref '$v2_cl_iref' resolves to no intent record"
      else
        [ "$v2_cl_seq" \> "$(v2_fm_get "$v2_cl_ip" record_seq)" ] \
          || v2_fail LINK_ORDER "$v2_cl_name" "receipt precedes its own intent"
      fi
    fi
  done <"$V2_SORTED"
}

# --- cross-record clocks --------------------------------------------------------------------------------
v2_check_clocks() {
  while read -r v2_ck_seq v2_ck_kind v2_ck_name v2_ck_file; do
    [ -n "${v2_ck_seq:-}" ] || continue
    case "$v2_ck_kind" in assignment|intent|dispatch) ;; *) continue ;; esac

    # Every clock-bearing record binds one exact admission. The intent REPEATS its assignment's
    # admission_ref for the same reason it materializes the receipt timeout: replay must be able to
    # check the binding from the records alone.
    v2_ck_adref="$(v2_fm_get "$v2_ck_file" admission_ref)"
    v2_ck_adp="$(v2_resolve_ref "$v2_ck_adref" admission)" || v2_ck_adp=""
    if [ -z "$v2_ck_adp" ]; then
      v2_ref_target_already_faulted "$v2_ck_adref" && continue
      v2_fail ADMISSION_REF "$v2_ck_name" "admission_ref '$v2_ck_adref' resolves to no admission record"
      continue
    fi
    [ "$v2_ck_seq" \> "$(v2_fm_get "$v2_ck_adp" record_seq)" ] \
      || v2_fail ADMISSION_REF "$v2_ck_name" "binds admission '$v2_ck_adref', which does not precede it"

    [ "$v2_ck_kind" = assignment ] && continue

    v2_ck_ap="$(v2_resolve_ref "$(v2_fm_get "$v2_ck_file" assignment_ref)" assignment)" || continue
    v2_ck_asadref="$(v2_fm_get "$v2_ck_ap" admission_ref)"
    if [ "$v2_ck_adref" != "$v2_ck_asadref" ]; then
      v2_fail ADMISSION_REF "$v2_ck_name" "binds admission '$v2_ck_adref' while its assignment binds '$v2_ck_asadref'"
      continue
    fi

    if [ "$v2_ck_kind" = intent ]; then
      # The materialized value must equal the ADMITTED one. Materializing it is what makes the bound
      # checkable; materializing a DIFFERENT number would make it checkable and wrong.
      v2_ck_ito="$(v2_fm_get "$v2_ck_file" receipt_commit_timeout_seconds)"
      v2_ck_ato="$(v2_fm_get "$v2_ck_adp" receipt_commit_timeout_seconds)"
      [ "$v2_ck_ito" = "$v2_ck_ato" ] \
        || v2_fail RECEIPT_TIMEOUT "$v2_ck_name" "materializes receipt_commit_timeout_seconds $v2_ck_ito, but admission $v2_ck_adref granted $v2_ck_ato"
      continue
    fi

    # The receipt must be committed under the name the intent PREDICTED. The participant polls
    # committed HEAD for exactly `expected_dispatch_ref`; a receipt landing under any other name
    # means it polls until its bound expires and writes nothing, while replay would otherwise call
    # the topic healthy and wait for an ACK that cannot come.
    v2_ck_ip="$(v2_resolve_ref "$(v2_fm_get "$v2_ck_file" intent_ref)" intent)" || v2_ck_ip=""
    if [ -n "$v2_ck_ip" ]; then
      v2_ck_exp="$(v2_fm_get "$v2_ck_ip" expected_dispatch_ref)"
      [ "$v2_ck_name" = "$v2_ck_exp" ] \
        || v2_fail EXPECTED_DISPATCH_REF "$v2_ck_name" "the intent predicted the receipt would be '$v2_ck_exp'; the participant polls for that exact name"
    fi

    # dispatch: ack_due_epoch == dispatched_epoch + the assignment's ack_timeout_seconds.
    v2_ck_de="$(v2_fm_get "$v2_ck_file" dispatched_epoch)"
    v2_ck_ad="$(v2_fm_get "$v2_ck_file" ack_due_epoch)"
    v2_ck_at="$(v2_fm_get "$v2_ck_ap" ack_timeout_seconds)"
    if ! v2_sum_eq "$v2_ck_de" "$v2_ck_at" "$v2_ck_ad"; then
      # A recovered receipt whose budget was computed from the PRE-CRASH epoch is the specific,
      # informative version of this defect — and the one the design names by hand — so it reports as
      # RECOVERY_EPOCH rather than as a generic arithmetic mismatch.
      v2_ck_pc="$(v2_fm_get "$v2_ck_file" pre_crash_dispatched_epoch)"
      if [ "$(v2_fm_get "$v2_ck_file" receipt_source)" = validated-uncommitted ] \
         && [ -n "$v2_ck_pc" ] && v2_sum_eq "$v2_ck_pc" "$v2_ck_at" "$v2_ck_ad"; then
        v2_fail RECOVERY_EPOCH "$v2_ck_name" "ack_due_epoch $v2_ck_ad was computed from pre_crash_dispatched_epoch $v2_ck_pc; a recovered receipt is re-stamped, and its ACK budget starts at the re-stamped dispatched_epoch $v2_ck_de"
      else
        v2_fail ACK_DUE "$v2_ck_name" "ack_due_epoch $v2_ck_ad != dispatched_epoch $v2_ck_de + assignment ack_timeout_seconds $v2_ck_at"
      fi
    fi
  done <"$V2_SORTED"
}

# --- ack: the delivery evidence ---------------------------------------------------------------------------
#
# Everything cross-record about the ACK lives here rather than in v2_check_clocks, because an ACK is
# nothing BUT bindings: it carries no independent facts of its own, and each field is a claim about a
# record that already exists. Checking it in isolation would validate its shape while leaving every
# claim unverified.
v2_schema_ack() { # <staged-file> <display-name>
  v2_ak_f="$1" v2_ak_n="$2"
  for v2_ak_k in assignment_ref intent_ref dispatch_ref admission_ref job_id idempotency_token \
                 observed_head preflight_clean relayed_base_sha ack_evidence_class \
                 ack_captured_epoch work_due_epoch; do
    v2_fm_has "$v2_ak_f" "$v2_ak_k" || { v2_fail MISSING_KEY "$v2_ak_n" "missing $v2_ak_k"; return 1; }
  done

  v2_ak_ce="$(v2_fm_get "$v2_ak_f" ack_captured_epoch)"
  v2_uint_value "$v2_ak_ce" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_ak_n" "ack_captured_epoch='$v2_ak_ce' is not a decimal integer within the exact range"; return 1; }
  v2_ak_wd="$(v2_fm_get "$v2_ak_f" work_due_epoch)"
  v2_uint_value "$v2_ak_wd" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_ak_n" "work_due_epoch='$v2_ak_wd' is not a decimal integer within the exact range"; return 1; }
}

# The cross-record half: every reference resolved, every bound value compared, and the preflight shape
# selected by the ADMITTED visibility.
v2_check_acks() {
  while read -r v2_ka_seq v2_ka_kind v2_ka_name v2_ka_file; do
    [ -n "${v2_ka_seq:-}" ] || continue
    [ "$v2_ka_kind" = ack ] || continue

    v2_ka_aref="$(v2_fm_get "$v2_ka_file" assignment_ref)"
    v2_ka_ap="$(v2_resolve_ref "$v2_ka_aref" assignment)" || v2_ka_ap=""
    [ -n "$v2_ka_ap" ] || continue   # LINK_DANGLING is v2_check_attempt_links' own code

    # Every attempt-scoped reference goes through v2_resolve_attempt_ref, so "resolves to a record of
    # the right kind" and "describes THIS attempt" are checked together. Resolving by kind alone is
    # topic-wide, and an ACK citing another attempt's receipt is evidence of a delivery that is not
    # the one under way.
    v2_ka_iref="$(v2_fm_get "$v2_ka_file" intent_ref)"
    v2_resolve_attempt_ref "$v2_ka_iref" intent "$v2_ka_file" "$v2_ka_name" ACK_BINDING || continue
    v2_ka_ip="$V2_REF_PATH"
    v2_ka_dref="$(v2_fm_get "$v2_ka_file" dispatch_ref)"
    v2_resolve_attempt_ref "$v2_ka_dref" dispatch "$v2_ka_file" "$v2_ka_name" ACK_BINDING || continue
    v2_ka_dp="$V2_REF_PATH"

    # An ACK cannot precede the receipt it acknowledges: the participant learns of the work by
    # observing that committed receipt, so an earlier ACK acknowledges something it could not have
    # seen.
    [ "$v2_ka_seq" \> "$(v2_fm_get "$v2_ka_dp" record_seq)" ] \
      || v2_fail LINK_ORDER "$v2_ka_name" "acknowledges receipt '$v2_ka_dref', which does not precede it"

    v2_ka_adref="$(v2_fm_get "$v2_ka_file" admission_ref)"
    v2_ka_adp="$(v2_resolve_ref "$v2_ka_adref" admission)" || v2_ka_adp=""
    if [ -z "$v2_ka_adp" ]; then
      v2_ref_target_already_faulted "$v2_ka_adref" && continue
      v2_fail ACK_BINDING "$v2_ka_name" "admission_ref '$v2_ka_adref' is not an admission record of this topic"
      continue
    fi

    # The whole point: the ACK must answer THIS attempt. An ACK bound to another attempt's receipt or
    # another turn's intent is evidence of a delivery that is not the one under way.
    [ "$v2_ka_adref" = "$(v2_fm_get "$v2_ka_ap" admission_ref)" ] \
      || v2_fail ACK_BINDING "$v2_ka_name" "binds admission '$v2_ka_adref' while its assignment binds '$(v2_fm_get "$v2_ka_ap" admission_ref)'"
    [ "$v2_ka_dref" = "$(v2_fm_get "$v2_ka_ip" expected_dispatch_ref)" ] \
      || v2_fail ACK_BINDING "$v2_ka_name" "binds receipt '$v2_ka_dref' while its intent expected '$(v2_fm_get "$v2_ka_ip" expected_dispatch_ref)'"
    [ "$(v2_fm_get "$v2_ka_file" job_id)" = "$(v2_fm_get "$v2_ka_dp" job_id)" ] \
      || v2_fail ACK_BINDING "$v2_ka_name" "job_id differs from the receipt's job_id"
    [ "$(v2_fm_get "$v2_ka_file" idempotency_token)" = "$(v2_fm_get "$v2_ka_ip" idempotency_token)" ] \
      || v2_fail ACK_BINDING "$v2_ka_name" "idempotency_token differs from the intent's token"
    [ "$(v2_fm_get "$v2_ka_file" ack_evidence_class)" = "$(v2_fm_get "$v2_ka_adp" ack_evidence_class)" ] \
      || v2_fail ACK_BINDING "$v2_ka_name" "ack_evidence_class differs from the admitted class"

    # --- capability, re-checked at ACK ------------------------------------------------------------------
    # Already checked at admission. Checked AGAIN here because that is the point of checking it in
    # three places: an illegal capability must fail closed at the moment it would first matter, not
    # surface later as unexplained drift.
    v2_ka_cap="$(v2_fm_get "$v2_ka_adp" capability)"
    v2_ka_vis="$(v2_fm_get "$v2_ka_adp" worktree_visible)"
    if [ "$v2_ka_cap" = commits ] && [ "$v2_ka_vis" = false ]; then
      v2_fail CAPABILITY_VISIBILITY "$v2_ka_name" "capability: commits requires worktree_visible: true"
      continue
    fi

    # --- the visibility-specific preflight contract -----------------------------------------------------
    v2_ka_base="$(v2_fm_get "$v2_ka_ap" base_sha)"
    v2_ka_head="$(v2_fm_get "$v2_ka_file" observed_head)"
    v2_ka_clean="$(v2_fm_get "$v2_ka_file" preflight_clean)"
    v2_ka_relay="$(v2_fm_get "$v2_ka_file" relayed_base_sha)"
    case "$v2_ka_vis" in
      true)
        # The participant looked, so it says what it saw. `preflight_clean: false` is not a milder
        # ACK — it is the participant reporting that the lease it was handed was already dirty, which
        # cannot be acknowledged as a clean start.
        [ "$v2_ka_head" = "$v2_ka_base" ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "observed_head '$v2_ka_head' is not the assignment base_sha '$v2_ka_base' (a visible participant reports what it saw)"
        [ "$v2_ka_clean" = true ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "preflight_clean must be true for a visible admission (got '$v2_ka_clean')"
        [ "$v2_ka_relay" = null ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "relayed_base_sha must be null for a visible admission (got '$v2_ka_relay')"
        ;;
      false)
        # The participant did NOT look. Reporting an observation would be a claim it cannot have made,
        # so the nulls are the honest encoding — and the relay base binds the input it was given.
        [ "$v2_ka_head" = null ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "observed_head must be null for an invisible admission (got '$v2_ka_head'); an invisible participant cannot have observed the worktree"
        [ "$v2_ka_clean" = null ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "preflight_clean must be null for an invisible admission (got '$v2_ka_clean')"
        [ "$v2_ka_relay" = "$v2_ka_base" ] \
          || v2_fail ACK_PREFLIGHT "$v2_ka_name" "relayed_base_sha '$v2_ka_relay' is not the assignment base_sha '$v2_ka_base'"
        ;;
      *)
        # Unreachable while v2_schema_admission rejects a non-boolean worktree_visible and the run
        # exits 2 before classification. Stated anyway: without it, a visibility the admission gate
        # ever stopped rejecting would run NEITHER preflight arm, and the whole contract would be
        # skipped in silence rather than failing.
        v2_fail ACK_PREFLIGHT "$v2_ka_name" "the admission declares worktree_visible='$v2_ka_vis', which selects no preflight contract"
        ;;
    esac

    # --- the work budget --------------------------------------------------------------------------------
    v2_ka_ce="$(v2_fm_get "$v2_ka_file" ack_captured_epoch)"
    v2_ka_wd="$(v2_fm_get "$v2_ka_file" work_due_epoch)"
    v2_ka_wt="$(v2_fm_get "$v2_ka_ap" work_timeout_seconds)"
    v2_sum_eq "$v2_ka_ce" "$v2_ka_wt" "$v2_ka_wd" \
      || v2_fail WORK_DUE "$v2_ka_name" "work_due_epoch $v2_ka_wd != ack_captured_epoch $v2_ka_ce + assignment work_timeout_seconds $v2_ka_wt"
  done <"$V2_SORTED"
}
# --- result-capture: exact bytes, two manifests ------------------------------------------------------------
v2_schema_result_capture() { # <staged-file> <display-name>
  v2_rk_f="$1" v2_rk_n="$2"
  for v2_rk_k in assignment_ref dispatch_ref ack_ref artifact_ref author_byte_count author_sha256 \
                 observed_byte_count observed_sha256 encoding trailing_newline captured_epoch; do
    v2_fm_has "$v2_rk_f" "$v2_rk_k" || { v2_fail MISSING_KEY "$v2_rk_n" "missing $v2_rk_k"; return 1; }
  done
  [ "$(v2_fm_get "$v2_rk_f" encoding)" = utf-8 ] \
    || v2_fail CAPTURE_ENCODING "$v2_rk_n" "encoding must be utf-8"
  case "$(v2_fm_get "$v2_rk_f" trailing_newline)" in
    present|absent) ;;
    *) v2_fail CAPTURE_NEWLINE "$v2_rk_n" "trailing_newline must be present or absent" ;;
  esac
  for v2_rk_k in author_sha256 observed_sha256; do
    v2_is_sha256 "$(v2_fm_get "$v2_rk_f" "$v2_rk_k")" \
      || v2_fail CAPTURE_SHA256 "$v2_rk_n" "$v2_rk_k is not a lowercase 64-character hex digest"
  done
  for v2_rk_k in author_byte_count observed_byte_count; do
    v2_uint_value "$(v2_fm_get "$v2_rk_f" "$v2_rk_k")" >/dev/null 2>&1 \
      || v2_fail CAPTURE_BYTES "$v2_rk_n" "$v2_rk_k is not a non-negative decimal integer within the exact range"
  done
  v2_uint_value "$(v2_fm_get "$v2_rk_f" captured_epoch)" >/dev/null 2>&1 \
    || v2_fail EPOCH_RANGE "$v2_rk_n" "captured_epoch is not a decimal integer within the exact range"
}

# The cross-record half: the manifests are compared against the ACTUAL COMMITTED BYTES, which is the
# only comparison that catches a stale capture. Comparing author against observed alone would pass
# any capture whose two manifests were computed from the same wrong bytes.
v2_check_captures() { # <topic>
  v2_cp_topic="$1"
  while read -r v2_cp_seq v2_cp_kind v2_cp_name v2_cp_file; do
    [ -n "${v2_cp_seq:-}" ] || continue
    [ "$v2_cp_kind" = result-capture ] || continue

    v2_cp_t="$(v2_fm_get "$v2_cp_file" turn_id)"
    v2_cp_a="$(v2_fm_get "$v2_cp_file" attempt_id)"
    v2_cp_art="$(v2_fm_get "$v2_cp_file" artifact_ref)"

    # The artifact lives under THIS attempt's own directory. A capture pointing anywhere else could
    # name another attempt's report — or a path outside the artifact tree entirely — and inherit its
    # digests, so the manifest would verify against bytes that belong to a different turn.
    case "$v2_cp_art" in
      "artifacts/t$v2_cp_t-a$v2_cp_a/report.md") ;;
      *) v2_fail CAPTURE_PATH "$v2_cp_name" "artifact_ref '$v2_cp_art' is not artifacts/t$v2_cp_t-a$v2_cp_a/report.md"
         continue ;;
    esac

    v2_cp_blob="$(v2_stage_committed "$v2_cp_topic" "$v2_cp_art")" || v2_cp_blob=""
    if [ -z "$v2_cp_blob" ]; then
      v2_fail CAPTURE_PATH "$v2_cp_name" "artifact '$v2_cp_art' is not in the committed tree; the bytes must be committed with the capture record"
      continue
    fi

    # Recompute from the committed bytes and compare BOTH manifests against them.
    v2_cp_obc="$(v2_byte_count "$v2_cp_blob")"
    v2_cp_osh="$(v2_sha256 "$v2_cp_blob")"
    v2_cp_otn="$(v2_has_trailing_newline "$v2_cp_blob")"

    [ "$(v2_fm_get "$v2_cp_file" author_byte_count)" = "$v2_cp_obc" ] \
      || v2_fail CAPTURE_BYTES "$v2_cp_name" "author_byte_count $(v2_fm_get "$v2_cp_file" author_byte_count) != the committed artifact's $v2_cp_obc bytes"
    [ "$(v2_fm_get "$v2_cp_file" observed_byte_count)" = "$v2_cp_obc" ] \
      || v2_fail CAPTURE_BYTES "$v2_cp_name" "observed_byte_count $(v2_fm_get "$v2_cp_file" observed_byte_count) != the committed artifact's $v2_cp_obc bytes"
    [ "$(v2_fm_get "$v2_cp_file" author_sha256)" = "$v2_cp_osh" ] \
      || v2_fail CAPTURE_SHA256 "$v2_cp_name" "author_sha256 does not match the committed artifact's digest $v2_cp_osh"
    [ "$(v2_fm_get "$v2_cp_file" observed_sha256)" = "$v2_cp_osh" ] \
      || v2_fail CAPTURE_SHA256 "$v2_cp_name" "observed_sha256 does not match the committed artifact's digest $v2_cp_osh"
    [ "$(v2_fm_get "$v2_cp_file" trailing_newline)" = "$v2_cp_otn" ] \
      || v2_fail CAPTURE_NEWLINE "$v2_cp_name" "declares trailing_newline: $(v2_fm_get "$v2_cp_file" trailing_newline) but the committed artifact is $v2_cp_otn"

    # The capture's own attempt-scoped references. `ack_ref: null` is the result-before-ACK path and
    # is legal; a non-null one must name THIS attempt's ACK.
    v2_cp_dref="$(v2_fm_get "$v2_cp_file" dispatch_ref)"
    v2_resolve_attempt_ref "$v2_cp_dref" dispatch "$v2_cp_file" "$v2_cp_name" CAPTURE_REF || true
    v2_cp_aref2="$(v2_fm_get "$v2_cp_file" ack_ref)"
    if [ -n "$v2_cp_aref2" ] && [ "$v2_cp_aref2" != null ]; then
      v2_resolve_attempt_ref "$v2_cp_aref2" ack "$v2_cp_file" "$v2_cp_name" CAPTURE_REF || true
    fi

    # --- capability and the relay patch ------------------------------------------------------------------
    v2_cp_ap="$(v2_resolve_ref "$(v2_fm_get "$v2_cp_file" assignment_ref)" assignment)" || continue
    v2_cp_adp="$(v2_resolve_ref "$(v2_fm_get "$v2_cp_ap" admission_ref)" admission)" || continue
    v2_cp_cap="$(v2_fm_get "$v2_cp_adp" capability)"

    # `read-only` is report-only BY CONTRACT. This is a protocol permission rule, not a claim that
    # emitting patch bytes requires filesystem writes: a read-only participant is perfectly capable
    # of printing a diff, and the rule is that its output may not be admitted as one.
    v2_cp_patch="artifacts/t$v2_cp_t-a$v2_cp_a/patch.diff"
    if v2_git "$v2_cp_topic" rev-parse --verify --quiet "HEAD:$v2_cp_patch" >/dev/null 2>&1; then
      case "$v2_cp_cap" in
        writes-repo-only) ;;
        *) v2_fail CAPABILITY_PATCH "$v2_cp_name" "capability: $v2_cp_cap admits no relay patch, but $v2_cp_patch is committed" ;;
      esac
      # A committed patch REQUIRES its manifest. Verifying only `if patch_sha256 is present` meant a
      # capture could simply omit the four patch fields and the patch bytes — the ones about to be
      # applied to the work repo — were certified by nothing at all. That is the stale-capture hole
      # this task exists to close, reopened for the patch.
      v2_cp_pmiss=""
      for v2_cp_k in patch_ref patch_base_sha patch_byte_count patch_sha256; do
        v2_fm_has "$v2_cp_file" "$v2_cp_k" || v2_cp_pmiss="$v2_cp_pmiss $v2_cp_k"
      done
      if [ -n "$v2_cp_pmiss" ]; then
        v2_fail CAPTURE_PATCH_MANIFEST "$v2_cp_name" "$v2_cp_patch is committed but the capture declares no$v2_cp_pmiss; relayed patch bytes are never uncertified"
      else
        [ "$(v2_fm_get "$v2_cp_file" patch_ref)" = "$v2_cp_patch" ] \
          || v2_fail CAPTURE_PATH "$v2_cp_name" "patch_ref '$(v2_fm_get "$v2_cp_file" patch_ref)' is not $v2_cp_patch"
        v2_is_sha "$(v2_fm_get "$v2_cp_file" patch_base_sha)" \
          || v2_fail BAD_SHA "$v2_cp_name" "patch_base_sha is not a 40-character hex SHA"
        v2_cp_pblob="$(v2_stage_committed "$v2_cp_topic" "$v2_cp_patch")" || v2_cp_pblob=""
        if [ -z "$v2_cp_pblob" ]; then
          v2_fail CAPTURE_PATH "$v2_cp_name" "$v2_cp_patch cannot be read from the committed tree"
        else
          [ "$(v2_fm_get "$v2_cp_file" patch_byte_count)" = "$(v2_byte_count "$v2_cp_pblob")" ] \
            || v2_fail CAPTURE_BYTES "$v2_cp_name" "patch_byte_count $(v2_fm_get "$v2_cp_file" patch_byte_count) != the committed patch's $(v2_byte_count "$v2_cp_pblob") bytes"
          [ "$(v2_fm_get "$v2_cp_file" patch_sha256)" = "$(v2_sha256 "$v2_cp_pblob")" ] \
            || v2_fail CAPTURE_SHA256 "$v2_cp_name" "patch_sha256 does not match the committed patch's digest $(v2_sha256 "$v2_cp_pblob")"
        fi
      fi
    elif v2_fm_has "$v2_cp_file" patch_ref; then
      v2_fail CAPTURE_PATH "$v2_cp_name" "declares patch_ref but $v2_cp_patch is not in the committed tree"
    fi
  done <"$V2_SORTED"
}

# --- result: a terminal status accountable to evidence -------------------------------------------------------
# Task 6 owns the LINKAGE — which evidence a terminal status must cite. The status/reason matrix and
# the result_sha rules are Task 8's port of the preserved v1 checks.
V2_ACK_NULL_REASONS="ack-preflight-failed transport-lossy result-before-ack terminated-before-result dispatch-confirmed-absent never-dispatched"

v2_schema_result() { # <staged-file> <display-name>
  v2_rs_f="$1" v2_rs_n="$2"
  for v2_rs_k in assignment_ref dispatch_ref ack_ref result_capture_ref status result_sha observed_at; do
    v2_fm_has "$v2_rs_f" "$v2_rs_k" || { v2_fail MISSING_KEY "$v2_rs_n" "missing $v2_rs_k"; return 1; }
  done
}

v2_check_results() {
  while read -r v2_rr_seq v2_rr_kind v2_rr_name v2_rr_file; do
    [ -n "${v2_rr_seq:-}" ] || continue
    [ "$v2_rr_kind" = result ] || continue

    v2_rr_status="$(v2_fm_get "$v2_rr_file" status)"
    v2_rr_ackref="$(v2_fm_get "$v2_rr_file" ack_ref)"
    v2_rr_capref="$(v2_fm_get "$v2_rr_file" result_capture_ref)"
    v2_rr_reason="$(v2_fm_get "$v2_rr_file" reason)"

    # A VERIFIED result claims the work was delivered AND that its report is the one the participant
    # finalized. Both claims need a record behind them; neither may be asserted from memory.
    if [ "$v2_rr_status" = VERIFIED ]; then
      if [ "$v2_rr_ackref" = null ] || [ -z "$v2_rr_ackref" ]; then
        v2_fail RESULT_ACK_REF "$v2_rr_name" "VERIFIED requires a valid ACK; ack_ref is null"
      else
        v2_resolve_attempt_ref "$v2_rr_ackref" ack "$v2_rr_file" "$v2_rr_name" RESULT_ACK_REF || true
      fi
      if [ "$v2_rr_capref" = null ] || [ -z "$v2_rr_capref" ]; then
        v2_fail RESULT_CAPTURE_REF "$v2_rr_name" "VERIFIED requires a matching result-capture; result_capture_ref is null"
      else
        v2_resolve_attempt_ref "$v2_rr_capref" result-capture "$v2_rr_file" "$v2_rr_name" RESULT_CAPTURE_REF || true
      fi
    elif [ "$v2_rr_ackref" = null ]; then
      # A failure result may carry no ACK, but only where no acknowledgement COULD exist. Anywhere
      # else, a null here would quietly excuse the missing delivery evidence this protocol exists to
      # obtain.
      v2_in_list "$v2_rr_reason" "$V2_ACK_NULL_REASONS" \
        || v2_fail RESULT_ACK_REF "$v2_rr_name" "ack_ref: null is legal only for a preflight decline, transport loss, or a fenced result-before-ACK (got reason=$v2_rr_reason)"
    elif [ -n "$v2_rr_ackref" ]; then
      v2_resolve_attempt_ref "$v2_rr_ackref" ack "$v2_rr_file" "$v2_rr_name" RESULT_ACK_REF || true
    fi

    if [ "$v2_rr_status" != VERIFIED ] && [ -n "$v2_rr_capref" ] && [ "$v2_rr_capref" != null ]; then
      v2_resolve_attempt_ref "$v2_rr_capref" result-capture "$v2_rr_file" "$v2_rr_name" RESULT_CAPTURE_REF || true
    fi
  done <"$V2_SORTED"
}
# --- fence-initiated: the durable timeout boundary ------------------------------------------------------
V2_FENCE_TRIGGERS="ack-timeout work-timeout"

v2_schema_fence() { # <staged-file> <display-name>
  v2_fc_f="$1" v2_fc_n="$2"
  # `trigger` is the design's key. `reason` is NOT an alias — accepting both spellings is how one of
  # them quietly stops being checked — so a record carrying `reason` reports a MISSING trigger.
  for v2_fc_k in trigger assignment_ref dispatch_ref ack_ref job_id due_epoch observed_epoch; do
    v2_fm_has "$v2_fc_f" "$v2_fc_k" || { v2_fail MISSING_KEY "$v2_fc_n" "missing $v2_fc_k"; return 1; }
  done
  v2_fc_tr="$(v2_fm_get "$v2_fc_f" trigger)"
  v2_in_list "$v2_fc_tr" "$V2_FENCE_TRIGGERS" \
    || { v2_fail FENCE_TRIGGER "$v2_fc_n" "trigger=$v2_fc_tr is not one of: $V2_FENCE_TRIGGERS"; return 1; }

  v2_fc_due="$(v2_fm_get "$v2_fc_f" due_epoch)"
  v2_fc_obs="$(v2_fm_get "$v2_fc_f" observed_epoch)"
  v2_uint_value "$v2_fc_due" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_fc_n" "due_epoch='$v2_fc_due' is not a decimal integer within the exact range"; return 1; }
  v2_uint_value "$v2_fc_obs" >/dev/null 2>&1 \
    || { v2_fail EPOCH_RANGE "$v2_fc_n" "observed_epoch='$v2_fc_obs' is not a decimal integer within the exact range"; return 1; }

  # The validator has no clock, so this is the ONLY temporal claim it can check: the primary says it
  # observed an expiry, and an observation cannot precede the expiry it claims to have observed.
  [ "$v2_fc_obs" -ge "$v2_fc_due" ] \
    || v2_fail FENCE_OBSERVED "$v2_fc_n" "observed_epoch $v2_fc_obs precedes due_epoch $v2_fc_due; a fence cannot observe an expiry that has not happened"

  # `ack_ref: null` is not an omission — it is the ACK-timeout fence saying there is no ACK, which is
  # the whole reason it exists. A work-timeout fence must name the ACK whose budget expired.
  v2_fc_ar="$(v2_fm_get "$v2_fc_f" ack_ref)"
  case "$v2_fc_tr" in
    ack-timeout)
      [ "$v2_fc_ar" = null ] \
        || v2_fail FENCE_ACK_REF "$v2_fc_n" "an ack-timeout fence carries ack_ref: null (got '$v2_fc_ar'); if an ACK exists, the ACK budget did not expire" ;;
    work-timeout)
      [ "$v2_fc_ar" != null ] && [ -n "$v2_fc_ar" ] \
        || v2_fail FENCE_ACK_REF "$v2_fc_n" "a work-timeout fence must name the ACK whose work budget expired" ;;
  esac
}

# The cross-record half: the due epoch must be the bound ACTUALLY STORED on the receipt or the ACK,
# and one attempt is fenced at most once.
v2_check_fences() {
  while read -r v2_fk_seq v2_fk_kind v2_fk_name v2_fk_file; do
    [ -n "${v2_fk_seq:-}" ] || continue
    [ "$v2_fk_kind" = fence-initiated ] || continue

    v2_fk_t="$(v2_fm_get "$v2_fk_file" turn_id)"
    v2_fk_a="$(v2_fm_get "$v2_fk_file" attempt_id)"

    # Duplicate detection is scoped to THIS attempt. Two fences on two different attempts are
    # ordinary; only a second fence on the SAME attempt is a duplicate. Taking the globally-first
    # fence-initiated record as "the first" blamed a record belonging to another attempt entirely,
    # cited the wrong file, and reported one duplication twice.
    v2_fk_first=""
    while read -r v2_fk_s2 v2_fk_k2 v2_fk_n2 v2_fk_f2; do
      [ -n "${v2_fk_s2:-}" ] || continue
      [ "$v2_fk_k2" = fence-initiated ] || continue
      [ "$(v2_fm_get "$v2_fk_f2" turn_id)" = "$v2_fk_t" ] || continue
      [ "$(v2_fm_get "$v2_fk_f2" attempt_id)" = "$v2_fk_a" ] || continue
      v2_fk_first="$v2_fk_n2"
      break
    done <"$V2_SORTED"
    # Reported against the LATER record only, so one duplication is one violation.
    [ "$v2_fk_name" = "$v2_fk_first" ] \
      || v2_fail FENCE_DUP "$v2_fk_name" "attempt t$v2_fk_t-a$v2_fk_a is already fenced by $v2_fk_first; a fence is a boundary, not a retry"

    # The due epoch is the ONE temporal claim a clockless validator can check, so a reference that
    # fails to resolve must be a violation — never a `continue`. Skipping made a fence with a
    # dangling dispatch_ref and a fabricated due_epoch classify FENCING at exit 0, which is the
    # boundary's only checkable property bypassed entirely.
    v2_fk_tr="$(v2_fm_get "$v2_fk_file" trigger)"
    v2_fk_due="$(v2_fm_get "$v2_fk_file" due_epoch)"
    case "$v2_fk_tr" in
      ack-timeout)
        v2_resolve_attempt_ref "$(v2_fm_get "$v2_fk_file" dispatch_ref)" dispatch \
          "$v2_fk_file" "$v2_fk_name" FENCE_DUE || continue
        v2_fk_dp="$V2_REF_PATH"
        [ "$v2_fk_due" = "$(v2_fm_get "$v2_fk_dp" ack_due_epoch)" ] \
          || v2_fail FENCE_DUE "$v2_fk_name" "due_epoch $v2_fk_due is not the receipt's ack_due_epoch $(v2_fm_get "$v2_fk_dp" ack_due_epoch)"
        [ "$(v2_fm_get "$v2_fk_file" job_id)" = "$(v2_fm_get "$v2_fk_dp" job_id)" ] \
          || v2_fail FENCE_DUE "$v2_fk_name" "job_id differs from the receipt's job_id" ;;
      work-timeout)
        v2_resolve_attempt_ref "$(v2_fm_get "$v2_fk_file" ack_ref)" ack \
          "$v2_fk_file" "$v2_fk_name" FENCE_ACK_REF || continue
        v2_fk_kp="$V2_REF_PATH"
        [ "$v2_fk_due" = "$(v2_fm_get "$v2_fk_kp" work_due_epoch)" ] \
          || v2_fail FENCE_DUE "$v2_fk_name" "due_epoch $v2_fk_due is not the ACK's work_due_epoch $(v2_fm_get "$v2_fk_kp" work_due_epoch)" ;;
    esac
  done <"$V2_SORTED"
}

v2_schema_late() { # <staged-file> <display-name>
  v2_lt_f="$1" v2_lt_n="$2"
  for v2_lt_k in assignment_ref named_sha; do
    v2_fm_has "$v2_lt_f" "$v2_lt_k" || { v2_fail MISSING_KEY "$v2_lt_n" "missing $v2_lt_k"; return 1; }
  done
  v2_lt_sha="$(v2_fm_get "$v2_lt_f" named_sha)"
  if [ "$v2_lt_sha" != null ]; then
    v2_is_sha "$v2_lt_sha" || v2_fail BAD_SHA "$v2_lt_n" "named_sha=$v2_lt_sha"
  fi
}
v2_schema_owner_question() { :; }   # Task 8
v2_schema_owner_answer()   { :; }   # Task 8
v2_schema_close()          { :; }   # Task 8
