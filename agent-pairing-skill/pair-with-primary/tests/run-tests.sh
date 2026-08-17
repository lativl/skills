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
#
# The patterns below are deliberately IDIOM-BLIND rather than command-specific. An earlier version
# named `ls` and a `$TOPIC/turns/*` glob, and every one of these slipped past it: a quoted
# `"$TOPIC"/turns/*` (the quote breaks a `$TOPIC/turns` pattern), a `find "$TOPIC/turns"`, and a
# `for f in .../turns/*.md`. What they share is not a command name — it is touching `turns` as a
# FILESYSTEM PATH. That is what gets refused.
# OBJECT reads are the whole point, so they are excluded first, by the marks that identify them:
# a `HEAD:`-prefixed path, `ls-tree`, or `cat-file`. `cat-file` in particular contains the substring
# `cat`, so a naive command-name pattern flags the correct idiom as the forbidden one. What remains
# after that exclusion is a command touching `turns` as a filesystem path, whatever it is called.
CODE_FS="$(printf '%s\n' "$CODE" | grep -v -E 'HEAD:|ls-tree|cat-file')"
if printf '%s\n' "$CODE_FS" | grep -Eq '(^|[^-[:alnum:]])(ls|find|cat|head|tail|for [A-Za-z_]+ in)[^|]*turns'; then
  nok "no filesystem read of the record tree" \
    "reading turns/ as a filesystem path reads the working tree; an uncommitted receipt would authorize work: $(printf '%s\n' "$CODE_FS" | grep -E '(^|[^-[:alnum:]])(ls|find|cat|head|tail|for [A-Za-z_]+ in)[^|]*turns' | head -1)"
else
  ok "no filesystem read of the record tree"
fi
refuse "no glob over the record tree" 'turns/\*' \
  "a glob over turns/ enumerates the working tree rather than committed objects"

# v1's wait re-ran forever on timeout, with the manual telling the agent to repeat indefinitely.
# `until false` is the same loop as `while true`, so both spellings are refused.
refuse "the wait is not an unbounded loop" '(while (true|:)|until (false|:)|while \[ 1 \])' \
  "an unbounded wait leaves a participant that can never be fenced or observed"

# --- prose is scanned too, for the idioms an agent would actually copy ---------------------------------
# The refusals above scan only fenced bash, because the manual EXPLAINS these defects and a scan over
# prose would fire on the sentences forbidding them. But an INSTRUCTION can live in prose, so prose is
# scanned for the narrow shape of a filesystem read spelled inside backticks — which is how a reader
# would copy it — while the explanatory sentences, which never use that shape, stay legal.
PROSE="$(awk '/^```/ { c = !c; next } !c' "$SKILL")"
if printf '%s\n' "$PROSE" | grep -Eq '`[^`]*(ls|find|cat) [^`]*turns[^`]*`'; then
  nok "no filesystem read of the record tree in prose" \
    "an inline command reads turns/ from the working tree: $(printf '%s\n' "$PROSE" | grep -Eo '`[^`]*(ls|find|cat) [^`]*turns[^`]*`' | head -1)"
else
  ok "no filesystem read of the record tree in prose"
fi

# The manual must give a POSITIVE recipe for enumerating committed records. Forbidding the working
# tree without saying what to do instead leaves `ls turns/` as the path of least resistance.
require_code "committed records can be enumerated" 'ls-tree' \
  "the manual must show how to LIST committed records, not only how to read one"

# --- what v2 requires instead -------------------------------------------------------------------------
require_code "records are read from committed objects" 'git -C .* (show|cat-file) .*HEAD:' \
  "the manual must read records with git show HEAD:PATH or an equivalent committed-object read"
require_code "the receipt existence check is a committed-object probe" 'cat-file -e' \
  "the manual must probe for the receipt object rather than for a file on disk"
require_code "the wait is bounded by the intent's receipt bound" 'RECEIPT_COMMIT_BY_EPOCH' \
  "the wait must terminate at receipt_commit_by_epoch"
