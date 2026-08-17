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
#
# Reads the narrow attempt index built during the record loop rather than re-parsing front matter.
# The previous form spawned two awk processes PER RECORD on every call, and this is called inside
# several nested loops -- the package gate spent most of its time here. The values in that index came
# from the same staged committed blobs, so nothing is trusted that was not trusted before.
v2_attempt_count() { # <turn_id> <attempt_id> <kind>
  awk -v t="$1" -v a="$2" -v k="$3" '$1 == t && $2 == a && $3 == k { n++ } END { print n + 0 }' \
    "$V2_WORK/attempts"
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

v2_files_of_kind() { # <kind> -> staged paths, in record order
  awk -v k="$1" '$2 == k { print $4 }' "$V2_SORTED"
}

v2_names_of_kind() { # <kind> -> basenames, in record order
  awk -v k="$1" '$2 == k { print $3 }' "$V2_SORTED"
}

# --- preserved v1 safety properties ------------------------------------------------------------------
#
# These are RE-IMPLEMENTED here, not shared with scripts/validate-v1.sh. That is a deliberate cost,
# recorded as an accepted risk in the plan: the frozen validator must stay independently executable
# and byte-identical, and no differential test can span the version boundary because the v2 validator
# rejects a v1 topic by construction. The mitigation is that every preserved check below has its own
# v2 fixture, so it is proven here rather than assumed correct by inheritance.

v2_repo_root() { case "$1" in */.git) dirname "$1" ;; *) printf '%s\n' "$1" ;; esac; }

# Canonicalize a path that may not exist yet, so two spellings of one directory compare equal.
# On macOS /tmp is a symlink to /private/tmp, and a topic pinned with one spelling would otherwise
# fail its own identity check against the other.
v2_canon() {
  v2_cn_raw="$1" v2_cn_probe="$1" v2_cn_suffix=""
  while [ ! -d "$v2_cn_probe" ] && [ "$v2_cn_probe" != "/" ]; do
    v2_cn_suffix="/$(basename "$v2_cn_probe")$v2_cn_suffix"
    v2_cn_parent="$(dirname "$v2_cn_probe")"
    [ "$v2_cn_parent" != "$v2_cn_probe" ] || break
    v2_cn_probe="$v2_cn_parent"
  done
  [ -d "$v2_cn_probe" ] || { printf '%s\n' "$v2_cn_raw"; return; }
  v2_cn_res="$(cd "$v2_cn_probe" 2>/dev/null && pwd -P)" || { printf '%s\n' "$v2_cn_raw"; return; }
  printf '%s%s\n' "$v2_cn_res" "$v2_cn_suffix"
}

# The accepted SHA as of a given record_seq: seeded from TOPIC.md's pinned base and advanced ONLY by
# a VERIFIED non-REVIEW result. REVIEW turns are stationary by contract and never move it.
v2_accepted_sha_upto() { # <seq>
  v2_as_acc="$(v2_fm_get "$V2_TOPIC_BLOB" base_sha)"
  while read -r v2_as_seq v2_as_kind v2_as_name v2_as_file; do
    [ "${v2_as_kind:-}" = result ] || continue
    [ "$v2_as_seq" \> "$1" ] && continue
    [ "$(v2_fm_get "$v2_as_file" status)" = VERIFIED ] || continue
    [ "$(v2_fm_get "$v2_as_file" turn_kind)" = REVIEW ] && continue
    v2_as_acc="$(v2_fm_get "$v2_as_file" result_sha)"
  done <"$V2_SORTED"
  printf '%s\n' "$v2_as_acc"
}

v2_accepted_sha() { v2_accepted_sha_upto 9999; }

# Read exactly one trailer value, or fail. A failed read is NOT "no trailer of that key": that
# conflation is how an unreadable range reads as an untrailered one.
v2_one_trailer() { # <repo-root> <commit> <key>
  v2_ot_msg="$(v2_git "$1" show -s --format=%B "$2" 2>/dev/null)" || return 1
  v2_ot_parsed="$(printf '%s\n' "$v2_ot_msg" | v2_git "$1" interpret-trailers --parse 2>/dev/null)" || return 1
  v2_ot_vals="$(printf '%s\n' "$v2_ot_parsed" | awk -F': ' -v k="$3" '$1 == k { sub(/^[^:]*: /, ""); print }')" || return 1
  [ "$(printf '%s\n' "$v2_ot_vals" | grep -c .)" -eq 1 ] || return 1
  printf '%s\n' "$v2_ot_vals"
}

