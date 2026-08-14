#!/bin/bash
# bash 3.2 compatible. Run: /bin/bash skills/agent-pairing/tests/run-tests.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$HERE/../scripts/validate.sh"
FIXTURES="$HERE/fixtures"
# D28 — destructive-path guards, defined before the first temp dir exists. An unchecked `mktemp`
# leaves an EMPTY variable and the very next line reads as `rm -rf "/turns"` or `cp -R fix/. /`.
# safe_rmdir is the ONLY recursive delete in this harness; it refuses anything outside its prefix.
safe_rmdir() { # <path> <required-prefix>
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || { echo "FATAL: safe_rmdir needs <path> <prefix>" >&2; exit 3; }
  case "$1" in "$2"?*) ;; *) echo "FATAL: refusing rm -rf $1 (not under $2)" >&2; exit 3;; esac
  case "$1" in *..*) echo "FATAL: refusing rm -rf $1 (contains ..)" >&2; exit 3;; esac
  rm -rf "$1"; }

TMPROOT="$(mktemp -d /tmp/agent-pairing-tests.XXXXXX)" \
  || { echo "FATAL: mktemp -d /tmp/agent-pairing-tests.XXXXXX failed" >&2; exit 3; }
[ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] || { echo "FATAL: mktemp produced no directory" >&2; exit 3; }
trap 'safe_rmdir "$TMPROOT" /tmp/agent-pairing-tests.' EXIT
. "$HERE/lib.sh"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf 'FAIL %s\n      %s\n' "$1" "$2"; }

# D16: unique dir per case — a counter incremented inside $( ) is lost to the subshell.
# D28: the mktemp is checked BEFORE $d reaches `cp`, because `cp -R "$FIXTURES/x"/. ""/` writes at /.
# On failure it returns 1 with an empty stdout; have_case then fails the case loudly at the assert.
clone_fixture() {
  d="$(mktemp -d "$TMPROOT/case.XXXXXX")" || { echo "FATAL: mktemp under $TMPROOT failed" >&2; return 1; }
  [ -n "$d" ] && [ -d "$d" ] || { echo "FATAL: mktemp produced no directory" >&2; return 1; }
  case "$d" in "$TMPROOT"/case.?*) ;; *) echo "FATAL: $d is not under $TMPROOT" >&2; return 1;; esac
  cp -R "$FIXTURES/$1"/. "$d"/ || { echo "FATAL: fixture $1 could not be copied into $d" >&2; return 1; }
  echo "$d"; }

