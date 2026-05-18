#!/usr/bin/env bats
# tests/walter/syncthing-bootstrap-delegation.bats
# Covers: AC-3, AC-4, AC-5, AC-6, AC-7
# Tests the 3-tier discovery in cmd_syncthing_bootstrap:
#   1. WALTER_OPERATOR_SCRIPTS_DIR  (highest precedence) — exercised
#   2. HOME/.config/walter-os/overlay/scripts/  (overlay) — exercised
#   3. HOME/config-personal/scripts/  (lowest) — exercised below

WALTER_OS_BIN="$BATS_TEST_DIRNAME/../../bin/walter-os"

setup() {
  # Point WALTER_OS_HOME to the repo under test so the binary can resolve itself.
  WALTER_OS_HOME="$BATS_TEST_DIRNAME/../.."
  export WALTER_OS_HOME

  # Each test gets an isolated temp HOME to avoid cross-contamination.
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME

  # Unset the env-var discovery path by default; individual tests set it.
  unset WALTER_OPERATOR_SCRIPTS_DIR
}

teardown() {
  [[ -n "${TEST_HOME:-}" && -d "${TEST_HOME}" ]] && rm -rf "$TEST_HOME"
}

# Helper: create an executable stub script that prints a sentinel and its args.
_make_stub() {
  local dir="$1"
  local name="${2:-syncthing-bootstrap.sh}"
  mkdir -p "$dir"
  cat > "$dir/$name" <<'EOF'
#!/usr/bin/env bash
echo "STUB_EXECD $*"
exit 0
EOF
  chmod +x "$dir/$name"
}

# --- AC-3: --help exits 0 and shows discovery order ---

@test "syncthing-bootstrap --help exits 0" {
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap --help
  [ "$status" -eq 0 ]
}

@test "syncthing-bootstrap --help output mentions WALTER_OPERATOR_SCRIPTS_DIR" {
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "WALTER_OPERATOR_SCRIPTS_DIR"
}

@test "syncthing-bootstrap --help output mentions skills/syncthing-cli/SKILL.md" {
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "syncthing-cli"
}

# --- AC-4: no script at any location → exits 2 with actionable message ---

@test "syncthing-bootstrap with no script exits 2" {
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap
  [ "$status" -eq 2 ]
}

@test "syncthing-bootstrap with no script prints 'no operator script' message" {
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "no operator script"
}

# --- AC-5: WALTER_OPERATOR_SCRIPTS_DIR wins (env var tier) ---

@test "syncthing-bootstrap execs script from WALTER_OPERATOR_SCRIPTS_DIR" {
  local env_dir
  env_dir="$(mktemp -d)"
  _make_stub "$env_dir"
  HOME="$TEST_HOME" WALTER_OPERATOR_SCRIPTS_DIR="$env_dir" \
    run "$WALTER_OS_BIN" syncthing-bootstrap
  rm -rf "$env_dir"
  echo "$output" | grep -q "STUB_EXECD"
}

@test "WALTER_OPERATOR_SCRIPTS_DIR wins over overlay when both exist" {
  local env_dir overlay_dir
  env_dir="$(mktemp -d)"
  overlay_dir="${TEST_HOME}/.config/walter-os/overlay/scripts"
  _make_stub "$env_dir"
  _make_stub "$overlay_dir"
  # Make overlay stub print different sentinel so we can tell them apart.
  cat > "$overlay_dir/syncthing-bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
echo "OVERLAY_EXECD"
exit 0
EOF
  chmod +x "$overlay_dir/syncthing-bootstrap.sh"
  HOME="$TEST_HOME" WALTER_OPERATOR_SCRIPTS_DIR="$env_dir" \
    run "$WALTER_OS_BIN" syncthing-bootstrap
  rm -rf "$env_dir"
  echo "$output" | grep -q "STUB_EXECD"
  ! (echo "$output" | grep -q "OVERLAY_EXECD")
}

# --- AC-6: overlay path exec'd when env var is not set ---

@test "syncthing-bootstrap execs overlay script when no env var set" {
  local overlay_dir
  overlay_dir="${TEST_HOME}/.config/walter-os/overlay/scripts"
  _make_stub "$overlay_dir"
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap
  echo "$output" | grep -q "STUB_EXECD"
}

# --- Tier-3 fallback: config-personal/scripts/ exec'd when env var unset
# and overlay absent. Not strictly required by AC-7, but the header comment
# claims this tier is exercised and the reviewer asked for parity. ---

@test "syncthing-bootstrap execs config-personal script as last fallback" {
  local cp_dir
  cp_dir="${TEST_HOME}/config-personal/scripts"
  _make_stub "$cp_dir"
  HOME="$TEST_HOME" run "$WALTER_OS_BIN" syncthing-bootstrap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STUB_EXECD"
}
