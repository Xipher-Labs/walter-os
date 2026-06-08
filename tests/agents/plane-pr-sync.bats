#!/usr/bin/env bats
# tests/agents/plane-pr-sync.bats
#
# Covers: docs/specs/plane-pr-sync.md
#
# shellcheck disable=SC2030,SC2031

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agents/plane-pr-sync.sh"
  MOCK_DIR="$(mktemp -d)"
  CALL_LOG="$MOCK_DIR/calls.log"
  ORIGINAL_PATH="$PATH"
  if [[ -v TMPDIR ]]; then
    ORIGINAL_TMPDIR="$TMPDIR"
    TMPDIR_WAS_SET=1
  else
    ORIGINAL_TMPDIR=""
    TMPDIR_WAS_SET=0
  fi
  export CALL_LOG
  export ORIGINAL_PATH
  export ORIGINAL_TMPDIR
  export TMPDIR_WAS_SET
  export PATH="$MOCK_DIR:$PATH"
  mkdir -p "$MOCK_DIR/tmp"
  export TMPDIR="$MOCK_DIR/tmp"
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
posted_comment_file="$(dirname "$CALL_LOG")/posted-comment"
if [[ " $* " == *" issues "* && " $* " == *" --comments "* && " $* " == *" --output json "* ]]; then
  if [[ "${TEA_FAIL_VIEW:-0}" == "1" ]]; then
    echo "simulated tea comment fetch failure" >&2
    exit 96
  fi
  if [[ "${TEA_MALFORMED_VIEW:-0}" == "1" ]]; then
    echo 'not-json'
    exit 0
  fi
  if [[ -f "$posted_comment_file" ]]; then
    printf '{"comments":[{"author":{"login":"%s"},"body":"%s"}]}\n' "${TEA_POST_AUTHOR:-${TEA_COMMENT_AUTHOR:-walter-bot}}" "$(cat "$posted_comment_file")"
    exit 0
  fi
  printf '{"comments":[{"author":{"login":"%s"},"body":"%s"}]}\n' "${TEA_COMMENT_AUTHOR:-walter-bot}" "${TEA_EXISTING_COMMENTS:-}"
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
    if [[ "${TEA_DROP_COMMENT:-0}" == "1" ]]; then
      exit 0
    fi
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--comment" ]]; then
        printf '%s' "${2:-}" > "$posted_comment_file"
        break
      fi
      shift
    done
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
  if [[ "$TMPDIR_WAS_SET" == "1" ]]; then
    export TMPDIR="$ORIGINAL_TMPDIR"
  else
    unset TMPDIR
  fi
  rm -rf "$MOCK_DIR"
}

combined_output() {
  printf '%s\n%s\n' "$output" "${stderr:-}"
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

@test "AC1: Forgejo link comment stores stable Plane issue marker" {
  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'walter-plane-issue:issue-uuid' "$CALL_LOG"
}

@test "AC1: Forgejo comments are idempotent" {
  export TEA_EXISTING_COMMENTS="[walter-plane-issue:issue-uuid] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'tea issues view 7 --repo acme/app --comments --output json' "$CALL_LOG"
  if grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: sync marker without Plane issue marker does not satisfy binding" {
  export TEA_EXISTING_COMMENTS="[walter-pr-sync:acme/app#7:link] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"
}

@test "AC1: wrong Plane issue marker does not satisfy binding" {
  export TEA_EXISTING_COMMENTS="[walter-plane-issue:other-issue] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"conflicting walter-plane-issue marker"* ]]
  if grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"; then
    return 1
  fi
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: untrusted existing Plane issue marker does not satisfy binding" {
  export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS="walter-bot"
  export TEA_COMMENT_AUTHOR="contributor"
  export TEA_POST_AUTHOR="walter-bot"
  export TEA_EXISTING_COMMENTS="[walter-plane-issue:issue-uuid] spoofed"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"
}

@test "AC1: explicitly empty Forgejo author allowlist aborts before Plane review" {
  export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS=" , ,, "
  export TEA_COMMENT_AUTHOR="contributor"
  export TEA_EXISTING_COMMENTS="[walter-plane-issue:issue-uuid] spoofed"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"empty WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS allowlist"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: trusted existing Plane issue marker satisfies binding" {
  export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS="walter-bot"
  export TEA_COMMENT_AUTHOR="walter-bot"
  export TEA_EXISTING_COMMENTS="[walter-plane-issue:issue-uuid] already posted"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  if grep -q 'tea issues comment 7 --repo acme/app' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: trusted newly posted marker satisfies binding" {
  export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS="walter-bot"
  export TEA_POST_AUTHOR="walter-bot"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  grep -q 'state-review' "$CALL_LOG"
}

@test "AC1: successful comment command without persisted marker aborts before Plane review" {
  export TEA_DROP_COMMENT=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"Forgejo PR marker comment was not persisted"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: untrusted newly posted marker aborts before Plane review" {
  export WALTER_FORGEJO_WEBHOOK_COMMENT_AUTHORS="walter-bot"
  export TEA_POST_AUTHOR="contributor"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"Forgejo PR marker comment is not trusted"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
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

@test "AC1: Forgejo marker persistence failure aborts before Plane review" {
  export TEA_FAIL_COMMENT=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"Forgejo PR marker comment failed"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: missing tea aborts before Plane review" {
  rm -f "$MOCK_DIR/tea"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"tea is required to persist the Forgejo PR marker"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: Forgejo comment inspection failure aborts before Plane review" {
  export TEA_FAIL_VIEW=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"failed to inspect Forgejo PR comments before marker persistence"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
}

@test "AC1: malformed Forgejo comment JSON aborts before Plane review" {
  export TEA_MALFORMED_VIEW=1

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 3 ]
  [[ "$(combined_output)" == *"failed to parse Forgejo PR comments before marker persistence"* ]]
  if grep -q 'state-review' "$CALL_LOG"; then
    return 1
  fi
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
  grep -q 'walter-plane-issue:issue-uuid' "$CALL_LOG"
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
  [[ "$(combined_output)" == *"missing Plane helper"* ]]
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
  [[ "$(combined_output)" == *"failed to inspect Plane comments"* ]]
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
  [[ "$(combined_output)" == *"failed to parse Plane comments"* ]]
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
  [[ "$(combined_output)" == *"unknown event: closed"* ]]
}

@test "AC4: unknown event fails before required options" {
  run bash "$SCRIPT" closed

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"unknown event: closed"* ]]
  [[ "$(combined_output)" != *"missing --issue"* ]]
}

