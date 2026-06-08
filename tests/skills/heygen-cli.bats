#!/usr/bin/env bats
# tests/skills/heygen-cli.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HEYGEN_SH="$REPO_ROOT/skills/heygen-cli/heygen.sh"

setup() {
  TMP_DIR="$(mktemp -d)"
  MOCK_BIN="$TMP_DIR/bin"
  CURL_ARGS="$TMP_DIR/curl-args.txt"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${HEYGEN_TEST_CURL_ARGS:?}"
if [[ "${HEYGEN_TEST_CURL_FAIL:-0}" == "1" ]]; then
  echo "curl: simulated network failure" >&2
  exit 7
fi
printf '{"ok":true}\n200'
CURL
  chmod +x "$MOCK_BIN/curl"
}

teardown() {
  if [[ -n "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

run_heygen() {
  env PATH="$MOCK_BIN:$PATH" \
    HEYGEN_API_KEY="test-key" \
    HEYGEN_TEST_CURL_ARGS="$CURL_ARGS" \
    "$@"
}

@test "_heygen_request sends literal JSON bodies with --data-raw" {
  run run_heygen bash -c "source '$HEYGEN_SH'; _heygen_request POST /v2/test '@/tmp/secret.json'"

  [ "$status" -eq 0 ]
  grep -qx -- '--data-raw' "$CURL_ARGS"
  grep -qx -- '@/tmp/secret.json' "$CURL_ARGS"
  if grep -qx -- '-d' "$CURL_ARGS"; then
    return 1
  fi
}

@test "_heygen_request reports curl transport failures distinctly" {
  run env PATH="$MOCK_BIN:$PATH" \
    HEYGEN_API_KEY="test-key" \
    HEYGEN_TEST_CURL_ARGS="$CURL_ARGS" \
    HEYGEN_TEST_CURL_FAIL=1 \
    bash -c "source '$HEYGEN_SH'; _heygen_request GET /v2/avatars"

  [ "$status" -eq 6 ]
  [[ "$output" == *"transport error"* ]]
}

@test "heygen_get_video_status URL-encodes video_id" {
  run run_heygen bash -c "source '$HEYGEN_SH'; heygen_get_video_status 'video id/with?chars'"

  [ "$status" -eq 0 ]
  grep -q '/v1/video_status.get?video_id=video%20id%2Fwith%3Fchars$' "$CURL_ARGS"
}

@test "heygen_generate_from_template URL-encodes template id" {
  run run_heygen bash -c "source '$HEYGEN_SH'; heygen_generate_from_template 'template/id with spaces' --variables '{\"name\":\"Walter\"}'"

  [ "$status" -eq 0 ]
  grep -q '/v2/template/template%2Fid%20with%20spaces/generate$' "$CURL_ARGS"
}

@test "heygen_generate_from_template rejects invalid variables JSON before curl" {
  run run_heygen bash -c "source '$HEYGEN_SH'; heygen_generate_from_template template-1 --variables '@/tmp/secret.json'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"--variables must be a JSON object"* ]]
  [ ! -f "$CURL_ARGS" ]
}
