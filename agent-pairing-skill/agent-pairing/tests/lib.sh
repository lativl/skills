# tests/lib.sh
gc() { git -C "$1" -c user.email=t@t -c user.name=t commit -qm "$2"; }

# D26 failure injection. Builds a directory holding a `git` shim that exits 128 exactly when EVERY
# whitespace-separated token in $AP_GITFAIL appears as one of its arguments, and otherwise execs the
# real git. Prepend it to PATH for a single validator invocation. Injecting one read at a time is
# the point: corrupting the repo instead (chmod 000 and friends) breaks several reads at once, and
# the assertion can then pass for a reason other than the one it names.
git_shim() { # -> directory to prepend to PATH
  # D28's three checks, in full. Unchecked (rev.6 shipped it that way and a round-6 verifier ran it
  # with a failing `mktemp`), `gs` is EMPTY and the two lines below write the shim to `/git` and
  # `chmod +x` it. Worse, the function then echoes nothing, and an unguarded
  # `PATH="$(git_shim):$PATH"` becomes a LEADING EMPTY PATH ELEMENT — which bash resolves as the
  # CURRENT DIRECTORY (verified: `PATH=":/usr/bin:/bin" git --version` ran ./git). Every call site
  # below therefore captures into a variable and refuses an empty one.
  gs="$(mktemp -d "$TMPROOT/gitshim.XXXXXX")" || { echo "git_shim: mktemp under $TMPROOT failed" >&2; return 1; }
  [ -n "$gs" ] && [ -d "$gs" ] || { echo "git_shim: mktemp produced no directory" >&2; return 1; }
  case "$gs" in "$TMPROOT"/gitshim.?*) ;; *) echo "git_shim: $gs is not under $TMPROOT" >&2; return 1;; esac
  rg="$(command -v git)" || { echo "git_shim: no git on PATH" >&2; return 1; }
  { printf '#!/bin/bash\n'
    printf 'need="${AP_GITFAIL:-}"\n'
    printf 'if [ -n "$need" ]; then miss=0\n'
    printf '  for t in $need; do hit=0; for a in "$@"; do [ "$a" = "$t" ] && hit=1; done\n'
    printf '    [ "$hit" = 1 ] || miss=1; done\n'
    printf '  [ "$miss" = 0 ] && exit 128\n'
    printf 'fi\n'
    printf 'exec %s "$@"\n' "$rg"
  } > "$gs/git" && chmod +x "$gs/git" || { echo "git_shim: could not build shim" >&2; return 1; }
  echo "$gs"; }

