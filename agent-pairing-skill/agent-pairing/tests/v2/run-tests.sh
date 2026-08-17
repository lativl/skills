#!/bin/bash
# bash 3.2 compatible. Run: /bin/bash agent-pairing/tests/v2/run-tests.sh [GROUP]
#
# GROUP restricts the run to one fixture group (version, common, admission, clocks, ack, capture,
# fence, classification, precedence, render). With no argument every group runs. An unknown group is
# an error rather than a silent zero-case pass, because a suite that runs nothing must never look
# like a suite that passes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
V2_VALIDATE="$HERE/../../scripts/validate.sh"
V2_FIXTURES="$HERE/fixtures"

V2_TMP="$(mktemp -d /tmp/agent-pairing-v2-tests.XXXXXX)" \
  || { echo "FATAL: temp root allocation failed" >&2; exit 3; }
[ -n "$V2_TMP" ] && [ -d "$V2_TMP" ] || { echo "FATAL: temp root allocation produced no directory" >&2; exit 3; }

. "$HERE/lib.sh"
. "$HERE/live.sh"
trap 'v2_safe_rmdir "$V2_TMP" /tmp/agent-pairing-v2-tests.' EXIT

V2_OUT="$V2_TMP/out"
V2_PASS=0
V2_FAIL=0
V2_RC=0
V2_LAST_TOPIC=""

# Only groups that ACTUALLY HAVE CASES are listed. A group name declared before its task implements
# it would answer `0 passed, 0 failed` and exit zero — a suite that runs nothing wearing the costume
# of a suite that passes. Each task appends its own group name here alongside its cases.
V2_GROUPS="version common admission clocks ack capture fence classification render templates"
V2_ONLY="${1:-}"
if [ -n "$V2_ONLY" ]; then
  v2_known=no
  for g in $V2_GROUPS; do [ "$g" = "$V2_ONLY" ] && v2_known=yes; done
  [ "$v2_known" = yes ] || { echo "FATAL: unknown group '$V2_ONLY'; expected one of: $V2_GROUPS" >&2; exit 3; }
fi

v2_group() { # <group> -> 0 when the group should run
  [ -z "$V2_ONLY" ] && return 0
  [ "$V2_ONLY" = "$1" ]
}

