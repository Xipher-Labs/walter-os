#!/usr/bin/env bats
# tests/agents/plane-pr-sync-trigger.bats
#
# Covers: docs/specs/plane-pr-sync.md trigger wrapper.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agents/plane-pr-sync-trigger.sh"
  MOCK_DIR="$(mktemp -d)"
  CALL_LOG="$MOCK_DIR/calls.log"
  export CALL_LOG
  export WALTER_PLANE_PR_SYNC_SCRIPT="$MOCK_DIR/plane-pr-sync.sh"

  cat > "$WALTER_PLANE_PR_SYNC_SCRIPT" <<'SYNC_MOCK'
#!/usr/bin/env bash
printf 'plane-pr-sync %s\n' "$*" >> "$CALL_LOG"
case " $* " in
  *" merge "*|*" push "*|*" approve "*)
    echo "forbidden sync command" >&2
    exit 99
    ;;
esac
exit 0
SYNC_MOCK
  chmod +x "$WALTER_PLANE_PR_SYNC_SCRIPT"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

write_payload() {
  local file="$MOCK_DIR/payload.json"
  cat > "$file"
  printf '%s\n' "$file"
}

combined_output() {
  printf '%s\n%s\n' "$output" "${stderr:-}"
}

@test "opened pull_request payload calls link sync primitive" {
  payload="$(write_payload <<'JSON'
{
  "action": "opened",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"},
    "merged": false
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 0 ]
  grep -q 'plane-pr-sync link --issue issue-uuid --pr-url https://git.example.test/acme/app/pulls/7 --pr-number 7 --repo acme/app --branch feature/thing' "$CALL_LOG"
}

@test "closed merged pull_request payload calls merged sync primitive" {
  payload="$(write_payload <<'JSON'
{
  "action": "closed",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"},
    "merged": true,
    "merged_commit_sha": "abcdef1234567890"
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 0 ]
  grep -q 'plane-pr-sync merged --issue issue-uuid --pr-url https://git.example.test/acme/app/pulls/7 --pr-number 7 --repo acme/app --branch feature/thing --merge-sha abcdef1234567890' "$CALL_LOG"
}

@test "closed unmerged pull_request payload is a no-op" {
  payload="$(write_payload <<'JSON'
{
  "action": "closed",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"},
    "merged": false
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 0 ]
  [[ "$(combined_output)" == *"no sync action for closed unmerged PR"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "unsupported event fails before invoking sync primitive" {
  payload="$(write_payload <<'JSON'
{"action":"opened"}
JSON
)"

  run bash "$SCRIPT" --event push --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"unsupported event: push"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "unsupported pull_request action fails before invoking sync primitive" {
  payload="$(write_payload <<'JSON'
{
  "action": "assigned",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"}
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"unsupported pull_request action: assigned"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "payload fields containing newlines are rejected before sync" {
  payload="$(write_payload <<'JSON'
{
  "action": "opened",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing\nbad"},
    "merged": false
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"branch contains a newline"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "merged payload without merge sha fails before sync" {
  payload="$(write_payload <<'JSON'
{
  "action": "closed",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"},
    "merged": true
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"missing merge sha"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "script never invokes merge push or approve operations" {
  payload="$(write_payload <<'JSON'
{
  "action": "closed",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing"},
    "merged": true,
    "merge_commit_sha": "abcdef1234567890"
  }
}
JSON
)"

  run bash "$SCRIPT" --event pull_request --issue issue-uuid --payload-file "$payload"

  [ "$status" -eq 0 ]
  if grep -Eq ' merge | push | approve ' "$CALL_LOG"; then
    return 1
  fi
}
