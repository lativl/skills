#!/bin/bash
set -u
EX="$(cd "$(dirname "$0")" && pwd -P)"
# Derived from the frozen v1 example's rehydrate.sh, whose hardening was earned over several review
# rounds: metadata validated before anything is deleted, bundles verified in an explicit repository
# context, restore into marker-owned staging and swap only on success, and an ownership marker
# written immediately after `git init` so a failed run is always recoverable by the next one. The v2
# changes are the WORK_BRANCH file and the closed-topic assertions at the bottom.
# safe_rm's containment test is only as good as the variables it compares against: a missing or
# partial PATHS.env must abort here, not leave $ROOT unset for a `case` to fall through.
. "$EX/PATHS.env" || { echo "PATHS.env missing or unreadable" >&2; exit 3; }
[ -n "${ROOT:-}" ] && [ -n "${R:-}" ] && [ -n "${T:-}" ] \
  || { echo "PATHS.env did not define ROOT, R and T" >&2; exit 3; }
case "$ROOT" in /*) ;; *) echo "PATHS.env ROOT must be absolute (got '$ROOT')" >&2; exit 3;; esac
# D40: metadata is validated BEFORE anything is deleted. rev.6 read these two files unchecked and
# then removed both repos, so a missing/empty FINAL_SHA destroyed the good restore to satisfy a run
# that could never succeed.
FINAL="$(sed -n '1p' "$EX/FINAL_SHA" 2>/dev/null)" || FINAL=""
TOPIC_BRANCH="$(sed -n '1p' "$EX/TOPIC_BRANCH" 2>/dev/null)" || TOPIC_BRANCH=""
case "$FINAL" in
  [0-9a-f][0-9a-f]*) [ ${#FINAL} -eq 40 ] || { echo "FINAL_SHA is not a 40-char sha" >&2; exit 3; } ;;
  *) echo "FINAL_SHA missing or unreadable" >&2; exit 3 ;;
esac
[ -n "$TOPIC_BRANCH" ] || { echo "TOPIC_BRANCH missing or empty" >&2; exit 3; }
# v2 reads the WORK branch from a file too. The v1 example hardcoded `pair/example`, so the branch
# name lived in two places and only one of them was generated.
WORK_BRANCH="$(sed -n '1p' "$EX/WORK_BRANCH" 2>/dev/null)" || WORK_BRANCH=""
[ -n "$WORK_BRANCH" ] || { echo "WORK_BRANCH missing or empty" >&2; exit 3; }
for b in work-repo topic-repo; do
  [ -f "$EX/$b.bundle" ] || { echo "$b.bundle is missing" >&2; exit 3; }
done

safe_rm() { # refuse to delete anything that is not ours
  case "$1" in "$ROOT"/repo|"$ROOT"/topic|"$ROOT"/repo.staging|"$ROOT"/topic.staging) ;;
    *) echo "refusing to remove $1" >&2; exit 3;; esac
  [ ! -e "$1" ] || [ -f "$1/.agent-pairing-example" ] || { echo "no ownership marker in $1" >&2; exit 3; }
  rm -rf "$1"; }
if [ "${1:-}" = "--clean" ]; then
  safe_rm "$R"; safe_rm "$T"; safe_rm "$ROOT/repo.staging"; safe_rm "$ROOT/topic.staging"; exit 0; fi
[ "${1:-}" = "--print-topic" ] || { echo "usage: rehydrate.sh --print-topic|--clean" >&2; exit 3; }

# D40: restore into marker-owned staging, verify, and only then swap. rev.6 deleted both repos
# first and wrote the ownership markers only after BOTH restore chains succeeded — so a fetch or
# checkout failure left an unmarked directory that every later run's safe_rm refused, wedging
# retries permanently. The guard added for safety became the thing that blocked recovery.
# The marker is now written immediately after `git init`, so every directory this script can
# create is removable by the next run, whatever happens next.
RS="$ROOT/repo.staging"; TS="$ROOT/topic.staging"
safe_rm "$RS"; safe_rm "$TS"
stage_fail() { safe_rm "$RS"; safe_rm "$TS"; echo "$1" >&2; exit 1; }
bundle_fail() { safe_rm "$RS"; safe_rm "$TS"; echo "$1" >&2; exit 3; }
# `git init` puts HEAD on `init.defaultBranch`, and `git fetch <bundle> 'refs/heads/*:refs/heads/*'`
# REFUSES WHOLESALE — rc 128, no branches created at all — when the bundle carries a branch of that
# same name. Both repos here are created by the same git on the same host, so the collision is the
# DEFAULT case, not an edge case: verified on git 2.50.1 that `git init dst; git -C dst fetch b.bundle
# 'refs/heads/*:refs/heads/*'` dies with "refusing to fetch into branch 'refs/heads/main' checked out
# at …" and leaves `pair/example` uncreated too. Moving HEAD to a name no bundle carries fixes it
# (verified: rc 0, both `main` and `pair/example` created, `checkout -f` then lands on the session
# branch). D5's earlier verification covered the `git clone` failure and never this one.
# Both repos are also CHAINED and asserted: rev.6 left the topic repo's three commands unchecked
# under `set -u` with no `set -e`, so a corrupt topic bundle printed a valid-looking path and exited
# 0, handing the D5 test an EMPTY topic directory — the vacuous pass D5 exists to prevent
# (reproduced: EXIT=0, `ls topic` shows only `.git` and the marker).
git init -q "$RS" || stage_fail "cannot create the work staging dir"
: > "$RS/.agent-pairing-example" || stage_fail "cannot mark the work staging dir"
# `git bundle verify` needs a REPOSITORY, not just a file: run with the caller's cwd outside any
# repo it dies with "error: need a repository to verify a bundle", which the earlier version
# reported as "<bundle> is corrupt" — accusing a byte-identical artifact of damage. An installed
# skill directory is not a repo, so `cd <skills-root>/agent-pairing && tests/run-tests.sh` — the
# first thing a reader does — failed five cases. The bundles are therefore verified with an
# EXPLICIT repository context (`git -C "$RS"`, the freshly initialised work staging dir), which
# makes the result independent of where the script was invoked from. Neither bundle carries
# prerequisites, so an empty repo is a sufficient context for a real verification. This still runs
# BEFORE anything of value is deleted: only the two staging dirs (ours, marker-guarded) exist yet,
# and $R/$T are not touched until the swap at the bottom.
for b in work-repo topic-repo; do
  git -C "$RS" bundle verify "$EX/$b.bundle" >/dev/null 2>&1 || bundle_fail "$b.bundle is corrupt"
done
git -C "$RS" symbolic-ref HEAD refs/heads/__rehydrate_placeholder \
  && git -C "$RS" fetch -q "$EX/work-repo.bundle" 'refs/heads/*:refs/heads/*' \
  && git -C "$RS" checkout -q -f "$WORK_BRANCH" \
  || stage_fail "work repo did not rehydrate"
git init -q "$TS" || stage_fail "cannot create the topic staging dir"
: > "$TS/.agent-pairing-example" || stage_fail "cannot mark the topic staging dir"
git -C "$TS" symbolic-ref HEAD refs/heads/__rehydrate_placeholder \
  && git -C "$TS" fetch -q "$EX/topic-repo.bundle" 'refs/heads/*:refs/heads/*' \
  && git -C "$TS" checkout -q -f "$TOPIC_BRANCH" \
  || stage_fail "topic repo did not rehydrate"
# Verify IN STAGING, so a bad restore never replaces a good one.
[ "$(git -C "$RS" rev-parse refs/heads/$WORK_BRANCH 2>/dev/null)" = "$FINAL" ] \
  || stage_fail "rehydration did not restore the tip"
{ [ -f "$TS/TOPIC.md" ] && [ -d "$TS/turns" ]; } \
  || stage_fail "rehydrated topic repo has no records"
# Swap last. safe_rm still refuses anything outside $ROOT or missing its marker.
safe_rm "$R"; safe_rm "$T"
mv "$RS" "$R" || stage_fail "could not move the work repo into place"
mv "$TS" "$T" || stage_fail "could not move the topic repo into place"
printf '%s\n' "$T"