# --- version: the compatibility boundary is fail-closed --------------------------------------------
if v2_group version; then
  v2_expect_classification "empty v2 topic classifies AWAITING_PARTICIPANT" topic-empty-v2 AWAITING_PARTICIPANT
  v2_expect_violation "missing version fails closed" topic-missing-version PROTOCOL_VERSION
  v2_expect_violation "v1 is rejected by default" topic-v1 PROTOCOL_VERSION
  v2_expect_usage "no arguments is a usage error"
  v2_expect_usage "unknown mode is a usage error" --validate "$V2_TMP"
  v2_expect_usage "missing topic directory is a usage error" --check "$V2_TMP/does-not-exist"

  # A topic that declares the version twice is the Global Constraints' "mixed" input. Reading the
  # first match and exiting zero is how a v1 record slips past the boundary wearing a v2 label.
  v2_expect_violation "a duplicated protocol_version is malformed, not first-match-wins" \
    topic-mixed-version TOPIC_FM_MALFORMED
  v2_expect_violation "unterminated topic front matter is malformed" \
    topic-unterminated-fm TOPIC_FM_MALFORMED

  # Regression: a DAMAGED record tree must never read as an empty one. Before this case,
  # `ls-tree | sort` reported sort's status, so a repository with committed records and a missing
  # tree object exited 0 as AWAITING_PARTICIPANT — a corrupt topic classified as a clean one.
  v2_case_unreadable_record_tree() {
    v2_t="$(v2_materialize "$V2_FIXTURES/common-valid")" || {
      v2_nok "a damaged record tree is unavailable evidence, not an empty one" "materialize failed"; return; }
    v2_tree="$(git -C "$v2_t" rev-parse HEAD:turns)" || {
      v2_nok "a damaged record tree is unavailable evidence, not an empty one" "cannot resolve HEAD:turns"; return; }
    rm -f "$v2_t/.git/objects/${v2_tree%${v2_tree#??}}/${v2_tree#??}"
    "$V2_VALIDATE" --check "$v2_t" >"$V2_OUT" 2>&1
    v2_rc=$?
    if [ "$v2_rc" -eq 3 ] && grep -F 'FATAL' "$V2_OUT" >/dev/null; then
      v2_ok "a damaged record tree is unavailable evidence, not an empty one"
    else
      v2_nok "a damaged record tree is unavailable evidence, not an empty one" \
        "expected exit 3 with FATAL; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_unreadable_record_tree

  # Regression: the harness itself must not report a pass for a fixture that never materialized.
  # $V2_OUT is truncated before every run, so a misspelled fixture cannot inherit the previous
  # case's evidence and satisfy a grep.
  v2_run "$V2_FIXTURES/no-such-fixture" 2>/dev/null
  if [ -s "$V2_OUT" ]; then
    v2_nok "a missing fixture leaves no stale evidence behind" "\$V2_OUT retained previous output"
  else
    v2_ok "a missing fixture leaves no stale evidence behind"
  fi
fi

# --- common: committed-only reads and the fields every v2 record carries -----------------------------
if v2_group common; then
  v2_expect_ok "the canonical valid attempt passes the common grammar" common-valid

  v2_expect_only_violation "record version is required" \
    common-defects/missing-record-version RECORD_PROTOCOL_VERSION
  v2_expect_only_violation "record sequence is decimal" \
    common-defects/bad-record-seq RECORD_SEQ
  v2_expect_only_violation "epoch is nonnegative" \
    common-defects/negative-epoch RECORDED_EPOCH
  v2_expect_only_violation "epochs do not decrease" \
    common-defects/decreasing-epoch EPOCH_ORDER
  v2_expect_only_violation "unknown kind is rejected" \
    common-defects/unknown-kind UNKNOWN_KIND
  v2_expect_only_violation "working-tree-only record is ignored then reported as residue" \
    common-defects/uncommitted-record UNCOMMITTED_RESIDUE

  # Regression: each record must be staged to its OWN file. `v2_stage_committed` runs inside `$( )`,
  # so a counter-derived slot name never increments in the parent — every record staged over the
  # same path and every cross-record read returned the LAST record's bytes, which is a comparison of
  # a record with itself reporting agreement. Asserting the violation's SUBJECT (not just its code)
  # is what pins per-record identity: under the collision the epoch defect was invisible entirely.
  v2_run "$V2_FIXTURES/common-defects/decreasing-epoch" || true
  if grep -F 'VIOLATION EPOCH_ORDER 0004-t0001-a01-dispatch.md' "$V2_OUT" >/dev/null; then
    v2_ok "a violation names the record that carries the defect"
  else
    v2_nok "a violation names the record that carries the defect" \
      "expected EPOCH_ORDER against 0004-t0001-a01-dispatch.md; got: $(grep -m1 VIOLATION "$V2_OUT")"
  fi

  # record_seq is the ordering authority, so a gap and a duplicate are both defects. These two cases
  # exist because the rules died silently once: a later fix reused one temp filename for two
  # different files, the prefix scan started reading index lines instead of record paths, and both
  # checks became unreachable while the suite stayed green. A rule with no case keeps passing after
  # it is deleted.
  v2_expect_only_violation "record_seq is contiguous from 0001" \
    common-defects/seq-gap SEQ_GAP
  v2_expect_only_violation "record_seq is not reused" \
    common-defects/seq-dup SEQ_DUP

  # Regression: a Finder .DS_Store under artifacts/ — ignored by the global core.excludesFile on
  # essentially every macOS machine — is not protocol residue. Artifact integrity is pinned by the
  # capture record's byte count and SHA-256, which is stronger evidence than a status line.
  v2_case_ds_store_is_not_residue() {
    v2_n="an ignored file outside the record tree is not residue"
    v2_t="$(v2_materialize "$V2_FIXTURES/common-valid")" || { v2_nok "$v2_n" "materialize failed"; return; }
    mkdir -p "$v2_t/artifacts/t0001-a01" || { v2_nok "$v2_n" "cannot create artifacts dir"; return; }
    printf 'finder junk\n' >"$v2_t/artifacts/t0001-a01/.DS_Store"
    printf '.DS_Store\n' >"$v2_t/.excludes"
    git -C "$v2_t" config core.excludesFile "$v2_t/.excludes" || { v2_nok "$v2_n" "cannot set excludesFile"; return; }
    "$V2_VALIDATE" --check "$v2_t" >"$V2_OUT" 2>&1
    v2_rc=$?
    if [ "$v2_rc" -eq 0 ]; then
      v2_ok "$v2_n"
    else
      v2_nok "$v2_n" "expected exit 0; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_ds_store_is_not_residue

  # Regression: a committed record path that looks like a glob must be INSPECTED, not expanded.
  # `for p in $LIST` performs pathname expansion even with IFS set, so a record named
  # `turns/000[6]-close.md` was replaced by whichever real file matched in the CURRENT directory.
  # Run from a neutral cwd the record was rejected; run from inside the topic it exited 0. The
  # assertion runs the validator with cwd set to the topic itself, which is where the bug lived.
  v2_case_glob_named_record() {
    v2_n="a record path that looks like a glob is inspected, not expanded"
    v2_t="$(v2_materialize "$V2_FIXTURES/common-valid")" || { v2_nok "$v2_n" "materialize failed"; return; }
    printf 'GARBAGE NOT FRONT MATTER\n' >"$v2_t/turns/000[6]-close.md"
    git -C "$v2_t" add -A >/dev/null 2>&1 && git -C "$v2_t" commit -qm glob >/dev/null 2>&1 \
      || { v2_nok "$v2_n" "cannot commit the glob-named record"; return; }
    ( cd "$v2_t" && "$V2_VALIDATE" --check . ) >"$V2_OUT" 2>&1
    v2_rc=$?
    if [ "$v2_rc" -eq 2 ] && grep -F '000[6]-close.md' "$V2_OUT" >/dev/null; then
      v2_ok "$v2_n"
    else
      v2_nok "$v2_n" "expected exit 2 naming the glob-shaped record; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_glob_named_record

  # Regression: an ignore rule must not decide whether residue evidence exists. Plain
  # `--porcelain --untracked-files=all` never reports ignored paths, so one `.gitignore` line made a
  # half-written receipt invisible and the topic classified as though nothing were there.
  v2_case_ignored_residue() {
    v2_n="an ignored record file is still residue"
    v2_t="$(v2_materialize "$V2_FIXTURES/common-valid")" || { v2_nok "$v2_n" "materialize failed"; return; }
    printf 'turns/0006-*.md\n' >"$v2_t/.gitignore"
    git -C "$v2_t" add .gitignore >/dev/null 2>&1 && git -C "$v2_t" commit -qm ignore >/dev/null 2>&1 \
      || { v2_nok "$v2_n" "cannot commit .gitignore"; return; }
    printf -- '---\nprotocol_version: 2\n---\nhalf-written\n' >"$v2_t/turns/0006-t0001-a01-result.md"
    "$V2_VALIDATE" --check "$v2_t" >"$V2_OUT" 2>&1
    v2_rc=$?
    if [ "$v2_rc" -eq 2 ] && grep -F 'VIOLATION UNCOMMITTED_RESIDUE' "$V2_OUT" >/dev/null; then
      v2_ok "$v2_n"
    else
      v2_nok "$v2_n" "expected UNCOMMITTED_RESIDUE; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_ignored_residue

  # Regression: a directory of record files INSIDE another repository is not a record repository.
  # `rev-parse --git-dir` walks upward, so every HEAD: read resolved against the host repo's tree —
  # classifying another topic's records as this one's.
  v2_case_not_own_repo() {
    v2_n="a topic inside another repository is not a record repository"
    v2_host="$(mktemp -d "$V2_TMP/host.XXXXXX")" || { v2_nok "$v2_n" "temp failed"; return; }
    git -C "$v2_host" init -q && git -C "$v2_host" config user.name t && git -C "$v2_host" config user.email t@t \
      || { v2_nok "$v2_n" "cannot init host repo"; return; }
    mkdir -p "$v2_host/sub" && cp -R "$V2_FIXTURES/common-valid/." "$v2_host/sub/" \
      || { v2_nok "$v2_n" "cannot place the topic"; return; }
    git -C "$v2_host" add -A >/dev/null 2>&1 && git -C "$v2_host" commit -qm host >/dev/null 2>&1 \
      || { v2_nok "$v2_n" "cannot commit host repo"; return; }
    "$V2_VALIDATE" --check "$v2_host/sub" >"$V2_OUT" 2>&1
    v2_rc=$?
    if [ "$v2_rc" -eq 2 ] && grep -F 'VIOLATION RECORD_REPO' "$V2_OUT" >/dev/null; then
      v2_ok "$v2_n"
    else
      v2_nok "$v2_n" "expected RECORD_REPO; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_not_own_repo

  # The residue case must ALSO prove the working-tree bytes were never treated as records: had the
  # validator read `turns/` from disk, it would have found five well-formed records and could have
  # classified the topic instead of reporting residue. The fixture is re-run rather than read from
  # whatever happens to be in $V2_OUT, so reordering the cases above cannot silently retarget it.
  v2_run "$V2_FIXTURES/common-defects/uncommitted-record" || true
  if grep -F 'VIOLATION UNCOMMITTED_RESIDUE' "$V2_OUT" >/dev/null \
     && ! grep -F 'classification:' "$V2_OUT" >/dev/null; then
    v2_ok "an uncommitted record set yields no classification"
  else
    v2_nok "an uncommitted record set yields no classification" \
      "the validator produced a classification from working-tree bytes"
  fi
fi

# --- admission: participant selection and the transport contract -------------------------------------
if v2_group admission; then
  # All four (start mode, selection source) pairs are legal. The protocol constrains HOW the mode was
  # resolved, not which mode goes with which source: an owner can answer the selection question with
  # either mode, and either mode can be unambiguous in the initial prompt.
  # These assert that the four pairs VALIDATE. The resulting classification is owned by the
  # `classification` group, which builds real repositories: IDLE is not a property of the record text
  # -- it additionally requires a registered, clean, stationary worktree, which a static fixture
  # cannot have.
  v2_expect_ok "primary-spawn from the initial prompt" admission/sel-spawn-prompt
  v2_expect_ok "primary-spawn from an owner answer" admission/sel-spawn-answer
  v2_expect_ok "owner-manual from the initial prompt" admission/sel-manual-prompt
  v2_expect_ok "owner-manual from an owner answer" admission/sel-manual-answer

  # A topic with no admission has no participant, whatever its selection mode says. Selecting
  # owner-manual is NOT admission: the ACK and work budgets cannot start against nobody.
  v2_expect_classification "selecting owner-manual is not itself admission" \
    topic-empty-v2 AWAITING_PARTICIPANT

  v2_expect_only_violation "selection source is an enumeration" \
    admission/bad-selection-source PARTICIPANT_SELECTION
  v2_expect_only_violation "the start mode is required" \
    admission/missing-start-mode PARTICIPANT_START_MODE
  v2_expect_only_violation "join_mode agrees with the topic's start mode" \
    admission/join-mode-mismatch JOIN_MODE
  v2_expect_only_violation "admission_id is unique" \
    admission/duplicate-admission-id ADMISSION_ID_DUP
  v2_expect_only_violation "a monitor handle is not a durable address" \
    admission/monitor-as-address DURABLE_ADDRESS_KIND
  v2_expect_only_violation "searchable requires a token-search recipe" \
    admission/searchable-without-recipe SEARCHABILITY
  v2_expect_only_violation "unsearchable forbids a token-search recipe" \
    admission/unsearchable-with-recipe SEARCHABILITY
  v2_expect_only_violation "commits requires a visible worktree" \
    admission/commits-invisible CAPABILITY_VISIBILITY
  v2_expect_only_violation "a changed transport contract needs a new admission_id" \
    admission/admission-mutated ADMISSION_MUTATED
fi

# --- clocks: two durations, a receipt bound, and recovery provenance ----------------------------------
if v2_group clocks; then
  # The validator NEVER reads wall-clock time. It checks stored arithmetic and PRINTS the due epochs
  # for the primary to compare against its own clock. A committed receipt starts only the ACK budget;
  # a captured ACK starts the work budget.
  v2_expect_line "the receipt's ACK budget is printed, not evaluated against now" \
    common-valid "ack_due_epoch: 1630"
  v2_expect_line "the captured ACK's work budget is printed" \
    common-valid "work_due_epoch: 4640"
  v2_expect_line "the intent's receipt bound is printed" \
    common-valid "receipt_commit_by_epoch: 1320"

  # Equal epochs are ordinary: several records can be stamped in one second, and record_seq breaks
  # the tie. This must not be mistaken for a stalled or reordered history.
  v2_expect_ok "records stamped in the same second are legal" clocks/same-second

  v2_expect_only_violation "the intent repeats its assignment's admission_ref" \
    clocks/intent-admission-ref ADMISSION_REF
  v2_expect_only_violation "the intent's receipt timeout is the admitted one" \
    clocks/intent-receipt-timeout RECEIPT_TIMEOUT
  v2_expect_only_violation "the receipt bound is intent epoch plus the materialized timeout" \
    clocks/receipt-commit-due RECEIPT_COMMIT_DUE
  v2_expect_only_violation "the ACK bound is dispatched epoch plus the assignment's ACK timeout" \
    clocks/ack-due ACK_DUE
  v2_expect_only_violation "a v1 absolute deadline is rejected in a v2 assignment" \
    clocks/legacy-deadline LEGACY_DEADLINE
  v2_expect_only_violation "an epoch beyond the exact integer range is rejected" \
    clocks/epoch-range EPOCH_RANGE

  # A recovered uncommitted receipt is RE-STAMPED, never restored. Reusing the pre-crash epoch would
  # publish an ACK budget that is already past at the moment the receipt first becomes visible to the
  # participant — recreating the v1 pre-expired-deadline defect inside the recovery path. The ACK
  # budget measures delivery latency, and the participant cannot observe an uncommitted receipt, so
  # the budget must start when visibility starts.
  v2_expect_only_violation "a recovered receipt records its pre-crash provenance" \
    clocks/recovery-missing-epoch RECOVERY_EPOCH
  v2_expect_only_violation "a recovered receipt's budget is not computed from the pre-crash epoch" \
    clocks/recovery-pre-crash-arithmetic RECOVERY_EPOCH
  v2_expect_only_violation "a pre-crash epoch cannot postdate the re-stamped commit" \
    clocks/recovery-pre-crash-after-dispatch RECOVERY_EPOCH
  # The participant polls committed HEAD for exactly the name the intent predicted. A receipt under
  # any other name means it polls until its bound expires and writes nothing, while replay would
  # otherwise call the topic healthy and wait for an ACK that cannot arrive.
  v2_expect_only_violation "the receipt is committed under the name the intent predicted" \
    clocks/unexpected-dispatch-name EXPECTED_DISPATCH_REF
fi

# --- ack: the acknowledgement is the delivery evidence --------------------------------------------------
# A primary-authored receipt proves only that the primary WROTE something. The ACK is the first
# evidence that the participant actually received the work, and it is worth nothing unless it binds
# the exact attempt it claims to answer.
if v2_group ack; then
  # The full visibility x capability matrix. Only `commits` is constrained by visibility, because it
  # is the only capability that admits a participant-authored landed commit — and a participant that
  # cannot see the worktree cannot have authored one in it.
  v2_expect_ok "visible + commits: observed HEAD, clean, no relay base" ack/valid-visible-commits
  v2_expect_ok "visible + writes-repo-only" ack/valid-visible-writes
  v2_expect_ok "visible + read-only" ack/valid-visible-readonly
  v2_expect_ok "invisible + writes-repo-only: null HEAD, relay base bound" ack/valid-invisible-writes
  v2_expect_ok "invisible + read-only" ack/valid-invisible-readonly

  v2_expect_only_violation "an invisible participant cannot hold capability: commits" \
    ack/invisible-commits CAPABILITY_VISIBILITY

  v2_expect_only_violation "the ACK binds the receipt's job_id" ack/wrong-job ACK_BINDING
  v2_expect_only_violation "the ACK binds the intent's idempotency token" ack/wrong-token ACK_BINDING
  v2_expect_only_violation "the ACK declares the admitted evidence class" ack/wrong-evidence-class ACK_BINDING
  v2_expect_only_violation "the ACK binds the assignment's admission" ack/wrong-admission-ref ACK_BINDING
  v2_expect_only_violation "the ACK binds the attempt's own receipt" ack/wrong-dispatch-ref ACK_BINDING

  # Visible: the participant looked, so it must say what it saw and that the tree was clean.
  v2_expect_only_violation "a visible ACK carries an observed HEAD" ack/visible-null-head ACK_PREFLIGHT
  v2_expect_only_violation "a visible ACK's observed HEAD is the assignment base" ack/visible-wrong-head ACK_PREFLIGHT
  v2_expect_only_violation "a visible ACK's preflight must be clean" ack/visible-dirty ACK_PREFLIGHT
  v2_expect_only_violation "a visible ACK carries no relay base" ack/visible-relay-base ACK_PREFLIGHT

  # Invisible: the participant did NOT look, so claiming an observation is a false claim. It binds the
  # relay input instead, and the primary separately verifies the shared worktree is stationary.
  v2_expect_only_violation "an invisible ACK claims no observation" ack/invisible-observed-head ACK_PREFLIGHT
  v2_expect_only_violation "an invisible ACK binds the relay base" ack/invisible-null-relay ACK_PREFLIGHT
  v2_expect_only_violation "an invisible ACK's relay base is the assignment base" ack/invisible-wrong-relay ACK_PREFLIGHT

  # The work budget starts when the ACK is captured — not when the receipt was written, and not when
  # the participant first saw the prompt.
  v2_expect_only_violation "the work bound is the captured ACK epoch plus the work timeout" \
    ack/wrong-work-due WORK_DUE
  # The participant learns of the work by observing the committed receipt, so an ACK ordered before
  # that receipt acknowledges something it could not have seen.
  v2_expect_only_violation "an ACK cannot precede the receipt it acknowledges" \
    ack/ack-before-receipt LINK_ORDER
fi

# --- capture: exact participant bytes ---------------------------------------------------------------
# The motivating v1 failure was a STALE capture: the captured report and the final report had
# different byte counts and different SHA-256 values, and nothing in the record noticed. v2 makes the
# participant finalize an author manifest, writes the bytes once without normalization, recomputes
# the manifest, and commits both.
if v2_group capture; then
  # Byte shapes that a line-oriented reconstruction would quietly alter.
  v2_expect_ok "ASCII with a trailing newline" capture/ascii-trailing-newline
  v2_expect_ok "ASCII WITHOUT a trailing newline" capture/ascii-no-trailing-newline
  v2_expect_ok "UTF-8 multi-byte content" capture/utf8-report
  # The artifact is an opaque byte boundary: a report body containing `---` and fences is content,
  # never control data, so it cannot inject front matter into the record stream.
  v2_expect_ok "a report body containing --- and fences" capture/framing-in-body

  v2_expect_only_violation "an author byte count that disagrees with the bytes" \
    capture/author-bytes-mismatch CAPTURE_BYTES
  v2_expect_only_violation "an author digest that disagrees with the bytes" \
    capture/author-sha-mismatch CAPTURE_SHA256
  v2_expect_only_violation "a declared trailing-newline state that disagrees with the bytes" \
    capture/newline-mismatch CAPTURE_NEWLINE
  v2_expect_only_violation "the artifact lives under this attempt's own directory" \
    capture/path-outside-attempt CAPTURE_PATH

  v2_expect_only_violation "read-only produces no relay patch" \
    capture/readonly-with-patch CAPABILITY_PATCH
  v2_expect_ok "writes-repo-only may relay a patch with its own manifest" \
    capture/writes-with-patch

  # A terminal status is accountable to evidence, not to the primary's memory of the turn.
  v2_expect_ok "a VERIFIED result citing its ACK and its capture" capture/result-verified
  v2_expect_only_violation "VERIFIED requires a valid ACK" \
    capture/result-verified-no-ack RESULT_ACK_REF
  v2_expect_only_violation "VERIFIED requires a matching capture" \
    capture/result-verified-no-capture RESULT_CAPTURE_REF
  # `ack_ref: null` is legal only where no acknowledgement could exist. A plain verification failure
  # is not one of those cases: the work WAS delivered, so the delivery evidence must still be cited.
  v2_expect_only_violation "a null ack_ref needs a reason that explains the absence" \
    capture/result-null-ack-bad-reason RESULT_ACK_REF

  # Relayed patch bytes are about to be applied to the work repo. Verifying them only when the
  # manifest happened to be present meant a capture could omit the four patch fields and the bytes
  # were certified by nothing -- the stale-capture hole, reopened for the patch.
  v2_expect_only_violation "a committed patch requires its manifest" \
    capture/patch-without-manifest CAPTURE_PATCH_MANIFEST
  v2_expect_only_violation "a patch digest that disagrees with the patch bytes" \
    capture/patch-sha-mismatch CAPTURE_SHA256
fi

# --- fence: the durable timeout boundary ---------------------------------------------------------------
# A timeout comparison changes NOTHING. Only a committed `fence-initiated` record moves an attempt,
# and the validator never compares a due epoch with the current time — it checks that a committed
# fence was observed no earlier than its own stored due epoch, and that the due epoch is the bound
# actually stored on the receipt or ACK.
if v2_group fence; then
  v2_expect_classification "a receipt with no ACK waits" fence/awaiting-ack AWAITING_ACK
  v2_expect_classification "an ACK-timeout fence supersedes AWAITING_ACK" fence/ack-timeout-fenced FENCING
  v2_expect_classification "a work-timeout fence supersedes WORKING" fence/work-timeout-fenced FENCING

  # RESULT_BUFFERED is the single capture-derived state, and it applies ONLY when the ACK is absent.
  # The protocol never synthesizes an "implied-at-result" acknowledgement.
  v2_expect_classification "a capture with no ACK is buffered, not acknowledged" \
    fence/capture-before-ack RESULT_BUFFERED
  # WORKING is ACK-anchored and capture-insensitive: a valid ACK with no terminal result is WORKING
  # whether or not a capture exists. The capture changes the primary's next ACTION, not the state.
  v2_expect_classification "a buffered capture plus a later ACK is WORKING" \
    fence/capture-then-ack WORKING
  v2_expect_classification "a buffered capture plus a fence is FENCING" \
    fence/capture-then-fence FENCING

  # After the fence commits, late evidence is an observation against the boundary. Nothing reopens.
  v2_expect_classification "a late ACK after a fence cannot reopen the attempt" \
    fence/late-after-fence FENCING
  v2_expect_classification "a late landed commit after a fence cannot reopen the attempt" \
    fence/late-commit-after-fence FENCING

  v2_expect_only_violation "a fence cannot be observed before its own due epoch" \
    fence/fence-before-due FENCE_OBSERVED
  v2_expect_only_violation "a fence's due epoch is the bound stored on the receipt" \
    fence/fence-wrong-due FENCE_DUE
  # The design's key is `trigger`. `reason` is NOT an accepted alias: silently accepting it would let
  # two spellings of the same field diverge, and one of them would stop being checked.
  v2_expect_only_violation "reason is not an alias for trigger" \
    fence/fence-reason-alias MISSING_KEY
  v2_expect_only_violation "a work-timeout fence names the ACK whose budget expired" \
    fence/work-fence-null-ack FENCE_ACK_REF
  v2_expect_only_violation "an ACK-timeout fence carries no ack_ref" \
    fence/ack-fence-with-ack FENCE_ACK_REF
  v2_expect_only_violation "one attempt is fenced at most once" \
    fence/second-fence FENCE_DUP
  # A fence's due epoch is its ONLY checkable temporal claim, so a reference that fails to resolve
  # must be a violation and never a skip. Skipping let a fence with a dangling dispatch_ref and a
  # fabricated due_epoch classify FENCING at exit 0.
  v2_expect_only_violation "a fence cannot skip its due-epoch check by naming a missing receipt" \
    fence/fence-dangling-dispatch FENCE_DUE
fi

# --- classification: one valid fixture for every state in the design's table --------------------------
# These build REAL repositories. The states below are not properties of the record text alone: they
# depend on where the branch tip is, whether the worktree is registered and clean, and whether the
# commits in range carry their attribution trailers. A fixture whose paths point nowhere would
# exercise the "unavailable evidence" branch and prove nothing about any of them.
if v2_group classification; then
  v2_expect_classification "no admission: no participant yet" topic-empty-v2 AWAITING_PARTICIPANT
  v2_expect_live "a completed turn on a clean stationary tree" idle IDLE
  v2_expect_live "an assignment with no intent was never dispatched" never-dispatched "OPEN (never-dispatched)"
  v2_expect_live "an intent with no receipt: delivery is unknown" dispatch-unknown DISPATCH_UNKNOWN
  v2_expect_live "an acknowledged turn in progress" working WORKING
  v2_expect_live "an unanswered owner question blocks everything" awaiting-owner AWAITING_OWNER
  v2_expect_live "an actionable answer not yet materialized" owner-action-pending OWNER_ACTION_PENDING
  v2_expect_live "a quarantined commit needs a remediation turn" remediation REMEDIATION_REQUIRED
  v2_expect_live "an unexplained tip is drift, not remediation" drift UNRECORDED_DRIFT
  v2_expect_live "uncommitted residue with no open attempt is drift" residue UNRECORDED_DRIFT
  v2_expect_live "close postconditions incomplete" closing "CLOSING:close-0001"
  v2_expect_live "every close postcondition satisfied" closed CLOSED

  # An unanswered question about the OPEN ATTEMPT still blocks: precedence puts the owner ahead of
  # every automatic action, so replay must not quietly continue the turn it asked about.
  v2_expect_live "an unanswered question about the open attempt blocks it too" \
    awaiting-owner-attempt AWAITING_OWNER

  # --- forged record sets that must fail CLOSED ---------------------------------------------------
  # Each of these classified cleanly at exit 0 before the close/owner validation stage existed. They
  # are live topics because that is the only way to prove it: every one is an otherwise ordinary
  # topic, and the defect is in what the records CLAIM about each other.

  # The close arm outranks turn state, so a close over a live attempt silently ends its lease.
  v2_expect_live_violation "a close may not be written over a live open attempt" \
    close-over-live-attempt CLOSE_PRECONDITION
  # The branch-at-final postcondition compares the branch against the close's OWN claim, so an
  # unchecked claim launders an unexplained tip into CLOSED -- the state the deployment gate trusts.
  v2_expect_live_violation "a close's final SHA must be the record-derived accepted SHA" \
    close-forged-final-sha CLOSE_SHA_MISMATCH
  # One answer marking two questions answered makes an unanswered owner question invisible, and the
  # topic then reports IDLE -- "safe to dispatch" into a topic the owner is blocking.
  v2_expect_live_violation "a question_id is unique" \
    duplicate-question-id QUESTION_DUP
  # Two attempts believing they hold the exclusive worktree lease is the design's named failure #1.
  v2_expect_live_violation "only the newest assignment may be open" \
    two-open-attempts OPEN_NOT_NEWEST
  # close < question < answer, in full: a cancel ordered before its own question would otherwise
  # dissolve a durable close boundary and reopen dispatch.
  v2_expect_live_violation "a cancel-close cannot precede its own question" \
    cancel-before-question LINK_ORDER
  # A no-op is stationary BY DEFINITION. Naming a drifted tip turns an alarm into a routine
  # remediation, and the quarantine arm believes the record.
  v2_expect_live_violation "a REJECTED no-op may name only its own base" \
    forged-no-op RESULT_SHA_RULE
  v2_expect_live_violation "a REVIEW turn cannot move the tip" \
    review-moved-tip RESULT_SHA_RULE
  # A timeout is terminal only after its boundary is committed, or the durable fence is optional.
  v2_expect_live_violation "a timeout result requires its committed fence" \
    timeout-without-fence REASON_CONTRADICTED
  # Counting a fence is not ordering one.
  v2_expect_live_violation "a timeout result cannot precede its own fence" \
    fence-after-timeout-result REASON_CONTRADICTED
  # A result claiming the owner confirmed termination must cite an answer that authorized THAT.
  v2_expect_live_violation "a result must cite an answer that authorized its own reason" \
    result-cites-wrong-answer OWNER_ANSWER_MISMATCH
  # A receipt asserting owner-answer provenance must name the answer, or it slips past the binding
  # stage entirely while claiming the owner materialized it.
  v2_expect_live_violation "a receipt claiming owner-answer provenance must cite it" \
    receipt-claims-owner-answer MISSING_KEY
  # Resolving a reference and checking arithmetic is not ordering. A fence at a lower record_seq
  # than its own receipt fences a delivery the record had not yet made durable.
  v2_expect_live_violation "a fence must follow the receipt it fences" \
    fence-before-dispatch FENCE_ORDER

  # The design's OWN authorized lifecycle, which was unrecordable: a clean stationary fenced
  # ack-timeout attempt terminates ABORTED: ack-timeout with ack_ref: null, because such an attempt
  # has no ACK by definition. Fail-closed is still wrong when it forbids the documented path.
  v2_expect_live "a fenced ack-timeout attempt can terminate" ack-timeout-terminal IDLE
fi

# --- render: deterministic, committed-only, and never destructive -------------------------------------
if v2_group render; then
  v2_case_render() {
    v2_t="$(v2_make_live idle)" || { v2_nok "render is byte-stable across runs" "cannot build live topic"; return; }

    # --check must never modify the topic. A validator that writes while reporting cannot be run
    # safely against a live record repository.
    v2_before="$(git -C "$v2_t" status --porcelain)"
    "$V2_VALIDATE" --check "$v2_t" >/dev/null 2>&1
    if [ "$(git -C "$v2_t" status --porcelain)" = "$v2_before" ]; then
      v2_ok "--check does not modify the topic"
    else
      v2_nok "--check does not modify the topic" "the working tree changed during --check"
    fi

    "$V2_VALIDATE" --render "$v2_t" >"$V2_OUT" 2>&1 \
      || { v2_nok "render is byte-stable across runs" "first render failed: $(sed -n '1p' "$V2_OUT")"; return; }
    cp "$v2_t/THREAD.md" "$V2_TMP/thread.first" || { v2_nok "render is byte-stable across runs" "cannot copy"; return; }
    "$V2_VALIDATE" --render "$v2_t" >"$V2_OUT" 2>&1 \
      || { v2_nok "render is byte-stable across runs" "second render failed"; return; }
    if cmp -s "$V2_TMP/thread.first" "$v2_t/THREAD.md"; then
      v2_ok "render is byte-stable across runs"
    else
      v2_nok "render is byte-stable across runs" "two consecutive renders differ"
    fi

    # Ordering is by record_seq, the ordering authority — not by timestamp, which is display-only and
    # may repeat.
    if [ "$(grep -c '^---8<---' "$v2_t/THREAD.md")" -ge 7 ]; then
      v2_ok "every record appears in the rendered thread"
    else
      v2_nok "every record appears in the rendered thread" "only $(grep -c '^---8<---' "$v2_t/THREAD.md") sections"
    fi

    # A failed render must PRESERVE the previous THREAD.md rather than publish a truncated one.
    cp "$v2_t/THREAD.md" "$V2_TMP/thread.good" || return
    chmod a-w "$v2_t" 2>/dev/null
    "$V2_VALIDATE" --render "$v2_t" >"$V2_OUT" 2>&1
    v2_rc=$?
    chmod u+w "$v2_t" 2>/dev/null
    if [ "$v2_rc" -ne 0 ] && cmp -s "$V2_TMP/thread.good" "$v2_t/THREAD.md"; then
      v2_ok "a failed render leaves the previous THREAD.md intact"
    elif [ "$v2_rc" -eq 0 ]; then
      v2_nok "a failed render leaves the previous THREAD.md intact" "the render unexpectedly succeeded on an unwritable topic"
    else
      v2_nok "a failed render leaves the previous THREAD.md intact" "THREAD.md was modified by a failed render"
    fi
  }
  v2_case_render

  # A report body containing record framing must be QUOTED in the thread, never parsed as control
  # data — otherwise a participant's report could inject a record into the rendered history.
  v2_case_render_quotes_artifacts() {
    v2_n="rendered report bytes are quoted, not parsed as records"
    v2_t="$(v2_materialize "$V2_FIXTURES/capture/framing-in-body")" || { v2_nok "$v2_n" "materialize failed"; return; }
    "$V2_VALIDATE" --render "$v2_t" >"$V2_OUT" 2>&1 || { v2_nok "$v2_n" "render failed"; return; }
    if grep -q '^> kind: result$' "$v2_t/THREAD.md" && ! grep -q '^kind: result$' "$v2_t/THREAD.md"; then
      v2_ok "$v2_n"
    else
      v2_nok "$v2_n" "the artifact's framing was not quoted in THREAD.md"
    fi
  }
  v2_case_render_quotes_artifacts
fi

# --- templates: the canonical bodies instantiate into a VALID topic ------------------------------------
# Moved here from the v1 harness in Task 4. A template is a contract with whoever fills it in: if the
# canonical body cannot be instantiated into a topic the validator accepts, every agent following the
# manual produces rejected records. Both halves matter — the validator must ACCEPT the result, and no
# `{{TOKEN}}` may survive, because an unresolved token is a field nobody filled that still looks
# filled. Each later task extends this with the template it adds.
if v2_group templates; then
  v2_case_templates() {
    v2_n_valid="every record template instantiates into a valid v2 topic"
    v2_n_token="no {{TOKEN}} survives template instantiation"
    v2_tpl="$HERE/../../templates"
    v2_t="$(mktemp -d "$V2_TMP/templated.XXXXXX")" || { v2_nok "$v2_n_valid" "temp failed"; return; }
    mkdir -p "$v2_t/turns" || { v2_nok "$v2_n_valid" "cannot create turns/"; return; }

    # Shared substitutions. The arithmetic is the same as common-valid's, so the materialized bounds
    # are consistent by construction rather than by luck.
    v2_sub() {
      sed -e 's/{{TOPIC_ID}}/templated/' \
          -e 's/{{PARTICIPANT_START_MODE}}/owner-manual/' \
          -e 's/{{PARTICIPANT_SELECTION_SOURCE}}/initial-prompt/' \
          -e 's/{{BASE_SHA}}/1111111111111111111111111111111111111111/' \
          -e 's|{{BASE_REF}}|origin/dev|' \
          -e 's|{{SESSION_BRANCH}}|pair/templated|' \
          -e 's|{{SESSION_WORKTREE}}|/private/tmp/wt/templated|' \
          -e 's|{{WORK_REPO_COMMON_DIR}}|/private/tmp/repo/.git|' \
          -e 's|{{SCOPE}}|src/ docs/|' \
          -e 's/{{PROFILE_ID}}/python-pinned/' -e 's/{{LOCK_IDENTITY}}/sha256:deadbeef/' \
          -e 's/{{BOOTSTRAP_COMMAND}}/uv sync --frozen/' \
          -e 's/{{VERIFICATION_COMMAND}}/uv run pytest -q/' \
          -e 's/{{REQUIRED_TOOLS}}/python 3.12.4/' \
          -e 's/{{REQUIRED_ENVIRONMENT_NAMES}}/TEST_APP_DATABASE_URL_PG/' \
          -e 's/{{TURN_KIND}}/NORMAL/' -e 's/{{TURN_ID}}/0001/' -e 's/{{ATTEMPT_ID}}/01/' \
          -e 's/{{AGENT_ID}}/agent-a/' \
          -e 's/{{RECORDED_AT}}/2026-08-14T10:00:00Z/' \
          "$@"
    }
    v2_sub "$v2_tpl/TOPIC.md" >"$v2_t/TOPIC.md" || { v2_nok "$v2_n_valid" "cannot instantiate TOPIC.md"; return; }

    v2_sub -e 's/{{RECORD_SEQ}}/0001/' -e 's/{{RECORDED_EPOCH}}/1000/' \
           -e 's/{{ADMISSION_ID}}/adm-0001/' -e 's/{{JOIN_MODE}}/owner-manual/' \
           -e 's/{{TRANSPORT}}/human-relay/' -e 's/{{CAPABILITY}}/writes-repo-only/' \
           -e 's/{{WORKTREE_VISIBLE}}/true/' -e 's/{{DURABLE_ADDRESS_KIND}}/human-relay/' \
           -e 's/{{DURABLE_ADDRESS}}/owner-relay-desk/' -e 's/{{SEARCHABILITY}}/unsearchable/' \
           -e 's/{{TOKEN_SEARCH_RECIPE_REF}}/null/' -e 's/{{REPORT_CHANNEL}}/human-relay/' \
           -e 's/{{ACK_EVIDENCE_CLASS}}/human-relayed/' \
           -e 's/{{RECEIPT_COMMIT_TIMEOUT_SECONDS}}/300/' -e 's/{{DEFAULT_ACK_TIMEOUT_SECONDS}}/600/' \
           "$v2_tpl/admission.md" >"$v2_t/turns/0001-admission.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0002/' -e 's/{{RECORDED_EPOCH}}/1010/' \
           -e 's/{{ADMISSION_REF}}/0001-admission.md/' \
           -e 's/{{ACK_TIMEOUT_SECONDS}}/600/' -e 's/{{WORK_TIMEOUT_SECONDS}}/3600/' \
           -e 's/{{VERIFICATION_PROFILE_ID}}/null/' \
           "$v2_tpl/assignment.md" >"$v2_t/turns/0002-t0001-a01-assignment.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0003/' -e 's/{{RECORDED_EPOCH}}/1020/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{IDEMPOTENCY_TOKEN}}/tok-0001/' -e 's/{{ADMISSION_REF}}/0001-admission.md/' \
           -e 's/{{EXPECTED_DISPATCH_REF}}/0004-t0001-a01-dispatch.md/' \
           -e 's/{{RECEIPT_COMMIT_TIMEOUT_SECONDS}}/300/' -e 's/{{RECEIPT_COMMIT_BY_EPOCH}}/1320/' \
           "$v2_tpl/intent.md" >"$v2_t/turns/0003-t0001-a01-intent.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0004/' -e 's/{{RECORDED_EPOCH}}/1030/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{TRANSPORT}}/human-relay/' -e 's/{{JOB_ID}}/job-0001/' \
           -e 's/{{INTENT_REF}}/0003-t0001-a01-intent.md/' -e 's/{{ADMISSION_REF}}/0001-admission.md/' \
           -e 's/{{DISPATCHED_EPOCH}}/1030/' -e 's/{{ACK_DUE_EPOCH}}/1630/' \
           -e 's/{{RECEIPT_SOURCE}}/direct/' \
           "$v2_tpl/dispatch.md" >"$v2_t/turns/0004-t0001-a01-dispatch.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0005/' -e 's/{{RECORDED_EPOCH}}/1040/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{INTENT_REF}}/0003-t0001-a01-intent.md/' \
           -e 's/{{DISPATCH_REF}}/0004-t0001-a01-dispatch.md/' \
           -e 's/{{ADMISSION_REF}}/0001-admission.md/' \
           -e 's/{{JOB_ID}}/job-0001/' -e 's/{{IDEMPOTENCY_TOKEN}}/tok-0001/' \
           -e 's/{{OBSERVED_HEAD}}/1111111111111111111111111111111111111111/' \
           -e 's/{{PREFLIGHT_CLEAN}}/true/' -e 's/{{RELAYED_BASE_SHA}}/null/' \
           -e 's/{{ACK_EVIDENCE_CLASS}}/human-relayed/' \
           -e 's/{{ACK_CAPTURED_EPOCH}}/1040/' -e 's/{{WORK_DUE_EPOCH}}/4640/' \
           "$v2_tpl/ack.md" >"$v2_t/turns/0005-t0001-a01-ack.md"

    # The capture's manifests are COMPUTED from the artifact this case writes, not typed, so the
    # instantiated template cannot claim a manifest its own bytes do not have.
    mkdir -p "$v2_t/artifacts/t0001-a01"
    printf 'Templated report.\n' >"$v2_t/artifacts/t0001-a01/report.md"
    v2_art="$v2_t/artifacts/t0001-a01/report.md"
    v2_bc="$(LC_ALL=C wc -c <"$v2_art" | tr -d ' ')"
    v2_sh="$(shasum -a 256 "$v2_art" | awk '{print $1}')"
    v2_sub -e 's/{{RECORD_SEQ}}/0006/' -e 's/{{RECORDED_EPOCH}}/1050/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{DISPATCH_REF}}/0004-t0001-a01-dispatch.md/' \
           -e 's/{{ACK_REF}}/0005-t0001-a01-ack.md/' \
           -e 's|{{ARTIFACT_REF}}|artifacts/t0001-a01/report.md|' \
           -e "s/{{AUTHOR_BYTE_COUNT}}/$v2_bc/" -e "s/{{AUTHOR_SHA256}}/$v2_sh/" \
           -e "s/{{OBSERVED_BYTE_COUNT}}/$v2_bc/" -e "s/{{OBSERVED_SHA256}}/$v2_sh/" \
           -e 's/{{TRAILING_NEWLINE}}/present/' -e 's/{{REPORT_CHANNEL}}/human-relay/' -e 's/{{CAPTURED_EPOCH}}/1050/' \
           "$v2_tpl/result-capture.md" >"$v2_t/turns/0006-t0001-a01-result-capture.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0007/' -e 's/{{RECORDED_EPOCH}}/1060/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{DISPATCH_REF}}/0004-t0001-a01-dispatch.md/' \
           -e 's/{{ACK_REF}}/0005-t0001-a01-ack.md/' \
           -e 's/{{RESULT_CAPTURE_REF}}/0006-t0001-a01-result-capture.md/' \
           -e 's/{{STATUS}}/VERIFIED/' -e 's/{{REASON}}//' \
           -e 's/{{RESULT_SHA}}/2222222222222222222222222222222222222222/' \
           -e 's/{{OBSERVED_AT}}/2026-08-14T10:01:00Z/' \
           "$v2_tpl/result.md" >"$v2_t/turns/0007-t0001-a01-result.md"

    # EVERY kind's template is instantiated, including the owner/close/fence/late ones. When those
    # schemas were no-op stubs, instantiating only the kinds that HAD schemas made the stubs
    # self-masking: the gate passed because nothing it built could exercise them.
    v2_sub -e 's/{{RECORD_SEQ}}/0008/' -e 's/{{RECORDED_EPOCH}}/1070/' \
           -e 's/{{TRIGGER}}/work-timeout/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{DISPATCH_REF}}/0004-t0001-a01-dispatch.md/' \
           -e 's/{{ACK_REF}}/0005-t0001-a01-ack.md/' \
           -e 's/{{JOB_ID}}/job-0001/' \
           -e 's/{{DUE_EPOCH}}/4640/' -e 's/{{OBSERVED_EPOCH}}/4700/' \
           "$v2_tpl/fence-initiated.md" >"$v2_t/turns/0008-t0001-a01-fence-initiated.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0009/' -e 's/{{RECORDED_EPOCH}}/1080/' \
           -e 's/{{ASSIGNMENT_REF}}/0002-t0001-a01-assignment.md/' \
           -e 's/{{NAMED_SHA}}/null/' \
           "$v2_tpl/late.md" >"$v2_t/turns/0009-t0001-a01-late-01.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0010/' -e 's/{{RECORDED_EPOCH}}/1090/' \
           -e 's/{{QUESTION_ID}}/q-1/' -e 's/{{BLOCKS}}/general/' \
           "$v2_tpl/owner-question.md" >"$v2_t/turns/0010-owner-question.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0011/' -e 's/{{RECORDED_EPOCH}}/1100/' \
           -e 's/{{QUESTION_REF}}/q-1/' -e 's/{{ACTION}}/record-decision/' \
           "$v2_tpl/owner-answer.md" >"$v2_t/turns/0011-owner-answer.md"

    v2_sub -e 's/{{RECORD_SEQ}}/0012/' -e 's/{{RECORDED_EPOCH}}/1110/' \
           -e 's/{{CLOSE_ID}}/close-0001/' \
           -e 's/{{FINAL_ACCEPTED_SHA}}/2222222222222222222222222222222222222222/' \
           "$v2_tpl/close.md" >"$v2_t/turns/0012-close.md"

    if grep -rl '{{[A-Z][A-Z0-9_]*}}' "$v2_t" >/dev/null 2>&1; then
      v2_nok "$v2_n_token" "surviving token in $(grep -rl '{{[A-Z][A-Z0-9_]*}}' "$v2_t" | tr '\n' ' ')"
    else
      v2_ok "$v2_n_token"
    fi

    git -C "$v2_t" init -q && git -C "$v2_t" config user.name v2-test \
      && git -C "$v2_t" config user.email v2@test && git -C "$v2_t" add -A \
      && git -C "$v2_t" commit -qm templated \
      || { v2_nok "$v2_n_valid" "cannot commit the instantiated topic"; return; }
    if "$V2_VALIDATE" --check "$v2_t" >"$V2_OUT" 2>&1; then
      v2_ok "$v2_n_valid"
    else
      v2_nok "$v2_n_valid" "validator refused the instantiated templates: $(sed -n '1p' "$V2_OUT")"
    fi
  }
  v2_case_templates
fi

printf '\n%s passed, %s failed\n' "$V2_PASS" "$V2_FAIL"
# A run that asserted nothing is a failure, not a pass. Without this, a group whose cases were
# deleted, guarded out, or never written reports success and the coverage loss is invisible.
if [ "$((V2_PASS + V2_FAIL))" -eq 0 ]; then
  printf 'FATAL: the run asserted nothing%s\n' "${V2_ONLY:+ (group $V2_ONLY)}" >&2
  exit 3
fi
[ "$V2_FAIL" -eq 0 ]
