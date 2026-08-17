#!/bin/bash
# bash 3.2 compatible. The package gate. Run from ANY directory, including a neutral non-repository
# one: /bin/bash agent-pairing/tests/run-tests.sh
#
# It runs the frozen v1 regression suite and the v2 suite. Later tasks append the participant,
# behavioral, and example gates. A suite that fails stops the gate with that suite's exit status.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

# --- the frozen v1 gate, pinned by COUNT and not only by "0 failed" ------------------------------------
#
# The plan's Global Constraints froze this gate at `360 passed, 0 failed`. The count is not constant,
# because a handful of v1 cases are DERIVED from shared, non-frozen inputs: one `referenced path
# exists:` assertion per template path named in SKILL.md. Every v2 template SKILL.md mentions adds a
# case, and the constraint's number goes stale.
#
# "0 failed, and each increment accounted for" is not sufficient on its own: a v1 case that is
# silently LOST is exactly as invisible as one gained. So the expected total is pinned here, with a
# ledger entry per increment. A task that adds a template updates both the manual and this number in
# the SAME commit, and a lost case turns the gate red instead of passing quietly.
#
#   360  the frozen baseline recorded before any v2 work
#   +1   Task 3  templates/admission.md         referenced by SKILL.md
#   -2   Task 4  record-template instantiation MOVED to tests/v2 (group `templates`): v2 templates
#                cannot produce a valid V1 topic by construction, so validating them with the v1
#                validator asserted the opposite of the compatibility boundary
#   +1   Task 5  templates/ack.md               referenced by SKILL.md
V1_EXPECTED_PASSES=360

V1_OUT="$(mktemp -t agent-pairing-v1-gate)" \
  || { echo "FATAL: cannot allocate the v1 gate output file" >&2; exit 3; }
trap 'rm -f "$V1_OUT"' EXIT

/bin/bash "$HERE/run-v1-tests.sh" 2>&1 | tee "$V1_OUT"
V1_STATUS=${PIPESTATUS[0]}
[ "$V1_STATUS" -eq 0 ] || exit "$V1_STATUS"

V1_LINE="$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$V1_OUT" | tail -1)"
if [ "$V1_LINE" != "$V1_EXPECTED_PASSES passed, 0 failed" ]; then
  printf 'FATAL: frozen v1 gate expected "%s passed, 0 failed"; got "%s"\n' \
    "$V1_EXPECTED_PASSES" "$V1_LINE" >&2
  printf '       A LOWER count means a v1 case was lost. A HIGHER count means one was added:\n' >&2
  printf '       account for it in the ledger above and update V1_EXPECTED_PASSES in the same commit.\n' >&2
  exit 3
fi

/bin/bash "$HERE/v2/run-tests.sh" || exit $?
/bin/bash "$HERE/v2/manual-contract.sh" || exit $?
/bin/bash "$HERE/../../pair-with-primary/tests/run-tests.sh" || exit $?
