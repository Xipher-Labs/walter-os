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

@test "overlay help documents configured opener behavior" {
  run bash "${OVERLAY_SCRIPT}" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"configured overlay opener"* ]]
  [[ "$output" == *"WALTER_OVERLAY_EDITOR"* ]]
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

@test "overlay invokes injected opener command with arguments" {
  local tmp_home opener_log opener
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"
  opener="${tmp_home}/opener"

  cat > "$opener" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "$opener"

  run env \
    HOME="$tmp_home" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_OPEN_CMD="$opener --flag" \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "--flag ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home"
}

@test "overlay command arguments do not expand globs" {
  local tmp_home opener_log opener
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"
  opener="${tmp_home}/opener"

  cat > "$opener" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "$opener"

  run env \
    HOME="$tmp_home" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_OPEN_CMD="$opener --pattern=*" \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "--pattern=* ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home"
}

@test "overlay uses explicit editor preference" {
  local tmp_home opener_log opener
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"
  opener="${tmp_home}/opener"

  cat > "$opener" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "$opener"

  run env \
    HOME="$tmp_home" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_EDITOR="$opener --project" \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "--project ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home"
}

@test "overlay system opener uses macOS open on Darwin" {
  local tmp_home tmp_bin opener_log
  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"

  cat > "${tmp_bin}/uname" <<'SH'
#!/usr/bin/env bash
printf 'Darwin\n'
SH
  cat > "${tmp_bin}/open" <<'SH'
#!/usr/bin/env bash
printf 'open %s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "${tmp_bin}/uname" "${tmp_bin}/open"

  run env \
    HOME="$tmp_home" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_EDITOR=system \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "open ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home" "$tmp_bin"
}

@test "overlay system opener uses xdg-open on Linux" {
  local tmp_home tmp_bin opener_log
  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"

  cat > "${tmp_bin}/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
  cat > "${tmp_bin}/xdg-open" <<'SH'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "${tmp_bin}/uname" "${tmp_bin}/xdg-open"

  run env \
    HOME="$tmp_home" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_EDITOR=system \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "xdg-open ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home" "$tmp_bin"
}

@test "overlay system opener prefers explorer.exe on WSL" {
  local tmp_home tmp_bin opener_log
  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"

  cat > "${tmp_bin}/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
  cat > "${tmp_bin}/wslpath" <<'SH'
#!/usr/bin/env bash
printf 'C:\\Users\\operator\\overlay\n'
SH
  cat > "${tmp_bin}/explorer.exe" <<'SH'
#!/usr/bin/env bash
printf 'explorer.exe %s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
SH
  cat > "${tmp_bin}/xdg-open" <<'SH'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
exit 99
SH
  chmod +x "${tmp_bin}/uname" "${tmp_bin}/wslpath" "${tmp_bin}/explorer.exe" "${tmp_bin}/xdg-open"

  run env \
    HOME="$tmp_home" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_OVERLAY_EDITOR=system \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    WSL_DISTRO_NAME=Ubuntu \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "explorer.exe C:\\Users\\operator\\overlay" ]

  rm -rf "$tmp_home" "$tmp_bin"
}

@test "overlay falls back to VISUAL when Linux system opener fails" {
  local tmp_home tmp_bin opener_log
  tmp_home="$(mktemp -d)"
  tmp_bin="$(mktemp -d)"
  mkdir -p "${tmp_home}/.config/walter-os/overlay"
  opener_log="${tmp_home}/opener.log"

  cat > "${tmp_bin}/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
  cat > "${tmp_bin}/xdg-open" <<'SH'
#!/usr/bin/env bash
exit 3
SH
  cat > "${tmp_bin}/visual-opener" <<'SH'
#!/usr/bin/env bash
printf 'visual %s\n' "$1" > "$WALTER_TEST_OPENER_LOG"
SH
  chmod +x "${tmp_bin}/uname" "${tmp_bin}/xdg-open" "${tmp_bin}/visual-opener"

  run env \
    HOME="$tmp_home" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    WALTER_OS_HOME="${REPO_ROOT}" \
    WALTER_TEST_OPENER_LOG="$opener_log" \
    VISUAL=visual-opener \
    "${WALTER_OS_BIN}" overlay

  [ "$status" -eq 0 ]
  [ "$(cat "$opener_log")" = "visual ${tmp_home}/.config/walter-os/overlay" ]

  rm -rf "$tmp_home" "$tmp_bin"
}

@test "overlay --print handles missing HOME with clear error" {
  run env -u HOME -u WALTER_OVERLAY_DIR bash "${OVERLAY_SCRIPT}" --print

  [ "$status" -eq 2 ]
  [[ "$output" == *"HOME is required"* ]]
}

@test "walter dispatch exposes overlay command" {
  run env HOME="/tmp/walter-test-home" WALTER_OS_HOME="${REPO_ROOT}" "${WALTER_BIN}" overlay --print

  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/walter-test-home/.config/walter-os/overlay" ]
}
