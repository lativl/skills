#!/bin/bash
# bash 3.2 compatible. Run from ANY directory:
#   /bin/bash agent-pairing/tests/behavior/run-tests.sh
#
# Validates the RECORDED behavioral artifacts. **It never invokes a model**, never reaches the
# network, and never reads a credential — so the package gate stays deterministic and runnable
# offline from a neutral directory. Capturing the artifacts is an operator step (capture-opus.sh).
#
# A gate that called a model would be a gate whose result depended on sampling, on a network, and on
# a bill. It would also be untrustworthy in the one situation it exists for: proving that a change to
# the manuals did not silently undo a behavior.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RUBRIC="$HERE/rubric.md"
BASELINE="$HERE/baseline-v1.md"
ACCEPTED="$HERE/accepted-v2.md"
CASES="$HERE/cases"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
nok() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

ALL_CASES="B01 B02 B03 B04 B05 B06 B07 B08 B09 B10 B11 B12 B13 B14 B15"
# The design's own expectation of what v1 got wrong. B12 is deliberately absent: v1 already had an
# owner-question path for a genuinely unsearchable transport, and a baseline that overstates the old
# defects understates the new ones.
MUST_BE_RED="B05 B06 B07 B08 B09 B10 B11 B13 B14 B15"

for f in "$RUBRIC" "$BASELINE" "$ACCEPTED"; do
  [ -f "$f" ] || { nok "artifact exists: $(basename "$f")" "missing"; continue; }
  ok "artifact exists: $(basename "$f")"
done
[ -d "$CASES" ] && ok "the case directory exists" || nok "the case directory exists" "missing $CASES"

# Every rubric case must have a prompt somewhere in the case files, or the artifact records a
# disposition for a question nobody asked.
for c in $ALL_CASES; do
  if grep -rq "^## $c " "$CASES" 2>/dev/null; then
    ok "case $c has a prompt"
  else
    nok "case $c has a prompt" "no '## $c' heading under cases/"
  fi
done

# Read one case's disposition from an artifact. The format is pinned by rubric.md.
disposition() { # <artifact> <case>
  awk -v c="$2" '
    $1 == "case_id:" && $2 == c { inblock = 1; next }
    inblock && $1 == "case_id:" { exit }
    inblock && $1 == "disposition:" { print $2; exit }
  ' "$1"
}
has_excerpt() { # <artifact> <case>
  awk -v c="$2" '
    $1 == "case_id:" && $2 == c { inblock = 1; next }
    inblock && $1 == "case_id:" { exit }
    inblock && $1 == "evidence_excerpt:" { found = 1 }
    END { exit !found }
  ' "$1"
}

check_artifact() { # <artifact> <label>
  a="$1" label="$2"
  [ -f "$a" ] || return 0

  # Exactly one block per case: no duplicates, none missing. A duplicated case id would let two
  # dispositions disagree and the first one silently win.
  dups="$(grep '^case_id:' "$a" | awk '{print $2}' | LC_ALL=C sort | uniq -d | tr '\n' ' ')"
  if [ -n "$dups" ]; then
    nok "$label: no duplicate case ids" "duplicated: $dups"
  else
    ok "$label: no duplicate case ids"
  fi

  missing=""
  for c in $ALL_CASES; do
    d="$(disposition "$a" "$c")"
    [ -n "$d" ] || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    nok "$label: every rubric case is recorded" "missing:$missing"
  else
    ok "$label: every rubric case is recorded"
  fi

  bad=""
  for c in $ALL_CASES; do
    d="$(disposition "$a" "$c")"
    [ -z "$d" ] && continue
    case "$d" in PASS|FAIL) ;; *) bad="$bad $c=$d" ;; esac
  done
  if [ -n "$bad" ]; then
    nok "$label: every disposition is exactly PASS or FAIL" "$bad"
  else
    ok "$label: every disposition is exactly PASS or FAIL"
  fi

  # A disposition with no verbatim excerpt is an opinion. The point of a captured baseline is that
  # the claim can be re-checked later against what was actually said.
  noev=""
  for c in $ALL_CASES; do
    [ -n "$(disposition "$a" "$c")" ] || continue
    has_excerpt "$a" "$c" || noev="$noev $c"
  done
  if [ -n "$noev" ]; then
    nok "$label: every disposition cites verbatim evidence" "no evidence_excerpt for:$noev"
  else
    ok "$label: every disposition cites verbatim evidence"
  fi

  # The captured model response is preserved as fenced text, separately from the deterministic
  # disposition. Inferring prose in place of the historical failures is exactly what this artifact
  # exists to prevent.
  if grep -q '^```' "$a"; then
    ok "$label: the observed response is preserved verbatim"
  else
    nok "$label: the observed response is preserved verbatim" "no fenced capture block"
  fi
}

check_artifact "$BASELINE" "baseline-v1"
check_artifact "$ACCEPTED" "accepted-v2"

# --- the baseline must actually be a baseline ------------------------------------------------------
if [ -f "$BASELINE" ]; then
  notred=""
  for c in $MUST_BE_RED; do
    [ "$(disposition "$BASELINE" "$c")" = FAIL ] || notred="$notred $c"
  done
  if [ -n "$notred" ]; then
    nok "the v1 baseline is RED where the design says it was" "expected FAIL for:$notred"
  else
    ok "the v1 baseline is RED where the design says it was"
  fi
fi

# --- and v2 must pass all fifteen --------------------------------------------------------------------
if [ -f "$ACCEPTED" ]; then
  notgreen=""
  for c in $ALL_CASES; do
    [ "$(disposition "$ACCEPTED" "$c")" = PASS ] || notgreen="$notgreen $c"
  done
  if [ -n "$notgreen" ]; then
    nok "the v2 manuals pass every rubric case" "not PASS:$notgreen"
  else
    ok "the v2 manuals pass every rubric case"
  fi
fi

# --- the runner must never become a model caller -------------------------------------------------------
# Checked structurally rather than promised in a comment: a gate that reaches the network is a gate
# whose result depends on sampling and on a bill.
#
# EVERY searched term is assembled from fragments and never spelled literally in this file. Written
# out, they would sit in this script, the scan below would match its own source, and the guard would
# fail on itself — a guard firing on its own text is the same defect it exists to catch, wearing the
# opposite sign. The comment above is written to avoid the terms too.
MODEL_CMD="cla""ude"
NET1="cu""rl"; NET2="wg""et"
if grep -Eq "(^|[^[:alnum:]_-])($MODEL_CMD|$NET1|$NET2)([^[:alnum:]_-]|\$)" "$0"; then
  nok "the behavior gate invokes no model and no network" "found a model or network invocation in $0"
else
  ok "the behavior gate invokes no model and no network"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$((PASS + FAIL))" -gt 0 ] || { echo "FATAL: the behavior gate asserted nothing" >&2; exit 3; }
[ "$FAIL" -eq 0 ]