emit_assignment() { # topic seq turn attempt kind base branch worktree common-dir scope
  out="$1/turns/$2-t$3-a$4-assignment.md"
  printf '%s\n' '---' "record_seq: $2" 'kind: assignment' 'topic_id: live' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "base_sha: $6" \
    "session_branch: $7" "session_worktree: $8" "work_repo_common_dir: $9" \
    "scope: ${10}" 'deadline: 2026-08-11T23:00:00Z' 'agent_id: test-agent' \
    'recorded_at: 2026-08-11T15:00:00Z' '---' 'Test assignment.' > "$out"
}
emit_intent() { # topic seq turn attempt kind assignment-ref token
  printf '%s\n' '---' "record_seq: $2" 'kind: intent' 'topic_id: live' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" \
    "idempotency_token: $7" 'recorded_at: 2026-08-11T15:01:00Z' '---' \
    'Dispatch intent.' > "$1/turns/$2-t$3-a$4-intent.md"
}
emit_dispatch() { # topic seq turn attempt kind assignment-ref intent-ref source [answer-ref]
  out="$1/turns/$2-t$3-a$4-dispatch.md"
  printf '%s\n' '---' "record_seq: $2" 'kind: dispatch' 'topic_id: live' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" \
    'transport: task-tool' "job_id: job-$3-$4" 'dispatched_at: 2026-08-11T15:02:00Z' \
    "intent_ref: $7" "receipt_source: $8" > "$out"
  [ -n "${9:-}" ] && printf 'owner_answer_ref: %s\n' "$9" >> "$out"
  printf '%s\n' 'recorded_at: 2026-08-11T15:02:00Z' '---' 'Dispatch receipt.' >> "$out"
}
emit_result() { # topic seq turn attempt kind status reason sha assignment-ref [answer-ref]
  out="$1/turns/$2-t$3-a$4-result.md"
  printf '%s\n' '---' "record_seq: $2" 'kind: result' 'topic_id: live' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $9" \
    "status: $6" "reason: $7" "result_sha: $8" 'observed_at: 2026-08-11T15:03:00Z' > "$out"
  [ -n "${10:-}" ] && printf 'owner_answer_ref: %s\n' "${10}" >> "$out"
  printf '%s\n' 'recorded_at: 2026-08-11T15:03:00Z' '---' 'Captured result.' >> "$out"
}
emit_question() { # topic seq question-id blocks
  printf '%s\n' '---' "record_seq: $2" 'kind: owner-question' 'topic_id: live' \
    "question_id: $3" "blocks: $4" 'recorded_at: 2026-08-11T15:04:00Z' '---' \
    'Owner direction required.' > "$1/turns/$2-owner-question.md"
}
emit_answer() { # topic seq question-ref action [key=value]
  out="$1/turns/$2-owner-answer.md"; topic="$1"; seq="$2"; qref="$3"; action="$4"; shift 4
  printf '%s\n' '---' "record_seq: $seq" 'kind: owner-answer' 'topic_id: live' \
    "question_ref: $qref" "action: $action" > "$out"
  for pair in "$@"; do printf '%s: %s\n' "${pair%%=*}" "${pair#*=}" >> "$out"; done
  printf '%s\n' 'recorded_at: 2026-08-11T15:05:00Z' '---' 'Owner answer.' >> "$out"
}
emit_topic() { # topic topic-id base-sha base-ref branch worktree common-dir
  printf '%s\n' '---' "topic_id: $2" "base_sha: $3" "base_ref: $4" \
    "session_branch: $5" "session_worktree: $6" "work_repo_common_dir: $7" '---' \
    "# $2" '## Charter' '## Preconditions' '## Registry' '## DECISIONS' '## Onboarding' \
    > "$1/TOPIC.md"
}
emit_close() { # topic seq close-id final-sha
  printf '%s\n' '---' "record_seq: $2" 'kind: close' 'topic_id: live' \
    "close_id: $3" "final_accepted_sha: $4" 'recorded_at: 2026-08-11T15:06:00Z' '---' \
    'Charter dispositions recorded.' > "$1/turns/$2-close.md"
}
emit_late() { # topic seq turn attempt kind assignment-ref late-index named-sha
  printf '%s\n' '---' "record_seq: $2" 'kind: late' 'topic_id: live' \
    "turn_id: $3" "attempt_id: $4" "turn_kind: $5" "assignment_ref: $6" \
    "named_sha: $8" 'recorded_at: 2026-08-11T15:07:00Z' '---' \
    'Late observation.' > "$1/turns/$2-t$3-a$4-late-$7.md"
}

make_live() { # <mode> -> topic dir
  # D16 + D28: an unchecked mktemp here makes R=/repo, W=/wt, T=/topic — and the
  # close_worktree_stale mode below then runs `rm -rf /wt`. Check before anything derives a path.
  B="$(mktemp -d "$TMPROOT/live.XXXXXX")" || { echo "FATAL: mktemp under $TMPROOT failed" >&2; return 1; }
  [ -n "$B" ] && [ -d "$B" ] || { echo "FATAL: mktemp produced no directory" >&2; return 1; }
  case "$B" in "$TMPROOT"/live.?*) ;; *) echo "FATAL: $B is not under $TMPROOT" >&2; return 1;; esac
  R="$B/repo"; W="$B/wt"; T="$B/topic"
  mkdir -p "$R"; git -C "$R" init -q
  ( cd "$R" && echo a > a.txt && git add -A ) && gc "$R" seed
  B0="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" worktree add -q "$W" -b pair/live "$B0"
  ( cd "$W" && mkdir -p src && echo x > src/x.txt && git add -A ) \
    && gc "$W" "work

