#!/usr/bin/env bats
# tests/agents/plane-pr-sync-webhook.bats
#
# Covers: docs/specs/plane-pr-sync.md signed webhook adapter.

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is required"
  command -v python3 >/dev/null 2>&1 || skip "python3 is required"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agents/plane-pr-sync-webhook.sh"
  MOCK_DIR="$(mktemp -d)"
  CALL_LOG="$MOCK_DIR/calls.log"
  ORIGINAL_PATH="$PATH"
  export CALL_LOG
  export ORIGINAL_PATH
  export WALTER_FORGEJO_WEBHOOK_SECRET="test-webhook-secret"
  export WALTER_PLANE_PR_SYNC_SCRIPT="$MOCK_DIR/plane-pr-sync.sh"
  export PATH="$MOCK_DIR:$PATH"

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

  cat > "$MOCK_DIR/tea" <<'TEA_MOCK'
#!/usr/bin/env bash
printf 'tea %s\n' "$*" >> "$CALL_LOG"
case " $* " in
  *" merge "*|*" push "*|*" approve "*)
    echo "forbidden tea command" >&2
    exit 99
    ;;
esac
if [[ " $* " == *" issues view "* && " $* " == *" --comments "* && " $* " == *" --output json "* ]]; then
  if [[ -n "${TEA_COMMENTS_FILE:-}" ]]; then
    cat "$TEA_COMMENTS_FILE"
  else
    echo '{"comments":[]}'
  fi
  exit 0
fi
exit 0
TEA_MOCK
  chmod +x "$MOCK_DIR/tea"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  rm -rf "$MOCK_DIR"
}

combined_output() {
  printf '%s\n%s\n' "$output" "${stderr:-}"
}

assert_log_contains() {
  local pattern="$1"
  [[ -f "$CALL_LOG" ]]
  grep -q "$pattern" "$CALL_LOG"
}

assert_no_forbidden_log_commands() {
  if [[ -f "$CALL_LOG" ]] && grep -Eq ' merge | push | approve ' "$CALL_LOG"; then
    return 1
  fi
}

write_payload() {
  local file="$MOCK_DIR/payload.json"
  cat > "$file"
  printf '%s\n' "$file"
}

write_comments() {
  local file="$MOCK_DIR/comments.json"
  cat > "$file"
  printf '%s\n' "$file"
}

signature_for() {
  python3 -c 'import hashlib, hmac, sys; print(hmac.new(sys.argv[1].encode(), open(sys.argv[2], "rb").read(), hashlib.sha256).hexdigest())' \
    "$WALTER_FORGEJO_WEBHOOK_SECRET" "$1"
}

@test "signed closed merged payload resolves marker and calls merged sync" {
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
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"[walter-plane-issue:issue-uuid] linked by Walter"}]}
JSON
)"
  export TEA_COMMENTS_FILE="$comments"
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload"

  [ "$status" -eq 0 ]
  assert_log_contains 'tea issues view 7 --repo acme/app --comments --output json'
  assert_log_contains 'plane-pr-sync merged --issue issue-uuid --pr-url https://git.example.test/acme/app/pulls/7 --pr-number 7 --repo acme/app --branch feature/thing --merge-sha abcdef1234567890'
}

@test "sha256-prefixed signatures are accepted" {
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
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"[walter-plane-issue:issue-uuid] linked by Walter"}]}
JSON
)"
  export TEA_COMMENTS_FILE="$comments"
  signature="sha256=$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload"

  [ "$status" -eq 0 ]
  assert_log_contains 'plane-pr-sync merged --issue issue-uuid'
}

