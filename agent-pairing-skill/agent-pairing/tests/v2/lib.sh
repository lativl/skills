#!/bin/bash
# bash 3.2 compatible. Sourced by tests/v2/run-tests.sh — never executed directly.
#
# Every ordinary fixture directory in this suite is an ORDINARY DIRECTORY on disk. The v2 validator
# reads records only from committed Git objects, so a fixture must become a Git record repository
# before it means anything. v2_materialize does exactly that, in a checked temporary directory, so
# the committed-object contract is exercised rather than described.
#
# A fixture may opt out by carrying a `.v2-no-commit` marker file: those cases deliberately leave
# record bytes in the working tree only, which is how UNCOMMITTED_RESIDUE is provoked. A fixture may
# also carry `.v2-setup.sh`, run inside the materialized repository after the seed commit, for cases
# that need extra Git shape (dirty tree, extra commits, a work repository) that files alone cannot
# express.

v2_ok() { V2_PASS=$((V2_PASS + 1)); printf 'ok   %s\n' "$1"; }
v2_nok() { V2_FAIL=$((V2_FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

# Destructive-path guard. This is the ONLY recursive delete in the v2 harness and it refuses any
# path that is not under its required prefix, so an empty variable from a failed allocation reads as
# a loud refusal instead of as `rm -rf /`.
v2_safe_rmdir() { # <path> <required-prefix>
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || { echo "FATAL: v2_safe_rmdir needs <path> <prefix>" >&2; exit 3; }
  case "$1" in "$2"?*) ;; *) echo "FATAL: refusing recursive delete of $1 (not under $2)" >&2; exit 3;; esac
  case "$1" in *..*) echo "FATAL: refusing recursive delete of $1 (contains ..)" >&2; exit 3;; esac
  rm -rf "$1"
}

# Turn a fixture directory into a committed record repository and print its path.
# Every allocation is checked BEFORE the path reaches cp/git, because an unchecked allocation leaves
# an empty variable and the next line reads as `cp -rf fixture/. /`.
v2_materialize() {
  v2_src="$1"
  [ -d "$v2_src" ] || { echo "FATAL: no such fixture: $v2_src" >&2; return 1; }
  v2_dst="$(mktemp -d "$V2_TMP/topic.XXXXXX")" || { echo "FATAL: temp allocation failed under $V2_TMP" >&2; return 1; }
  [ -n "$v2_dst" ] && [ -d "$v2_dst" ] || { echo "FATAL: temp allocation produced no directory" >&2; return 1; }
  cp -rf "$v2_src"/. "$v2_dst"/ || return 1
  git -C "$v2_dst" init -q || return 1
  git -C "$v2_dst" config user.name v2-test || return 1
  git -C "$v2_dst" config user.email v2@test || return 1
  if [ ! -f "$v2_dst/.v2-no-commit" ]; then
    git -C "$v2_dst" add -A || return 1
    git -C "$v2_dst" commit -qm seed || return 1
  else
    rm -f "$v2_dst/.v2-no-commit" || return 1
    # Commit everything EXCEPT the record tree, so `turns/` exists only in the working tree.
    git -C "$v2_dst" add TOPIC.md || return 1
    git -C "$v2_dst" commit -qm seed || return 1
  fi
  if [ -f "$v2_dst/.v2-setup.sh" ]; then
    ( cd "$v2_dst" && /bin/bash ./.v2-setup.sh ) || return 1
  fi
  printf '%s\n' "$v2_dst"
}

# Run the default validator against a materialized fixture. Output (both streams) lands in $V2_OUT
# and the validator's exit status in $V2_RC.
#
# $V2_OUT is TRUNCATED FIRST. Without that, a fixture that fails to materialize returns before the
# validator ever runs, leaving the PREVIOUS case's output in place — and an assertion that greps
# $V2_OUT then passes on a neighbour's evidence. A misspelled fixture path must be a loud failure,
# not a silent green.
v2_run() {
  : >"$V2_OUT" || { echo "FATAL: cannot truncate $V2_OUT" >&2; return 1; }
  V2_RC=127
  v2_topic="$(v2_materialize "$1")" || return 1
  V2_LAST_TOPIC="$v2_topic"
  "$V2_VALIDATE" --check "$v2_topic" >"$V2_OUT" 2>&1
  V2_RC=$?
  return $V2_RC
}

