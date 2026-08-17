# bash 3.2 compatible. Sourced by scripts/validate.sh — never executed directly.
#
# Committed-object enumeration, front-matter parsing, common v2 fields, filenames, hashes, and epoch
# primitives.
#
# The single invariant of this file: RECORD BYTES COME FROM COMMITTED GIT OBJECTS. Every record the
# validator inspects is copied out of `HEAD:` into a checked temporary file and parsed there. The
# record working tree is compared against the committed tree only to REPORT residue — never to
# supply a record. A validator that could be talked into reading an uncommitted receipt would bless
# the exact v1 defect this protocol exists to remove.

# --- violation accounting ---------------------------------------------------------------------------
# Violations accumulate through the schema stage and then stop the run, so one malformed topic
# reports every structural defect it has rather than only the first. Classification is never reached
# with a nonzero count: an unparseable record set has no trustworthy state to report.
V2_VIOLATIONS=0
v2_fail() { # <code> <subject> <detail>
  V2_VIOLATIONS=$((V2_VIOLATIONS + 1))
  printf 'VIOLATION %s %s: %s\n' "$1" "$2" "$3" >&2
}

# A read that FAILED is not a record that is absent, and neither is a clean topic. An environment
# failure exits 3 so it can never be mistaken for either.
v2_fatal() { # <detail>
  printf 'FATAL %s\n' "$1" >&2
  exit 3
}

# --- Git access ---------------------------------------------------------------------------------------
# GIT_NO_REPLACE_OBJECTS keeps a replace ref from substituting the bytes under audit.
# GIT_OPTIONAL_LOCKS=0 keeps a read-only check from rewriting .git/index in someone else's repository.
# GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / GIT_COMMON_DIR are UNSET, not merely overridden: an
# exported GIT_DIR in the caller's environment silently redirects every read here to a different
# repository, and `-C` does not override it. The validator's whole claim is about which objects it
# read, so it must not inherit that choice from whoever invoked it.
v2_git() { # <topic> <git-args...>
  v2_g_topic="$1"; shift
  GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 \
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      git -C "$v2_g_topic" "$@"
}

v2_read_committed() { # <topic> <path-in-tree>  -> blob bytes on stdout
  v2_git "$1" show "HEAD:$2"
}

# Copy one committed blob into a checked temporary file and print that file's path.
# Every allocation is checked BEFORE the path is used, because an unchecked allocation leaves an
# empty variable and the next redirection writes to a path nobody chose.
# Git's own diagnosis is kept rather than discarded, so an unreadable object is reported with its
# reason instead of as a bare failure. It is kept in a FILE, not a variable: every caller invokes
# these helpers inside `$( )`, and a variable assigned in a command substitution dies with its
# subshell.
v2_git_err() { [ -f "$V2_WORK/git.err" ] && tr '\n' ';' <"$V2_WORK/git.err"; }

# The staged path is derived from the record path, NOT from a counter.
#
# A counter is wrong here for a reason worth stating: `v2_stage_committed` is always called as
# `$(v2_stage_committed …)`, which runs in a subshell, so an incremented counter never reaches the
# parent. Every record would stage to the same file, each overwriting the last, and every later read
# of any record would return the LAST record's bytes — cross-record checks comparing a record with
# itself and reporting agreement. A path-derived name is stable across subshells by construction.
v2_stage_committed() { # <topic> <path-in-tree> -> staged file path
  [ -n "${V2_WORK:-}" ] && [ -d "${V2_WORK:-}" ] || v2_fatal "staging area is not allocated"
  v2_s_slot="$(printf '%s' "$2" | tr '/' '_')"
  v2_s_file="$V2_WORK/blob.$v2_s_slot"
  if ! v2_read_committed "$1" "$2" >"$v2_s_file" 2>"$V2_WORK/git.err"; then
    return 1
  fi
  : >"$V2_WORK/git.err"
  printf '%s\n' "$v2_s_file"
}

