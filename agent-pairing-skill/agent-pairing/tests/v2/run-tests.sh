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
trap 'v2_safe_rmdir "$V2_TMP" /tmp/agent-pairing-v2-tests.' EXIT

V2_OUT="$V2_TMP/out"
V2_PASS=0
V2_FAIL=0
V2_RC=0
V2_LAST_TOPIC=""

# Only groups that ACTUALLY HAVE CASES are listed. A group name declared before its task implements
# it would answer `0 passed, 0 failed` and exit zero — a suite that runs nothing wearing the costume
# of a suite that passes. Each task appends its own group name here alongside its cases.
V2_GROUPS="version common"
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

printf '\n%s passed, %s failed\n' "$V2_PASS" "$V2_FAIL"
# A run that asserted nothing is a failure, not a pass. Without this, a group whose cases were
# deleted, guarded out, or never written reports success and the coverage loss is invisible.
if [ "$((V2_PASS + V2_FAIL))" -eq 0 ]; then
  printf 'FATAL: the run asserted nothing%s\n' "${V2_ONLY:+ (group $V2_ONLY)}" >&2
  exit 3
fi
[ "$V2_FAIL" -eq 0 ]