@test "missing signature fails before comments or sync" {
  payload="$(write_payload <<'JSON'
{"action":"closed","repository":{"full_name":"acme/app"},"pull_request":{"number":7,"html_url":"https://git.example.test/acme/app/pulls/7","head":{"ref":"feature/thing"},"merged":true,"merged_commit_sha":"abcdef1234567890"}}
JSON
)"

  run bash "$SCRIPT" --event pull_request --payload-file "$payload"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"missing --signature"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "invalid signature fails before comments or sync" {
  payload="$(write_payload <<'JSON'
{"action":"closed","repository":{"full_name":"acme/app"},"pull_request":{"number":7,"html_url":"https://git.example.test/acme/app/pulls/7","head":{"ref":"feature/thing"},"merged":true,"merged_commit_sha":"abcdef1234567890"}}
JSON
)"

  run bash "$SCRIPT" --event pull_request --signature "$(printf '0%.0s' {1..64})" --payload-file "$payload"

  [ "$status" -eq 4 ]
  [[ "$(combined_output)" == *"invalid webhook signature"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "closed unmerged payload is a no-op before marker lookup" {
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
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload"

  [ "$status" -eq 0 ]
  [[ "$(combined_output)" == *"no sync action for closed unmerged PR"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "missing marker fails closed before sync" {
  payload="$(write_payload <<'JSON'
{"action":"closed","repository":{"full_name":"acme/app"},"pull_request":{"number":7,"html_url":"https://git.example.test/acme/app/pulls/7","head":{"ref":"feature/thing"},"merged":true,"merged_commit_sha":"abcdef1234567890"}}
JSON
)"
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"no marker here"}]}
JSON
)"
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload" --comments-file "$comments"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"missing walter-plane-issue marker"* ]]
  if [[ -f "$CALL_LOG" ]] && grep -q 'plane-pr-sync' "$CALL_LOG"; then
    return 1
  fi
}

@test "ambiguous markers fail closed before sync" {
  payload="$(write_payload <<'JSON'
{"action":"closed","repository":{"full_name":"acme/app"},"pull_request":{"number":7,"html_url":"https://git.example.test/acme/app/pulls/7","head":{"ref":"feature/thing"},"merged":true,"merged_commit_sha":"abcdef1234567890"}}
JSON
)"
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"[walter-plane-issue:first]"},{"body":"[walter-plane-issue:second]"}]}
JSON
)"
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload" --comments-file "$comments"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"ambiguous walter-plane-issue markers"* ]]
  if [[ -f "$CALL_LOG" ]] && grep -q 'plane-pr-sync' "$CALL_LOG"; then
    return 1
  fi
}

@test "payload fields containing control characters are rejected before sync" {
  payload="$(write_payload <<'JSON'
{
  "action": "closed",
  "repository": {"full_name": "acme/app"},
  "pull_request": {
    "number": 7,
    "html_url": "https://git.example.test/acme/app/pulls/7",
    "head": {"ref": "feature/thing\nbad"},
    "merged": true,
    "merged_commit_sha": "abcdef1234567890"
  }
}
JSON
)"
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"[walter-plane-issue:issue-uuid] linked by Walter"}]}
JSON
)"
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload" --comments-file "$comments"

  [ "$status" -eq 2 ]
  [[ "$(combined_output)" == *"branch contains control characters"* ]]
  if [[ -f "$CALL_LOG" ]] && grep -q 'plane-pr-sync' "$CALL_LOG"; then
    return 1
  fi
}

@test "adapter never invokes merge push or approve operations" {
  payload="$(write_payload <<'JSON'
{"action":"closed","repository":{"full_name":"acme/app"},"pull_request":{"number":7,"html_url":"https://git.example.test/acme/app/pulls/7","head":{"ref":"feature/thing"},"merged":true,"merge_commit_sha":"abcdef1234567890"}}
JSON
)"
  comments="$(write_comments <<'JSON'
{"comments":[{"body":"[walter-plane-issue:issue-uuid] linked by Walter"}]}
JSON
)"
  signature="$(signature_for "$payload")"

  run bash "$SCRIPT" --event pull_request --signature "$signature" --payload-file "$payload" --comments-file "$comments"

  [ "$status" -eq 0 ]
  assert_no_forbidden_log_commands
}