# Enumerate committed record paths into $V2_WORK/records.sorted, one per line, LC_ALL=C ordered.
# Sets V2_RECORD_NEWLINE=yes when a committed path contains a newline (see below).
#
# An absent turns/ path is an EMPTY record set, not an error: `ls-tree -r --name-only HEAD turns`
# exits zero with no output when the path does not exist (verified on Apple Git 2.50.1). A
# `cat-file -e … || return 0` guard would be strictly worse — it cannot distinguish an absent path
# from a genuine read failure, and would convert fail-closed I/O into an empty record set.
#
# The read is NOT piped into `sort`. A pipeline's status is its LAST command's, so `ls-tree | sort`
# reports sort's success and a damaged record tree reads as an empty record set — a corrupt
# repository classified as a clean, never-dispatched topic. Status is captured on its own line.
#
# `-z` plus `core.quotePath=false` gives RAW path bytes: the default output C-quotes anything
# non-ASCII or unusual, which would make the validator inspect a record path that is not the one in
# the tree. Because the caller reads line-by-line, an embedded newline would silently split one
# record into two; the entry count is compared against the line count so that case is REPORTED
# rather than mis-parsed.
V2_RECORD_NEWLINE=no
v2_list_records() { # <topic>
  v2_lr_z="$V2_WORK/records.z"
  if ! v2_git "$1" -c core.quotePath=false ls-tree -r --name-only -z HEAD turns \
       >"$v2_lr_z" 2>"$V2_WORK/git.err"; then
    return 1
  fi
  : >"$V2_WORK/git.err"
  v2_lr_entries="$(tr -cd '\000' <"$v2_lr_z" | wc -c | tr -d ' ')"
  tr '\000' '\n' <"$v2_lr_z" | LC_ALL=C sort >"$V2_WORK/records.sorted" || return 1
  v2_lr_lines="$(grep -c . "$V2_WORK/records.sorted" || true)"
  if [ "$v2_lr_entries" -ne "$v2_lr_lines" ]; then V2_RECORD_NEWLINE=yes; else V2_RECORD_NEWLINE=no; fi
}

v2_require_record_repo() { # <topic>
  v2_git "$1" rev-parse --git-dir >/dev/null 2>&1 \
    || { v2_fail RECORD_REPO "$1" "not a Git record repository; v2 reads records only from committed objects"; return 1; }
  v2_git "$1" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { v2_fail RECORD_REPO "$1" "record repository has no commit at HEAD"; return 1; }
}

# --- front matter -------------------------------------------------------------------------------------
# The block opens with `---` on line 1 and ends at the first subsequent `---`. The body is not
# inspected, so a horizontal rule or a fenced `---` inside a report body stays legal.
V2_FM_ERR=""
v2_fm_structure() { # <staged-file>; sets V2_FM_ERR, returns 1 when malformed
  V2_FM_ERR="$(awk '
    NR == 1 { if ($0 != "---") { print "front matter does not open with --- on line 1"; bad = 1; exit }
              next }
    done_fm == 1 { next }
    $0 == "---" { done_fm = 1; next }
    {
      if ($0 == "") { print "blank line inside front matter (line " NR ")"; bad = 1; exit }
      if ($0 !~ /^[A-Za-z_][A-Za-z0-9_]*:( |$)/) {
        print "line " NR " is not a flat key: value pair: " $0; bad = 1; exit }
      k = $0; sub(/:.*/, "", k)
      if (k in seen) { print "duplicate front-matter key: " k; bad = 1; exit }
      seen[k] = 1
    }
    END { if (bad != 1 && done_fm != 1) print "front matter block is never closed by ---" }
  ' "$1")"
  [ -z "$V2_FM_ERR" ]
}

# Read one front-matter scalar. The value is everything after the first `: `, verbatim, so a trailing
# space or a quoted "2" stays distinguishable from the exact scalar 2.
v2_fm_get() { # <staged-file> <key>
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    c >= 2 { exit }' "$1"
}

v2_fm_has() { # <staged-file> <key>  -> 0 when the key is present, even with an empty value
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && ($0 == k ":" || index($0, k ": ") == 1) { found = 1; exit }
    c >= 2 { exit }
    END { exit !found }' "$1"
}

v2_body_nonempty() { # <staged-file>
  awk '/^---$/ { c++; next } c >= 2 && NF' "$1" | grep -q .
}

# --- scalars ---------------------------------------------------------------------------------------------
v2_in_list() { v2_l_v="$1"; for v2_l_w in $2; do [ "$v2_l_w" = "$v2_l_v" ] && return 0; done; return 1; }

v2_is_sha() { case "$1" in *[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 40 ]; }
v2_is_sha256() { case "$1" in *[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 64 ]; }

# Decimal, non-negative, no sign, no leading zeros beyond a bare `0`, and no whitespace. Leading
# zeros are rejected rather than normalized: `010` reads as 8 to anything octal-aware, and a record
# whose arithmetic depends on the reader's base is not a durable record.
v2_is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 0 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

# The exact integer range both the shell and awk handle without loss. Beyond this, `$(( ))` and
# awk's `%.0f` stop agreeing, and an arithmetic check that silently disagrees with itself is worse
# than no check. 2^53 - 1 is the exact-integer ceiling of IEEE-754 doubles, which awk uses.
V2_EPOCH_MAX=9007199254740991

v2_uint_value() { # <value> -> the same integer, or rc 1
  v2_is_uint "$1" || return 1
  awk -v n="$1" -v m="$V2_EPOCH_MAX" 'BEGIN { if (n + 0 > m) exit 1; printf "%.0f\n", n + 0 }'
}

