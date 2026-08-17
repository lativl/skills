#!/bin/bash
# bash 3.2 compatible. Run from ANY directory:
#   /bin/bash pair-with-primary/tests/run-tests.sh
#
# A contract over the PARTICIPANT MANUAL. The participant writes no records, so the validator can
# never check its behavior — every rule it follows is prose, and prose with no test decays. These
# assertions are the only thing standing between "the manual says wait for the committed receipt"
# and a manual that quietly says something else.
#
# The v1 behaviors below are not hypothetical. Each is what the seeded manual actually did, and each
# is a defect the accepted design names by hand.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../SKILL.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
nok() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

[ -f "$SKILL" ] || { echo "FATAL: no participant SKILL.md at $SKILL" >&2; exit 3; }

# Executable lines only. The manual EXPLAINS these defects, so a scan that included prose would fire
# on the very sentences that forbid them — a guard matching its own documentation is the same defect
# it is trying to catch, wearing the opposite sign. Only fenced bash blocks are scanned.
CODE="$(awk '/^```bash$/ { c = 1; next } /^```$/ { c = 0; next } c' "$SKILL")"

refuse() { # <name> <extended-regex> <why>
  if printf '%s\n' "$CODE" | grep -Eq "$2"; then
    nok "$1" "$3"
  else
    ok "$1"
  fi
}
require() { # <name> <literal>
  if grep -Fq "$2" "$SKILL"; then ok "$1"; else nok "$1" "the manual does not say: $2"; fi
}
require_code() { # <name> <extended-regex> <why>
  if printf '%s\n' "$CODE" | grep -Eq "$2"; then ok "$1"; else nok "$1" "$3"; fi
}

# --- the v1 behaviors, each individually refused ---------------------------------------------------
# v1 told the participant to report by Git note while the protocol forbade ref updates. A note IS a
# ref update; the two instructions could not both be followed.
refuse "no Git notes" 'git .*notes' \
  "reporting by Git note updates a ref, which the protocol forbids; the admitted report_channel is the only path"

# v1 listed turns/ from the WORKING TREE, so an uncommitted receipt authorized work. That is the
# defect this whole protocol exists to remove.
refuse "the record working tree is never listed" '(^|[^-])ls .*\$?\{?TOPIC\}?.*turns' \
  "listing turns/ reads the working tree; an uncommitted receipt would authorize work"
refuse "no working-tree glob over records" '\$\{?TOPIC\}?/turns/\*' \
  "a glob over turns/ reads the working tree rather than committed objects"

# v1's wait re-ran forever on timeout, with the manual telling the agent to repeat indefinitely.
refuse "the wait is not an unbounded loop" 'while (true|:)' \
  "an unbounded wait leaves a participant that can never be fenced or observed"

# --- what v2 requires instead -------------------------------------------------------------------------
require_code "records are read from committed objects" 'git -C .* (show|cat-file) .*HEAD:' \
  "the manual must read records with git show HEAD:PATH or an equivalent committed-object read"
require_code "the receipt existence check is a committed-object probe" 'cat-file -e' \
  "the manual must probe for the receipt object rather than for a file on disk"
require_code "the wait is bounded by the intent's receipt bound" 'RECEIPT_COMMIT_BY_EPOCH' \
  "the wait must terminate at receipt_commit_by_epoch"

require "the expiry writes nothing to the worktree" "worktree_writes: 0"
require "the ACK is the first response" "ACK FIRST"
require "the ACK binds the idempotency token" "idempotency_token"
require "the ACK binds the admission" "admission_ref"
require "the ACK binds the receipt" "dispatch_ref"
require "the ACK binds the job" "job_id"
require "the ACK declares its evidence class" "ack_evidence_class"
require "the visible preflight reports an observed HEAD" "observed_head"
require "the visible preflight reports cleanliness" "preflight_clean"
require "the invisible preflight binds the relay base" "relayed_base_sha"
require "the report uses the admitted channel" "report_channel"
require "the report manifest carries a byte count" "byte_count"
require "the report manifest carries a digest" "shasum -a 256"
require "the report manifest declares its encoding" "encoding: utf-8"
require "the report manifest declares trailing-newline state" "trailing_newline"
require "one turn per dispatch" "one turn"
require "the participant never writes the record" "never write the record"

# --- ordering: the ACK must come before the work, in the text itself -----------------------------------
# A manual that lists the ACK after the work section teaches the wrong order even if every rule is
# present. Compare the line numbers.
ack_line="$(grep -n 'ACK FIRST' "$SKILL" | head -1 | cut -d: -f1)"
work_line="$(grep -n 'Do the turn' "$SKILL" | head -1 | cut -d: -f1)"
if [ -n "$ack_line" ] && [ -n "$work_line" ] && [ "$ack_line" -lt "$work_line" ]; then
  ok "the ACK section precedes the work section"
else
  nok "the ACK section precedes the work section" "ACK at line ${ack_line:-none}, work at line ${work_line:-none}"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$((PASS + FAIL))" -gt 0 ] || { echo "FATAL: the contract asserted nothing" >&2; exit 3; }
[ "$FAIL" -eq 0 ]
