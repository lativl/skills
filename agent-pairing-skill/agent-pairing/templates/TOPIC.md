---
protocol_version: 2
topic_id: {{TOPIC_ID}}
participant_start_mode: {{PARTICIPANT_START_MODE}}
participant_selection_source: {{PARTICIPANT_SELECTION_SOURCE}}
base_sha: {{BASE_SHA}}
base_ref: {{BASE_REF}}
session_branch: {{SESSION_BRANCH}}
session_worktree: {{SESSION_WORKTREE}}
work_repo_common_dir: {{WORK_REPO_COMMON_DIR}}
---
<!-- protocol_version is the compatibility boundary. The default validator accepts only the exact
     scalar 2; historical records are read by scripts/validate-v1.sh and by nothing else.

     participant_start_mode is `primary-spawn` or `owner-manual`, and
     participant_selection_source records WHERE that choice came from: `initial-prompt` when the
     opening request was unambiguous, `owner-answer` when it was absent or contradictory and the
     owner was asked the one selection question. Both values are written at OPEN, before any
     admission exists, so replay can tell an inferred choice from an answered one. -->

<!-- base_sha is the pinned base (§3.0 step 3); base_ref is the EXPLICIT ref it was cut from
     (§2.2, "never guessed"). The validator seeds accepted_sha from base_sha and presence-checks
     base_ref — it cannot resolve a remote ref in a rehydrated repo and does not claim to. -->
# {{TOPIC_ID}}
## Charter
## Preconditions
## Registry
## Verification profiles

One block per profile the topic uses. An assignment binds one by `verification_profile_id`, or the
literal `null` for a turn that verifies nothing. A verification claim is only as good as the
environment it was made in, so the environment is pinned here rather than assumed.

```yaml
profile_id: {{PROFILE_ID}}
lock_identity: {{LOCK_IDENTITY}}
bootstrap_command: {{BOOTSTRAP_COMMAND}}
verification_command: {{VERIFICATION_COMMAND}}
required_tools: {{REQUIRED_TOOLS}}
required_environment_names: {{REQUIRED_ENVIRONMENT_NAMES}}
```

`lock_identity` is the lockfile or environment-manifest identity — a digest, not a version range.
`required_environment_names` lists the NAMES of variables that must be set. **Secret values never
enter a record.**

## DECISIONS
## Onboarding
