#!/usr/bin/env bats
# Tests for hooks/branch-flow-guard.sh
#
# Policy enforced by the hook (per ADR 0013):
#   - feature/* may target main directly (no dev → staging → main gate)
#   - direct push to or from main/master/staging/production is forbidden

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
  rm -rf "$TMPDIR_TEST"
}

input_json() {
  printf '{"tool":"Bash","tool_input":{"command":%s}}' "$(jq -Rs '.' <<<"$1")"
}

@test "allows random non-git commands" {
  result="$(input_json "ls -la" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows gh pr create from feature/* to main (ADR 0013 — direct flow)" {
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows gh pr create from feature/* with no explicit --base" {
  result="$(input_json "gh pr create --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "blocks direct push to main" {
  git checkout -q -b main
  result="$(input_json "git push origin main" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "blocks push to staging from staging branch" {
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

@test "manual-PR remote pattern blocks gh pr create without override flag" {
  export WALTER_MANUAL_PR_REMOTE_PATTERN=example/test
  result="$(input_json "gh pr create --title test" | "$HOOK")"
  unset WALTER_MANUAL_PR_REMOTE_PATTERN
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "manual-PR remote pattern allows with override flag" {
  export WALTER_MANUAL_PR_REMOTE_PATTERN=example/test
  result="$(input_json "gh pr create --allow-manual-pr --title test" | "$HOOK")"
  unset WALTER_MANUAL_PR_REMOTE_PATTERN
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}