# The between-turns wait is a DIFFERENT wait from the receipt wait, and it needs its own bound.
require_code "the idle wait between turns is bounded too" 'IDLE_BUDGET_SECONDS|IDLE_UNTIL' \
  "an unbounded between-turns waiter cannot be observed or fenced"
# ...and the loop must not re-find the dispatch it just finished. On the second pass the previous
# EXPECTED_DISPATCH_REF still names a committed receipt, so without this the participant
# re-acknowledges and re-works one dispatch -- taking a second turn on it, which the manual forbids.
require_code "handled attempts are tracked across the loop" 'HANDLED' \
  "the loop must skip attempts it has already acknowledged"
require "the loop waits for a NEW intent, not the old receipt" "Wait one — for a NEW intent"

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
# Presence of the WORD proves nothing -- it appears in any sentence mentioning the field. Require the
# operative instruction: the admitted channel is the only path, and Git notes are refused by name.
require "the report uses the admitted channel" "admitted \`report_channel\`"
require "no other channel is permitted" "never by any other ref update"
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

# --- the committed/uncommitted distinction, executed rather than described ---------------------------
# The manual's central claim is that an uncommitted receipt authorizes nothing. Asserting the words
# is not the same as running the probe: these two fixtures hold BYTE-IDENTICAL receipts and differ
# only in committedness, so the probe extracted from the manual must answer differently for them.
#
# The probe is taken from the manual itself, not restated here, so the two cannot drift apart.
# The RECEIPT probe specifically -- the manual has another `cat-file -e` for TOPIC.md, and that one
# is committed in both fixtures, so extracting it would make the two cases indistinguishable and the
# test would pass while proving nothing. The line is an `if ...; then` fragment in the manual, so the
# surrounding syntax is stripped to leave the bare command.
PROBE="$(printf '%s\n' "$CODE" | grep -F 'cat-file -e' | grep -F 'EXPECTED_DISPATCH_REF' | head -1 \
         | sed -e 's/^[[:space:]]*if[[:space:]]*//' -e 's/;[[:space:]]*then[[:space:]]*$//')"
if [ -z "$PROBE" ]; then
  nok "the manual's receipt probe is extractable" "no cat-file -e line found in the manual's code"
else
  ok "the manual's receipt probe is extractable"

  FTMP="$(mktemp -d /tmp/agent-pairing-participant.XXXXXX)" \
    || { echo "FATAL: temp allocation failed" >&2; exit 3; }
  case "$FTMP" in /tmp/agent-pairing-participant.?*) ;; *) echo "FATAL: bad temp path" >&2; exit 3 ;; esac
  trap 'rm -rf "$FTMP"' EXIT

  probe_fixture() { # <fixture> <commit-turns?> -> 0 when the probe says "go"
    d="$FTMP/$1"; mkdir -p "$d"
    cp -R "$HERE/fixtures/$1"/. "$d"/ || return 2
    rm -f "$d/.leave-uncommitted"
    git -C "$d" init -q && git -C "$d" config user.name p && git -C "$d" config user.email p@t || return 2
    if [ "$2" = yes ]; then git -C "$d" add -A; else git -C "$d" add TOPIC.md; fi
    git -C "$d" commit -qm seed || return 2
    TOPIC="$d"
    HEAD_SHA="$(git -C "$TOPIC" rev-parse HEAD)" || return 2
    EXPECTED_DISPATCH_REF=0004-t0001-a01-dispatch.md
    eval "$PROBE" >/dev/null 2>&1
  }

  if probe_fixture committed-receipt yes; then
    ok "the probe finds a COMMITTED receipt"
  else
    nok "the probe finds a COMMITTED receipt" "the manual's own probe did not resolve a committed receipt"
  fi
  if probe_fixture uncommitted-receipt no; then
    nok "an UNCOMMITTED receipt authorizes nothing" \
      "the manual's probe resolved a receipt that exists only in the working tree"
  else
    ok "an UNCOMMITTED receipt authorizes nothing"
  fi
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$((PASS + FAIL))" -gt 0 ] || { echo "FATAL: the contract asserted nothing" >&2; exit 3; }
[ "$FAIL" -eq 0 ]
