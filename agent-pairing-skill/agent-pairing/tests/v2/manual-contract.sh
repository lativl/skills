#!/bin/bash
# bash 3.2 compatible. Run: /bin/bash agent-pairing/tests/v2/manual-contract.sh
#
# The manuals carry rules the validator deliberately does NOT enforce. In v2.0 the severity policy is
# primary-enforced: the validator never parses findings prose and never claims a findings ledger. So
# the only thing that can hold those rules in place is a test that the text still says them.
#
# This is a contract over the MANUALS, not over records. It asserts that the primary manual and the
# onboarding projection literally state the environment-parity rule and the severity/verdict mapping,
# and it instantiates a topic carrying a verification profile to prove the template can express one
# with no token left unresolved.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../../SKILL.md"
RUNBOOK="$HERE/../../RUNBOOK.md"
ONBOARDING="$HERE/../../templates/onboarding.md"
TOPIC_TPL="$HERE/../../templates/TOPIC.md"
ASSIGNMENT_TPL="$HERE/../../templates/assignment.md"
VALIDATE="$HERE/../../scripts/validate.sh"

MC_TMP="$(mktemp -d /tmp/agent-pairing-manual-contract.XXXXXX)" \
  || { echo "FATAL: temp allocation failed" >&2; exit 3; }
[ -n "$MC_TMP" ] && [ -d "$MC_TMP" ] || { echo "FATAL: temp allocation produced no directory" >&2; exit 3; }
mc_cleanup() { case "$MC_TMP" in /tmp/agent-pairing-manual-contract.?*) rm -rf "$MC_TMP" ;; esac; }
trap mc_cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
nok() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

require_text() { # <name> <file> <literal>
  if grep -Fq "$3" "$2"; then ok "$1"; else nok "$1" "missing from $(basename "$2"): $3"; fi
}

# --- the environment-parity rule ------------------------------------------------------------------------
# An unpinned dependency mismatch is a fact about the machine that ran the check, not about the
# snapshot under review. Without this rule stated, a reviewer rejects a correct snapshot because its
# own environment drifted -- which is how a verification gate stops meaning anything.
require_text "the manual states that unpinned red is an executor fact" \
  "$SKILL" "unpinned red is a fact about the executor environment, not the snapshot"

# --- the three severities and the binary verdict ---------------------------------------------------------
for sev in BLOCKING GATE NONBLOCKING; do
  require_text "the manual defines severity: $sev" "$SKILL" "$sev"
done
require_text "the manual defines PASS exactly" \
  "$SKILL" "PASS = no BLOCKING findings and every GATE has tracker_ref plus owner"
require_text "the manual defines FAIL exactly" \
  "$SKILL" "FAIL = any BLOCKING finding or any unmaterialized GATE"
require_text "the manual states that v2.0 severity enforcement is the primary's, not the validator's" \
  "$SKILL" "the validator does not parse findings prose"

# --- the onboarding projection carries the same contract to the participant --------------------------------
require_text "onboarding carries the environment profile" "$ONBOARDING" "verification_profile_id"
require_text "onboarding requires captured output with the exact command" "$ONBOARDING" "captured output"

# --- a topic can actually express a verification profile ---------------------------------------------------
# Instantiating it is the point: a profile the template cannot express is a rule the manual states and
# nothing can follow.
mc_topic="$MC_TMP/topic"
mkdir -p "$mc_topic/turns" || { echo "FATAL: cannot create the topic" >&2; exit 3; }

