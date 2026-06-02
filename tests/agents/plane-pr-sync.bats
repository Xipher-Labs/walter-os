#!/usr/bin/env bats
# tests/agents/plane-pr-sync.bats
#
# Covers: docs/specs/plane-pr-sync.md

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agents/plane-pr-sync.sh"
  MOCK_DIR="$(mktemp -d)"
  CALL_LOG="$MOCK_DIR/calls.log"
  ORIGINAL_PATH="$PATH"
  export CALL_LOG
  export ORIGINAL_PATH
  export PATH="$MOCK_DIR:$PATH"
  export WALTER_OS_HOME="$REPO_ROOT"
  export PLANE_API_TOKEN="test-token"
  export PLANE_API_URL="http://plane.test/api/v1"
  export PLANE_WORKSPACE="walter-os"
  export PLANE_PROJECT="project-uuid"

  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALL_LOG"
args="$*"
if echo "$args" | grep -q "/states/"; then
  echo '{"results":[{"id":"state-review","name":"review"},{"id":"state-done","name":"done"}]}'
elif echo "$args" | grep -q "/comments/"; then
  if echo "$args" | grep -q -- "-X GET"; then
    if [[ "${PLANE_FAIL_COMMENT_FETCH:-0}" == "1" ]]; then
      echo "simulated Plane comment fetch failure" >&2
      exit 97
    fi
    if [[ "${PLANE_MALFORMED_COMMENTS:-0}" == "1" ]]; then
      echo 'not-json'
      exit 0
    fi
    if [[ -n "${PLANE_EXISTING_COMMENTS:-}" ]]; then
      printf '{"results":[{"comment_stripped":"%s"}]}\n' "$PLANE_EXISTING_COMMENTS"
      exit 0
    fi
    echo '{"results":[]}'
  else
    echo '{"ok":true}'
  fi
else
  echo '{"ok":true}'
fi
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  cat > "$MOCK_DIR/tea" <<'TEA_MOCK'
#!/usr/bin/env bash
printf 'tea %s\n' "$*" >> "$CALL_LOG"
if [[ " $* " == *" issues "* && " $* " == *" --comments "* && " $* " == *" --output json "* ]]; then
  printf '{"comments":[{"body":"%s"}]}\n' "${TEA_EXISTING_COMMENTS:-}"
  exit 0
fi
case " $* " in
  *" merge "*|*" push "*)
    echo "forbidden tea command" >&2
    exit 99
    ;;
  *" issues comment "*)
    if [[ "${TEA_FAIL_COMMENT:-0}" == "1" ]]; then
      echo "simulated tea comment failure" >&2
      exit 98
    fi
    ;;
esac
exit 0
TEA_MOCK
  chmod +x "$MOCK_DIR/tea"

  cat > "$MOCK_DIR/git" <<'GIT_MOCK'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALL_LOG"
case " $* " in
  *" merge "*|*" push "*)
    echo "forbidden git command" >&2
    exit 99
    ;;
esac
exit 0
GIT_MOCK
  chmod +x "$MOCK_DIR/git"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  rm -rf "$MOCK_DIR"
}

@test "AC1: link comments on Plane, moves to review, and comments on Forgejo" {
  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'walter-pr-sync:acme/app#7:link' "$CALL_LOG"
  grep -q 'state-review' "$CALL_LOG"
  grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"
}

@test "AC1: Forgejo comments are idempotent" {
  export TEA_EXISTING_COMMENTS="[walter-pr-sync:acme/app#7:link] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'tea issues 7 --repo acme/app --comments --output json' "$CALL_LOG"
  if grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: Plane comments are idempotent" {
  export PLANE_EXISTING_COMMENTS="[walter-pr-sync:acme/app#7:link] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  if grep -Eq 'curl .* -X POST .*comments/' "$CALL_LOG"; then
    return 1
  fi
  grep -q 'state-review' "$CALL_LOG"
}

@test "AC1: Forgejo comment failure warns and continues" {
  export TEA_FAIL_COMMENT=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN Forgejo PR comment failed"* ]]
  grep -q 'state-review' "$CALL_LOG"
}

@test "AC2: merged comments with merge sha and moves Plane to done" {
  run bash "$SCRIPT" merged \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing" \
    --merge-sha "abcdef1234567890"

  [ "$status" -eq 0 ]
  grep -q 'walter-pr-sync:acme/app#7:merged' "$CALL_LOG"
  grep -q 'abcdef123456' "$CALL_LOG"
  grep -q 'state-done' "$CALL_LOG"
}

@test "AC3: missing Plane env fails before state changes" {
  unset PLANE_API_TOKEN

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -ne 0 ]
  if [[ -f "$CALL_LOG" ]] && grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC3: missing Plane helper is setup failure" {
  local missing_home="$MOCK_DIR/missing-home"
  mkdir -p "$missing_home"

  run env WALTER_OS_HOME="$missing_home" bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$output" == *"missing Plane helper"* ]]
}

@test "AC3: Plane comment fetch failure aborts before state changes" {
  export PLANE_FAIL_COMMENT_FETCH=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$output" == *"failed to inspect Plane comments"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC3: malformed Plane comments abort before state changes" {
  export PLANE_MALFORMED_COMMENTS=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$output" == *"failed to parse Plane comments"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC4: unknown event fails closed" {
  run bash "$SCRIPT" closed \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown event: closed"* ]]
}

@test "AC4: unknown event fails before required options" {
  run bash "$SCRIPT" closed

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown event: closed"* ]]
  [[ "$output" != *"missing --issue"* ]]
}

@test "AC4: missing event fails closed" {
  run bash "$SCRIPT"

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing event"* ]]
}

@test "AC4: explicit help exits cleanly" {
  run bash "$SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "AC4: missing option value fails closed" {
  run bash "$SCRIPT" link \
    --issue \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 2 ]
  [[ "$output" == *"missing value for --issue"* ]]
}

@test "AC5: newline input is rejected" {
  run bash "$SCRIPT" link \
    --issue $'issue\nuuid' \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 2 ]
  [[ "$output" == *"newline"* ]]
}

@test "AC6: script never invokes merge or push" {
  run bash "$SCRIPT" merged \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing" \
    --merge-sha "abcdef1234567890"

  [ "$status" -eq 0 ]
  if grep -Eq '^tea .* merge( |$)' "$CALL_LOG"; then
    return 1
  fi
  if grep -Eq 'git .* push' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC6: script declares jq preflight" {
  grep -q 'command -v jq' "$SCRIPT"
  grep -q 'jq is required' "$SCRIPT"
}

@test "AC6: script declares optional flock guard" {
  grep -q 'command -v flock' "$SCRIPT"
  grep -q 'flock -n' "$SCRIPT"
}