Agent-Pairing-Topic: live
Agent-Pairing-Turn: 0001
Agent-Pairing-Attempt: 01"
  C1="$(git -C "$W" rev-parse HEAD)"
  mkdir -p "$T/turns"; git -C "$T" init -q
  # TOPIC.md first — §3.0 writes it before any record, and it is the base seed + identity source.
  emit_topic "$T" live "$B0" "refs/heads/$(git -C "$R" symbolic-ref --short HEAD)" \
             pair/live "$W" "$R/.git"
  emit_assignment "$T" 0001 0001 01 NORMAL "$B0" pair/live "$W" "$R/.git" "src/"
  emit_intent     "$T" 0002 0001 01 NORMAL 0001-t0001-a01-assignment.md tok-1
  emit_dispatch   "$T" 0003 0001 01 NORMAL 0001-t0001-a01-assignment.md 0002-t0001-a01-intent.md direct
  emit_result     "$T" 0004 0001 01 NORMAL VERIFIED "" "$C1" 0001-t0001-a01-assignment.md
  case "$1" in
    accepted) : ;;
    dirty)    echo dirt > "$W/src/z.txt" ;;
    identity_wrong_branch) git -C "$W" checkout -q -b other ;;
    quarantined)
      ( cd "$W" && echo rejected > src/rejected.txt && git add -A ) && gc "$W" "rejected

Agent-Pairing-Topic: live
Agent-Pairing-Turn: 0002
Agent-Pairing-Attempt: 01"
      C2="$(git -C "$W" rev-parse HEAD)"
      emit_assignment "$T" 0005 0002 01 NORMAL "$C1" pair/live "$W" "$R/.git" "src/"
      emit_intent "$T" 0006 0002 01 NORMAL 0005-t0002-a01-assignment.md tok-2
      emit_dispatch "$T" 0007 0002 01 NORMAL 0005-t0002-a01-assignment.md 0006-t0002-a01-intent.md direct
      emit_result "$T" 0008 0002 01 NORMAL REJECTED out-of-scope-changes "$C2" 0005-t0002-a01-assignment.md ;;
    trailered)
      ( cd "$W" && echo residue > src/residue.txt && git add -A ) && gc "$W" "residue

Agent-Pairing-Topic: live
Agent-Pairing-Turn: 0001
Agent-Pairing-Attempt: 01" ;;
    trailered_wrong_topic)
      ( cd "$W" && echo residue > src/residue.txt && git add -A ) && gc "$W" "residue

Agent-Pairing-Topic: another-topic
Agent-Pairing-Turn: 0001
Agent-Pairing-Attempt: 01" ;;
    foreign)
      ( cd "$W" && echo foreign > src/foreign.txt && git add -A ) && gc "$W" foreign ;;
    noworktree) git -C "$R" worktree remove --force "$W" ;;
    close_worktree_stale)  emit_close "$T" 0005 c-0001 "$C1"
                           safe_rmdir "$W" "$TMPROOT/live." ;;   # entry survives; D7 spelling; D28
    close_worktree_dangling)  # D26: a dangling symlink still occupies the session path
                           emit_close "$T" 0005 c-0001 "$C1"
                           git -C "$R" worktree remove "$W"; ln -s "$B/nowhere" "$W" ;;
    close_repo_unreadable) # D26: a git read that FAILS must not read as "no entry"
                           emit_close "$T" 0005 c-0001 "$C1"
                           git -C "$R" worktree remove "$W"; chmod 000 "$R/.git" ;;
    close_worktree_present) emit_close "$T" 0005 c-0001 "$C1" ;;               # worktree still registered + present
    close_branch_moved)    emit_close "$T" 0005 c-0001 "$C1"
                           ( cd "$W" && echo drift > src/d.txt && git add -A ) && gc "$W" drift
                           git -C "$R" worktree remove --force "$W" ;;
    closed_pending)        emit_close "$T" 0005 c-0001 "$C1"; git -C "$R" worktree remove "$W" ;;
    closed_branch_moved_late)   # I1: pin branch-at-final's CONSUMPTION, isolated from thread-header.
                           # Same shape as closed_pending, but render+commit THREAD.md while the
                           # branch is STILL at the final SHA (so classification is genuinely CLOSED
                           # at render time and thread-header PASSes later), THEN move the branch —
                           # branch-at-final is the only conjunct left to fail.
                           emit_close "$T" 0005 c-0001 "$C1"
                           git -C "$R" worktree remove "$W"
                           /bin/bash "$VALIDATE" --render "$T" >/dev/null 2>&1
                           git -C "$R" update-ref refs/heads/pair/live "$B0" ;;
  esac
  git -C "$T" add -A && gc "$T" records
  echo "$T"; }
