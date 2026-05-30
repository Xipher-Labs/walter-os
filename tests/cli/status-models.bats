#!/usr/bin/env bats
# tests/cli/status-models.bats
#
# Covers: `walter-os status --models` effective model routing output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  mkdir -p "$WALTER_CONFIG" "$TMP_HOME/.config/walter-os/overlay"
  cat > "$TMP_HOME/.config/walter-os/overlay/personal.env" <<ENV
WALTER_OS_HOME=${REPO_ROOT}
WALTER_MODEL_BACKEND_REVIEW=codex,claude
WALTER_MODEL_FRONTEND=claude
ENV
}

teardown() {
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

@test "status --models prints effective routing" {
  run "$WALTER_OS_BIN" status --models

  [ "$status" -eq 0 ]
  [[ "$output" == *"Model routing"* ]]
  [[ "$output" == *"backend_review: codex,claude"* ]]
  [[ "$output" == *"frontend: claude"* ]]
  [[ "$output" == *"phi: local-ollama"* ]]
}
