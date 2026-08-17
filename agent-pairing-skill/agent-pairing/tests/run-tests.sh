#!/bin/bash
# bash 3.2 compatible. The package gate. Run from ANY directory, including a neutral non-repository
# one: /bin/bash agent-pairing/tests/run-tests.sh
#
# It runs the frozen v1 regression suite and the v2 suite. Later tasks append the participant,
# behavioral, and example gates. A suite that fails stops the gate with that suite's exit status.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$HERE/run-v1-tests.sh" || exit $?
/bin/bash "$HERE/v2/run-tests.sh" || exit $?
