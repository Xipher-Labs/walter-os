#!/usr/bin/env bats
# Tests for hooks/branch-flow-guard.sh

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

@test "blocks gh pr create from feature/* to main" {
  result="$(input_json "gh pr create --base main --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "allows gh pr create from feature/* to dev" {
  result="$(input_json "gh pr create --base dev --title test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows --allow-branch-skip override" {
  result="$(input_json "gh pr create --base main --allow-branch-skip --title hotfix" | "$HOOK")"
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

@test "allows push to feature branch" {
  result="$(input_json "git push origin feature/test" | "$HOOK")"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}