sed -e 's/{{TOPIC_ID}}/profiled/' \
    -e 's/{{PARTICIPANT_START_MODE}}/owner-manual/' \
    -e 's/{{PARTICIPANT_SELECTION_SOURCE}}/initial-prompt/' \
    -e 's/{{BASE_SHA}}/1111111111111111111111111111111111111111/' \
    -e 's|{{BASE_REF}}|refs/heads/main|' \
    -e 's|{{SESSION_BRANCH}}|pair/profiled|' \
    -e 's|{{SESSION_WORKTREE}}|/private/tmp/agent-pairing-profiled/wt|' \
    -e 's|{{WORK_REPO_COMMON_DIR}}|/private/tmp/agent-pairing-profiled/repo/.git|' \
    -e 's/{{PROFILE_ID}}/python-pinned/' \
    -e 's/{{LOCK_IDENTITY}}/sha256:3f1c2b4a5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708/' \
    -e 's/{{BOOTSTRAP_COMMAND}}/uv sync --frozen/' \
    -e 's/{{VERIFICATION_COMMAND}}/uv run pytest -q/' \
    -e 's/{{REQUIRED_TOOLS}}/python 3.12.4, uv 0.4.20/' \
    -e 's/{{REQUIRED_ENVIRONMENT_NAMES}}/TEST_APP_DATABASE_URL_PG TEST_SYSTEM_DATABASE_URL_PG/' \
    "$TOPIC_TPL" >"$mc_topic/TOPIC.md"

if grep -q '{{[A-Z][A-Z0-9_]*}}' "$mc_topic/TOPIC.md"; then
  nok "the instantiated profile topic has no unresolved token" \
      "$(grep -o '{{[A-Z][A-Z0-9_]*}}' "$mc_topic/TOPIC.md" | tr '\n' ' ')"
else
  ok "the instantiated profile topic has no unresolved token"
fi

for k in profile_id lock_identity bootstrap_command verification_command required_tools required_environment_names; do
  require_text "the profile body carries $k" "$mc_topic/TOPIC.md" "$k:"
done

# A secret VALUE must never be recordable by following the template. Only names are.
if grep -qE '^(password|token|secret|api_key):' "$mc_topic/TOPIC.md"; then
  nok "the profile records no secret values" "a secret-looking key is present"
else
  ok "the profile records no secret values"
fi

# --- the assignment binds a profile, or the literal null for a non-verification turn -----------------------
require_text "the assignment template binds a verification profile" \
  "$ASSIGNMENT_TPL" "verification_profile_id:"

# The instantiated topic must still validate: a profile section is BODY text, and body text is never
# parsed as control data.
sed -e 's/{{RECORD_SEQ}}/0001/' -e 's/{{TOPIC_ID}}/profiled/' -e 's/{{RECORDED_EPOCH}}/1000/' \
    -e 's/{{RECORDED_AT}}/2026-08-14T10:00:00Z/' \
    -e 's/{{ADMISSION_ID}}/adm-0001/' -e 's/{{AGENT_ID}}/agent-a/' \
    -e 's/{{JOIN_MODE}}/owner-manual/' -e 's/{{TRANSPORT}}/human-relay/' \
    -e 's/{{CAPABILITY}}/writes-repo-only/' -e 's/{{WORKTREE_VISIBLE}}/true/' \
    -e 's/{{DURABLE_ADDRESS_KIND}}/human-relay/' -e 's/{{DURABLE_ADDRESS}}/owner-relay-desk/' \
    -e 's/{{SEARCHABILITY}}/unsearchable/' -e 's/{{TOKEN_SEARCH_RECIPE_REF}}/null/' \
    -e 's/{{REPORT_CHANNEL}}/human-relay/' -e 's/{{ACK_EVIDENCE_CLASS}}/human-relayed/' \
    -e 's/{{RECEIPT_COMMIT_TIMEOUT_SECONDS}}/300/' -e 's/{{DEFAULT_ACK_TIMEOUT_SECONDS}}/600/' \
    "$HERE/../../templates/admission.md" >"$mc_topic/turns/0001-admission.md"

git -C "$mc_topic" init -q \
  && git -C "$mc_topic" config user.name mc && git -C "$mc_topic" config user.email mc@test \
  && git -C "$mc_topic" add -A && git -C "$mc_topic" commit -qm profiled \
  || { echo "FATAL: cannot commit the instantiated topic" >&2; exit 3; }

if /bin/bash "$VALIDATE" --check "$mc_topic" >"$MC_TMP/out" 2>&1; then
  ok "a topic carrying a verification profile validates"
else
  nok "a topic carrying a verification profile validates" "$(sed -n '1p' "$MC_TMP/out")"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$((PASS + FAIL))" -gt 0 ] || { echo "FATAL: the contract asserted nothing" >&2; exit 3; }
[ "$FAIL" -eq 0 ]