# yes | no | unavailable. Every commit in the range must carry all three attribution trailers, name
# THIS topic, and belong to an attempt that has a terminal result. `unavailable` is its own answer so
# a failed walk can never be reported as an untrailered range.
v2_range_trailers_closed() { # <from> <to>
  v2_rt_bad=0
  v2_rt_root="$(v2_repo_root "$V2_CDIR")"
  v2_rt_list="$(v2_git "$v2_rt_root" rev-list "$1..$2" 2>/dev/null)" || { printf 'unavailable\n'; return; }
  while read -r v2_rt_sha; do
    [ -n "${v2_rt_sha:-}" ] || continue
    v2_rt_topic="$(v2_one_trailer "$v2_rt_root" "$v2_rt_sha" Agent-Pairing-Topic)" || { v2_rt_bad=1; continue; }
    v2_rt_t="$(v2_one_trailer "$v2_rt_root" "$v2_rt_sha" Agent-Pairing-Turn)" || { v2_rt_bad=1; continue; }
    v2_rt_a="$(v2_one_trailer "$v2_rt_root" "$v2_rt_sha" Agent-Pairing-Attempt)" || { v2_rt_bad=1; continue; }
    [ "$v2_rt_topic" = "$V2_TOPIC_ID" ] || v2_rt_bad=1
    [ "$(v2_attempt_count "$v2_rt_t" "$v2_rt_a" result)" -ge 1 ] || v2_rt_bad=1
  done <<EOF
$v2_rt_list
EOF
  [ "$v2_rt_bad" -eq 0 ] && printf 'yes\n' || printf 'no\n'
}

# --- owner questions ------------------------------------------------------------------------------------
v2_answer_of_question() { # <question staged-file> -> answer staged path, or empty
  v2_aq_id="$(v2_fm_get "$1" question_id)"
  for v2_aq_f in $(v2_files_of_kind owner-answer); do
    [ "$(v2_fm_get "$v2_aq_f" question_ref)" = "$v2_aq_id" ] && { printf '%s\n' "$v2_aq_f"; return; }
  done
}

v2_first_unanswered_question() { # -> staged path, or empty
  for v2_uq_f in $(v2_files_of_kind owner-question); do
    [ -z "$(v2_answer_of_question "$v2_uq_f")" ] && { printf '%s\n' "$v2_uq_f"; return; }
  done
}

# --- close ----------------------------------------------------------------------------------------------
V2_ACTIONABLE_DISPATCH="dispatch-job-found dispatch-confirmed-absent dispatch-termination-confirmed"

# The seq of the answer that cancels a close, or empty. The FULL ordering is required:
#
#     close_seq  <  question_seq  <  answer_seq
#
# Checking only `question_seq > close_seq` let an answer that PRECEDES its own question dissolve a
# durable close boundary and reopen dispatch — a misordered or forged record set could cancel a close
# that had not been questioned yet.
v2_cancelling_answer_seq() { # <close staged-file>
  v2_cc_id="$(v2_fm_get "$1" close_id)"
  v2_cc_seq="$(v2_fm_get "$1" record_seq)"
  for v2_cc_af in $(v2_files_of_kind owner-answer); do
    [ "$(v2_fm_get "$v2_cc_af" action)" = cancel-close ] || continue
    v2_cc_qf=""
    for v2_cc_q in $(v2_files_of_kind owner-question); do
      [ "$(v2_fm_get "$v2_cc_q" question_id)" = "$(v2_fm_get "$v2_cc_af" question_ref)" ] && v2_cc_qf="$v2_cc_q"
    done
    [ -n "$v2_cc_qf" ] || continue
    [ "$(v2_fm_get "$v2_cc_qf" blocks)" = "CLOSING:$v2_cc_id" ] || continue
    v2_cc_qseq="$(v2_fm_get "$v2_cc_qf" record_seq)"
    v2_cc_aseq="$(v2_fm_get "$v2_cc_af" record_seq)"
    [ "$v2_cc_qseq" \> "$v2_cc_seq" ] && [ "$v2_cc_aseq" \> "$v2_cc_qseq" ] \
      && { printf '%s\n' "$v2_cc_aseq"; return 0; }
  done
  return 1
}

v2_close_is_cancelled() { # <close staged-file>
  v2_cancelling_answer_seq "$1" >/dev/null
}