v2_sum_eq() { # <left> <right> <expected>  -> 0 when left + right == expected
  v2_se_l="$(v2_uint_value "$1")" || return 1
  v2_se_r="$(v2_uint_value "$2")" || return 1
  v2_se_e="$(v2_uint_value "$3")" || return 1
  [ "$((v2_se_l + v2_se_r))" -eq "$v2_se_e" ]
}

# --- exact bytes -------------------------------------------------------------------------------------------
v2_byte_count() { LC_ALL=C wc -c <"$1" | tr -d ' '; }
v2_sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
v2_has_trailing_newline() { # -> present | absent
  # An EMPTY report has no final byte to inspect, so its trailing-newline state is `absent`. That is
  # a statement about the bytes, not a repair of them.
  [ ! -s "$1" ] && { printf 'absent\n'; return 0; }
  v2_tn_last="$(tail -c 1 "$1" | od -An -tuC | tr -d ' ')"
  if [ "$v2_tn_last" = 10 ]; then printf 'present\n'; else printf 'absent\n'; fi
}

# --- record identity --------------------------------------------------------------------------------------
v2_seq_of() { v2_sq_b="$(basename "$1")"; printf '%s\n' "${v2_sq_b%%-*}"; }

V2_KINDS="admission assignment intent dispatch ack result-capture fence-initiated result late owner-question owner-answer close"
# Kinds that name one attempt and therefore carry turn_id/attempt_id/turn_kind and the
# SSSS-tTTTT-aAA-KIND.md filename shape. `admission` is deliberately topic-level: it proves
# participant readiness for the topic, and binding it to one attempt would force a new admission per
# turn while making the assignment's `admission_ref` circular.
V2_ATTEMPT_KINDS="assignment intent dispatch ack result-capture fence-initiated result late"
V2_TOPIC_KINDS="admission owner-question owner-answer close"

# Common fields carried by EVERY v2 record, in the design's order.
V2_COMMON_KEYS="protocol_version record_seq kind topic_id recorded_epoch recorded_at"

v2_is_iso8601() {
  v2_ts="$1"
  case "$v2_ts" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*Z) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9]) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*[+-][0-9][0-9]:[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  v2_mo="${v2_ts:5:2}"; v2_da="${v2_ts:8:2}"; v2_hh="${v2_ts:11:2}"; v2_mi="${v2_ts:14:2}"; v2_se="${v2_ts:17:2}"
  [ "$((10#$v2_mo))" -ge 1 ] && [ "$((10#$v2_mo))" -le 12 ] || return 1
  [ "$((10#$v2_da))" -ge 1 ] && [ "$((10#$v2_da))" -le 31 ] || return 1
  [ "$((10#$v2_hh))" -le 23 ] || return 1
  [ "$((10#$v2_mi))" -le 59 ] || return 1
  [ "$((10#$v2_se))" -le 59 ] || return 1
}

# --- uncommitted residue -----------------------------------------------------------------------------------
# Record bytes that exist only in the working tree are never a record. They ARE reportable evidence:
# a half-written receipt sitting beside a committed history is exactly the crash state the recovery
# rules exist for, and silently ignoring it would let a primary believe it dispatched.
v2_check_uncommitted_residue() { # <topic>
  # `--ignored=matching` is REQUIRED, not defensive. Plain `--porcelain --untracked-files=all` never
  # reports ignored paths, so a single `turns/0006-*.md` line in a `.gitignore` — or in a global
  # core.excludesFile the topic never sees — makes a half-written receipt invisible and the topic
  # classifies as though nothing were there. An ignore rule must not be able to decide whether the
  # protocol's residue evidence exists.
  #
  # The pathspec is the RECORD TREE only: `turns/` and `TOPIC.md`. `artifacts/` is deliberately
  # excluded, and not as a concession — an artifact's integrity is pinned by its capture record's
  # byte count and SHA-256, which is strictly stronger evidence than a status line, and an
  # uncommitted artifact fails when the validator tries to read `HEAD:` for it. Including
  # `artifacts/` under `--ignored=matching` meanwhile made a Finder `.DS_Store` — ignored by a
  # global excludesFile on essentially every macOS machine — report as protocol residue and fail an
  # otherwise valid topic.
  v2_res_status="$(v2_git "$1" status --porcelain --untracked-files=all --ignored=matching \
                     -- turns TOPIC.md 2>/dev/null)"
  v2_res_rc=$?
  if [ "$v2_res_rc" -ne 0 ]; then
    v2_fail GIT_READ "$1" "cannot read record working-tree status"
    return 1
  fi
  [ -z "$v2_res_status" ] && return 0
  v2_fail UNCOMMITTED_RESIDUE "$1" "record-tree paths differ from the committed tree: $(printf '%s' "$v2_res_status" | tr '\n' ';')"
  return 1
}
