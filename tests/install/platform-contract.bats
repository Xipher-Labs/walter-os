#!/usr/bin/env bats
# tests/install/platform-contract.bats
#
# Issue #214: macOS + Ubuntu install support must be an explicit,
# testable contract without requiring real package installation.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALL_SH="${REPO_ROOT}/install.sh"
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
}

_stub_tool() {
  local name="$1"
  local body="${2:-printf '%s\n' \"$name stub\"}"
  cat > "$TMPBIN/$name" <<STUB
#!/usr/bin/env bash
${body}
STUB
  chmod +x "$TMPBIN/$name"
}

_stub_required_tools() {
  _stub_tool git
  _stub_tool curl
  _stub_tool jq
  _stub_tool docker 'if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then printf "%s\n" "Docker Compose version v2.27.0"; exit 0; fi; printf "%s\n" "Docker version 27.0.0"'
}

@test "--check macOS branch reports Homebrew and Docker Desktop guidance" {
  _stub_tool git
  _stub_tool curl
  _stub_tool jq

  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Darwin \
    WALTER_INSTALL_TEST_ARCH_OVERRIDE=arm64 \
    bash "$INSTALL_SH" --check

  [[ "$output" == *"OS: macOS (arm64)"* ]]
  [[ "$output" == *"brew install yq"* ]]
  [[ "$output" == *"brew install gitleaks"* ]]
  [[ "$output" == *"Docker Desktop or OrbStack"* ]]
}

@test "--check Ubuntu branch reports apt/snap/manual guidance" {
  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Linux \
    WALTER_INSTALL_TEST_LINUX_ID_OVERRIDE=ubuntu \
    bash "$INSTALL_SH" --check

  [[ "$output" == *"OS: Linux (Ubuntu/Debian compatible)"* ]]
  [[ "$output" == *"sudo snap install yq"* ]]
  [[ "$output" == *"Docker Engine + Compose plugin"* ]]
  [[ "$output" == *"sudo apt-get install -y bats shellcheck ripgrep"* ]]
  [[ "$output" == *"mise install node@22 pnpm@9 uv@latest"* ]]
  [[ "$output" == *"Infisical CLI docs"* ]]
}

@test "--check rejects Debian/Ubuntu kislyuk yq with remediation" {
  _stub_required_tools
  _stub_tool yq 'printf "%s\n" "yq 3.4.3"'

  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Linux \
    WALTER_INSTALL_TEST_LINUX_ID_OVERRIDE=ubuntu \
    bash "$INSTALL_SH" --check

  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT mikefarah/yq"* ]]
  [[ "$output" == *"sudo apt-get remove -y yq"* ]]
  [[ "$output" == *"sudo snap install yq"* ]]
}

@test "--check Linux secrets guidance includes headless fallback caveat" {
  _stub_required_tools
  _stub_tool yq 'printf "%s\n" "yq (https://github.com/mikefarah/yq/) version v4.44.3"'

  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Linux \
    WALTER_INSTALL_TEST_LINUX_ID_OVERRIDE=ubuntu \
    bash "$INSTALL_SH" --check

  [ "$status" -eq 0 ]
  [[ "$output" == *"No Linux credential store found"* ]]
  [[ "$output" == *"Headless Ubuntu"* ]]
  [[ "$output" == *"pass + GPG"* ]]
}

@test "--dry-run can exercise macOS Step 1 without brew or package installs" {
  _stub_tool docker 'printf "%s\n" "Docker version 27.0.0"'

  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Darwin \
    WALTER_INSTALL_TEST_ARCH_OVERRIDE=arm64 \
    bash "$INSTALL_SH" --step 1 --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"macOS detected (arm64)"* ]]
  [[ "$output" == *"would require: brew"* ]]
  [[ "$output" == *"brew install"* ]] || [[ "$output" == *"already installed"* ]]
}

@test "--dry-run can exercise Ubuntu Step 1 without apt or package installs" {
  _stub_tool docker 'printf "%s\n" "Docker version 27.0.0"'

  run env \
    PATH="$TMPBIN:/usr/bin:/bin" \
    WALTER_INSTALL_TEST_OS_OVERRIDE=Linux \
    WALTER_INSTALL_TEST_LINUX_ID_OVERRIDE=ubuntu \
    bash "$INSTALL_SH" --step 1 --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Linux detected"* ]]
  [[ "$output" == *"would require: apt-get"* ]] || [[ "$output" == *"apt-get install"* ]]
  [[ "$output" == *"would run: sudo snap install yq"* ]]
}