# The newest close that has NOT been cancelled, found by scanning backward. "Last record wins" would
# pick a cancelled close whenever one followed it.
v2_latest_active_close() { # -> staged path, or empty
  v2_lc_out=""
  for v2_lc_f in $(v2_files_of_kind close); do
    v2_close_is_cancelled "$v2_lc_f" || v2_lc_out="$v2_lc_f"
  done
  printf '%s\n' "$v2_lc_out"
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

# --- work-repo arms -------------------------------------------------------------------------------------
#
# Reached only when there is no active close, no unanswered question, and no open attempt. Every read
# below is captured with its own status, because a FAILED read must never flow into a comparison as
# if it were data: "the tree is clean" and "the status command failed" are different facts, and
# collapsing them reports a repository nobody could inspect as a healthy one.
V2_WR_CLASS=""
v2_classify_work_repo() {
  if [ ! -d "$V2_CDIR" ] || [ ! -d "$V2_WT" ]; then
    printf 'postcondition work-repo-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: work-repo)'; return
  fi
  v2_wr_root="$(v2_repo_root "$V2_CDIR")"
  v2_wr_want="$(v2_canon "$V2_WT")"

  v2_wr_list="$(v2_git "$v2_wr_root" worktree list --porcelain 2>/dev/null)" || {
    printf 'postcondition work-repo-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: worktree-list)'; return; }
  v2_wr_registered=no
  while read -r v2_wr_k v2_wr_v; do
    [ "${v2_wr_k:-}" = worktree ] && [ "$(v2_canon "$v2_wr_v")" = "$v2_wr_want" ] && v2_wr_registered=yes
  done <<EOF
$v2_wr_list
EOF

  v2_wr_common="$(v2_git "$V2_WT" rev-parse --git-common-dir 2>/dev/null)" || {
    printf 'postcondition worktree-identity: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: git-common-dir)'; return; }
  case "$v2_wr_common" in /*) ;; *)
    v2_wr_common="$(cd "$V2_WT" && cd "$v2_wr_common" 2>/dev/null && pwd -P)" || {
      printf 'postcondition worktree-identity: UNAVAILABLE\n'
      V2_WR_CLASS='UNRECORDED_DRIFT (unverified: git-common-dir)'; return; } ;;
  esac

  # A detached HEAD is not "some other branch" — it is a worktree whose branch cannot be read at all.
  v2_wr_head_branch="$(v2_git "$V2_WT" symbolic-ref --short HEAD 2>/dev/null)" || {
    printf 'postcondition worktree-identity: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: head-branch)'; return; }

  if [ "$v2_wr_registered" != yes ] \
     || [ "$(v2_canon "$v2_wr_common")" != "$(v2_canon "$V2_CDIR")" ] \
     || [ "$v2_wr_head_branch" != "$V2_BRANCH" ]; then
    printf 'postcondition worktree-identity: FAIL\n'
    V2_WR_CLASS='UNRECORDED_DRIFT'; return
  fi
  printf 'postcondition worktree-identity: PASS\n'

  v2_wr_tip="$(v2_git "$v2_wr_root" rev-parse "refs/heads/$V2_BRANCH" 2>/dev/null)" || {
    printf 'postcondition work-repo-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: branch-tip)'; return; }
  v2_wr_head="$(v2_git "$V2_WT" rev-parse HEAD 2>/dev/null)" || {
    printf 'postcondition work-repo-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: branch-tip)'; return; }
  v2_wr_dirty="$(v2_git "$V2_WT" status --porcelain 2>/dev/null)" || {
    printf 'postcondition worktree-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: worktree-status)'; return; }

  if [ "$v2_wr_tip" = "$V2_ACCEPTED" ] && [ "$v2_wr_head" = "$V2_ACCEPTED" ] && [ -z "$v2_wr_dirty" ]; then
    V2_WR_CLASS='IDLE'; return
  fi

  # A tip that a REJECTED or SUPERSEDED result already NAMES is quarantined: the history explains
  # where it came from, so the answer is a remediation turn rather than an alarm.
  for v2_wr_rf in $(v2_files_of_kind result); do
    case "$(v2_fm_get "$v2_wr_rf" status)" in REJECTED|SUPERSEDED) ;; *) continue ;; esac
    [ "$(v2_fm_get "$v2_wr_rf" result_sha)" = "$v2_wr_tip" ] && { V2_WR_CLASS='REMEDIATION_REQUIRED'; return; }
  done

  # Otherwise the tip moved and nothing accounts for it. The range must be NON-EMPTY for "all commits
  # carry trailers" to mean anything — a vacuous truth over zero commits would classify residue as
  # remediation.
  v2_wr_n="$(v2_git "$v2_wr_root" rev-list --count "$V2_ACCEPTED..$v2_wr_tip" 2>/dev/null)" || {
    printf 'postcondition commit-range-readable: UNAVAILABLE\n'
    V2_WR_CLASS='UNRECORDED_DRIFT (unverified: commit-range)'; return; }
  if [ "$v2_wr_n" -gt 0 ]; then
    v2_wr_tr="$(v2_range_trailers_closed "$V2_ACCEPTED" "$v2_wr_tip")"
    if [ "$v2_wr_tr" = unavailable ]; then
      printf 'postcondition trailer-range-readable: UNAVAILABLE\n'
      V2_WR_CLASS='UNRECORDED_DRIFT (unverified: trailer-range)'; return
    fi
    [ "$v2_wr_tr" = yes ] && { V2_WR_CLASS='REMEDIATION_REQUIRED'; return; }
  fi
  V2_WR_CLASS='UNRECORDED_DRIFT'
}

# --- close postconditions ---------------------------------------------------------------------------------
v2_check_close_postconditions() { # <close staged-file> -> sets V2_PC_ALL / V2_PC_UNVERIFIED
  V2_PC_ALL=yes; V2_PC_UNVERIFIED=""
  v2_cp_final="$(v2_fm_get "$1" final_accepted_sha)"
  v2_cp_root="$(v2_repo_root "$V2_CDIR")"

  # 1. THREAD.md is committed and says CLOSED.
  if [ "$V2_MODE" = --render ]; then
    printf 'postcondition thread-header: PROJECTED\n'
  else
    v2_cp_top="$(v2_git "$V2_TOPIC" rev-parse --show-toplevel 2>/dev/null)" || v2_cp_top=""
    if [ -z "$v2_cp_top" ]; then
      printf 'postcondition thread-header: UNAVAILABLE\n'
      V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}thread-header"
    elif ! v2_git "$V2_TOPIC" ls-files --error-unmatch THREAD.md >/dev/null 2>&1 \
         || ! v2_git "$V2_TOPIC" diff --quiet HEAD -- THREAD.md; then
      printf 'postcondition thread-header: FAIL\n'; V2_PC_ALL=no
    else
      v2_cp_hdr="$(v2_git "$V2_TOPIC" show HEAD:THREAD.md 2>/dev/null)"
      if [ $? -ne 0 ]; then
        printf 'postcondition thread-header: UNAVAILABLE\n'
        V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}thread-header"
      elif printf '%s\n' "$v2_cp_hdr" | awk '/^$/ { exit } /^status: CLOSED$/ { f = 1 } END { exit !f }'; then
        printf 'postcondition thread-header: PASS\n'
      else
        printf 'postcondition thread-header: FAIL\n'; V2_PC_ALL=no
      fi
    fi
  fi

  # 2. The session worktree is gone AND deregistered. A dangling symlink is not absence: -e is false
  #    for one while -L is true.
  if [ ! -d "$V2_CDIR" ]; then
    printf 'postcondition worktree-absent: UNAVAILABLE\n'
    V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}${V2_PC_UNVERIFIED:+,}worktree-absent"
  elif [ -e "$V2_WT" ] || [ -L "$V2_WT" ]; then
    printf 'postcondition worktree-absent: FAIL\n'; V2_PC_ALL=no
  else
    v2_cp_wl="$(v2_git "$v2_cp_root" worktree list --porcelain 2>/dev/null)"
    if [ $? -ne 0 ]; then
      printf 'postcondition worktree-absent: UNAVAILABLE\n'
      V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}${V2_PC_UNVERIFIED:+,}worktree-absent"
      v2_cp_wl_failed=yes
    else
      v2_cp_wl_failed=no
    fi
    v2_cp_listed=no
    while read -r v2_cp_k v2_cp_v; do
      [ "${v2_cp_k:-}" = worktree ] && [ "$(v2_canon "$v2_cp_v")" = "$(v2_canon "$V2_WT")" ] && v2_cp_listed=yes
    done <<EOF
$v2_cp_wl
EOF
    if [ "$v2_cp_wl_failed" = yes ]; then :   # already reported UNAVAILABLE above
    elif [ "$v2_cp_listed" = yes ]; then printf 'postcondition worktree-absent: FAIL\n'; V2_PC_ALL=no
    else printf 'postcondition worktree-absent: PASS\n'; fi
  fi

  # 3. The branch stands at the final accepted SHA.
  if [ ! -d "$V2_CDIR" ]; then
    printf 'postcondition branch-at-final: UNAVAILABLE\n'
    V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}${V2_PC_UNVERIFIED:+,}branch-at-final"
  else
    v2_cp_tip="$(v2_git "$v2_cp_root" rev-parse "refs/heads/$V2_BRANCH" 2>/dev/null)" || v2_cp_tip=""
    if [ -z "$v2_cp_tip" ]; then
      printf 'postcondition branch-at-final: UNAVAILABLE\n'
      V2_PC_ALL=no; V2_PC_UNVERIFIED="${V2_PC_UNVERIFIED}${V2_PC_UNVERIFIED:+,}branch-at-final"
    elif [ "$v2_cp_tip" = "$v2_cp_final" ]; then
      printf 'postcondition branch-at-final: PASS\n'
    else
      printf 'postcondition branch-at-final: FAIL\n'; V2_PC_ALL=no
    fi
  fi
}

# --- the whole precedence order ------------------------------------------------------------------------------
#
# Fail-closed, most-authoritative first. The ORDER is the substance:
#
#   1. An active close boundary outranks ordinary turn state. A topic being closed is not idle, and
#      evaluating turn state first would let a finished topic look like one accepting work.
#   2. An unanswered owner question blocks ALL automatic action. The owner was asked precisely
#      because replay could not decide; continuing would answer the question by acting.
#   3. The open attempt — where fence, capture and ACK precedence live (v2_classify_open_attempt).
#   4. Quarantine and drift, which prevent IDLE: a moved tip or residue is never "nothing to do".
#   5. IDLE last, because it is the only state that means "safe to dispatch", and it must be
#      reachable only when every louder condition has been ruled out.
v2_classify() {
  V2_ACCEPTED="$(v2_accepted_sha)"
  printf 'accepted_sha: %s\n' "$V2_ACCEPTED"

  v2_cl_close="$(v2_latest_active_close)"
  if [ -n "$v2_cl_close" ]; then
    v2_cl_cid="$(v2_fm_get "$v2_cl_close" close_id)"
    for v2_cl_qf in $(v2_files_of_kind owner-question); do
      [ "$(v2_fm_get "$v2_cl_qf" blocks)" = "CLOSING:$v2_cl_cid" ] || continue
      [ -n "$(v2_answer_of_question "$v2_cl_qf")" ] || { printf 'classification: AWAITING_OWNER\n'; return; }
    done
    v2_check_close_postconditions "$v2_cl_close"
    if [ "$V2_PC_ALL" = yes ]; then printf 'classification: CLOSED\n'
    else printf 'classification: CLOSING:%s%s\n' "$v2_cl_cid" "${V2_PC_UNVERIFIED:+ (unverified: $V2_PC_UNVERIFIED)}"; fi
    return
  fi

  [ -n "$(v2_first_unanswered_question)" ] && { printf 'classification: AWAITING_OWNER\n'; return; }

  v2_cl_open="$(v2_open_attempt)"
  if [ -n "$v2_cl_open" ]; then
    v2_cl_state="$(v2_classify_open_attempt $v2_cl_open)"
    # An attempt whose delivery is unknown, but whose owner question has an ACTIONABLE answer, is
    # waiting for that authorization to be materialized — not for more waiting.
    if [ "$v2_cl_state" = DISPATCH_UNKNOWN ]; then
      set -- $v2_cl_open
      v2_cl_latest=""; v2_cl_latest_seq=""
      for v2_cl_qf in $(v2_files_of_kind owner-question); do
        [ "$(v2_fm_get "$v2_cl_qf" blocks)" = "t$1-a$2" ] || continue
        v2_cl_af="$(v2_answer_of_question "$v2_cl_qf")"
        [ -n "$v2_cl_af" ] || continue
        v2_cl_aseq="$(v2_fm_get "$v2_cl_af" record_seq)"
        # The LATEST answer wins: an owner may withdraw an earlier authorization with a later
        # `dispatch-unresolved`, and acting on the earlier one would execute a decision already
        # reversed.
        { [ -z "$v2_cl_latest_seq" ] || [ "$v2_cl_aseq" \> "$v2_cl_latest_seq" ]; } \
          && { v2_cl_latest="$v2_cl_af"; v2_cl_latest_seq="$v2_cl_aseq"; }
      done
      if [ -n "$v2_cl_latest" ] \
         && v2_in_list "$(v2_fm_get "$v2_cl_latest" action)" "$V2_ACTIONABLE_DISPATCH"; then
        printf 'classification: OWNER_ACTION_PENDING\n'; return
      fi
    fi
    printf 'classification: %s\n' "$v2_cl_state"
    return
  fi

  # Called directly, NOT in $( ): the postcondition lines it prints are output in their own right,
  # and capturing them would fold them into the classification line.
  v2_classify_work_repo
  printf 'classification: %s\n' "$V2_WR_CLASS"
}
