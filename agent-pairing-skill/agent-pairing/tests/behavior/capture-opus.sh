#!/bin/bash
# bash 3.2 compatible.
#
#   capture-opus.sh --manual-version v1|v2 --primary-skill FILE --runbook FILE \
#                   --participant-skill FILE --cases DIRECTORY --output FILE
#
# An OPERATOR step, never a gate step. `run-tests.sh` validates the recorded artifacts and never
# invokes a model, so the package gate stays deterministic and runnable offline. This script is what
# an operator runs, by hand, to produce those artifacts in the first place.
#
# It concatenates the three manuals and the sorted case files into one checked temporary prompt,
# instructs the reviewer to answer all fifteen rubric cases without tools, and makes ONE
# non-interactive call.
#
# EVERY CLI FLAG IS VERIFIED AGAINST `claude --help` AT EXECUTION TIME, below. Flags move; a baked-in
# flag string that silently stopped meaning what it meant would produce a capture that looks right
# and was taken under different conditions. If a capability this script needs has no flag, it says so
# and stops — capture the evaluation manually and paste the verbatim response into the artifact
# rather than inventing a flag.
set -u

MANUAL_VERSION="" PRIMARY="" RUNBOOK="" PARTICIPANT="" CASES="" OUTPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --manual-version)     MANUAL_VERSION="${2:-}"; shift 2 ;;
    --primary-skill)      PRIMARY="${2:-}"; shift 2 ;;
    --runbook)            RUNBOOK="${2:-}"; shift 2 ;;
    --participant-skill)  PARTICIPANT="${2:-}"; shift 2 ;;
    --cases)              CASES="${2:-}"; shift 2 ;;
    --output)             OUTPUT="${2:-}"; shift 2 ;;
    *) echo "usage: capture-opus.sh --manual-version v1|v2 --primary-skill FILE --runbook FILE --participant-skill FILE --cases DIR --output FILE" >&2; exit 3 ;;
  esac
done
case "$MANUAL_VERSION" in v1|v2) ;; *) echo "FATAL: --manual-version must be v1 or v2" >&2; exit 3 ;; esac
for f in "$PRIMARY" "$RUNBOOK" "$PARTICIPANT"; do
  [ -f "$f" ] || { echo "FATAL: not a file: $f" >&2; exit 3; }
done
[ -d "$CASES" ] || { echo "FATAL: not a directory: $CASES" >&2; exit 3; }
[ -n "$OUTPUT" ] || { echo "FATAL: --output is required" >&2; exit 3; }

TMP="$(mktemp -d /tmp/agent-pairing-capture.XXXXXX)" \
  || { echo "FATAL: temp allocation failed" >&2; exit 3; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "FATAL: temp allocation produced no directory" >&2; exit 3; }
trap 'case "$TMP" in /tmp/agent-pairing-capture.?*) rm -rf "$TMP";; esac' EXIT

# --- flag verification, at execution time ------------------------------------------------------------
CLI=claude
command -v "$CLI" >/dev/null 2>&1 || {
  echo "FATAL: '$CLI' is not on PATH. Capture the evaluation manually and paste the verbatim" >&2
  echo "       response into $OUTPUT rather than inventing an invocation." >&2
  exit 3
}
"$CLI" --help >"$TMP/help" 2>&1 || { echo "FATAL: '$CLI --help' failed" >&2; exit 3; }

MISSING=""
for flag in --print --model --disallowedTools --strict-mcp-config; do
  grep -q -- "$flag" "$TMP/help" || MISSING="$MISSING $flag"
done
if [ -n "$MISSING" ]; then
  echo "FATAL: '$CLI --help' does not report:$MISSING" >&2
  echo "       Do NOT guess a replacement. Capture the evaluation manually and paste the verbatim" >&2
  echo "       response into $OUTPUT, noting in the artifact that it was captured by hand." >&2
  exit 3
fi

# --- the prompt ---------------------------------------------------------------------------------------
{
  printf 'You are evaluating an agent protocol'\''s MANUALS. Answer strictly from the text supplied\n'
  printf 'below. Do not use tools. Do not consult any repository. If the manuals do not settle a\n'
  printf 'question, say so explicitly rather than inferring what a reasonable agent would do — a\n'
  printf 'guess recorded as an observation is what this evaluation exists to prevent.\n\n'
  printf 'Manual version under evaluation: %s\n\n' "$MANUAL_VERSION"
  printf 'Answer EVERY case B01 through B15. For each, give:\n'
  printf '  - the action you would take, in one line;\n'
  printf '  - the VERBATIM span of the manual your answer rests on;\n'
  printf '  - PASS or FAIL against what the case asks for.\n\n'
  printf '===== PRIMARY MANUAL (%s) =====\n\n' "$MANUAL_VERSION"
  cat "$PRIMARY"
  printf '\n\n===== RUNBOOK (%s) =====\n\n' "$MANUAL_VERSION"
  cat "$RUNBOOK"
  printf '\n\n===== PARTICIPANT MANUAL (%s) =====\n\n' "$MANUAL_VERSION"
  cat "$PARTICIPANT"
  printf '\n\n===== CASES =====\n\n'
  for c in $(find "$CASES" -name '*.md' | LC_ALL=C sort); do
    cat "$c"; printf '\n'
  done
} >"$TMP/prompt" || { echo "FATAL: cannot assemble the prompt" >&2; exit 3; }

# --- one non-interactive, tools-disabled call ------------------------------------------------------------
# The tool list is denied explicitly rather than assumed off: the evaluation is about what the
# MANUALS say, and a model that went and read the repository would be answering a different question.
"$CLI" --print \
  --model opus \
  --strict-mcp-config \
  --disallowedTools "Bash Read Write Edit Glob Grep WebFetch WebSearch Task NotebookEdit" \
  <"$TMP/prompt" >"$TMP/response" 2>"$TMP/err"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "FATAL: the model call failed (exit $RC):" >&2
  sed -n '1,20p' "$TMP/err" >&2
  echo "       Capture the evaluation manually and paste the verbatim response into $OUTPUT." >&2
  exit 3
fi
[ -s "$TMP/response" ] || { echo "FATAL: the model returned no output" >&2; exit 3; }

# --- write the artifact skeleton ---------------------------------------------------------------------------
# The observed response is preserved as FENCED text. The deterministic per-case disposition is kept
# SEPARATE and is written by the operator from that response — inferring prose in place of the
# historical failures is exactly what this artifact exists to prevent.
{
  printf '# Behavioral evaluation — %s manuals\n\n' "$MANUAL_VERSION"
  printf 'Captured by `capture-opus.sh` on the manuals as of this commit. The response below is\n'
  printf 'verbatim. The per-case dispositions beneath it are written by the operator FROM that\n'
  printf 'response, and each cites the span it rests on.\n\n'
  printf 'Sanitize paths, tokens and environment values before committing.\n\n'
  printf '## Observed response (verbatim)\n\n'
  printf '````text\n'
  cat "$TMP/response"
  printf '\n````\n\n'
  printf '## Dispositions\n\n'
  printf '<!-- One block per case, per rubric.md. Fill from the response above. -->\n'
} >"$OUTPUT" || { echo "FATAL: cannot write $OUTPUT" >&2; exit 3; }

printf 'captured %s manuals -> %s\n' "$MANUAL_VERSION" "$OUTPUT"
printf 'NEXT: write the fifteen disposition blocks from the response, then run:\n'
printf '  /bin/bash %s/run-tests.sh\n' "$(cd "$(dirname "$0")" && pwd)"
