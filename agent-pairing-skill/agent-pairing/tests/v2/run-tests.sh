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
V2_LAST_TOPIC=""

V2_GROUPS="version common admission clocks ack capture fence classification precedence render"
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
fi

printf '\n%s passed, %s failed\n' "$V2_PASS" "$V2_FAIL"
[ "$V2_FAIL" -eq 0 ]
