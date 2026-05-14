#!/usr/bin/env bats
# tests/cli/overlay.bats
#
# Covers: `walter-os overlay` and `walter overlay`.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WALTER_OS_BIN="${REPO_ROOT}/bin/walter-os"
WALTER_BIN="${REPO_ROOT}/bin/walter"
OVERLAY_SCRIPT="${REPO_ROOT}/scripts/walter/subcommands/overlay.sh"

export WALTER_OS_HOME="${REPO_ROOT}"

@test "overlay --print prints the overlay path" {
  run env HOME="/tmp/walter-test-home" WALTER_OS_HOME="${REPO_ROOT}" "${WALTER_OS_BIN}" overlay --print

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/walter-test-home/.config/walter-os/overlay" ]
}

@test "overlay help documents VS Code behavior" {
  run bash "${OVERLAY_SCRIPT}" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Visual Studio Code"* ]]
  [[ "$output" == *"--print"* ]]
}

@test "overlay invokes injected opener with overlay path" {
  local tmp_home opener_log opener
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"
  opener="${tmp_home}/opener"

  cat > "$opener" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "$opener"

  run env \
    HOME="$tmp_home" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_OPEN_CMD="$opener" \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home"
}

@test "walter dispatch exposes overlay command" {
  run env HOME="/tmp/walter-test-home" WALTER_OS_HOME="${REPO_ROOT}" "${WALTER_BIN}" overlay --print

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/walter-test-home/.config/walter-os/overlay" ]
}