# Assert the validator refuses a fixture with one exact violation code.
#
# Exit 2 is required, not merely "nonzero". Exit 3 is a usage or environment failure and exit 127 is
# a missing validator: neither is a protocol violation, and letting either satisfy this assertion is
# how a suite reports coverage it does not have.
v2_expect_violation() { # <name> <fixture> <code>
  v2_name="$1" v2_fixture="$2" v2_code="$3"
  if v2_run "$V2_FIXTURES/$v2_fixture"; then
    v2_nok "$v2_name" "validator unexpectedly returned zero"
  elif [ "$V2_RC" -ne 2 ]; then
    v2_nok "$v2_name" "expected exit 2 (protocol violation); got $V2_RC: $(sed -n '1p' "$V2_OUT")"
  elif grep -F "VIOLATION $v2_code" "$V2_OUT" >/dev/null; then
    v2_ok "$v2_name"
  else
    v2_nok "$v2_name" "expected VIOLATION $v2_code; got: $(sed -n '1p' "$V2_OUT")"
  fi
}

# Assert the validator refuses a fixture with EXACTLY ONE violation code — the expected one.
#
# One-defect fixtures are only evidence if one defect produces one code. A case that passes because
# the mutation happened to trip three unrelated rules proves nothing about the rule it names, and it
# keeps passing after the rule it names is deleted.
v2_expect_only_violation() { # <name> <fixture> <code>
  v2_name="$1" v2_fixture="$2" v2_code="$3"
  if v2_run "$V2_FIXTURES/$v2_fixture"; then
    v2_nok "$v2_name" "validator unexpectedly returned zero"
    return
  fi
  if [ "$V2_RC" -ne 2 ]; then
    v2_nok "$v2_name" "expected exit 2 (protocol violation); got $V2_RC: $(sed -n '1p' "$V2_OUT")"
    return
  fi
  v2_codes="$(awk '$1 == "VIOLATION" { print $2 }' "$V2_OUT" | LC_ALL=C sort -u | tr '\n' ' ')"
  v2_codes="${v2_codes% }"
  if [ "$v2_codes" = "$v2_code" ]; then
    v2_ok "$v2_name"
  else
    v2_nok "$v2_name" "expected exactly [$v2_code]; got [$v2_codes]"
  fi
}

# Assert the validator accepts a fixture. Used where a task has established a fixture's validity but
# a later task still owns the classification it should produce.
v2_expect_ok() { # <name> <fixture>
  v2_name="$1" v2_fixture="$2"
  if v2_run "$V2_FIXTURES/$v2_fixture"; then
    v2_ok "$v2_name"
  else
    v2_nok "$v2_name" "validator refused a valid fixture (rc $V2_RC): $(sed -n '1p' "$V2_OUT")"
  fi
}

# Assert the validator accepts a fixture and prints one exact classification line.
v2_expect_classification() { # <name> <fixture> <classification>
  v2_name="$1" v2_fixture="$2" v2_class="$3"
  if v2_run "$V2_FIXTURES/$v2_fixture"; then
    if grep -Fx "classification: $v2_class" "$V2_OUT" >/dev/null; then
      v2_ok "$v2_name"
    else
      v2_nok "$v2_name" "expected classification: $v2_class; got: $(grep -m1 '^classification:' "$V2_OUT" || sed -n '1p' "$V2_OUT")"
    fi
  else
    v2_nok "$v2_name" "validator refused a valid fixture: $(sed -n '1p' "$V2_OUT")"
  fi
}

# Assert an exact stdout line from a valid fixture (due epochs, postconditions, and similar output).
v2_expect_line() { # <name> <fixture> <exact-line>
  v2_name="$1" v2_fixture="$2" v2_line="$3"
  if v2_run "$V2_FIXTURES/$v2_fixture"; then
    if grep -Fx "$v2_line" "$V2_OUT" >/dev/null; then
      v2_ok "$v2_name"
    else
      v2_nok "$v2_name" "expected line: $v2_line; output began: $(sed -n '1p' "$V2_OUT")"
    fi
  else
    v2_nok "$v2_name" "validator refused a valid fixture: $(sed -n '1p' "$V2_OUT")"
  fi
}

# Assert invalid CLI usage exits 3 and never reports a protocol violation.
v2_expect_usage() { # <name> [args...]
  v2_name="$1"; shift
  "$V2_VALIDATE" "$@" >"$V2_OUT" 2>&1
  v2_rc=$?
  if [ "$v2_rc" -eq 3 ]; then
    v2_ok "$v2_name"
  else
    v2_nok "$v2_name" "expected exit 3; got $v2_rc: $(sed -n '1p' "$V2_OUT")"
  fi
}