@test "AC4: missing event fails closed" {
  run bash "$SCRIPT"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"missing event"* ]]
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
  [[ "$(combined_output)" == *"missing value for --issue"* ]]
}

@test "AC4: non-numeric PR number fails closed" {
  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "-7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"--pr-number must be numeric"* ]]
}

@test "AC5: newline input is rejected" {
  run bash "$SCRIPT" link \
    --issue $'issue\nuuid' \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"newline"* ]]
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
  grep -q 'chmod 700' "$SCRIPT"
  grep -q 'lock_dir' "$SCRIPT"
}

@test "AC6: lock setup failure warns and continues" {
  cat > "$MOCK_DIR/flock" <<'FLOCK_MOCK'
#!/usr/bin/env bash
exit 0
FLOCK_MOCK
  chmod +x "$MOCK_DIR/flock"

  cat > "$MOCK_DIR/chmod" <<'CHMOD_MOCK'
#!/usr/bin/env bash
if [[ "$1" == "700" ]]; then
  echo "simulated chmod failure" >&2
  exit 99
fi
/bin/chmod "$@"
CHMOD_MOCK
  /bin/chmod +x "$MOCK_DIR/chmod"

  run bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  [[ "$(combined_output)" == *"failed to secure lock dir"* ]]
  grep -q 'walter-pr-sync:acme/app#7:link' "$CALL_LOG"
}

@test "AC6: symlink lock dir warns and continues" {
  cat > "$MOCK_DIR/flock" <<'FLOCK_MOCK'
#!/usr/bin/env bash
exit 0
FLOCK_MOCK
  chmod +x "$MOCK_DIR/flock"
  mkdir -p "$MOCK_DIR/tmp" "$MOCK_DIR/lock-target"
  ln -s "$MOCK_DIR/lock-target" "$MOCK_DIR/tmp/walter-os-plane-pr-sync"

  run env TMPDIR="$MOCK_DIR/tmp" bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  [[ "$(combined_output)" == *"unsafe symlink lock dir"* ]]
  grep -q 'walter-pr-sync:acme/app#7:link' "$CALL_LOG"
}

@test "AC6: symlink lock file warns and continues" {
  cat > "$MOCK_DIR/flock" <<'FLOCK_MOCK'
#!/usr/bin/env bash
exit 0
FLOCK_MOCK
  chmod +x "$MOCK_DIR/flock"
  mkdir -p "$MOCK_DIR/tmp/walter-os-plane-pr-sync" "$MOCK_DIR/lock-target"
  ln -s "$MOCK_DIR/lock-target" "$MOCK_DIR/tmp/walter-os-plane-pr-sync/acme_app-7.lock"

  run env TMPDIR="$MOCK_DIR/tmp" bash "$SCRIPT" link \
    --issue "issue-uuid" \
    --pr-url "https://git.example.test/acme/app/pulls/7" \
    --pr-number "7" \
    --repo "acme/app" \
    --branch "feature/thing"

  [ "$status" -eq 0 ]
  [[ "$(combined_output)" == *"unsafe lock file"* ]]
  grep -q 'walter-pr-sync:acme/app#7:link' "$CALL_LOG"
}
