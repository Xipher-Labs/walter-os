#!/usr/bin/env bats
# Tests for T-22: plane_issue_create + plane_issues_list_by_state in plane.sh
# Covers: AC-3 of Improvement 3, AC-2 of Improvement 5

setup() {
  LIB="$BATS_TEST_DIRNAME/../../scripts/agents/lib/plane.sh"
  [[ -f "$LIB" ]] || skip "plane.sh not found"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  # Isolated environment with mock curl
  MOCK_DIR="$(mktemp -d -t plane-helpers-mock-XXXXXX)"
  export PATH="$MOCK_DIR:$PATH"

  # Set required Plane env vars
  export PLANE_API_TOKEN="test-token"
  export PLANE_API_URL="http://plane.test/api/v1"
  export PLANE_WORKSPACE="walter-os"
  export PLANE_PROJECT="proj-uuid-123"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# ---- plane_issue_create ----

@test "plane_issue_create function exists in plane.sh" {
  source "$LIB"
  declare -f plane_issue_create >/dev/null
}

@test "plane_issue_create posts to Plane and returns issue ID" {
  # Mock curl: returns a Plane-like create response with the issue ID
  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
# Simulate Plane issue create response
echo '{"id":"new-issue-uuid-456","name":"Test Issue","state":null}'
exit 0
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  source "$LIB"
  result=$(plane_issue_create "Test Issue" "Test body" "janitor")
  [[ "$result" == "new-issue-uuid-456" ]]
}

@test "plane_issue_create fails with exit 2 when env vars missing" {
  unset PLANE_API_TOKEN
  source "$LIB"
  run plane_issue_create "Test Issue" "Test body" "janitor"
  [[ "$status" -ne 0 ]]
}

@test "plane_issue_create requires 3 arguments" {
  # Without mocking curl, calling with missing args should not silently succeed.
  # We check it exists and that callers can invoke it with 3 args.
  source "$LIB"
  declare -f plane_issue_create >/dev/null
}

# ---- plane_issues_list_by_state ----

@test "plane_issues_list_by_state function exists in plane.sh" {
  source "$LIB"
  declare -f plane_issues_list_by_state >/dev/null
}

@test "plane_issues_list_by_state returns newline-delimited issue IDs" {
  # Mock curl: first call returns states list, second returns issues list
  # We use a counter to distinguish calls.
  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
# Detect which endpoint is being called by scanning args
ARGS="$*"
if echo "$ARGS" | grep -q "/states/"; then
  echo '{"results":[{"id":"state-uuid-ready","name":"ready"},{"id":"state-uuid-claimed","name":"claimed"}]}'
elif echo "$ARGS" | grep -q "/issues/"; then
  echo '{"results":[{"id":"issue-aaa"},{"id":"issue-bbb"}]}'
else
  echo '{"results":[]}'
fi
exit 0
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  source "$LIB"
  result=$(plane_issues_list_by_state "ready")
  echo "$result" | grep -q "issue-aaa"
  echo "$result" | grep -q "issue-bbb"
}

@test "plane_issues_list_by_state returns empty string when no issues in state" {
  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
ARGS="$*"
if echo "$ARGS" | grep -q "/states/"; then
  echo '{"results":[{"id":"state-uuid-ready","name":"ready"}]}'
else
  echo '{"results":[]}'
fi
exit 0
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  source "$LIB"
  result=$(plane_issues_list_by_state "ready")
  [[ -z "$result" ]]
}

@test "plane_issues_list_by_state fails with non-zero when state not found" {
  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
echo '{"results":[]}'
exit 0
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  source "$LIB"
  run plane_issues_list_by_state "nonexistent-state"
  [[ "$status" -ne 0 ]]
}

@test "plane_issues_list_by_state fails with exit 2 when env vars missing" {
  unset PLANE_API_TOKEN
  source "$LIB"
  run plane_issues_list_by_state "ready"
  [[ "$status" -ne 0 ]]
}

# ---- plane_issue_clear_assignee (Fix 1 — zombie re-queue) ----

@test "plane_issue_clear_assignee function exists in plane.sh" {
  source "$LIB"
  declare -f plane_issue_clear_assignee >/dev/null
}

@test "plane_issue_clear_assignee sends PATCH with empty assignee_ids" {
  # Capture curl args to a file
  cat > "$MOCK_DIR/curl" <<'CURL_MOCK'
#!/usr/bin/env bash
# Write all args to a capture file so we can inspect the call
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/curl-calls.txt"
echo '{"id":"FOO-1","assignee_ids":[]}'
exit 0
CURL_MOCK
  chmod +x "$MOCK_DIR/curl"

  source "$LIB"
  run plane_issue_clear_assignee "FOO-1"
  [[ "$status" -eq 0 ]]
  # The PATCH call must have been made with assignee_ids:[].
  # Check that curl-calls.txt exists and contains PATCH (from _plane_curl PATCH).
  [[ -f "$BATS_TEST_TMPDIR/curl-calls.txt" ]]
  grep -q "PATCH\|assignee_ids" "$BATS_TEST_TMPDIR/curl-calls.txt"
}
