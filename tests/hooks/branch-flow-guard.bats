#!/usr/bin/env bats
# Tests for hooks/branch-flow-guard.sh
#
# Policy per ADR 0013 — operator-configurable branch flow:
#   WALTER_BRANCH_FLOW=single-tier  (default) — feature/* can target main directly
#   WALTER_BRANCH_FLOW=three-stage  — feature → dev → staging → main gate
#
# Independent of mode:
#   - direct push to or from main/master/staging/production is forbidden
#   - optional WALTER_MANUAL_PR_REMOTE_PATTERN gate (manual-PR-only remotes)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/branch-flow-guard.sh"

  # Create a temp git repo so the hook has a branch context
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q -b feature/test
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  git remote add origin https://github.com/example/test.git
}

teardown() {
  unset WALTER_BRANCH_FLOW WALTER_MANUAL_PR_REMOTE_PATTERN
  rm -rf "$TMPDIR_TEST"
}

input_json() {
  printf '{"tool":"Bash","tool_input":{"command":%s}}' "$(jq -Rs '.' <<<"$1")"
}

# ---- baseline ---------------------------------------------------------

@test "allows random non-git commands" {
  result="$(input_json "ls -la" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

# ---- single-tier mode (default) ---------------------------------------

@test "single-tier (default): allows feature/* → main without --base" {
  result="$(input_json "gh pr create --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "single-tier (default): allows feature/* → main with explicit --base" {
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "single-tier (explicit env): allows feature/* → main" {
  export WALTER_BRANCH_FLOW=single-tier
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "single-tier: unknown WALTER_BRANCH_FLOW value falls back to allow" {
  export WALTER_BRANCH_FLOW=does-not-exist
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

# ---- three-stage mode -------------------------------------------------

@test "three-stage: blocks feature/* → main" {
  export WALTER_BRANCH_FLOW=three-stage
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "three-stage: allows feature/* → dev" {
  export WALTER_BRANCH_FLOW=three-stage
  result="$(input_json "gh pr create --base dev --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "three-stage: --allow-branch-skip bypasses the gate" {
  export WALTER_BRANCH_FLOW=three-stage
  result="$(input_json "gh pr create --base main --allow-branch-skip --title hotfix" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "three-stage: blocks dev → main without skip" {
  export WALTER_BRANCH_FLOW=three-stage
  git checkout -q -b dev
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "three-stage: allows dev → staging" {
  export WALTER_BRANCH_FLOW=three-stage
  git checkout -q -b dev
  result="$(input_json "gh pr create --base staging --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

# ---- protected-branch push block (both modes) -------------------------

@test "blocks direct push to main (single-tier mode)" {
  git checkout -q -b main
  result="$(input_json "git push origin main" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "blocks direct push to main (three-stage mode)" {
  export WALTER_BRANCH_FLOW=three-stage
  git checkout -q -b main
  result="$(input_json "git push origin main" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "blocks push from staging branch" {
  git checkout -q -b staging
  result="$(input_json "git push" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "blocks direct push to master" {
  git checkout -q -b master
  result="$(input_json "git push origin master" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "blocks direct push to production" {
  git checkout -q -b production
  result="$(input_json "git push origin production" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "allows push to feature branch" {
  result="$(input_json "git push origin feature/test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

# ---- manual-PR remote pattern (independent of branch flow) ------------

@test "manual-PR remote pattern blocks gh pr create without override flag" {
  export WALTER_MANUAL_PR_REMOTE_PATTERN=example/test
  result="$(input_json "gh pr create --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "manual-PR remote pattern allows with override flag" {
  export WALTER_MANUAL_PR_REMOTE_PATTERN=example/test
  result="$(input_json "gh pr create --allow-manual-pr --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}