# ONE front-matter editor set for the whole harness (D27), and every one of them FAILS LOUDLY
# unless it made exactly the edit it was asked for. rev.5's fm_set returned 0 and changed nothing
# when the key was absent — the silent no-op these editors exist to kill: the MISSING_EVIDENCE case
# set `reason:` on a fixture with no `reason` key and could never pass. Three earlier hand-rolled
# mutations edited the BODY instead — `$a\` appends past the closing `---`, and `/^---$/,$d` starts
# at the OPENING delimiter and empties the file. Nothing else may edit a record in place.
# Matching is `$1 == "key:"`, so a BARE `key:` (empty value) is editable — load-bearing, because a
# VERIFIED result carries `reason:` with an empty value (D31).
# The arg-count guard comes BEFORE any `f="$1"`, in ALL SEVEN: under `set -u` a zero-arg call
# would otherwise die with `$1: unbound variable` instead of printing the usage message the guard
# exists to print (reproduced on this host; the guarded form prints the usage and exits 1).
fm_hit()  { # <file> <key> — true when the front-matter block carries that key
  [ $# -eq 2 ] && [ -f "${1:-}" ] || { echo "fm_hit: usage fm_hit <file> <key> (got: $*)" >&2; exit 1; }
  awk -v k="$2" 'BEGIN{c=0} /^---$/{c++} c==1 && $1==k":" {f=1} END{exit !f}' "$1"; }
fm_set()  {
  [ $# -eq 3 ] && [ -f "${1:-}" ] || { echo "fm_set: usage fm_set <file> <key> <value> (got: $*)" >&2; exit 1; }
  f="$1"
  fm_hit "$f" "$2" || { echo "fm_set: no key $2 in $1" >&2; exit 1; }
  awk -v k="$2" -v v="$3" 'BEGIN{c=0} /^---$/{c++}
    { if (c==1 && $1==k":") print k": "v; else print }' "$f" > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_set: could not rewrite $1" >&2; exit 1; }; }
fm_add()  {
  [ $# -eq 3 ] && [ -f "${1:-}" ] || { echo "fm_add: usage fm_add <file> <key> <value> (got: $*)" >&2; exit 1; }
  f="$1"
  # A duplicate key would be shadowed by fm_get's first-match rule, so adding one is refused. The
  # two refusal causes are reported separately: "fired for a different reason than the one named"
  # is the class this round is closing.
  ! fm_hit "$f" "$2" || { echo "fm_add: key $2 is already present in $1" >&2; exit 1; }
  awk -v k="$2" -v v="$3" 'BEGIN{c=0}
    /^---$/{ c++; if (c==2) { print k": "v; hit=1 } } {print} END{ exit !hit }' \
    "$f" > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_add: $1 has no closing --- to insert before" >&2; exit 1; }; }
fm_del()  {
  [ $# -eq 2 ] && [ -f "${1:-}" ] || { echo "fm_del: usage fm_del <file> <key> (got: $*)" >&2; exit 1; }
  f="$1"
  fm_hit "$f" "$2" || { echo "fm_del: no key $2 in $1" >&2; exit 1; }
  awk -v k="$2" 'BEGIN{c=0} /^---$/{c++} { if (c==1 && $1==k":") next; print }' \
    "$f" > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_del: could not rewrite $1" >&2; exit 1; }; }
body_del(){
  [ $# -eq 1 ] && [ -f "${1:-}" ] || { echo "body_del: usage body_del <file> (got: $*)" >&2; exit 1; }
  f="$1"
  awk 'BEGIN{c=0} {print} /^---$/{ c++; if (c==2) { seen=1; exit } } END { exit !seen }' \
    "$f" > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "body_del: $1 has no closing --- delimiter" >&2; exit 1; }; }

# Three more, for D33's structural rules: a MALFORMED block cannot be expressed by the editors
# above, by construction. They carry the SAME loud tail as the other four — rev.6 shipped them
# without one and a round-6 verifier executed all three: `fm_truncate` and `fm_insert_raw` returned
# 0 having changed NOTHING on a file with no closing `---` (the exact silent-no-op D27 exists to
# kill, reintroduced by D27's own fix), and all three left a `<file>.new` residue when their
# `awk`/`cat` failed. `END{exit !seen}` / `END{exit !hit}` is the postcondition that makes each
# loud. Verified on this host after hardening: unterminated input ⇒ rc 1, message on stderr, file
# byte-identical, no `.new`; well-formed input ⇒ rc 0 and the intended edit.
fm_truncate()   {
  [ $# -eq 1 ] && [ -f "${1:-}" ] || { echo "fm_truncate: usage fm_truncate <file> (got: $*)" >&2; exit 1; }
  f="$1"
  awk 'BEGIN{c=0} /^---$/{c++; if(c==2){seen=1; exit}} {print} END{exit !seen}' "$f" > "$f.new" \
    && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_truncate: $1 has no closing ---" >&2; exit 1; }; }
fm_preamble()   {
  [ $# -eq 1 ] && [ -f "${1:-}" ] || { echo "fm_preamble: usage fm_preamble <file> (got: $*)" >&2; exit 1; }
  f="$1"
  { printf 'stray preamble\n'; cat "$f"; } > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_preamble: could not rewrite $1" >&2; exit 1; }; }
fm_insert_raw() {
  [ $# -eq 2 ] && [ -f "${1:-}" ] || { echo "fm_insert_raw: usage fm_insert_raw <file> <line> (got: $*)" >&2; exit 1; }
  f="$1"
  awk -v line="$2" 'BEGIN{c=0} /^---$/{c++; if(c==2){print line; hit=1}} {print} END{exit !hit}' \
    "$f" > "$f.new" && mv "$f.new" "$f" \
    || { rm -f "$f.new"; echo "fm_insert_raw: $1 has no closing --- to insert before" >&2; exit 1; }; }

have_case() { # <desc> <dir> — an absent case dir means a fixture helper failed; never run on "".
  [ -n "${2:-}" ] && [ -d "$2" ] && return 0
  nok "$1" "no case directory (a fixture helper failed) — got '${2:-}'"; return 1; }

assert_check_ok() { # <desc> <dir>
  [ $# -eq 2 ] || { nok "${1:-assert_check_ok}" "usage: assert_check_ok <desc> <dir> (got $# args)"; return 0; }
  have_case "$1" "$2" || return 0
  if /bin/bash "$VALIDATE" --check "$2" >"$TMPROOT/out" 2>"$TMPROOT/err"; then ok "$1"
  else nok "$1" "expected exit 0 — $(cat "$TMPROOT/err")"; fi; }

# THE oracle (D29). It compares the WHOLE distinct code set — not "does this code appear somewhere
# in stderr". A substring-anywhere match passes as soon as any earlier, unintended violation is also
# present, which is exactly how mutation tests came to assert codes their fixtures cannot produce.
# A nonzero exit with NO violation line (crash, unbound variable) is a failure, not a pass.
assert_violations() { # <desc> "<CODE> [CODE …]" <dir>
  [ $# -eq 3 ] || { nok "${1:-assert_violations}" "usage: assert_violations <desc> <CODES> <dir> (got $# args)"; return 0; }
  have_case "$1" "$3" || return 0
  if /bin/bash "$VALIDATE" --check "$3" >"$TMPROOT/out" 2>"$TMPROOT/err"; then
    nok "$1" "expected VIOLATION [$2], got exit 0"; return 0; fi
  got="$(awk '$1=="VIOLATION"{print $2}' "$TMPROOT/err" | sort -u | tr '\n' ' ')"
  want="$(printf '%s\n' $2 | grep . | sort -u | tr '\n' ' ')"
  if [ -z "$got" ]; then
    nok "$1" "nonzero exit but no VIOLATION line — stderr was: $(cat "$TMPROOT/err")"
  elif [ "$got" = "$want" ]; then ok "$1"
  else nok "$1" "expected exactly [$want], got [$got] — $(cat "$TMPROOT/err")"; fi; }

assert_violation() { # <desc> <CODE> <dir> — the single-code case, same oracle
  [ $# -eq 3 ] || { nok "${1:-assert_violation}" "usage: assert_violation <desc> <CODE> <dir> (got $# args)"; return 0; }
  assert_violations "$1" "$2" "$3"; }

assert_no_violation() { # <desc> <CODE> <dir> — whole-token compare, never a substring grep
  [ $# -eq 3 ] || { nok "${1:-assert_no_violation}" "usage: assert_no_violation <desc> <CODE> <dir> (got $# args)"; return 0; }
  have_case "$1" "$3" || return 0
  /bin/bash "$VALIDATE" --check "$3" >"$TMPROOT/out" 2>"$TMPROOT/err"
  if awk -v c="$2" '$1=="VIOLATION" && $2==c {f=1} END{exit !f}' "$TMPROOT/err"; then
    nok "$1" "unexpected VIOLATION $2"; else ok "$1"; fi; }

# --- harness self-tests: every guard added this round has a test that goes RED if it is stubbed ---
# D28: the three refusals must refuse AND delete nothing. safe_rmdir exits 3, so each runs in ( ).
mkdir -p "$TMPROOT/guard/keep"
( safe_rmdir "" "$TMPROOT/guard/" ) >/dev/null 2>&1 \
  && nok "safe_rmdir refuses an empty path" "accepted" || ok "safe_rmdir refuses an empty path"
( safe_rmdir "/" "$TMPROOT/guard/" ) >/dev/null 2>&1 \
  && nok "safe_rmdir refuses /" "accepted" || ok "safe_rmdir refuses /"
( safe_rmdir "$TMPROOT/guard/keep/../../guard" "$TMPROOT/guard/" ) >/dev/null 2>&1 \
  && nok "safe_rmdir refuses a .. escape" "accepted" || ok "safe_rmdir refuses a .. escape"
[ -d "$TMPROOT/guard/keep" ] && ok "the refused deletes removed nothing" \
  || nok "the refused deletes removed nothing" "$TMPROOT/guard/keep is gone"
( safe_rmdir "$TMPROOT/guard/keep" "$TMPROOT/guard/" ) >/dev/null 2>&1
[ ! -e "$TMPROOT/guard/keep" ] && ok "safe_rmdir removes a contained path" \
  || nok "safe_rmdir removes a contained path" "still present"

# D27: each editor must FAIL on the precondition it needs, and must not touch the file when it does.
d=$(clone_fixture minimal); F="$d/turns/0001-t0001-a01-assignment.md"; cp "$F" "$TMPROOT/fm-before"
( fm_set "$F" nosuchkey value ) >/dev/null 2>&1 \
  && nok "fm_set fails on a missing key" "returned 0" || ok "fm_set fails on a missing key"
( fm_del "$F" nosuchkey ) >/dev/null 2>&1 \
  && nok "fm_del fails on a missing key" "returned 0" || ok "fm_del fails on a missing key"
( fm_add "$F" agent_id second ) >/dev/null 2>&1 \
  && nok "fm_add refuses an existing key" "returned 0" || ok "fm_add refuses an existing key"
cmp -s "$TMPROOT/fm-before" "$F" && ok "a refused edit leaves the record byte-identical" \
  || nok "a refused edit leaves the record byte-identical" "$(diff "$TMPROOT/fm-before" "$F")"
ls "$d"/turns/*.new >/dev/null 2>&1 && nok "no editor temp file survives a refusal" "found one" \
  || ok "no editor temp file survives a refusal"
fm_set "$F" agent_id agent-z; grep -q '^agent_id: agent-z$' "$F" \
  && ok "fm_set replaces an existing key" || nok "fm_set replaces an existing key" "not replaced"
fm_add "$F" extra_key 1; grep -q '^extra_key: 1$' "$F" \
  && ok "fm_add inserts before the closing delimiter" || nok "fm_add inserts before the closing delimiter" "missing"
fm_del "$F" extra_key; grep -q '^extra_key: ' "$F" \
  && nok "fm_del removes the key" "still present" || ok "fm_del removes the key"

# The three STRUCTURAL editors get the same negative tests — rev.6 asserted they fail loudly and a
# round-6 verifier proved they did not. Each is applied twice: once to make the malformed file, and
# once MORE to the already-malformed file, where the postcondition must refuse.
d=$(clone_fixture minimal); G="$d/turns/0001-t0001-a01-assignment.md"
fm_truncate "$G"                                   # legal: removes the closing --- and the body
cp "$G" "$TMPROOT/struct-before"
( fm_truncate "$G" ) >/dev/null 2>&1 \
  && nok "fm_truncate fails on an unterminated block" "returned 0" \
  || ok "fm_truncate fails on an unterminated block"
( fm_insert_raw "$G" 'agent_id: agent-b' ) >/dev/null 2>&1 \
  && nok "fm_insert_raw fails with no closing ---" "returned 0" \
  || ok "fm_insert_raw fails with no closing ---"
cmp -s "$TMPROOT/struct-before" "$G" && ok "a refused structural edit changes nothing" \
  || nok "a refused structural edit changes nothing" "$(diff "$TMPROOT/struct-before" "$G")"
( fm_preamble "$d/turns/no-such-record.md" ) >/dev/null 2>&1 \
  && nok "fm_preamble fails on a non-file" "returned 0" || ok "fm_preamble fails on a non-file"
ls "$d"/turns/*.new >/dev/null 2>&1 && nok "no structural-editor temp file survives" "found one" \
  || ok "no structural-editor temp file survives"
# Under `set -u` a zero-arg call must reach the usage message, not `$1: unbound variable`.
( fm_truncate ) 2>"$TMPROOT/zeroarg" >/dev/null
grep -q '^fm_truncate: usage' "$TMPROOT/zeroarg" && ok "a zero-arg editor call prints usage" \
  || nok "a zero-arg editor call prints usage" "$(cat "$TMPROOT/zeroarg")"

# The oracle must DISCRIMINATE: a run with MORE THAN ONE distinct code cannot satisfy a one-code
# assertion. (This probe produces three: BAD_TURN_KIND, BAD_SHA and TOPIC_BASE_MISMATCH.)
# Run the probe in a subshell so its verdict and counters belong to the self-test, not the suite.
d=$(clone_fixture minimal)
fm_set "$d"/turns/0001-*.md turn_kind SIDEWAYS
fm_set "$d"/turns/0001-*.md base_sha not-a-sha
verdict="$( PASS=0; FAIL=0; assert_violation "probe" BAD_TURN_KIND "$d" )"
case "$verdict" in
  FAIL*) ok "assert_violation is discriminating (a second code is not ignored)" ;;
  *)     nok "assert_violation is discriminating (a second code is not ignored)" \
              "a one-code assertion passed a two-code run: $verdict" ;;
esac

# --- Task 1 cases ---
d=$(clone_fixture minimal); assert_check_ok "minimal fixture passes schema" "$d"

d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md kind banana
assert_violation "unknown kind" BAD_KIND "$d"
d=$(clone_fixture minimal); fm_del "$d"/turns/0001-*.md agent_id
assert_violation "missing key" MISSING_KEY "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md base_sha not-a-sha
assert_violations "malformed sha" "BAD_SHA TOPIC_BASE_MISMATCH" "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md turn_kind SIDEWAYS
assert_violation "bad turn_kind" BAD_TURN_KIND "$d"
# D8: enum membership must not be a regex match
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md turn_kind '.*'
assert_violation "regex .* rejected as turn_kind" BAD_TURN_KIND "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md turn_kind '[A-Z]*'
assert_violation "regex class rejected as turn_kind" BAD_TURN_KIND "$d"
# WIDTH is asserted on turn_id, not record_seq: a malformed record_seq ALSO trips
# SEQ_FILENAME_MISMATCH and (from Task 2 on) SEQ_GAP, so it is not a single-code case. That
# three-code combination is asserted in Task 2, where SEQ_GAP exists.
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md turn_id 001
assert_violation "turn_id width" WIDTH "$d"

d=$(clone_fixture minimal)
mv "$d"/turns/0001-t0001-a01-assignment.md "$d"/turns/0002-t0001-a01-assignment.md
assert_violation "filename/front-matter seq mismatch" SEQ_FILENAME_MISMATCH "$d"

# S1 (acceptance round 2, schema gap) — §3.2 requires ISO-8601 timestamps; recorded_at/deadline/
# dispatched_at/observed_at were only checked non-empty. One negative case per field.
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "not-a-timestamp"
assert_violation "malformed recorded_at" BAD_TIMESTAMP "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-08-11 15:00:00"
assert_violation "recorded_at missing the T/Z ISO-8601 separators" BAD_TIMESTAMP "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md deadline "2026/08/11T23:00:00Z"
assert_violation "malformed deadline" BAD_TIMESTAMP "$d"
d=$(clone_fixture open-dispatched); fm_set "$d"/turns/0003-*.md dispatched_at "11-08-2026T15:02:00Z"
assert_violation "malformed dispatched_at" BAD_TIMESTAMP "$d"
d=$(clone_fixture verified-normal); fm_set "$d"/turns/0004-*.md observed_at "2026-08-11T15:03:00"
assert_violation "malformed observed_at (missing trailing Z)" BAD_TIMESTAMP "$d"

# --- Finding C (codex round 3, P2) ---------------------------------------------------------------
# `is_iso8601` rev.1 was a fixed-form `case` glob with no range check: it REJECTED legitimate
# ISO-8601 (a numeric offset, fractional seconds) while ACCEPTING an impossible-but-well-shaped
# value. Two acceptance cases for the widened forms, one for both combined, and two rejection
# cases for the range check.
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-08-11T15:00:00+02:00"
assert_check_ok "recorded_at with a numeric UTC offset is legal ISO-8601" "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-08-11T15:00:00.123Z"
assert_check_ok "recorded_at with fractional seconds is legal ISO-8601" "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-08-11T15:00:00.123+02:00"
assert_check_ok "recorded_at with fractional seconds AND a numeric offset is legal ISO-8601" "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-99-99T99:99:99Z"
assert_violation "recorded_at with an impossible month/day/hour/minute/second" BAD_TIMESTAMP "$d"
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md recorded_at "2026-13-40T25:61:61Z"
assert_violation "recorded_at with out-of-range month/day/hour/minute/second" BAD_TIMESTAMP "$d"

# S2 (acceptance round 2, schema gap) — §3.2's filename grammar, per kind. Only the FILE is
# renamed in every case (front matter untouched), so no downstream record's *_ref goes dangling
# and no LINK_* code can fire alongside — each case isolates FILENAME_SHAPE alone. `minimal`,
# `open-dispatched`-derived dispatch, and `verified-normal`-derived result are chosen because
# nothing else in their fixture cites those records' OWN filenames (unlike an assignment's or an
# intent's, which downstream `assignment_ref`/`intent_ref` values point at).
d=$(clone_fixture minimal)                        # attempt-linked: wrong kind segment
mv "$d"/turns/0001-t0001-a01-assignment.md "$d"/turns/0001-t0001-a01-intent.md
assert_violation "assignment filename carries the wrong kind segment" FILENAME_SHAPE "$d"
# NIT: the message used to print the literal `[-KK]` bracket text for EVERY kind, including
# non-late ones (like `assignment`, here) that never have a -KK suffix at all. It must read cleanly.
grep -q '\[-KK\]' "$TMPROOT/err" \
  && nok "FILENAME_SHAPE message reads cleanly (no literal [-KK] bracket) for a non-late kind" "$(cat "$TMPROOT/err")" \
  || ok "FILENAME_SHAPE message reads cleanly (no literal [-KK] bracket) for a non-late kind"

d=$(clone_fixture open-dispatched)                 # attempt-linked: wrong attempt segment
mv "$d"/turns/0003-t0001-a01-dispatch.md "$d"/turns/0003-t0001-a02-dispatch.md
assert_violation "dispatch filename carries the wrong attempt segment" FILENAME_SHAPE "$d"

d=$(clone_fixture open-dispatched)                 # attempt-linked: wrong turn segment
mv "$d"/turns/0003-t0001-a01-dispatch.md "$d"/turns/0003-t0002-a01-dispatch.md
assert_violation "dispatch filename carries the wrong turn segment" FILENAME_SHAPE "$d"

d=$(clone_fixture verified-normal)                 # attempt-linked: wrong kind segment
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0004-t0001-a01-late-01.md
assert_violation "result filename carries the wrong kind segment" FILENAME_SHAPE "$d"

d=$(clone_fixture minimal)                          # late: wrong attempt segment (never the
printf '%s\n' '---' 'record_seq: 0002' 'kind: late' 'topic_id: minimal' 'turn_id: 0001' \
  'attempt_id: 01' 'turn_kind: NORMAL' 'assignment_ref: 0001-t0001-a01-assignment.md' \
  'named_sha: null' 'recorded_at: 2026-08-11T15:09:00Z' '---' 'Observed only.' \
  > "$d/turns/0002-t0001-a02-late-01.md"           # -KK width, already WIDTH's own case
assert_violation "late filename carries the wrong attempt segment" FILENAME_SHAPE "$d"
# NIT: the late kind's message must read as a clean literal (…-late-KK.md), not the old shared
# "[-KK]" bracket suffix appended to every kind indiscriminately.
grep -q 'late-KK\.md' "$TMPROOT/err" \
  && ok "FILENAME_SHAPE message names the late suffix cleanly (…-late-KK.md)" \
  || nok "FILENAME_SHAPE message names the late suffix cleanly (…-late-KK.md)" "$(cat "$TMPROOT/err")"
grep -q '\[-KK\]' "$TMPROOT/err" \
  && nok "FILENAME_SHAPE message reads cleanly (no literal [-KK] bracket) for the late kind" "$(cat "$TMPROOT/err")" \
  || ok "FILENAME_SHAPE message reads cleanly (no literal [-KK] bracket) for the late kind"

# NIT: a bad late-index WIDTH (e.g. a single-digit tail) must fire WIDTH ONLY — before this fix it
# also tripped FILENAME_SHAPE for the identical defect, contradicting S2's own one-defect-one-code
# comment. `record_seq` is correct (0002) and `turn_id`/`attempt_id` are correct (0001/01), so the
# ONLY thing wrong with this filename is its late-tail width.
d=$(clone_fixture minimal)
printf '%s\n' '---' 'record_seq: 0002' 'kind: late' 'topic_id: minimal' 'turn_id: 0001' \
  'attempt_id: 01' 'turn_kind: NORMAL' 'assignment_ref: 0001-t0001-a01-assignment.md' \
  'named_sha: null' 'recorded_at: 2026-08-11T15:09:00Z' '---' 'Observed only.' \
  > "$d/turns/0002-t0001-a01-late-1.md"            # single-digit index: WIDTH's own defect, alone
assert_violation "bad late-index width fires WIDTH only, not also FILENAME_SHAPE (one-defect-one-code)" WIDTH "$d"

d=$(clone_fixture awaiting-owner)                  # short-form kind: spurious tTTTT-aAA segment
mv "$d"/turns/0003-owner-question.md "$d"/turns/0003-t0001-a01-owner-question.md
assert_violation "owner-question filename carries a spurious attempt segment" FILENAME_SHAPE "$d"

d=$(clone_fixture closing)                         # short-form kind: wrong kind segment
mv "$d"/turns/0005-close.md "$d"/turns/0005-owner-question.md
assert_violation "close filename carries the wrong kind segment" FILENAME_SHAPE "$d"

# --- D33: structural front matter, and the TOPIC.md gate (§3.0). Each rule gets a case that goes
# --- RED if the rule is stubbed out; none of them is satisfiable by another code firing first.
d=$(clone_fixture minimal); rm -f "$d/TOPIC.md"
assert_violation "TOPIC.md is required"                TOPIC_MISSING     "$d"
d=$(clone_fixture minimal); fm_del "$d/TOPIC.md" base_ref
assert_violation "TOPIC.md must pin the base ref"      TOPIC_MISSING_KEY "$d"
# topic_id is the third required key with a single-code deletion: TOPIC_ID is then empty, so D32's
# comparison loop is skipped rather than firing a second code. The remaining three required keys
# (the identity triple) cannot be single-code once TOPIC_MISMATCH exists, so their case lives in
# Task 3; `session_branch` stands for all three — they share one loop and one code path.
d=$(clone_fixture minimal); fm_del "$d/TOPIC.md" topic_id
assert_violation "TOPIC.md must carry topic_id"        TOPIC_MISSING_KEY "$d"
# Single-code by construction: with base_sha ABSENT the validator reports the missing key and does
# NOT then run the shape check or the base cross-check on an empty string — three codes for one
# deletion is how a case starts passing for a neighbour's reason.
d=$(clone_fixture minimal); fm_del "$d/TOPIC.md" base_sha
assert_violation "TOPIC.md must pin the base sha"      TOPIC_MISSING_KEY "$d"
d=$(clone_fixture minimal); fm_set "$d/TOPIC.md" base_sha not-a-sha
assert_violations "TOPIC.md base_sha must be a sha"    "BAD_SHA TOPIC_BASE_MISMATCH" "$d"
d=$(clone_fixture minimal); fm_preamble "$d/TOPIC.md"
assert_violation "preamble before TOPIC.md front matter" FM_MALFORMED    "$d"
# The TOPIC_FM_OK regression (D33). The base_sha is changed FIRST so the recovered value genuinely
# disagrees with the assignment's, and the block is then truncated. Without the gate, the four later
# `fm_get "$TOPICMD"` readers mine the malformed block and this reports
# {FM_MALFORMED, TOPIC_BASE_MISMATCH}; the single-code assertion goes RED if the gate is stubbed.
d=$(clone_fixture minimal)
fm_set "$d/TOPIC.md" base_sha 2222222222222222222222222222222222222222
fm_truncate "$d/TOPIC.md"
assert_violation "a malformed TOPIC.md is not mined for keys" FM_MALFORMED "$d"
d=$(clone_fixture minimal); fm_truncate "$d"/turns/0001-*.md
assert_violation "unterminated front-matter block"     FM_MALFORMED      "$d"
d=$(clone_fixture minimal); fm_insert_raw "$d"/turns/0001-*.md 'agent_id: agent-b'
assert_violation "duplicate front-matter key"          FM_MALFORMED      "$d"
d=$(clone_fixture minimal); fm_insert_raw "$d"/turns/0001-*.md 'this is not a key value pair'
assert_violation "non key: value line in the block"    FM_MALFORMED      "$d"
d=$(clone_fixture minimal); fm_insert_raw "$d"/turns/0001-*.md ''
assert_violation "blank line inside the block"         FM_MALFORMED      "$d"
# FM_UNPARSEABLE keeps a test of its OWN: a structurally valid block whose record_seq is missing.
# (Task 2's "no front matter at all" case now targets FM_MALFORMED, which fires first.)
d=$(clone_fixture minimal); fm_del "$d"/turns/0001-*.md record_seq
assert_violation "well-formed block without record_seq" FM_UNPARSEABLE   "$d"
# §3.0 commits TOPIC.md BEFORE any record exists: an empty log is a freshly opened topic, not
# corruption. NO_TURNS survives for a MISSING turns/ directory (tested in Task 2).
d=$(clone_fixture minimal); rm -f "$d"/turns/*.md
assert_check_ok     "empty turns/ after OPEN is legal" "$d"
assert_no_violation "empty turns/ is not NO_TURNS" NO_TURNS "$d"

/bin/bash "$VALIDATE" --check >"$TMPROOT/out" 2>"$TMPROOT/err"; [ $? -eq 3 ] \
  && ok "usage: missing arg => exit 3" || nok "usage: missing arg => exit 3" "wrong exit"
mkdir -p "$TMPROOT/has space/turns"
/bin/bash "$VALIDATE" --check "$TMPROOT/has space" >"$TMPROOT/out" 2>"$TMPROOT/err"; [ $? -eq 3 ] \
  && ok "whitespace path rejected" || nok "whitespace path rejected" "accepted"
# `USAGE` is an ADVERTISED code, so the code token is asserted and not only the exit status — the
# whitespace guard could emit a different word (or no VIOLATION line) and an exit-only test would
# still pass. The missing-arg path is deliberately NOT checked for a code: it prints the plain
# `usage:` line from `usage()` and emits no VIOLATION, which is what this asserts.
grep -q '^VIOLATION USAGE ' "$TMPROOT/err" && ok "whitespace path reports VIOLATION USAGE" \
  || nok "whitespace path reports VIOLATION USAGE" "stderr: $(cat "$TMPROOT/err")"

# --- Task 2 cases ---
d=$(clone_fixture open-dispatched); assert_check_ok "open-dispatched fixture passes" "$d"

mut() { clone_fixture "$1"; }   # alias kept for readability; D16 applies

# Defined before its first use: the SEQ_DUP case needs a record kind that MULTI_PER_ATTEMPT and
# TOKEN_DUP do NOT also fire on, or it cannot be a single-code assertion under the D29 oracle.
# `topic_id: minimal` is hard-coded, so this emitter is only valid inside the `minimal` fixture.
emit_late_for_test() { # <topic> <seq> <turn> <attempt> <turn_kind> <aref> <KK> <named_sha>
  printf '%s\n' '---' "record_seq: $2" 'kind: late' 'topic_id: minimal' "turn_id: $3" \
    "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" "named_sha: $8" \
    'recorded_at: 2026-08-11T15:09:00Z' '---' 'Observed only.' \
    > "$1/turns/$2-t$3-a$4-late-$7.md"; }

d=$(mut open-dispatched); mv "$d"/turns/0003-*.md "$d"/turns/0004-t0001-a01-dispatch.md
fm_set "$d"/turns/0004-*.md record_seq 0004
assert_violation "seq gap" SEQ_GAP "$d"

# Two late records sharing one record_seq: SEQ_DUP and nothing else. (Duplicating the intent, as
# rev.5 did, ALSO fires MULTI_PER_ATTEMPT and TOKEN_DUP.) Still the P1-4 regression: on rev.1 this
# printed a violation and exited 0.
d=$(clone_fixture minimal)
emit_late_for_test "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
emit_late_for_test "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 02 null
assert_violation "duplicate record_seq" SEQ_DUP "$d"

# record_seq width, moved here from Task 1: a non-four-digit record_seq necessarily also disagrees
# with its filename prefix AND breaks the 1..N sequence. All three codes are named, so none of them
# can hide behind another.
d=$(clone_fixture minimal); fm_set "$d"/turns/0001-*.md record_seq 001
assert_violations "record_seq width, with the mismatch and gap it implies" \
  "SEQ_FILENAME_MISMATCH SEQ_GAP WIDTH" "$d"

d=$(mut open-dispatched); cp "$d"/turns/0002-*.md "$d"/turns/0004-t0001-a01-intent.md
fm_set "$d"/turns/0004-*.md record_seq 0004
fm_set "$d"/turns/0004-*.md idempotency_token tok-x
assert_violation "second intent for one attempt" MULTI_PER_ATTEMPT "$d"

# A second assignment for one attempt necessarily leaves the FIRST one open and not-newest.
d=$(mut open-dispatched); cp "$d"/turns/0001-*.md "$d"/turns/0004-t0001-a01-assignment.md
fm_set "$d"/turns/0004-*.md record_seq 0004
assert_violations "second assignment for one attempt" "MULTI_PER_ATTEMPT OPEN_NOT_NEWEST" "$d"

# Reusing a token needs a second intent, whose tuple then disagrees with its own assignment_ref.
d=$(mut open-dispatched); cp "$d"/turns/0002-*.md "$d"/turns/0004-t0001-a02-intent.md
fm_set "$d"/turns/0004-*.md record_seq 0004
fm_set "$d"/turns/0004-*.md attempt_id 02
assert_violations "reused idempotency token" "LINK_TUPLE_MISMATCH TOKEN_DUP" "$d"

# Dangling on a LATE record: dangling the intent's assignment_ref would additionally make the
# dispatch↔intent assignment_ref comparison fire LINK_TUPLE_MISMATCH.
d=$(clone_fixture minimal)
emit_late_for_test "$d" 0002 0001 01 NORMAL 0009-t0009-a09-assignment.md 01 null
assert_violation "dangling assignment_ref" LINK_DANGLING "$d"

d=$(mut open-dispatched); fm_set "$d"/turns/0002-*.md turn_id 0002
# S2 (acceptance round 2): the intent's turn_id (now 0002) also stops matching its OWN, unrenamed
# filename (still ...-t0001-...), so this fixture now genuinely trips the filename-grammar check
# too — a second real defect, not a mask of the first. Strengthened, not weakened: the original
# LINK_TUPLE_MISMATCH assertion still holds.
assert_violations "tuple mismatch vs assignment" "FILENAME_SHAPE LINK_TUPLE_MISMATCH" "$d"

d=$(mut open-dispatched); fm_set "$d"/turns/0002-*.md turn_kind REVIEW
assert_violation "turn_kind differs from assignment" LINK_TUPLE_MISMATCH "$d"

# dispatch before its intent (renumber so the receipt precedes the intent)
d=$(mut open-dispatched)
fm_set "$d"/turns/0002-*.md record_seq 0003
fm_set "$d"/turns/0003-*dispatch.md record_seq 0002
mv "$d"/turns/0002-t0001-a01-intent.md   "$d"/turns/0003-t0001-a01-intent.md.new
mv "$d"/turns/0003-t0001-a01-dispatch.md "$d"/turns/0002-t0001-a01-dispatch.md
mv "$d"/turns/0003-t0001-a01-intent.md.new "$d"/turns/0003-t0001-a01-intent.md
fm_set "$d"/turns/0002-*dispatch.md intent_ref 0003-t0001-a01-intent.md
assert_violation "receipt precedes its intent" LINK_ORDER "$d"

# D27: through the front-matter editors. The rev.4 form used `$a\`, which appends AFTER the closing
# `---`; fm_get then returned empty and the run fired MISSING_KEY, not the asserted LINK_DANGLING.
d=$(mut open-dispatched)
fm_set "$d"/turns/0003-t0001-a01-dispatch.md receipt_source owner-answer
fm_add "$d"/turns/0003-t0001-a01-dispatch.md owner_answer_ref 0099-owner-answer.md
assert_violation "dangling owner_answer_ref on a receipt" LINK_DANGLING "$d"

# --- codes advertised since round 1 with no test at all. Each uses only fixtures that exist by
# --- THIS task; the result/answer-dependent ones are in Task 3, where their fixtures are built.
d=$(clone_fixture minimal); safe_rmdir "$d/turns" "$TMPROOT/case."   # D28: never a bare rm -rf
assert_violation "no turns/ directory" NO_TURNS "$d"
# Line 1 is not `---`, so D33's STRUCTURAL pass fires first and `continue`s — this case targets
# FM_MALFORMED. FM_UNPARSEABLE keeps its own case in Task 1 (a well-formed block with no
# record_seq), so neither code becomes advertised-but-untested.
d=$(clone_fixture minimal); printf 'no front matter here\n' > "$d/turns/0002-t0001-a01-intent.md"
assert_violation "no opening delimiter" FM_MALFORMED "$d"
d=$(clone_fixture open-dispatched); fm_set "$d"/turns/0003-*.md receipt_source carrier-pigeon
assert_violation "unknown receipt_source" BAD_RECEIPT_SOURCE "$d"
# an unmatched assignment that is not the newest assignment record
d=$(clone_fixture open-dispatched); cp "$d"/turns/0001-*.md "$d"/turns/0004-t0002-a01-assignment.md
fm_set "$d"/turns/0004-*.md record_seq 0004; fm_set "$d"/turns/0004-*.md turn_id 0002
assert_violation "older assignment left open" OPEN_NOT_NEWEST "$d"
d=$(clone_fixture minimal)
emit_late_for_test "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 02 null
emit_late_for_test "$d" 0003 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
assert_violation "late index goes backwards" LATE_NONMONOTONIC "$d"
d=$(clone_fixture minimal)
emit_late_for_test "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 not-a-sha
assert_violation "malformed named_sha" BAD_SHA "$d"

# structural guards (D1/D2): inspect code after stripping comments, not the explanatory comments.
if awk '{ sub(/[[:space:]]*#.*/, ""); if ($0 ~ /\|[[:space:]]*while/) found=1 } END { exit !found }' "$VALIDATE"; then
  nok "no piped while loops (D2)" "found a piped while in executable code"
else ok "no piped while loops (D2)"; fi
# The allocator's name is assembled from two fragments and never spelled literally in this file:
# these lines live in run-tests.sh, and the D28 scan below would otherwise flag the D1 guard's own
# pattern and messages as unchecked allocations — a guard firing on its neighbour's source is the
# same defect as one firing on its own. Both guards share MK_PAT for exactly that reason.
MK_PAT="mk""temp"
if awk -v pat="(^|[^[:alnum:]_])$MK_PAT([^[:alnum:]_]|\$)" \
   '{ sub(/[[:space:]]*#.*/, ""); if ($0 ~ pat) found=1 } END { exit !found }' "$VALIDATE"; then
  nok "no temp-dir allocation in the validator (D1)" "found one in executable code"
else ok "no temp-dir allocation in the validator (D1)"; fi

# D27 structural guard, stated narrowly enough to be checkable: NO in-place stream editor invocation
# anywhere in the harness files that exist at this point. This comment deliberately does NOT spell
# the two-token pattern it searches for — written out, it would live in run-tests.sh, the grep below
# would match it, and the guard would fail on its own source (rev.4's guards matching their own
# comments, in mirror image). `lib.sh` appears from Task 5 on; the list is built from what exists,
# and an empty list is a failure, not a silent pass by absence.
guard_files=""
# D38: pressure/run-scenario.sh joins the guarded set. It is one of the three files that actually
# shipped rev.6's unchecked-mktemp P0, and narrowing (j) left it covered by prose while the guard
# watched two files that never had the defect. mk_scan takes arbitrary files; the [ -f ] keeps the
# guard green before Task 8 creates it.
for p in "$HERE/run-tests.sh" "$HERE/lib.sh" "$HERE/../pressure/run-scenario.sh"; do
  [ -f "$p" ] && guard_files="$guard_files $p"; done
if [ -z "$guard_files" ]; then nok "harness files exist for the D27 guard" "none found under $HERE"
else ok "harness files exist for the D27 guard"; fi
if grep -n 'sed[[:space:]]\{1,\}-i' $guard_files >/dev/null 2>&1; then
  nok "no hand-rolled in-place record edit in the harness (D27)" "$(grep -n 'sed[[:space:]]\{1,\}-i' $guard_files)"
else ok "no hand-rolled in-place record edit in the harness (D27)"; fi
# ...and the guard itself is proven against a planted line, so a pattern that matches nothing cannot
# masquerade as a clean harness. The planted text is ASSEMBLED FROM A VARIABLE: written literally it
# would live in run-tests.sh, the guard above would match it, and the guard would fail on its own
# source — rev.4's guards matching their own comments, in mirror image.
PLANT_CMD=sed
printf '%s\n' "$PLANT_CMD -i '' 's/^a/b/' \"\$d\"/turns/0001-x.md" > "$TMPROOT/planted.sh"
if grep -q 'sed[[:space:]]\{1,\}-i' "$TMPROOT/planted.sh"; then
  ok "the D27 guard detects a planted in-place record edit"
else nok "the D27 guard detects a planted in-place record edit" "the guard pattern matches nothing"; fi

# D28 structural guard — the temp-dir claim is CHECKED, not asserted in prose. Rev.6's prose
# universal ("no unchecked temp-dir allocation anywhere in this plan") was false in THREE places
# written by that same revision, two of them helpers created for the decision. So it gets the same
# treatment as D1/D2/D27: an executable-lines scan over the harness files that exist at this point.
# The rule: an allocating line must carry `||` on the SAME line, or be a backslash continuation
# whose next line carries it. THE SEARCH TERM IS NEVER SPELLED IN THIS FILE — it is assembled from
# two fragments and passed in with `-v`, because written literally it would sit in run-tests.sh, the
# scan would flag its own source, and a guard that fires on itself is the D27 defect wearing the
# opposite sign. Every message below is phrased so it cannot contain the term either. MK_PAT is
# already defined above, beside the D1 guard, which shares it.
mk_scan() { # <file> -> prints offending lines
  awk -v pat="$MK_PAT" '
    { line=$0; sub(/[[:space:]]*#.*/, "", line); code[NR]=line }
    END { for (i=1; i<=NR; i++)
            if (code[i] ~ pat && code[i] !~ /\|\|/ &&
                !(code[i] ~ /\\$/ && code[i+1] ~ /\|\|/)) print FILENAME": "i": "code[i] }' "$1"; }
: > "$TMPROOT/mkscan"
for gf in $guard_files; do mk_scan "$gf" >> "$TMPROOT/mkscan"; done
if grep -q . "$TMPROOT/mkscan"; then
  nok "every temp-dir allocation in the harness checks its status (D28)" "$(cat "$TMPROOT/mkscan")"
else ok "every temp-dir allocation in the harness checks its status (D28)"; fi
# ...and the guard is proven against a planted unchecked allocation, assembled from the same two
# fragments for the same reason.
printf '%s\n' "x=\"\$($MK_PAT -d /tmp/x.XXXXXX)\"" > "$TMPROOT/planted-mk.sh"
if [ -n "$(mk_scan "$TMPROOT/planted-mk.sh")" ]; then
  ok "the D28 guard detects a planted unchecked allocation"
else nok "the D28 guard detects a planted unchecked allocation" "the guard pattern matches nothing"; fi

# C3 (acceptance round 2, coverage gap) — D15's two safety properties on the g() wrapper
# (`GIT_NO_REPLACE_OBJECTS=1`, `GIT_OPTIONAL_LOCKS=0`) are unenforced comments: removing either
# assignment individually left the whole suite green, because nothing asserted they were actually
# on the wrapper's executable line. Same shape as the D1/D2/D27/D28 structural guards above: pull
# the wrapper's own executable line (comments stripped) and require both assignments literally on
# it, then prove each guard against a planted line missing exactly one of the two.
g_line="$(awk '/^g\(\) \{/{ sub(/[[:space:]]*#.*/, ""); print; exit }' "$VALIDATE")"
case "$g_line" in
  *GIT_NO_REPLACE_OBJECTS=1*) ok "g() wrapper sets GIT_NO_REPLACE_OBJECTS=1 (D15)" ;;
  *) nok "g() wrapper sets GIT_NO_REPLACE_OBJECTS=1 (D15)" "wrapper line: $g_line" ;;
esac
case "$g_line" in
  *GIT_OPTIONAL_LOCKS=0*) ok "g() wrapper sets GIT_OPTIONAL_LOCKS=0 (D15)" ;;
  *) nok "g() wrapper sets GIT_OPTIONAL_LOCKS=0 (D15)" "wrapper line: $g_line" ;;
esac
planted_no_nro='g() { GIT_OPTIONAL_LOCKS=0 git -C "$@"; }'
case "$planted_no_nro" in
  *GIT_NO_REPLACE_OBJECTS=1*) nok "the D15 guard detects a wrapper missing GIT_NO_REPLACE_OBJECTS=1" "matched a line that lacks it" ;;
  *) ok "the D15 guard detects a wrapper missing GIT_NO_REPLACE_OBJECTS=1" ;;
esac
planted_no_lock='g() { GIT_NO_REPLACE_OBJECTS=1 git -C "$@"; }'
case "$planted_no_lock" in
  *GIT_OPTIONAL_LOCKS=0*) nok "the D15 guard detects a wrapper missing GIT_OPTIONAL_LOCKS=0" "matched a line that lacks it" ;;
  *) ok "the D15 guard detects a wrapper missing GIT_OPTIONAL_LOCKS=0" ;;
esac

# --- Task 3 cases ---
d=$(clone_fixture verified-normal); assert_check_ok "VERIFIED NORMAL result passes" "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md result_sha 1111111111111111111111111111111111111111
assert_violation "VERIFIED NORMAL stationary" RESULT_SHA_RULE "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md result_sha null
assert_violation "VERIFIED with null sha" RESULT_SHA_RULE "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason out-of-scope-changes
fm_set "$d"/turns/0004-*.md result_sha null
assert_violation "null sha with a commit-bearing reason" RESULT_SHA_RULE "$d"

# MINOR — D31's own comment says a no-op names base_sha. A forged no-op sha equal to an unexplained
# tip flips arm 5's verdict from UNRECORDED_DRIFT (alarm) to REMEDIATION_REQUIRED (mechanical) —
# alarm-softening. `reason: no-op-result` naming ANY non-base commit (not null — that is D31's own
# case above) must now be rejected. Dispatch stays present so REASON_CONTRADICTED cannot confound
# this with the reason-class closure rule.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason no-op-result
assert_violation "no-op-result naming a non-base commit (forged stationary result)" RESULT_SHA_RULE "$d"
# (over-rejection guard, naming the attempt's own base_sha: "REJECTED: no-op-result naming base_sha
# with a dispatch receipt on file is legal (over-rejection guard)", added with the reason-class
# closure cases below.)

# Passable only because the fixture carries a bare `reason:` key. Rev.5's sed no-opped, leaving
# `reason` absent, which fired BAD_REASON and never MISSING_EVIDENCE — the case could not pass.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status ABORTED
fm_set "$d"/turns/0004-*.md reason terminated-before-result
fm_set "$d"/turns/0004-*.md result_sha null
assert_violation "owner-authorized reason without owner_answer_ref" MISSING_EVIDENCE "$d"

d=$(clone_fixture review-turn); assert_check_ok "REVIEW result, sha == base" "$d"
d=$(mut review-turn); fm_set "$d"/turns/0004-*.md result_sha 3333333333333333333333333333333333333333
assert_violation "REVIEW result that moved" RESULT_SHA_RULE "$d"

# --- D31: the status x reason x result_sha matrix, one case per cell the union list let through.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status ABORTED
fm_set "$d"/turns/0004-*.md reason transport-lossy
assert_violation "ABORTED naming a landed commit" RESULT_SHA_RULE "$d"

d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status ABORTED
fm_set "$d"/turns/0004-*.md reason verification-failed
fm_set "$d"/turns/0004-*.md result_sha null
assert_violation "gate-failure reason under ABORTED" BAD_REASON "$d"

d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md reason verification-failed
assert_violation "VERIFIED carrying a failure reason" BAD_REASON "$d"

# Intent-less (§6.3.3 shape) so only the SUPERSEDED/BAD_REASON clause under test can fire — with
# an intent on file this would ALSO trip REASON_CONTRADICTED (this reason's own class of defect).
d=$(mut verified-normal)
rm "$d"/turns/0002-t0001-a01-intent.md "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0002-t0001-a01-result.md
fm_set "$d"/turns/0002-t0001-a01-result.md record_seq 0002
fm_set "$d"/turns/0002-t0001-a01-result.md status SUPERSEDED
fm_set "$d"/turns/0002-t0001-a01-result.md reason never-dispatched
assert_violation "never-dispatched under SUPERSEDED" BAD_REASON "$d"

d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason other
body_del "$d"/turns/0004-*.md
assert_violation "reason: other with no explanation" MISSING_EVIDENCE "$d"

# REVIEW forbids commits in every status, not only when the turn passed.
d=$(mut review-turn); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason review-failed
fm_set "$d"/turns/0004-*.md result_sha 3333333333333333333333333333333333333333
assert_violation "REJECTED REVIEW that named a commit" RESULT_SHA_RULE "$d"

# The `never-dispatched` narrowing (fable round 4) shipped with NO negative test; these two are it.
# §6.3.3 routes `never-dispatched` through ABORTED, so under REJECTED it is BAD_REASON — NOT
# RESULT_SHA_RULE: with the D31 deny list, a null sha is legal for every non-commit-bearing reason,
# so the old NOCOMMIT allow list is not what rejects this record.
# Intent-less (§6.3.3 shape), same reason as above.
d=$(mut verified-normal)
rm "$d"/turns/0002-t0001-a01-intent.md "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0002-t0001-a01-result.md
fm_set "$d"/turns/0002-t0001-a01-result.md record_seq 0002
fm_set "$d"/turns/0002-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0002-t0001-a01-result.md reason never-dispatched
fm_set "$d"/turns/0002-t0001-a01-result.md result_sha null
assert_violation "REJECTED: never-dispatched is not a REJECTED reason" BAD_REASON "$d"

# D37 — the deny list's other half. codex round 6: `REJECTED + agent-declined-with-question + <sha>`
# validated, i.e. a record claiming a commit after a decline, against §3.2's "null ... reserved for
# no-commit failure results (ABORTED, declined)". Both SHA_FORBIDDEN_REASONS get a case.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason agent-declined-with-question
assert_violation "REJECTED: declined may not name a commit" RESULT_SHA_RULE "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason patch-apply-failed
assert_violation "REJECTED: patch-apply-failed may not name a commit" RESULT_SHA_RULE "$d"
# ...and its over-rejection guard: the same reasons with null are legal.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason agent-declined-with-question
fm_set "$d"/turns/0004-*.md result_sha null
assert_check_ok "REJECTED: declined + null is legal" "$d"
# The deliberate non-member: §4 step 3 can record residue-after-termination over a LANDED zombie
# commit, so it is not SHA-forbidden. Asserted so a later edit cannot quietly add it to the list.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason residue-after-termination
assert_check_ok "REJECTED: residue-after-termination may name the landed commit" "$d"

# Two over-rejection guards. A matrix that only ever says NO is indistinguishable from a broken one.
# REBUILT (REASON_CONTRADICTED amendment): this case used to run on `mut verified-normal`, whose
# one attempt carries BOTH an intent and a receipt — so it was asserting the fail-open as legal
# (§6.3.3's mechanical `never-dispatched` is authorized only by "no intent ever existed"; a result
# claiming that over an attempt that DID commit an intent is exactly the class REASON_CONTRADICTED
# now catches). Rebuilt on the actually-legal shape: assignment + ABORTED/never-dispatched result,
# no intent and no dispatch receipt anywhere in the attempt.
d=$(mut verified-normal)
rm "$d"/turns/0002-t0001-a01-intent.md "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0002-t0001-a01-result.md
fm_set "$d"/turns/0002-t0001-a01-result.md record_seq 0002
fm_set "$d"/turns/0002-t0001-a01-result.md status ABORTED
fm_set "$d"/turns/0002-t0001-a01-result.md reason never-dispatched
fm_set "$d"/turns/0002-t0001-a01-result.md result_sha null
assert_check_ok "ABORTED: never-dispatched with no intent/receipt is legal (§6.3.3 shape)" "$d"

# --- REASON_CONTRADICTED: a reason whose justification IS a record shape must be checked against
# --- that shape (item 3/4 companions to the amendment above). Two shapes reproduced against HEAD:
# --- intent-only, and intent+receipt — `never-dispatched` is self-contradicted by either.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status ABORTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason never-dispatched
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "never-dispatched contradicted by a committed intent (no receipt)" REASON_CONTRADICTED "$d"

d=$(mut verified-normal)
fm_set "$d"/turns/0004-*.md status ABORTED
fm_set "$d"/turns/0004-*.md reason never-dispatched
fm_set "$d"/turns/0004-*.md result_sha null
assert_violation "never-dispatched contradicted by intent AND receipt" REASON_CONTRADICTED "$d"

# dispatch-confirmed-absent is likewise self-contradicted by a receipt on file for the attempt: the
# receipt is the very thing the owner supposedly confirmed absent. Built like D25 dim4/dim5 above
# (owner-action-pending + an answer overridden to dispatch-confirmed-absent + an ABORTED result
# correctly citing it), but with a real dispatch receipt ALSO on file for the same attempt.
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_dispatch "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md 0002-t0001-a01-intent.md direct
fm_set "$d"/turns/0005-t0001-a01-dispatch.md topic_id owner-action-pending
emit_result "$d" 0006 0001 01 NORMAL ABORTED dispatch-confirmed-absent null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0006-t0001-a01-result.md topic_id owner-action-pending
assert_violation "dispatch-confirmed-absent contradicted by a dispatch receipt on file" REASON_CONTRADICTED "$d"

# The `never-dispatched` guard is `intent==0 AND dispatch==0` — a receipt alone must also
# contradict it, independent of the intent conjunct (D25's own lesson: a two-conjunct guard with
# only intent-bearing fixtures leaves the dispatch conjunct untested). `intent_ref` deliberately
# names an intent record that was never written, so LINK_DANGLING is asserted alongside — the
# fixture cannot be made to trip ONLY REASON_CONTRADICTED without a real intent on file, and a real
# intent on file would make the intent conjunct redundant with the cases above.
d=$(clone_fixture minimal)
emit_dispatch "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 0002-t0001-a01-intent.md direct
fm_set "$d"/turns/0002-t0001-a01-dispatch.md topic_id minimal
emit_result "$d" 0003 0001 01 NORMAL ABORTED never-dispatched null 0001-t0001-a01-assignment.md
fm_set "$d"/turns/0003-t0001-a01-result.md topic_id minimal
assert_violations "never-dispatched contradicted by a dispatch receipt with no intent" \
  "LINK_DANGLING REASON_CONTRADICTED" "$d"

# --- Finding A (codex round 3, P0) ---------------------------------------------------------------
# A `late` record is evidence something WAS dispatched for the attempt, same class as a committed
# intent or receipt — REASON_CONTRADICTED previously only counted intent/dispatch, so a `late`
# record on file did not contradict `never-dispatched` or `dispatch-confirmed-absent`.
d=$(clone_fixture minimal)
emit_late_for_test "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
emit_result "$d" 0003 0001 01 NORMAL ABORTED never-dispatched null 0001-t0001-a01-assignment.md
fm_set "$d"/turns/0003-t0001-a01-result.md topic_id minimal
assert_violation "never-dispatched contradicted by a late observation (no intent/receipt)" REASON_CONTRADICTED "$d"

d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_late_for_test "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
fm_set "$d"/turns/0005-t0001-a01-late-01.md topic_id owner-action-pending
emit_result "$d" 0006 0001 01 NORMAL ABORTED dispatch-confirmed-absent null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0006-t0001-a01-result.md topic_id owner-action-pending
assert_violation "dispatch-confirmed-absent contradicted by a late observation (no dispatch receipt)" REASON_CONTRADICTED "$d"

# Over-rejection guard: the §6.3.3-legal shape (assignment + result, nothing else — no intent, no
# dispatch, no late) must still validate clean. Reuses the shape already asserted above at
# "ABORTED: never-dispatched with no intent/receipt is legal (§6.3.3 shape)"; repeated here as an
# explicit companion to the two RED cases just added, so the guard sits beside what it guards.
d=$(mut verified-normal)
rm "$d"/turns/0002-t0001-a01-intent.md "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0002-t0001-a01-result.md
fm_set "$d"/turns/0002-t0001-a01-result.md record_seq 0002
fm_set "$d"/turns/0002-t0001-a01-result.md status ABORTED
fm_set "$d"/turns/0002-t0001-a01-result.md reason never-dispatched
fm_set "$d"/turns/0002-t0001-a01-result.md result_sha null
assert_check_ok "ABORTED: never-dispatched with no intent/receipt/late is legal (over-rejection guard)" "$d"

# --- Reason-class closure (the reviewer's general rule, three rounds after never-dispatched and
# dispatch-confirmed-absent each shipped alone): every reason whose text implies the job EXECUTED
# requires a dispatch receipt on file for that attempt. One RED case (receiptless, intent-only —
# §3.2 orders intent strictly before dispatch, so this is the minimal contradiction shape) and one
# OVER-REJECTION guard (the legitimate full assignment->intent->dispatch->result chain stays clean)
# per DISPATCH_REQUIRED_REASONS member. `verification-failed`'s and `agent-declined-with-question`'s
# over-rejection guards already exist just below/above (REJECTED + null + <reason> is legal) and are
# not duplicated here.

# transport-lossy — CRITICAL: §3.6 defines it as an integrity failure of a RELAYED result, which is
# impossible without a dispatch. Before this rule, an intent-only attempt + `ABORTED: transport-
# lossy` validated clean and closed a possibly-live job with no owner ever involved.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status ABORTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason transport-lossy
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "CRITICAL: transport-lossy contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status ABORTED
fm_set "$d"/turns/0004-*.md reason transport-lossy
fm_set "$d"/turns/0004-*.md result_sha null
assert_check_ok "ABORTED: transport-lossy with a dispatch receipt on file is legal (over-rejection guard)" "$d"

# verification-failed — describes a delivered job's OUTPUT, impossible pre-dispatch.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason verification-failed
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "verification-failed contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
# (over-rejection guard: "REJECTED + null + verification-failed is legal", just below)

# review-failed — same class as verification-failed.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason review-failed
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "review-failed contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason review-failed
fm_set "$d"/turns/0004-*.md result_sha null
assert_check_ok "REJECTED: review-failed with a dispatch receipt on file is legal (over-rejection guard)" "$d"

# no-op-result — COMMIT_BEARING, so the RED case names the attempt's base_sha (the only legal value
# after the MINOR fix below), not null; the contradiction under test is the missing dispatch, not
# the sha shape.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason no-op-result
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha 1111111111111111111111111111111111111111
assert_violation "no-op-result contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason no-op-result
fm_set "$d"/turns/0004-*.md result_sha 1111111111111111111111111111111111111111
assert_check_ok "REJECTED: no-op-result naming base_sha with a dispatch receipt on file is legal (over-rejection guard)" "$d"

# patch-apply-failed — SHA_FORBIDDEN, so null.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason patch-apply-failed
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "patch-apply-failed contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason patch-apply-failed
fm_set "$d"/turns/0004-*.md result_sha null
assert_check_ok "REJECTED: patch-apply-failed with a dispatch receipt on file is legal (over-rejection guard)" "$d"

# agent-declined-with-question — SHA_FORBIDDEN, so null.
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason agent-declined-with-question
fm_set "$d"/turns/0003-t0001-a01-result.md result_sha null
assert_violation "agent-declined-with-question contradicted by no dispatch receipt on file" REASON_CONTRADICTED "$d"
# (over-rejection guard: "REJECTED: declined + null is legal", above)

# --- DISPATCH_OR_OWNER_ANSWER_REASONS: §3.2's worktree-gate-failure path legitimately produces a
# RECEIPTLESS REJECTED for these two, but only WITH a resolvable owner_answer_ref — the owner is the
# one who observed the residue/diff, standing in for a receipt. Three cases each: RED (neither
# dispatch nor owner_answer_ref), and two over-rejection guards (dispatch present; receiptless with
# a resolvable owner_answer_ref).

# out-of-scope-changes
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason out-of-scope-changes
assert_violation "out-of-scope-changes contradicted by no dispatch receipt and no owner_answer_ref" REASON_CONTRADICTED "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason out-of-scope-changes
assert_check_ok "REJECTED: out-of-scope-changes with a dispatch receipt on file is legal (over-rejection guard)" "$d"
d=$(clone_fixture minimal)
emit_question "$d" 0002 q-0001 owner-confirmed-scope
fm_set "$d"/turns/0002-owner-question.md topic_id minimal
emit_answer "$d" 0003 q-0001 record-decision
fm_set "$d"/turns/0003-owner-answer.md topic_id minimal
emit_result "$d" 0004 0001 01 NORMAL REJECTED out-of-scope-changes 3333333333333333333333333333333333333333 \
  0001-t0001-a01-assignment.md 0003-owner-answer.md
fm_set "$d"/turns/0004-t0001-a01-result.md topic_id minimal
assert_check_ok "REJECTED: out-of-scope-changes receiptless with a resolvable owner_answer_ref is legal (over-rejection guard)" "$d"

# residue-after-termination
d=$(mut verified-normal)
rm "$d"/turns/0003-t0001-a01-dispatch.md
mv "$d"/turns/0004-t0001-a01-result.md "$d"/turns/0003-t0001-a01-result.md
fm_set "$d"/turns/0003-t0001-a01-result.md record_seq 0003
fm_set "$d"/turns/0003-t0001-a01-result.md status REJECTED
fm_set "$d"/turns/0003-t0001-a01-result.md reason residue-after-termination
assert_violation "residue-after-termination contradicted by no dispatch receipt and no owner_answer_ref" REASON_CONTRADICTED "$d"
# (over-rejection guard, dispatch present: "REJECTED: residue-after-termination may name the landed
# commit", above)
d=$(clone_fixture minimal)
emit_question "$d" 0002 q-0001 owner-confirmed-scope
fm_set "$d"/turns/0002-owner-question.md topic_id minimal
emit_answer "$d" 0003 q-0001 record-decision
fm_set "$d"/turns/0003-owner-answer.md topic_id minimal
emit_result "$d" 0004 0001 01 NORMAL REJECTED residue-after-termination null 0001-t0001-a01-assignment.md 0003-owner-answer.md
fm_set "$d"/turns/0004-t0001-a01-result.md topic_id minimal
assert_check_ok "REJECTED: residue-after-termination receiptless with a resolvable owner_answer_ref is legal (over-rejection guard)" "$d"

# --- terminated-before-result: its RECEIPT exemption stays (job_id fencing legitimately coexists
# with a receipt-less fence — the existing owner_answer_ref requirement is untouched), but it now
# also requires an INTENT on file: §6.3.3's proof is that no intent means provably nothing was ever
# dispatched, so there was nothing to terminate. Reproduced shape: lone assignment + question +
# `dispatch-termination-confirmed` answer + `ABORTED: terminated-before-result` citing it, with no
# intent anywhere — validated clean before this rule.
d=$(clone_fixture minimal)
emit_question "$d" 0002 q-0001 t0001-a01
fm_set "$d"/turns/0002-owner-question.md topic_id minimal
emit_answer "$d" 0003 q-0001 dispatch-termination-confirmed evidence="confirmed via owner"
fm_set "$d"/turns/0003-owner-answer.md topic_id minimal
emit_result "$d" 0004 0001 01 NORMAL ABORTED terminated-before-result null 0001-t0001-a01-assignment.md 0003-owner-answer.md
fm_set "$d"/turns/0004-t0001-a01-result.md topic_id minimal
assert_violation "terminated-before-result contradicted by no intent on file for this attempt" REASON_CONTRADICTED "$d"
# Over-rejection guard: the legitimate shape — an intent on file AND a correctly-cited
# dispatch-termination-confirmed answer, no dispatch receipt (job_id fencing) — stays clean.
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-termination-confirmed
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed via owner"
emit_result "$d" 0005 0001 01 NORMAL ABORTED terminated-before-result null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_check_ok "ABORTED: terminated-before-result with an intent on file is legal (over-rejection guard)" "$d"

# §3.2: "a NORMAL result with no reported SHA while the tip moved is REJECTED" — the case a
# NOCOMMIT allow list would have rejected (D31).
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason verification-failed
fm_set "$d"/turns/0004-*.md result_sha null
assert_check_ok "REJECTED + null + verification-failed is legal" "$d"

# The three MISSING_EVIDENCE actions. The fixture must carry NONE of the evidence keys or these
# cases pass for the wrong reason — asserted, not assumed (and there is nothing to delete, so no
# fm_del: an fm_del of an absent key aborts the run by design).
d=$(clone_fixture dispatch-question)
for k in transport job_id evidence; do
  if grep -q "^$k: " "$d/turns/0004-owner-answer.md"; then
    nok "dispatch-question fixture carries no $k" "present — the MISSING_EVIDENCE cases would be vacuous"
  else ok "dispatch-question fixture carries no $k"; fi
done
for a in dispatch-job-found dispatch-confirmed-absent dispatch-termination-confirmed; do
  d=$(mut dispatch-question)
  fm_set "$d"/turns/0004-owner-answer.md action "$a"
  assert_violation "$a without its required evidence" MISSING_EVIDENCE "$d"
done
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md action dispatch-unresolved
assert_check_ok "dispatch-unresolved needs no evidence" "$d"
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md action cancel-close
assert_violation "cancel-close on an attempt question" ACTION_CONTEXT "$d"
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md action authorize-close
assert_violation "general action on a dispatch question" ACTION_CONTEXT "$d"
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md action nonsense
assert_violation "unknown action value" BAD_ACTION "$d"
# `other` on an attempt question is ALSO out of context. Both codes are named so neither hides the
# other; the empty body is what produces MISSING_EVIDENCE, and only that.
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md action other
body_del "$d"/turns/0004-owner-answer.md
assert_violations "action: other without explanation" "ACTION_CONTEXT MISSING_EVIDENCE" "$d"
d=$(mut dispatch-question); fm_add "$d"/turns/0003-owner-question.md supersedes_question_ref q-nope
assert_violation "supersedes an unknown question" BAD_SUPERSEDES "$d"
# The row states FOUR rules ("resolves to an ANSWERED question with identical blocks", earlier);
# only the resolve clause was tested, because `q-nope` returns at the first check and never reaches
# the other three. Each case below adds a SECOND question at 0005 that supersedes the fixture's
# existing, answered `q-0001` — added after the answer, so no ordering or dangling code co-fires.
sup_q() { # <dir> <seq> <question-id> <blocks> <supersedes>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-question' 'topic_id: dispatch-question' \
    "question_id: $3" "blocks: $4" "supersedes_question_ref: $5" \
    'recorded_at: 2026-08-11T15:09:00Z' '---' 'Superseding question.' \
    > "$1/turns/$2-owner-question.md"
}
d=$(mut dispatch-question); sup_q "$d" 0005 q-0002 t0001-a01 q-0001
assert_check_ok "superseding a later, answered question with the same blocks is legal" "$d"
# (a) ordering: the superseded question must be EARLIER. Superseding ITSELF is the minimal case that
# trips only the ordering clause — same blocks, and it is its own (answered) question.
d=$(mut dispatch-question); fm_add "$d"/turns/0003-owner-question.md supersedes_question_ref q-0001
assert_violation "supersedes a question that is not earlier" BAD_SUPERSEDES "$d"
# (b) identical `blocks`
d=$(mut dispatch-question); sup_q "$d" 0005 q-0002 t0002-a01 q-0001
assert_violation "supersedes a question blocking a different state" BAD_SUPERSEDES "$d"
# (c) the superseded question must be ANSWERED. The answer is deleted, so `q-0001` is unanswered —
# and that also makes the topic AWAITING_OWNER, which is a classification, never a second code.
# The new question takes seq 0004, FILLING the hole the deletion leaves: numbered 0005 it would also
# trip SEQ_GAP, and under the D29 oracle a two-code run cannot satisfy a one-code assertion.
d=$(mut dispatch-question); rm -f "$d"/turns/0004-owner-answer.md
sup_q "$d" 0004 q-0002 t0001-a01 q-0001
assert_violation "supersedes an unanswered question" BAD_SUPERSEDES "$d"

# --- Finding B, second half (codex round 3) -----------------------------------------------------
# (d) the superseded question's ANSWER must precede the superseding question — not merely exist
# somewhere in the topic. §5's flow is "old answered dispatch-unresolved, THEN a new question
# supersedes it on explicit owner request"; nothing enforced that ORDER, only that old had SOME
# answer eventually. Built so old (q-0001) is asked first but answered LAST: the superseding
# question (q-0002) is asked and answered first, and only afterward does q-0001 receive its own
# (actionable) answer. Arm 3 classifies from the latest ANSWER by record_seq (§6.3.3, unaffected by
# this fix — see the comment beside it), so pre-fix this record shape let the late-arriving answer to
# the nominally-superseded question outrank the answer that was supposed to supersede it.
d=$(mut dispatch-question); rm -f "$d"/turns/0004-owner-answer.md
sup_q "$d" 0004 q-0002 t0001-a01 q-0001
emit_answer "$d" 0005 q-0002 dispatch-unresolved
fm_set "$d"/turns/0005-owner-answer.md topic_id dispatch-question
emit_answer "$d" 0006 q-0001 dispatch-job-found transport=codex job_id=j-9
fm_set "$d"/turns/0006-owner-answer.md topic_id dispatch-question
assert_violation "superseded question's answer arrives after the superseding question" BAD_SUPERSEDES "$d"

# --- the remaining round-1 codes, here because they need THIS task's fixtures (D27 editors) ---
# `reason` is set to a legal value too, so this case asserts BAD_STATUS and nothing else: any
# non-VERIFIED status makes the reason enum apply, and an empty reason is in no status's set.
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status BANANA
fm_set "$d"/turns/0004-*.md reason out-of-scope-changes
assert_violation "unknown status" BAD_STATUS "$d"
d=$(mut verified-normal); fm_set "$d"/turns/0004-*.md status REJECTED
fm_set "$d"/turns/0004-*.md reason not-a-listed-reason
assert_violation "unknown reason" BAD_REASON "$d"
# Deleting result_sha necessarily breaks the VERIFIED sha rule as well; both codes are named.
d=$(mut verified-normal); fm_del "$d"/turns/0004-*.md result_sha
assert_violations "result_sha is a required key" "MISSING_KEY RESULT_SHA_RULE" "$d"
d=$(mut dispatch-question); fm_set "$d"/turns/0004-owner-answer.md question_ref q-nonexistent
assert_violation "answer names no question" ANSWER_DANGLING "$d"
# D18's general clause — "every answer follows its question" — had no test: the one close-related
# LINK_ORDER case above trips the `close < question` clause instead. Swap the pair so the answer
# (0003) precedes its question (0004); both the filename prefix and `record_seq` move, or
# SEQ_FILENAME_MISMATCH co-fires. The answer's action is `dispatch-unresolved`, which needs no
# evidence and authorizes nothing, so no context or evidence code can fire alongside.
d=$(mut dispatch-question)
mv "$d"/turns/0003-owner-question.md "$d"/turns/0004-owner-question.md
mv "$d"/turns/0004-owner-answer.md   "$d"/turns/0003-owner-answer.md
fm_set "$d"/turns/0004-owner-question.md record_seq 0004
fm_set "$d"/turns/0003-owner-answer.md   record_seq 0003
assert_violation "an answer that precedes its question" LINK_ORDER "$d"
d=$(mut dispatch-question); cp "$d"/turns/0004-owner-answer.md "$d"/turns/0005-owner-answer.md
fm_set "$d"/turns/0005-owner-answer.md record_seq 0005
assert_violation "two answers for one question" ANSWER_DUP "$d"

# close ordering — all four shapes
emit_question_closing() { # <topic> <seq> <question-id> <blocks>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-question' 'topic_id: closing' \
    "question_id: $3" "blocks: $4" 'recorded_at: 2026-08-11T15:06:00Z' '---' \
    'Owner direction required.' > "$1/turns/$2-owner-question.md"
}
emit_answer_closing() { # <topic> <seq> <question-id> <action>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-answer' 'topic_id: closing' \
    "question_ref: $3" "action: $4" 'recorded_at: 2026-08-11T15:07:00Z' '---' \
    'Owner response captured verbatim.' > "$1/turns/$2-owner-answer.md"
}
emit_close_for_test() { # <topic> <seq> <close-id> <sha>
  printf '%s\n' '---' "record_seq: $2" 'kind: close' 'topic_id: closing' \
    "close_id: $3" "final_accepted_sha: $4" 'recorded_at: 2026-08-11T15:08:00Z' '---' \
    'Charter dispositions recorded.' > "$1/turns/$2-close.md"
}
d=$(clone_fixture closing); assert_check_ok "close with nothing after it passes" "$d"
d=$(mut closing); cp "$d"/turns/0001-*.md "$d"/turns/0006-t0009-a01-assignment.md
fm_set "$d"/turns/0006-*.md record_seq 0006; fm_set "$d"/turns/0006-*.md turn_id 0009
assert_violation "assignment after an active close" CLOSE_ORDER "$d"
d=$(mut closing); emit_close_for_test "$d" 0006 c-0002 2222222222222222222222222222222222222222
assert_violation "second close inside an active close window" CLOSE_ORDER "$d"
# §3.8 step 3 — "the only safe resolution is cancel-close". Rev.5 added this clause and rev.6
# shipped it with NO test: every ACTION_CONTEXT case used `dispatch-question` (ctx=attempt), and
# every case that produced ctx=close answered with `cancel-close`, the one value the branch permits.
# Both cases below are single-code by construction: `cancelling_answer_seq` requires
# `action: cancel-close`, so no cancellation fires, the close's window stays empty, and the question
# and answer are both legal occupants of it — CLOSE_ORDER cannot co-fire.
d=$(mut closing); emit_question_closing "$d" 0006 q-close-1 CLOSING:c-0001
emit_answer_closing "$d" 0007 q-close-1 record-decision
assert_violation "only cancel-close may resolve a CLOSING question" ACTION_CONTEXT "$d"
# The sibling clause: a DISPATCH action on a question that does not block an attempt tuple.
# `dispatch-unresolved` needs no evidence, so MISSING_EVIDENCE cannot co-fire.
d=$(mut closing); emit_question_closing "$d" 0006 q-close-1 CLOSING:c-0001
emit_answer_closing "$d" 0007 q-close-1 dispatch-unresolved
assert_violation "a dispatch action cannot answer a CLOSING question" ACTION_CONTEXT "$d"

# Whole-branch review, finding 1: two rules an earlier review misjudged as "masked and redundant"
# — both are single-code fail-opens, proved by neutering each target line and watching these two
# cases go clean. Neither fixture reuses `emit_question_closing`'s CLOSING:-prefixed helper on
# purpose: both probe what happens when `blocks` on a `cancel-close` answer is NOT in that shape.
#
# validate.sh:317 — a topic with NO close record at all. `blocks: CLOSING:c-nope` still classifies
# ctx=close (the case pattern only looks at the prefix), so the cancel-close is legal in shape; the
# close-search loop finds nothing, `found` stays `no`, and :317 is the only rule that objects.
emit_bare_question() { # <dir> <seq> <question-id> <blocks> <topic>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-question' "topic_id: $5" \
    "question_id: $3" "blocks: $4" 'recorded_at: 2026-08-11T15:03:00Z' '---' \
    'Owner direction required.' > "$1/turns/$2-owner-question.md"
}
emit_bare_answer() { # <dir> <seq> <question-id> <action> <topic>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-answer' "topic_id: $5" \
    "question_ref: $3" "action: $4" 'recorded_at: 2026-08-11T15:04:00Z' '---' \
    'Owner response captured verbatim.' > "$1/turns/$2-owner-answer.md"
}
d=$(mut dispatch-unknown)
emit_bare_question "$d" 0003 q-close-nope CLOSING:c-nope dispatch-unknown
emit_bare_answer "$d" 0004 q-close-nope cancel-close dispatch-unknown
assert_violation "cancel-close names a close_id with no close record" ACTION_CONTEXT "$d"

# validate.sh:309 — the topic DOES have close c-0001, and `blocks` is the BARE close id `c-0001`
# (no `CLOSING:` prefix), so the case pattern falls through to ctx=other. `${blocks#CLOSING:}` is a
# no-op on a string that never carried the prefix, so `cid` still equals `c-0001` and the
# close-search loop still finds it: without :309, only the ctx guard stood between a bare close id
# and treating it exactly like `CLOSING:c-0001`. A LEGITIMATE cancel-close pair (0006/0007) closes
# the window first, so the window-occupancy check (CLOSE_ORDER) cannot fire on what follows; the
# bare-id pair is placed past that cancellation (0008/0009), where :314's ordering check is
# satisfied trivially (0008 > close's 0005) either way — isolating :309 as the one line standing
# between this pair and silent acceptance. (A bare-id pair placed BEFORE the close instead trips
# :314's LINK_ORDER as a second code — checked directly, not assumed — so it cannot serve as a
# single-code pin; this placement is the one that does.)
d=$(mut closing)
emit_question_closing "$d" 0006 q-close-legit CLOSING:c-0001
emit_answer_closing "$d" 0007 q-close-legit cancel-close
emit_bare_question "$d" 0008 q-close-bare c-0001 closing
emit_bare_answer "$d" 0009 q-close-bare cancel-close closing
assert_violation "cancel-close naming a bare close id (no CLOSING: prefix)" ACTION_CONTEXT "$d"

d=$(mut closing); emit_question_closing "$d" 0006 q-close-1 CLOSING:c-0001
emit_answer_closing "$d" 0007 q-close-1 cancel-close
cp "$d"/turns/0001-*.md "$d"/turns/0008-t0009-a01-assignment.md
fm_set "$d"/turns/0008-*.md record_seq 0008; fm_set "$d"/turns/0008-*.md turn_id 0009
assert_check_ok "records resume after cancel-close" "$d"
d=$(mut closing); emit_question_closing "$d" 0006 q-close-1 CLOSING:c-0001
cp "$d"/turns/0001-*.md "$d"/turns/0007-t0009-a01-assignment.md
fm_set "$d"/turns/0007-*.md record_seq 0007; fm_set "$d"/turns/0007-*.md turn_id 0009
emit_answer_closing "$d" 0008 q-close-1 cancel-close
assert_violation "assignment inside the pre-cancel window" CLOSE_ORDER "$d"

# D18: a question/answer cannot pre-authorize cancellation of a later close.
d=$(mut closing); mv "$d"/turns/0005-close.md "$d"/turns/0007-close.md
fm_set "$d"/turns/0007-close.md record_seq 0007
emit_question_closing "$d" 0005 q-close-early CLOSING:c-0001
emit_answer_closing "$d" 0006 q-close-early cancel-close
assert_violation "cancel-close authorization must follow its close" LINK_ORDER "$d"

# D17 — a close may not name a SHA the record never accepted (codex N4)
d=$(mut closing); fm_set "$d"/turns/0005-close.md final_accepted_sha 4444444444444444444444444444444444444444
assert_violation "close names an unaccepted sha" CLOSE_SHA_MISMATCH "$d"

# A duplicate close_id necessarily also sits inside the first close's window; both codes are named.
d=$(mut closing); emit_close_for_test "$d" 0006 c-0001 2222222222222222222222222222222222222222
assert_violations "two closes share a close_id" "CLOSE_ID_DUP CLOSE_ORDER" "$d"

# --- D30: §3.8 step 1's OTHER precondition. Both fixtures below validated clean through rev.5 —
# --- CLOSE_ORDER only looks after the close, OPEN_NOT_NEWEST does not fire on a lone open attempt,
# --- and CLOSE_SHA_MISMATCH passes because accepted_sha never advanced. Each fixture is built so
# --- exactly one clause trips: the SHA is corrected in the first, and the second adds only a
# --- question.
d=$(mut closing)
rm "$d"/turns/0004-t0001-a01-result.md
mv "$d"/turns/0005-close.md "$d"/turns/0004-close.md
fm_set "$d"/turns/0004-close.md record_seq 0004
fm_set "$d"/turns/0004-close.md final_accepted_sha 1111111111111111111111111111111111111111
assert_violation "close over an attempt with no terminal result" CLOSE_PRECONDITION "$d"

d=$(mut closing)
mv "$d"/turns/0005-close.md "$d"/turns/0006-close.md
fm_set "$d"/turns/0006-close.md record_seq 0006
emit_question_closing "$d" 0005 q-open-1 t0001-a01
assert_violation "close over an unanswered owner question" CLOSE_PRECONDITION "$d"

d=$(mut dispatch-question); cp "$d"/turns/0003-owner-question.md "$d"/turns/0005-owner-question.md
fm_set "$d"/turns/0005-owner-question.md record_seq 0005
assert_violation "duplicate question_id" QUESTION_DUP "$d"

# --- D32: topic identity. The owner-question is used because it is not tuple-linked, so
# --- LINK_TUPLE_MISMATCH cannot fire alongside and mask which rule actually caught it.
d=$(mut dispatch-question); fm_set "$d"/turns/0003-owner-question.md topic_id another-topic
assert_violation "a record carrying a foreign topic_id" TOPIC_ID_MISMATCH "$d"

# Through the D27 editors: hand-writing a two-line TOPIC.md would ALSO trip TOPIC_MISSING_KEY,
# TOPIC_BASE_MISMATCH and TOPIC_ID_MISMATCH, so the case would no longer fail for the reason it
# names.
d=$(mut open-dispatched); fm_set "$d/TOPIC.md" session_branch pair/other
assert_violation "assignment disagrees with TOPIC.md" TOPIC_MISMATCH "$d"
d=$(mut open-dispatched); fm_set "$d/TOPIC.md" base_sha 2222222222222222222222222222222222222222
assert_violation "first assignment disagrees with the pinned base" TOPIC_BASE_MISMATCH "$d"
# Deleting an identity key is TWO codes now that the `[ -n "$want" ] || continue` skip is gone: the
# key is missing AND every assignment disagrees with the empty value. Both are named. The other two
# identity keys share this loop and this code path exactly and are not separately tested — stated,
# not left to be assumed as covered.
d=$(mut open-dispatched); fm_del "$d/TOPIC.md" session_branch
assert_violations "a missing identity key is reported, not skipped" \
  "TOPIC_MISSING_KEY TOPIC_MISMATCH" "$d"

# --- Task 4 cases ---
assert_classification() { # <desc> <expected> <dir>
  [ $# -eq 3 ] || { nok "${1:-assert_classification}" "usage: <desc> <expected> <dir> (got $# args)"; return 0; }
  have_case "$1" "$3" || return 0
  /bin/bash "$VALIDATE" --check "$3" >"$TMPROOT/out" 2>"$TMPROOT/err"
  if grep -q "^classification: $2" "$TMPROOT/out"; then ok "$1"
  else nok "$1" "wanted '$2', got: $(grep '^classification:' "$TMPROOT/out"; head -3 "$TMPROOT/err")"; fi; }
assert_postcondition() { # <desc> <name> <PASS|FAIL|UNAVAILABLE> <dir>
  [ $# -eq 4 ] || { nok "${1:-assert_postcondition}" "usage: <desc> <name> <verdict> <dir> (got $# args)"; return 0; }
  have_case "$1" "$4" || return 0
  /bin/bash "$VALIDATE" --check "$4" >"$TMPROOT/out" 2>&1
  grep -q "^postcondition $2: $3$" "$TMPROOT/out" && ok "$1" \
    || nok "$1" "wanted 'postcondition $2: $3', got: $(grep '^postcondition' "$TMPROOT/out")"; }

d=$(clone_fixture minimal);                   assert_classification "lone assignment"        "OPEN (never-dispatched)" "$d"
d=$(clone_fixture open-dispatched);           assert_classification "receipt present"        "OPEN (dispatched)" "$d"
d=$(clone_fixture dispatch-unknown);          assert_classification "intent, no receipt"     "DISPATCH_UNKNOWN" "$d"
d=$(clone_fixture awaiting-owner);            assert_classification "unanswered question"    "AWAITING_OWNER" "$d"
d=$(clone_fixture dispatch-unresolved);       assert_classification "unresolved stays unknown" "DISPATCH_UNKNOWN" "$d"
d=$(clone_fixture owner-action-pending);      assert_classification "actionable, unmaterialized" "OWNER_ACTION_PENDING" "$d"
# B1 (acceptance rev.2, P1 blocker) — §6.3.3: "latest answer dispatch-unresolved → remain
# DISPATCH_UNKNOWN without another automatic question." A SECOND question blocking the SAME
# attempt, answered LATER with dispatch-unresolved, must supersede the earlier actionable answer —
# not be ignored by a scan that stops at the first hit.
d=$(clone_fixture owner-action-pending)
emit_question "$d" 0005 q-0002 t0001-a01
emit_answer "$d" 0006 q-0002 dispatch-unresolved
fm_set "$d"/turns/0005-owner-question.md topic_id owner-action-pending
fm_set "$d"/turns/0006-owner-answer.md topic_id owner-action-pending
assert_classification "later dispatch-unresolved supersedes an earlier actionable answer" "DISPATCH_UNKNOWN" "$d"
d=$(clone_fixture owner-action-materialized); assert_classification "materialized receipt"   "OPEN (dispatched)" "$d"
# D25: a mismatched authorization is CORRUPTION, not a state. These were rev.4's two new tests,
# asserting OWNER_ACTION_PENDING — a state arm 3 cannot produce once a receipt exists, because it
# returns OPEN (dispatched) first. They are violations now, and they fire in Task 3's stage.
d=$(clone_fixture owner-action-materialized)
fm_set "$d"/turns/*-dispatch.md job_id different-job
assert_violation "different job cannot materialize authorization" OWNER_ANSWER_MISMATCH "$d"
d=$(clone_fixture owner-action-materialized)
fm_set "$d"/turns/*-dispatch.md transport different-transport
assert_violation "different transport cannot materialize authorization" OWNER_ANSWER_MISMATCH "$d"
d=$(clone_fixture owner-action-miskind)
assert_violation "wrong record kind cannot materialize authorization" OWNER_ANSWER_MISMATCH "$d"
# D25's three missing dimensions. Each of these validated CLEAN through rev.5 and then classified
# `OPEN (dispatched)` — arm 3 returns on the dispatch COUNT, so no classification-stage rule could
# ever have caught them. Each fixture trips exactly one clause, and each clause has its own code so
# a green test cannot be green for a neighbour's reason.
d=$(clone_fixture owner-action-materialized)      # receipt cites an answer that comes AFTER it
mv "$d"/turns/0004-owner-answer.md "$d"/turns/0005-owner-answer.md.tmp
mv "$d"/turns/0005-t0001-a01-dispatch.md "$d"/turns/0004-t0001-a01-dispatch.md
mv "$d"/turns/0005-owner-answer.md.tmp "$d"/turns/0005-owner-answer.md
fm_set "$d"/turns/0005-owner-answer.md record_seq 0005
fm_set "$d"/turns/0004-t0001-a01-dispatch.md record_seq 0004
fm_set "$d"/turns/0004-t0001-a01-dispatch.md owner_answer_ref 0005-owner-answer.md
assert_violation "receipt citing a future answer" OWNER_ANSWER_ORDER "$d"

d=$(clone_fixture owner-action-materialized)      # answer authorizes a DIFFERENT attempt
fm_set "$d"/turns/0003-owner-question.md blocks t0002-a01
assert_violation "receipt citing another attempt's answer" OWNER_ANSWER_TUPLE "$d"

d=$(clone_fixture owner-action-materialized)      # dispatch-unresolved authorizes nothing (§3.2)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-unresolved
assert_violation "dispatch-unresolved cannot authorize a receipt" OWNER_ANSWER_UNAUTHORIZED "$d"

# --- Finding C1 (acceptance round 2, coverage gap) ---------------------------------------------
# D25's five-dimension authorization binding (validate.sh:~538: dispatch kind, receipt source,
# result kind, result status, result reason) could each be neutered INDIVIDUALLY with the suite
# staying green: the existing fixtures above (owner-action-miskind, the future/tuple/unresolved
# trio) each trip TWO or more of these clauses at once — or a wholly separate check outside D25 —
# so removing any ONE guard left a neighbouring clause to still fire OWNER_ANSWER_MISMATCH and
# mask the hole. Each case below is built so ONLY its own guard can produce that code.
#
# dim 1 — dispatch-job-found must be materialized by kind: dispatch. A `late` record (never
# subject to MULTI_PER_ATTEMPT, so it can coexist with the fixture's real dispatch) forges the
# other three checked fields (receipt_source/transport/job_id) so only the kind check can fire.
d=$(clone_fixture owner-action-materialized)
emit_late "$d" 0006 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
fm_set "$d"/turns/0006-t0001-a01-late-01.md topic_id owner-action-materialized
fm_add "$d"/turns/0006-t0001-a01-late-01.md owner_answer_ref 0004-owner-answer.md
fm_add "$d"/turns/0006-t0001-a01-late-01.md receipt_source owner-answer
fm_add "$d"/turns/0006-t0001-a01-late-01.md transport codex
fm_add "$d"/turns/0006-t0001-a01-late-01.md job_id j-9
assert_violation "D25 dim1: dispatch-job-found cited by a non-dispatch record" OWNER_ANSWER_MISMATCH "$d"

# dim 2 — dispatch-job-found's receipt must carry receipt_source: owner-answer. A REAL dispatch
# record with receipt_source: direct that still (illegally) cites the answer, with transport/
# job_id forged to match, so only the receipt_source check can fire.
d=$(clone_fixture owner-action-pending)
emit_dispatch "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md 0002-t0001-a01-intent.md direct 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-dispatch.md topic_id owner-action-pending
fm_set "$d"/turns/0005-t0001-a01-dispatch.md transport codex
fm_set "$d"/turns/0005-t0001-a01-dispatch.md job_id j-9
assert_violation "D25 dim2: dispatch-job-found materialized with receipt_source != owner-answer" OWNER_ANSWER_MISMATCH "$d"

# dim 3 — dispatch-confirmed-absent must be materialized by kind: result. Same `late`-record trick
# as dim 1, with status/reason forged to match so only the kind check can fire.
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_late "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md 01 null
fm_set "$d"/turns/0005-t0001-a01-late-01.md topic_id owner-action-pending
fm_add "$d"/turns/0005-t0001-a01-late-01.md owner_answer_ref 0004-owner-answer.md
fm_add "$d"/turns/0005-t0001-a01-late-01.md status ABORTED
fm_add "$d"/turns/0005-t0001-a01-late-01.md reason dispatch-confirmed-absent
assert_violation "D25 dim3: dispatch-confirmed-absent cited by a non-result record" OWNER_ANSWER_MISMATCH "$d"

# dim 4 — the materializing result must carry status: ABORTED. A real result whose reason equals
# the authorized dispatch-confirmed-absent (so dim 5 cannot also fire) but whose status is
# REJECTED. §3.2's terminal-status matrix independently rejects `dispatch-confirmed-absent` as a
# REJECTED reason (BAD_REASON) — that is a genuinely different rule catching a genuinely different
# thing, so it is asserted alongside, not worked around.
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_result "$d" 0005 0001 01 NORMAL REJECTED dispatch-confirmed-absent null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_violations "D25 dim4: dispatch-confirmed-absent materialized by a non-ABORTED result" "BAD_REASON OWNER_ANSWER_MISMATCH" "$d"

# dim 5 — the materializing ABORTED result's reason must equal the answer's OWN dispatch reason
# (dispatch-confirmed-absent -> dispatch-confirmed-absent, dispatch-termination-confirmed ->
# terminated-before-result), not merely any legal ABORTED reason. status: ABORTED and reason: other
# are each independently legal (no BAD_REASON), so only dim 5 can fire.
# (Not `never-dispatched`: this fixture carries a committed intent for the attempt, which would
# ALSO trip REASON_CONTRADICTED. Not `transport-lossy` either, for the same reason since the
# reason-class closure rule: the fixture carries no dispatch receipt for the attempt, and
# `transport-lossy` is now in DISPATCH_REQUIRED_REASONS — it would independently trip
# REASON_CONTRADICTED, a different code than the one dim 5 tests for. `other` carries no such
# claim, so it stays the clean single-code probe for THIS rule.)
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_result "$d" 0005 0001 01 NORMAL ABORTED other null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_violation "D25 dim5: dispatch-confirmed-absent materialized with the wrong ABORTED reason" OWNER_ANSWER_MISMATCH "$d"

# --- Gate-failure deadlock fix ------------------------------------------------------------------
# §3.2's worktree-gate-failure fallback: when the primary inspects the worktree after an
# owner-authorized dispatch-confirmed-absent/dispatch-termination-confirmed and finds residue (or
# an out-of-scope diff), the truthful record is REJECTED + residue-after-termination/
# out-of-scope-changes citing that SAME answer — not the ABORTED materialization dim4/dim5 test
# above. Before this fix, D25(iii) accepted only the ABORTED path, so this truthful record fired
# OWNER_ANSWER_MISMATCH twice with no valid encoding available at all — a fail-closed deadlock on
# the crash-recovery path this protocol exists for.
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_result "$d" 0005 0001 01 NORMAL REJECTED residue-after-termination null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_check_ok "gate-failure fallback: dispatch-confirmed-absent materialized as REJECTED residue-after-termination is legal" "$d"

d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-termination-confirmed
fm_add "$d"/turns/0004-owner-answer.md evidence "termination confirmed via transport dashboard"
emit_result "$d" 0005 0001 01 NORMAL REJECTED out-of-scope-changes 3333333333333333333333333333333333333333 \
  0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_check_ok "gate-failure fallback: dispatch-termination-confirmed materialized as REJECTED out-of-scope-changes is legal" "$d"

# RED: a REJECTED reason outside the gate-failure set still fires OWNER_ANSWER_MISMATCH — the
# fallback is exactly the two §3.2 reasons, not "any REJECTED".
d=$(clone_fixture owner-action-pending)
fm_set "$d"/turns/0004-owner-answer.md action dispatch-confirmed-absent
fm_add "$d"/turns/0004-owner-answer.md evidence "confirmed absent via transport dashboard"
emit_result "$d" 0005 0001 01 NORMAL REJECTED other null 0001-t0001-a01-assignment.md 0004-owner-answer.md
fm_set "$d"/turns/0005-t0001-a01-result.md topic_id owner-action-pending
assert_violation "gate-failure fallback does not extend to arbitrary REJECTED reasons" OWNER_ANSWER_MISMATCH "$d"

# --- Finding C1 (CRITICAL, acceptance round) --------------------------------------------------
# §3.2: an owner may authorize closing an UN-RECEIPTED attempt only via dispatch-job-found,
# dispatch-confirmed-absent, or dispatch-termination-confirmed, and the closing record must cite
# that exact answer. Before the fix, `validate.sh:368-372` required only that `owner_answer_ref` be
# PRESENT, and D25's general-action branch (`: ;;`) bound nothing — so a result citing a GENERAL
# answer (`record-decision`) closed an attempt that was never confirmed absent. Reproduction: an
# assignment + intent with NO dispatch receipt (the exact crash window §3.2 fences), an answered
# general question, and an ABORTED result citing that general answer.
emit_intent_for_test() { # <topic> <seq> <turn> <attempt> <turn_kind> <assignment-ref> <token>
  printf '%s\n' '---' "record_seq: $2" 'kind: intent' 'topic_id: minimal' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" \
    "idempotency_token: $7" 'recorded_at: 2026-08-11T15:09:30Z' '---' \
    'Dispatch intent.' > "$1/turns/$2-t$3-a$4-intent.md"
}
emit_general_question() { # <topic> <seq> <question-id> <blocks>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-question' 'topic_id: minimal' \
    "question_id: $3" "blocks: $4" 'recorded_at: 2026-08-11T15:10:00Z' '---' \
    'Owner direction required.' > "$1/turns/$2-owner-question.md"
}
emit_general_answer() { # <topic> <seq> <question-ref> <action>
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-answer' 'topic_id: minimal' \
    "question_ref: $3" "action: $4" 'recorded_at: 2026-08-11T15:11:00Z' '---' \
    'Owner response captured verbatim.' > "$1/turns/$2-owner-answer.md"
}
emit_result_for_test() { # <topic> <seq> <turn> <attempt> <turn_kind> <assignment-ref> <status> <reason> <sha> <answer-ref>
  out="$1/turns/$2-t$3-a$4-result.md"
  printf '%s\n' '---' "record_seq: $2" 'kind: result' 'topic_id: minimal' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" \
    "status: $7" "reason: $8" "result_sha: $9" 'observed_at: 2026-08-11T15:12:00Z' > "$out"
  printf 'owner_answer_ref: %s\n' "${10}" >> "$out"
  printf '%s\n' 'recorded_at: 2026-08-11T15:12:00Z' '---' 'Captured result.' >> "$out"
}

d=$(clone_fixture minimal)
emit_intent_for_test  "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md tok-c1a
emit_general_question "$d" 0003 q-gen-1 general-note
emit_general_answer   "$d" 0004 q-gen-1 record-decision
emit_result_for_test  "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md \
  ABORTED dispatch-confirmed-absent null 0004-owner-answer.md
assert_violation "C1: dispatch-confirmed-absent citing a general answer must not close" \
  OWNER_ANSWER_MISMATCH "$d"

d=$(clone_fixture minimal)
emit_intent_for_test  "$d" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md tok-c1b
emit_general_question "$d" 0003 q-gen-1 general-note
emit_general_answer   "$d" 0004 q-gen-1 record-decision
emit_result_for_test  "$d" 0005 0001 01 NORMAL 0001-t0001-a01-assignment.md \
  ABORTED terminated-before-result null 0004-owner-answer.md
assert_violation "C1: terminated-before-result citing a general answer must not close" \
  OWNER_ANSWER_MISMATCH "$d"

# --- Finding I2 (Important, same seam) ---------------------------------------------------------
# A `dispatch` record with `receipt_source: owner-answer` could cite a general answer
# (`record-decision`) and validate clean — classification is unchanged (same as a `direct` receipt)
# but the record falsely claims §3.2's owner-materialization provenance. The question must block a
# general (non-attempt) context, or the general action itself would be illegal (ACTION_CONTEXT).
d=$(clone_fixture owner-action-materialized)
fm_set "$d"/turns/0003-owner-question.md blocks general-note
fm_set "$d"/turns/0004-owner-answer.md action record-decision
assert_violation "I2: dispatch receipt_source=owner-answer citing a general answer" \
  OWNER_ANSWER_MISMATCH "$d"

# --- Finding M-1 (Minor) -------------------------------------------------------------------------
# `blocks` had no shape check: a typo like `t001-a1` (wrong width — not tTTTT-aAA) silently fell to
# `ctx=other` downstream, legalizing a GENERAL answer where a DISPATCH answer was clearly intended.
d=$(clone_fixture minimal)
emit_general_question "$d" 0002 q-typo t001-a1
emit_general_answer   "$d" 0003 q-typo record-decision
assert_violation "M-1: blocks=t001-a1 looks like a malformed attempt reference" BLOCKS_SHAPE "$d"

d=$(clone_fixture closing);                   assert_classification "close, postconditions missing" "CLOSING:c-0001" "$d"
# A topic with NO assignment must classify, not crash: every identity/base read comes from
# TOPIC.md. Before rev.6 the identity/base reads were "the first/newest assignment" and both were
# empty here. `newest_assign` (Task 2) still exists, but only as OPEN_NOT_NEWEST's subject.
d=$(clone_fixture owner-only);                assert_classification "owner-only topic, no assignment yet" "AWAITING_OWNER" "$d"

# --- Task 4 (round-7 review finding): three CLOSE_ORDER window-scan branches were unreachable by
# --- any prior test — neutering each flipped 0 of 131 cases. Each case below isolates ONE branch.
d=$(mut closing)
emit_question_closing "$d" 0006 q-close-1 CLOSING:c-0001
emit_question_closing "$d" 0007 q-close-2 CLOSING:c-0001
assert_violation "a second question blocking the same close" CLOSE_ORDER "$d"
# coverage added in Task 4 (round-7 review finding)

d=$(mut closing)
emit_question_closing "$d" 0006 q-other-1 t0001-a01
assert_violation "a question in the window blocking something else" CLOSE_ORDER "$d"
# coverage added in Task 4 (round-7 review finding)

# The underlying question must precede the close (so CLOSE_PRECONDITION co-fires by construction —
# an answer landing inside the window necessarily leaves a pre-close question's answer unresolved
# before the close), while its answer lands inside the window: the only way to reach the
# unrelated-answer branch without the question record itself also being in the window (where it
# would trip its own branch first).
d=$(mut closing)
mv "$d"/turns/0005-close.md "$d"/turns/0006-close.md
fm_set "$d"/turns/0006-close.md record_seq 0006
emit_question_closing "$d" 0005 q-other-2 t0001-a01
emit_answer_closing "$d" 0007 q-other-2 dispatch-unresolved
assert_violations "an answer in the window whose question blocks something else" \
  "CLOSE_PRECONDITION CLOSE_ORDER" "$d"
# coverage added in Task 4 (round-7 review finding)

# --- Task 5 cases ---
d=$(make_live accepted);              assert_classification "tip == accepted, clean"          "IDLE" "$d"
d=$(make_live quarantined);           assert_classification "tip is a rejected result_sha"    "REMEDIATION_REQUIRED" "$d"
d=$(make_live trailered);             assert_classification "unexplained tip, closed-attempt trailers" "REMEDIATION_REQUIRED" "$d"
d=$(make_live trailered_wrong_topic); assert_classification "foreign topic trailer is not ours" "UNRECORDED_DRIFT" "$d"
d=$(make_live foreign);               assert_classification "unexplained tip, no trailers"    "UNRECORDED_DRIFT" "$d"
d=$(make_live dirty);                 assert_classification "dirty but stationary => drift"   "UNRECORDED_DRIFT" "$d"
d=$(make_live noworktree);            assert_classification "worktree gone before close"      "UNRECORDED_DRIFT (unverified: work-repo)" "$d"
d=$(make_live identity_wrong_branch); assert_classification "worktree off the session branch" "UNRECORDED_DRIFT" "$d"

# --- false-CLOSED routes, after tests/lib.sh exists; each assertion observes a helper verdict ---
d=$(make_live closed_pending)
assert_postcondition "worktree-absent really PASSes" worktree-absent PASS "$d"
assert_postcondition "branch-at-final really PASSes" branch-at-final PASS "$d"
assert_classification "no THREAD.md => CLOSING" "CLOSING:c-0001" "$d"

d=$(make_live close_worktree_present)
assert_postcondition "present worktree fails the postcondition" worktree-absent FAIL "$d"
assert_classification "present worktree => CLOSING" "CLOSING:c-0001" "$d"

d=$(make_live close_worktree_stale)
assert_postcondition "stale /tmp worktree-list entry fails" worktree-absent FAIL "$d"
assert_classification "stale list entry => CLOSING" "CLOSING:c-0001" "$d"

d=$(make_live close_worktree_dangling)   # D26
assert_postcondition "dangling symlink is not absence" worktree-absent FAIL "$d"
assert_classification "dangling symlink => CLOSING" "CLOSING:c-0001" "$d"

# PRECONDITION — the same one the render block states: this mode injects with `chmod 000`, which
# root ignores. Under root the read SUCCEEDS, `worktree-absent` reports PASS and the assertion would
# FAIL for an environmental reason rather than a defect, so the case is skipped and reported UNRUN.
if [ "$(id -u)" -eq 0 ]; then
  printf 'UNRUN close_repo_unreadable (running as root: chmod 000 does not deny root)\n'
else
d=$(make_live close_repo_unreadable)     # D26 — the fail-open route: failure read as "no entry"
assert_postcondition "unreadable repo is UNAVAILABLE, not PASS" worktree-absent UNAVAILABLE "$d"
assert_classification "unreadable repo => CLOSING, never CLOSED" "CLOSING:c-0001" "$d"
chmod 755 "$(dirname "$d")/repo/.git" 2>/dev/null || true   # so the EXIT trap can clean up
fi

d=$(make_live close_branch_moved)
assert_postcondition "moved branch fails the postcondition" branch-at-final FAIL "$d"
assert_classification "moved branch => CLOSING" "CLOSING:c-0001" "$d"

# I1 — the `branch-at-final` conjunct of the CLOSED decision (validate.sh:774, `&& [ "$bra" = ok ]`)
# was an UNKILLED MUTANT: `close_branch_moved` above never renders/commits THREAD.md, so it fails on
# the thread-header conjunct instead and pins nothing about branch-at-final's own consumption. This
# fixture renders+commits THREAD.md (status: CLOSED) BEFORE moving the branch, isolating
# branch-at-final as the only failing conjunct.
d=$(make_live closed_branch_moved_late)
assert_postcondition "thread-header really PASSes (rendered before the move)" thread-header PASS "$d"
assert_postcondition "worktree-absent really PASSes" worktree-absent PASS "$d"
assert_postcondition "branch moved after render fails the postcondition" branch-at-final FAIL "$d"
assert_classification "branch moved after render => CLOSING, never CLOSED" "CLOSING:c-0001" "$d"

# --- read-only guard (D21): topic dir, a dedicated TMPDIR, AND the work repo ---
# The work-repo snapshot is the one that catches an index rewrite by `git status` (D15) —
# neither of the other two would ever see it.
snapshot_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}
snap() { # portable on the declared Darwin target; any failed read fails the test
  base="$1"; paths="$(cd "$base" && find . -print)" || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    full="$base/${rel#./}"
    meta="$(stat -f '%HT|%Sp|%z' "$full")" || return 1
    if [ -f "$full" ] && [ ! -L "$full" ]; then
      digest="$(snapshot_hash "$full")" || return 1
    elif [ -L "$full" ]; then
      digest="link:$(readlink "$full")" || return 1
    else digest=-; fi
    printf '%s|%s|%s\n' "$rel" "$meta" "$digest"
  done <<< "$(printf '%s\n' "$paths" | sort)"
}
d=$(make_live accepted); R="$(dirname "$d")/repo"; RO="$TMPROOT/ro-tmp"; mkdir -p "$RO"
# B2 (acceptance rev.2, P1 blocker — false FAIL on a cold host) — on macOS, /usr/bin/git is a
# launcher shim that creates `xcrun_db` under TMPDIR on its FIRST invocation. Taking the "before"
# snapshot ahead of that first-ever `git … TMPDIR="$RO"` call meant the cache file could be born
# between the two snapshots, so `--check` was blamed for a write it never made — passing only when
# some earlier test had already warmed the launcher cache for this TMPDIR. Prewarm it here, before
# the "before" snapshot, so the cache file (if any) exists in BOTH snapshots and the comparison
# below tests only what `--check` itself writes.
TMPDIR="$RO" git --version >/dev/null 2>&1
snap "$d" > "$TMPROOT/s1" || { nok "snapshot topic before --check" "snapshot failed"; exit 1; }
snap "$RO" > "$TMPROOT/s2" || { nok "snapshot TMPDIR before --check" "snapshot failed"; exit 1; }
snap "$R" > "$TMPROOT/s3" || { nok "snapshot work repo before --check" "snapshot failed"; exit 1; }
TMPDIR="$RO" /bin/bash "$VALIDATE" --check "$d" >/dev/null 2>&1
snap "$d" > "$TMPROOT/s1b" || { nok "snapshot topic after --check" "snapshot failed"; exit 1; }
snap "$RO" > "$TMPROOT/s2b" || { nok "snapshot TMPDIR after --check" "snapshot failed"; exit 1; }
snap "$R" > "$TMPROOT/s3b" || { nok "snapshot work repo after --check" "snapshot failed"; exit 1; }
cmp -s "$TMPROOT/s1" "$TMPROOT/s1b" && ok "--check leaves the topic dir untouched" || nok "--check leaves the topic dir untouched" "$(diff "$TMPROOT/s1" "$TMPROOT/s1b")"
cmp -s "$TMPROOT/s2" "$TMPROOT/s2b" && ok "--check writes nothing under TMPDIR"    || nok "--check writes nothing under TMPDIR" "$(diff "$TMPROOT/s2" "$TMPROOT/s2b")"
cmp -s "$TMPROOT/s3" "$TMPROOT/s3b" && ok "--check leaves the work repo untouched" || nok "--check leaves the work repo untouched" "$(diff "$TMPROOT/s3" "$TMPROOT/s3b")"
# D15 claims the token appears in the validator AT ALL — so the guard searches for the token, not
# for the two-word literal `git --git-dir`. Every git call goes through the `g()` wrapper, so a
# future `g "$p" --git-dir=… rev-parse` or a `GIT_DIR=` assignment contains no such literal and the
# old pattern reported clean. The message no longer implies a "fallback" D15 says does not exist.
# This guard lives in run-tests.sh, which is not "$VALIDATE", so it cannot match its own source.
if awk '{ sub(/[[:space:]]*#.*/, ""); if ($0 ~ /--git-dir|GIT_DIR/) found=1 } END { exit !found }' "$VALIDATE"; then
  nok "validator never uses --git-dir (D15)" "found --git-dir or GIT_DIR in executable code"
else ok "validator never uses --git-dir (D15)"; fi
# The Task-4 stub must not survive its replacement. bash takes the LAST definition of a name, so a
# surviving stub is invisible at runtime — precisely the kind of accident this plan keeps shipping.
grep -q 'stub — replaced' "$VALIDATE" \
  && nok "Task-4 work-repo stub is gone" "the stub survived into the finished validator" \
  || ok "Task-4 work-repo stub is gone"

# --- D26 failure injection: a FAILED git read must DEGRADE, never satisfy a condition ------------
# Each case asserts the DISTINGUISHING marker, not just the classification. UNRECORDED_DRIFT was
# already reachable by accident on every one of these paths (a `none` sentinel compares unequal to
# everything, an unreadable range counts as 0), so a bare state assertion would pass against the
# unfixed code and prove nothing. The markers go RED if the rc capture is stubbed out.
GITSHIM="$(git_shim)"; gsrc=$?
if [ "$gsrc" -ne 0 ] || [ -z "$GITSHIM" ]; then
  nok "git shim builds" "could not build the git shim (rc=$gsrc, dir='$GITSHIM')"; GITSHIM=""
else ok "git shim builds"; fi
run_shim() { # <AP_GITFAIL tokens> <topic-dir>  -> stdout in $TMPROOT/out
  # NEVER interpolate an unchecked shim dir into PATH: an empty leading element is the CWD, and the
  # validator under test would then run whatever `git` happens to sit in the case directory.
  : > "$TMPROOT/out"; : > "$TMPROOT/err"   # so a refusal cannot leave a PREVIOUS run's output
  [ -n "$GITSHIM" ] || { nok "git shim available for injection" "empty shim dir would put CWD on PATH"; return 1; }
  AP_GITFAIL="$1" PATH="$GITSHIM:$PATH" /bin/bash "$VALIDATE" --check "$2" \
    >"$TMPROOT/out" 2>"$TMPROOT/err"; }
shim_says() { # <grep pattern> <desc>
  grep -q "$1" "$TMPROOT/out" && ok "$2" \
    || nok "$2" "got: $(grep -E '^(postcondition|classification)' "$TMPROOT/out" | tr '\n' ' ')"; }

d=$(make_live accepted)
assert_classification "shim baseline: accepted is IDLE with real git" "IDLE" "$d"
run_shim 'status --porcelain' "$d"        # existing rc capture, now with a direct regression test
shim_says 'unverified: worktree-status' "failed git status degrades, never reads as clean"
shim_says '^classification: UNRECORDED_DRIFT' "failed git status is never IDLE"
run_shim '--git-common-dir' "$d"
shim_says '^postcondition worktree-identity: UNAVAILABLE' "unreadable --git-common-dir is UNAVAILABLE, not FAIL"
run_shim 'symbolic-ref' "$d"
shim_says 'unverified: head-branch' "unreadable HEAD branch is UNAVAILABLE, not a branch mismatch"
run_shim 'rev-parse refs/heads/pair/live' "$d"
shim_says 'unverified: branch-tip' "unreadable branch tip degrades before any comparison"
# Whole-branch review, finding 2: the `head_rc` half of this same guard (validate.sh:613-614) had
# no red test. `rev-parse HEAD` (with the literal `HEAD` token) matches only the worktree HEAD read
# at :613 — the branch-tip read above passes `refs/heads/pair/live`, never the bare token `HEAD`,
# so this row cannot be satisfied by the wrong call.
run_shim 'rev-parse HEAD' "$d"
shim_says 'unverified: branch-tip' "unreadable worktree HEAD degrades before any comparison"
run_shim 'worktree list' "$d"
shim_says '^classification: UNRECORDED_DRIFT (unverified: worktree-list)' "failed worktree list degrades, never reads as absent"

d=$(make_live trailered)                  # this fixture genuinely reaches REMEDIATION_REQUIRED
assert_classification "shim baseline: trailered is REMEDIATION_REQUIRED" "REMEDIATION_REQUIRED" "$d"
run_shim 'rev-list --count' "$d"
shim_says 'unverified: commit-range' "unreadable commit range is not an empty commit range"

# C2 (acceptance round 2, coverage gap) — the trailer walk's OWN `rev-list` read, inside
# `all_commits_carry_closed_attempt_trailers`, is a SEPARATE git invocation from the `--count` read
# just above and can fail independently of it. The generic `AP_GITFAIL` token-presence shim cannot
# isolate this call: its args (`rev-list <range>`) are a strict SUBSET of the `--count` call's args
# (`rev-list --count <range>`), so any token set that matches the bare walk also matches — and, in
# program order, first hits — the `--count` read, which returns before the walk is ever reached.
# A purpose-built shim that fails ONLY on `rev-list` WITHOUT `--count` is required to reach it.
trailer_walk_shim() { # -> dir whose git fails a bare `rev-list <range>` (never a `--count` one)
  gs="$(mktemp -d "$TMPROOT/trailershim.XXXXXX")" || { echo "trailer_walk_shim: mktemp under $TMPROOT failed" >&2; return 1; }
  [ -n "$gs" ] && [ -d "$gs" ] || { echo "trailer_walk_shim: mktemp produced no directory" >&2; return 1; }
  case "$gs" in "$TMPROOT"/trailershim.?*) ;; *) echo "trailer_walk_shim: $gs is not under $TMPROOT" >&2; return 1;; esac
  rg="$(command -v git)" || { echo "trailer_walk_shim: no git on PATH" >&2; return 1; }
  { printf '#!/bin/bash\n'
    printf 'has_revlist=0; has_count=0\n'
    printf 'for a in "$@"; do [ "$a" = rev-list ] && has_revlist=1; [ "$a" = --count ] && has_count=1; done\n'
    printf '[ "$has_revlist" = 1 ] && [ "$has_count" = 0 ] && exit 128\n'
    printf 'exec %s "$@"\n' "$rg"
  } > "$gs/git" && chmod +x "$gs/git" || { echo "trailer_walk_shim: could not build shim" >&2; return 1; }
  echo "$gs"; }
d=$(make_live trailered)
TWS="$(trailer_walk_shim)"; twsrc=$?
if [ "$twsrc" -ne 0 ] || [ -z "$TWS" ]; then
  nok "trailer-walk shim builds" "could not build the shim (rc=$twsrc, dir='$TWS')"
else
  PATH="$TWS:$PATH" /bin/bash "$VALIDATE" --check "$d" >"$TMPROOT/out" 2>"$TMPROOT/err"
  grep -q '^postcondition trailer-range-readable: UNAVAILABLE' "$TMPROOT/out" \
    && ok "unreadable trailer walk degrades, never reads as untrailered data" \
    || nok "unreadable trailer walk degrades, never reads as untrailered data" "got: $(grep -E '^(postcondition|classification)' "$TMPROOT/out" | tr '\n' ' ')"
  grep -q 'unverified: trailer-range' "$TMPROOT/out" \
    && ok "unreadable trailer walk is not silently UNRECORDED_DRIFT" \
    || nok "unreadable trailer walk is not silently UNRECORDED_DRIFT" "got: $(grep '^classification:' "$TMPROOT/out")"
  # the `--count` read itself must still be reachable and succeed — this shim targets ONLY the walk
  grep -q '^classification: UNRECORDED_DRIFT (unverified: commit-range)' "$TMPROOT/out" \
    && nok "trailer-walk shim does not also trip the --count read" "commit-range fired instead" \
    || ok "trailer-walk shim does not also trip the --count read"
fi

# C2 — `check_thread_header`'s `--show-toplevel` read (validate.sh:~715). Reached only via the
# CLOSE arm (arm 1), so the fixture must actually be CLOSED first.
d=$(make_live closed_pending)
/bin/bash "$VALIDATE" --render "$d" >/dev/null 2>&1
git -C "$d" add THREAD.md && gc "$d" render
assert_classification "shim baseline: rendered+committed close is CLOSED" "CLOSED" "$d"
run_shim '--show-toplevel' "$d"
shim_says '^postcondition thread-header: UNAVAILABLE' "unreadable --show-toplevel degrades, not FAIL"
shim_says 'CLOSING:c-0001 (unverified: thread-header)' "unreadable --show-toplevel blocks CLOSED"

# C2 — the CLOSE-time branch-tip read in `check_branch_at_final` (validate.sh:~752) is a distinct
# call site from arm 6's branch-tip read (already covered above with the same command tokens, via
# `make_live accepted`, which never reaches a close at all) — reached only once the topic is
# actually CLOSED.
d=$(make_live closed_pending)
/bin/bash "$VALIDATE" --render "$d" >/dev/null 2>&1
git -C "$d" add THREAD.md && gc "$d" render
run_shim 'rev-parse refs/heads/pair/live' "$d"
shim_says '^postcondition branch-at-final: UNAVAILABLE' "unreadable close-time branch tip degrades, not FAIL"
shim_says 'CLOSING:c-0001 (unverified: branch-at-final)' "unreadable close-time branch tip blocks CLOSED"

# --- Task 6 cases ---
d=$(clone_fixture open-dispatched)
/bin/bash "$VALIDATE" --render "$d"
for pat in '^GENERATED — do not edit' '^accepted_sha: ' '^open_attempt: t0001-a01' \
           '^dispatched_at: 2026-08-11T15:05:00Z' '^classification: OPEN (dispatched)' \
           '0001-t0001-a01-assignment.md'; do
  grep -q "$pat" "$d/THREAD.md" && ok "render header/body: $pat" || nok "render header/body: $pat" "missing"; done
cp "$d/THREAD.md" "$TMPROOT/first"; /bin/bash "$VALIDATE" --render "$d"
cmp -s "$TMPROOT/first" "$d/THREAD.md" && ok "render is deterministic" || nok "render is deterministic" "differs"
ls "$d"/THREAD.md.tmp.* >/dev/null 2>&1 && nok "no temp residue" "tmp survived" || ok "no temp residue"

# the P0-3 circularity, both halves
d=$(make_live closed_pending)
assert_classification "before render: CLOSING" "CLOSING:c-0001" "$d"
/bin/bash "$VALIDATE" --render "$d"
grep -q '^status: CLOSED' "$d/THREAD.md" && ok "render projects the CLOSED header" || nok "render projects the CLOSED header" "not projected"
assert_classification "rendered but uncommitted: still CLOSING" "CLOSING:c-0001" "$d"
git -C "$d" add THREAD.md && git -C "$d" -c user.email=t@t -c user.name=t commit -qm render
assert_classification "committed render: CLOSED" "CLOSED" "$d"
# and the projection must NOT fire past a live worktree
d=$(make_live close_worktree_present); /bin/bash "$VALIDATE" --render "$d"
grep -q '^status: CLOSED' "$d/THREAD.md" && nok "no CLOSED header past a live worktree" "projected anyway" \
  || ok "no CLOSED header past a live worktree"

# --- render durability (D35): a FAILED render must never publish a partial THREAD.md ------------
# Each case asserts the SPECIFIC stderr message, not just a non-zero exit, so a pass can only come
# from the path that was injected. Asserting the exit code alone is how a test starts passing for
# an unrelated early failure and stops testing what it names.
# PRECONDITION: the suite must not be run as root — case (i) relies on `chmod 555` denying writes.
failbin() { # <command-name> -> dir whose <command-name> always fails
  # Same D28 preamble as git_shim, and for the same two reasons: unchecked, `fb` is empty and the
  # printf below writes `/cat` or `/mv` at the filesystem root and marks it executable; and an
  # empty return value interpolated into PATH is a leading empty element, i.e. the CWD.
  [ $# -eq 1 ] && [ -n "${1:-}" ] || { echo "failbin: usage failbin <command-name>" >&2; return 1; }
  fb="$(mktemp -d "$TMPROOT/failbin.XXXXXX")" || { echo "failbin: mktemp under $TMPROOT failed" >&2; return 1; }
  [ -n "$fb" ] && [ -d "$fb" ] || { echo "failbin: mktemp produced no directory" >&2; return 1; }
  case "$fb" in "$TMPROOT"/failbin.?*) ;; *) echo "failbin: $fb is not under $TMPROOT" >&2; return 1;; esac
  printf '#!/bin/bash\nexit 1\n' > "$fb/$1" && chmod +x "$fb/$1" \
    || { echo "failbin: could not build $1" >&2; return 1; }
  echo "$fb"; }
use_failbin() { # <command-name> -> sets FB, or nok+returns 1 — never an empty PATH element
  FB="$(failbin "$1")"; fbrc=$?
  [ "$fbrc" -eq 0 ] && [ -n "$FB" ] && return 0
  nok "failbin builds a failing $1" "rc=$fbrc, dir='$FB' — an empty dir would put CWD on PATH"
  FB=""; return 1; }
assert_render_failed() { # <desc> <dir> <expected stderr fragment> <rc>
  [ "$4" -ne 0 ] && ok "$1: exits nonzero" || nok "$1: exits nonzero" "exit was $4"
  { grep -q 'VIOLATION RENDER_FAILED' "$TMPROOT/rerr" && grep -q "$3" "$TMPROOT/rerr"; } \
    && ok "$1: fails for the injected reason" \
    || nok "$1: fails for the injected reason" "stderr: $(cat "$TMPROOT/rerr")"
  cmp -s "$TMPROOT/goodthread" "$2/THREAD.md" && ok "$1: previous THREAD.md survives intact" \
    || nok "$1: previous THREAD.md survives intact" "THREAD.md was replaced or truncated"
  ls "$2"/THREAD.md.tmp.* >/dev/null 2>&1 && nok "$1: no temp residue" "tmp file survived" \
    || ok "$1: no temp residue"; }

d=$(clone_fixture open-dispatched)
/bin/bash "$VALIDATE" --render "$d" || nok "render durability setup" "baseline render failed"
cp "$d/THREAD.md" "$TMPROOT/goodthread"

# (i) the temp write itself fails — topic dir not writable
chmod 555 "$d"
/bin/bash "$VALIDATE" --render "$d" >/dev/null 2>"$TMPROOT/rerr"; rc=$?
chmod 755 "$d"
assert_render_failed "render/write-failure" "$d" "render group failed" "$rc"

# (ii) a record body cannot be read — `cat` shadowed on PATH. The schema stage reads records with
# awk and never with cat, so this injects the RENDER's read and nothing earlier; corrupting the
# file instead would trip FM_MALFORMED and the case would pass for the wrong reason.
if use_failbin cat; then
  PATH="$FB:$PATH" /bin/bash "$VALIDATE" --render "$d" >/dev/null 2>"$TMPROOT/rerr"; rc=$?
  assert_render_failed "render/cat-failure" "$d" "render group failed" "$rc"
fi

# (iii) the atomic rename fails — `mv` shadowed on PATH
if use_failbin mv; then
  PATH="$FB:$PATH" /bin/bash "$VALIDATE" --render "$d" >/dev/null 2>"$TMPROOT/rerr"; rc=$?
  assert_render_failed "render/rename-failure" "$d" "atomic rename failed" "$rc"
fi

# and a clean run after all three still produces exactly the same bytes — no state left behind
/bin/bash "$VALIDATE" --render "$d" >/dev/null 2>&1 && cmp -s "$TMPROOT/goodthread" "$d/THREAD.md" \
  && ok "render recovers byte-identically after the injected failures" \
  || nok "render recovers byte-identically after the injected failures" "differs or failed"

# D26 — the committed-header read is DATA. With `git show` failing, thread-header must report
# UNAVAILABLE, not FAIL. This is the one place the header genuinely PASSes, so the case is real.
d=$(make_live closed_pending); /bin/bash "$VALIDATE" --render "$d" >/dev/null
git -C "$d" add THREAD.md && git -C "$d" -c user.email=t@t -c user.name=t commit -qm render
assert_postcondition "committed header PASSes with a working git" thread-header PASS "$d"
# Captured and checked, never `PATH="$(git_shim):$PATH"` inline: on a failed build that is an
# empty leading PATH element, i.e. the current directory (D28).
GS6="$(git_shim)"; gs6rc=$?
if [ "$gs6rc" -ne 0 ] || [ -z "$GS6" ]; then
  nok "git shim builds for the header-read injection" "rc=$gs6rc, dir='$GS6'"
else
  AP_GITFAIL='show' PATH="$GS6:$PATH" /bin/bash "$VALIDATE" --check "$d" >"$TMPROOT/out" 2>&1
  grep -q '^postcondition thread-header: UNAVAILABLE' "$TMPROOT/out" \
    && ok "unreadable committed header is UNAVAILABLE, not FAIL" \
    || nok "unreadable committed header is UNAVAILABLE, not FAIL" "$(grep '^postcondition thread-header' "$TMPROOT/out")"
  grep -q '^classification: CLOSING:c-0001' "$TMPROOT/out" \
    && ok "unreadable committed header can never reach CLOSED" \
    || nok "unreadable committed header can never reach CLOSED" "$(grep '^classification:' "$TMPROOT/out")"
fi

# --- Task 7 cases ---
d="$TMPROOT/templated"; mkdir -p "$d/turns"
# TOPIC.md is instantiated too — Task 1's gate requires it, and its base_sha must equal the first
# assignment's (TOPIC_BASE_MISMATCH) and its identity keys every assignment's (TOPIC_MISMATCH).
sed -e 's/{{TOPIC_ID}}/templated/' \
    -e 's/{{BASE_SHA}}/1111111111111111111111111111111111111111/' \
    -e 's|{{BASE_REF}}|origin/dev|' \
    -e 's|{{SESSION_BRANCH}}|pair/templated|' -e 's|{{SESSION_WORKTREE}}|/tmp/wt/templated|' \
    -e 's|{{WORK_REPO_COMMON_DIR}}|/tmp/repo/.git|' \
    "$HERE/../templates/TOPIC.md" > "$d/TOPIC.md"
inst() { # <template> <outfile> <sed-arguments>
  tpl="$HERE/../templates/$1.md"; out="$d/turns/$2"; shift 2
  sed "$@" \
    -e 's/{{TOPIC_ID}}/templated/' -e 's/{{TURN_KIND}}/NORMAL/' \
    -e 's/{{RECORDED_AT}}/2026-08-11T15:00:00Z/' \
    -e 's/{{BASE_SHA}}/1111111111111111111111111111111111111111/' \
    -e 's|{{SESSION_BRANCH}}|pair/templated|' -e 's|{{SESSION_WORKTREE}}|/tmp/wt/templated|' \
    -e 's|{{WORK_REPO_COMMON_DIR}}|/tmp/repo/.git|' -e 's|{{SCOPE}}|src/ docs/|' \
    -e 's/{{DEADLINE}}/2026-08-11T23:00:00Z/' -e 's/{{AGENT_ID}}/agent-a/' \
    -e 's/{{TURN_ID}}/0001/' -e 's/{{ATTEMPT_ID}}/01/' \
    "$tpl" > "$out"; }
inst assignment 0001-t0001-a01-assignment.md -e 's/{{RECORD_SEQ}}/0001/'
inst intent     0002-t0001-a01-intent.md     -e 's/{{RECORD_SEQ}}/0002/' -e 's/{{ASSIGNMENT_REF}}/0001-t0001-a01-assignment.md/' -e 's/{{IDEMPOTENCY_TOKEN}}/tok-1/'
inst dispatch   0003-t0001-a01-dispatch.md \
  -e 's/{{RECORD_SEQ}}/0003/' \
  -e 's/{{ASSIGNMENT_REF}}/0001-t0001-a01-assignment.md/' \
  -e 's/{{TRANSPORT}}/task-tool/' -e 's/{{JOB_ID}}/job-1/' \
  -e 's/{{DISPATCHED_AT}}/2026-08-11T15:02:00Z/' \
  -e 's/{{INTENT_REF}}/0002-t0001-a01-intent.md/' -e 's/{{RECEIPT_SOURCE}}/direct/'
inst result     0004-t0001-a01-result.md \
  -e 's/{{RECORD_SEQ}}/0004/' \
  -e 's/{{ASSIGNMENT_REF}}/0001-t0001-a01-assignment.md/' \
  -e 's/{{STATUS}}/VERIFIED/' -e 's/{{REASON}}//' \
  -e 's/{{RESULT_SHA}}/2222222222222222222222222222222222222222/' \
  -e 's/{{OBSERVED_AT}}/2026-08-11T15:03:00Z/'
inst late       0005-t0001-a01-late-01.md \
  -e 's/{{RECORD_SEQ}}/0005/' \
  -e 's/{{ASSIGNMENT_REF}}/0001-t0001-a01-assignment.md/' -e 's/{{NAMED_SHA}}/null/'
inst owner-question 0006-owner-question.md   -e 's/{{RECORD_SEQ}}/0006/' -e 's/{{QUESTION_ID}}/q-1/' -e 's/{{BLOCKS}}/t0002-a01/'
inst owner-answer   0007-owner-answer.md     -e 's/{{RECORD_SEQ}}/0007/' -e 's/{{QUESTION_REF}}/q-1/' -e 's/{{ACTION}}/dispatch-unresolved/'
inst close          0008-close.md            -e 's/{{RECORD_SEQ}}/0008/' -e 's/{{CLOSE_ID}}/c-1/' -e 's/{{FINAL_ACCEPTED_SHA}}/2222222222222222222222222222222222222222/'
assert_check_ok "all eight record templates instantiate into a valid topic" "$d"
grep -rq '{{' "$d/turns" && nok "no placeholder survives instantiation" "found {{" || ok "no placeholder survives instantiation"

for t in TOPIC onboarding assignment intent dispatch result late owner-question owner-answer close; do
  [ -f "$HERE/../templates/$t.md" ] && ok "template exists: $t" || nok "template exists: $t" "missing"; done
for s in 'Absolute paths' 'DECISIONS' 'pre-flight' 'VERIFIED' 'RELAY-THIS' "DON'T" 'TRUNCATED'; do
  grep -q "$s" "$HERE/../templates/onboarding.md" && ok "onboarding covers: $s" || nok "onboarding covers: $s" "missing"; done
for s in 'Charter' 'Preconditions' 'Registry' 'DECISIONS' 'Onboarding'; do
  grep -q "$s" "$HERE/../templates/TOPIC.md" && ok "TOPIC.md covers: $s" || nok "TOPIC.md covers: $s" "missing"; done
# §3.0 step 3 / §2.2: the pinned base and the explicit base ref are front-matter fields, not prose.
for k in topic_id base_sha base_ref session_branch session_worktree work_repo_common_dir; do
  grep -q "^$k: {{" "$HERE/../templates/TOPIC.md" && ok "TOPIC.md pins: $k" || nok "TOPIC.md pins: $k" "missing"; done
grep -q '{{' "$d/TOPIC.md" && nok "TOPIC.md instantiates cleanly" "placeholder survived" || ok "TOPIC.md instantiates cleanly"
grep -rlE '\b[0-9a-f]{40}\b' "$HERE/../templates" >/dev/null 2>&1 \
  && nok "templates carry no literal SHAs" "found one" || ok "templates carry no literal SHAs"

# The suite is CUMULATIVE and every later task APPENDS above this point (Global Constraints). This
# asserts the invariant that makes that instruction safe: the summary and the exit expression are
# the last two statements in the file. Appended below them, the summary would report Task-1 counts
# only and the script's exit status would be the last `ok`/`nok` — always 0 — silently disarming
# the Task 9 and Task 11 gates that read it.
tail -1 "$0" | grep -q '^\[ "\$FAIL" -eq 0 \]$' \
  && ok "the suite's exit expression is the last line of run-tests.sh" \
  || nok "the suite's exit expression is the last line of run-tests.sh" "got: $(tail -1 "$0")"

# --- Task 9 cases ---
S="$HERE/../SKILL.md"
for w in OPEN CYCLE FENCE RESUME CLOSE; do
  grep -q "## $w" "$S" && ok "SKILL.md has $w checklist" || nok "SKILL.md has $w checklist" "missing"; done
grep -q '^name: agent-pairing' "$S" && ok "frontmatter name" || nok "frontmatter name" "missing"
grep -q 'validate.sh --check' "$S" && ok "gates on the validator" || nok "gates on the validator" "missing"
grep -q -- '--name-status -M -C -z' "$S" && ok "scope check command present" || nok "scope check command present" "missing"
# OPEN must pin the base in TOPIC.md before any record exists (§3.0 step 3) — the validator's seed.
for k in base_sha base_ref; do
  grep -q "$k" "$S" && ok "OPEN pins $k in TOPIC.md" || nok "OPEN pins $k in TOPIC.md" "missing"; done
for p in $(grep -oE 'templates/[a-zA-Z-]+\.md|scripts/validate\.sh' "$S" | sort -u); do
  [ -e "$HERE/../$p" ] && ok "referenced path exists: $p" || nok "referenced path exists: $p" "missing"; done

# --- Task 10 cases ---
EX="$HERE/../example"
assert_classification "shipped snapshot classifies CLOSING" "CLOSING:c-0001" "$EX/topic"
assert_postcondition  "snapshot: thread-header UNAVAILABLE" thread-header UNAVAILABLE "$EX/topic"
RT="$(/bin/bash "$EX/rehydrate.sh" --print-topic)"
assert_check_ok       "rehydrated example passes --check" "$RT"
assert_postcondition  "rehydrated: branch-at-final PASS" branch-at-final PASS "$RT"
assert_postcondition  "rehydrated: worktree-absent PASS" worktree-absent PASS "$RT"
assert_classification "rehydrated example classifies CLOSED" "CLOSED" "$RT"
cp "$RT/THREAD.md" "$TMPROOT/exthread"; /bin/bash "$VALIDATE" --render "$RT"
cmp -s "$TMPROOT/exthread" "$RT/THREAD.md" && ok "example THREAD.md is render-stable" \
  || nok "example THREAD.md is render-stable" "regeneration differs from committed"
/bin/bash "$EX/rehydrate.sh" --clean

# --- Task 10: check 7 is EXECUTED, not grepped ---------------------------------------------------
# Before this block the suite's only coverage of check 7 was `grep -- '--name-status -M -C -z'`
# over SKILL.md: the command that catches a rename bypass was prose, pinned by nothing. These
# cases build a real repo, perform the rename SKILL.md's own text warns about — SOURCE out of
# scope, DESTINATION in scope, which `--name-only` reports as an in-scope path only — and run
# SKILL.md's check-7 block AS WRITTEN. Both halves of the rename rule are covered (source out /
# destination out) plus the over-rejection twin, so no single-path mutation leaves the suite green.
#
# The block is EXTRACTED from SKILL.md at run time rather than copied here, so it is byte-identical
# by construction and an edit to either side surfaces as a failing test instead of as silent drift.
# Only the first line — the `SCOPE="<placeholder>"` line, which is not part of the algorithm — is
# replaced, and its exact text is asserted first so that a future edit to it cannot be swallowed.
#
# The extractor is anchored on the block's CONTENT, not on its position: the first bash fence after
# the Check 7 heading whose first line is the `SCOPE=` assignment AND whose body runs
# `--name-status`. Positional anchoring ("the first bash fence after the heading") silently pins the
# wrong block the moment anyone inserts one between the heading and the algorithm, and the suite
# stays green while testing nothing.
c7_block() { awk '
  /^\*\*Check 7/ {f=1}
  f && !c && /^```bash$/ {c=1; n=0; hit=0; next}
  c && /^```$/ {
    if (n > 0 && b[1] ~ /^SCOPE=/ && hit) { for (i=1; i<=n; i++) print b[i]; exit }
    c=0; next }
  c { b[++n]=$0; if ($0 ~ /--name-status/) hit=1 }
' "$HERE/../SKILL.md"; }
c7_first="$(c7_block | sed -n '1p')"
[ "$c7_first" = 'SCOPE="<the assignment'"'"'s space-separated scope prefixes>"' ] \
  && ok "check-7 block's first line is the SCOPE placeholder this test substitutes" \
  || nok "check-7 block's first line is the SCOPE placeholder this test substitutes" "got: $c7_first"
[ -n "$(c7_block | sed -n '2p')" ] \
  && ok "check-7 block extracts from SKILL.md" || nok "check-7 block extracts from SKILL.md" "empty"
run_c7() { # <scope> <wt> <base> <res> — runs SKILL.md's check 7 verbatim, prints its stdout
  ( SCOPE="$1"; WT="$2"; BASE="$3"; RES="$4"; eval "$(c7_block | sed '1d')" ) 2>&1; }

# One repo, one rename: vendor/lib.txt -> src/lib.txt.
C7="$TMPROOT/check7"; mkdir -p "$C7/src" "$C7/vendor"
git -C "$C7" init -q
echo app > "$C7/src/app.txt"; echo lib > "$C7/vendor/lib.txt"
git -C "$C7" add -A; gc "$C7" seed
C7BASE="$(git -C "$C7" rev-parse HEAD)"
git -C "$C7" mv vendor/lib.txt src/lib.txt; gc "$C7" "rename out of vendor/ into src/"
C7RES="$(git -C "$C7" rev-parse HEAD)"
# The premise: `--name-only` (the wrong command) sees ONLY the destination, which is in scope.
git -C "$C7" diff --name-only "$C7BASE".."$C7RES" | grep -q '^vendor/' \
  && nok "premise: --name-only hides the rename source" "vendor/ still visible" \
  || ok "premise: --name-only hides the rename source"
# REJECT case — source out of scope, destination in scope.
c7out="$(run_c7 "src/" "$C7" "$C7BASE" "$C7RES")"
case "$c7out" in
  *"OUT OF SCOPE:"*vendor/lib.txt*) ok "check 7 REJECTS a rename whose source is out of scope" ;;
  *) nok "check 7 REJECTS a rename whose source is out of scope" "got: '$c7out'" ;;
esac
# OVER-REJECTION TWIN — the same rename with both prefixes declared must pass silently.
c7out2="$(run_c7 "src/ vendor/" "$C7" "$C7BASE" "$C7RES")"
[ -z "$c7out2" ] && ok "check 7 PASSES the same rename when both prefixes are in scope" \
  || nok "check 7 PASSES the same rename when both prefixes are in scope" "got: '$c7out2'"
# The DESTINATION half of the same rule, so a mutation that reads only ONE of the two paths cannot
# leave the suite green: the rename now goes the other way (source in scope, destination out).
git -C "$C7" checkout -q -b destcase "$C7RES"
git -C "$C7" mv src/lib.txt vendor/lib.txt; gc "$C7" "rename out of src/ into vendor/"
C7D="$(git -C "$C7" rev-parse HEAD)"
case "$(run_c7 "src/" "$C7" "$C7RES" "$C7D")" in
  *"OUT OF SCOPE:"*vendor/lib.txt*) ok "check 7 REJECTS a rename whose destination is out of scope" ;;
  *) nok "check 7 REJECTS a rename whose destination is out of scope" "vendor/lib.txt accepted under scope src/" ;;
esac
# And the segment-boundary rule SKILL.md states in prose: `src/` must not match `src2/`.
git -C "$C7" checkout -q -b boundary "$C7BASE"
mkdir -p "$C7/src2"; echo x > "$C7/src2/x.txt"; git -C "$C7" add -A; gc "$C7" "add src2/"
C7B2="$(git -C "$C7" rev-parse HEAD)"
case "$(run_c7 "src/" "$C7" "$C7BASE" "$C7B2")" in
  *"OUT OF SCOPE:"*src2/x.txt*) ok "check 7 matches prefixes at a path-segment boundary (src/ != src2/)" ;;
  *) nok "check 7 matches prefixes at a path-segment boundary (src/ != src2/)" "src2/x.txt accepted under scope src/" ;;
esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
