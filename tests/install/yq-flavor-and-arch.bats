#!/usr/bin/env bats
# tests/install/yq-flavor-and-arch.bats
#
# Closes #120 + Copilot R2/R3 #125. install.sh's Linux yq-install path
# distinguishes mikefarah/yq (Go-based, required) from apt's kislyuk/yq
# (Python-based, wrong syntax). Verifies the helper + arch detection
# code is present and behaves on the strings we expect.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_SH="${REPO_ROOT}/install.sh"
  [[ -f "$INSTALL_SH" ]] || skip "install.sh missing"
}

# -----------------------------------------------------------------------
# Flavor detection helper
# -----------------------------------------------------------------------
@test "install.sh defines _yq_is_mikefarah() helper" {
  grep -qE '^[[:space:]]+_yq_is_mikefarah\(\)' "$INSTALL_SH"
}

@test "_yq_is_mikefarah greps for 'mikefarah' in 'yq --version' output" {
  grep -qE "yq --version.*grep.*mikefarah" "$INSTALL_SH"
}

# -----------------------------------------------------------------------
# Pre-installed flavor check
# -----------------------------------------------------------------------
@test "pre-installed wrong-flavor yq fails fast with remediation" {
  # The check block runs `_yq_is_mikefarah` when a yq is already on PATH.
  grep -qE '_yq_is_mikefarah' "$INSTALL_SH"
  # Remediation strings the operator sees on mismatch:
  grep -qE 'sudo apt-get remove -y yq' "$INSTALL_SH"
  grep -qE 'sudo snap install yq' "$INSTALL_SH"
  grep -qE 'github\.com/mikefarah/yq' "$INSTALL_SH"
}

# -----------------------------------------------------------------------
# Arch detection in the snap-missing fallback (Copilot R3 #125)
# -----------------------------------------------------------------------
@test "snap-missing fallback no longer hardcodes amd64 — arch detection present" {
  # _yq_arch case statement must cover at least amd64 + arm64.
  grep -qE 'case "\$\(uname -m\)" in' "$INSTALL_SH"
  grep -qE 'aarch64\|arm64.*arm64' "$INSTALL_SH"
  grep -qE 'x86_64\|amd64.*amd64' "$INSTALL_SH"
}

@test "snap-missing fallback uses \${_yq_arch} in the download URL" {
  grep -qE 'yq_linux_\$\{_yq_arch\}' "$INSTALL_SH"
}

# -----------------------------------------------------------------------
# Post-install verification (Copilot R3 #125 L2)
# -----------------------------------------------------------------------
@test "post-snap-install path runs hash -r and command -v yq" {
  # `hash -r` refreshes bash's command cache so snap's /snap/bin/yq
  # is picked up without re-sourcing the shell.
  grep -qE 'hash -r' "$INSTALL_SH"
  # And the install path actually verifies yq is on PATH after install.
  grep -qE 'yq install succeeded but .yq. is not on PATH' "$INSTALL_SH"
}

@test "post-snap-install path runs the flavor check" {
  # After install we re-run _yq_is_mikefarah so a wrong-flavor binary
  # shadowing snap's yq is caught immediately.
  grep -qE 'if ! _yq_is_mikefarah; then' "$INSTALL_SH"
}

# -----------------------------------------------------------------------
# Confirm yq is in required_deps (not optional)
# -----------------------------------------------------------------------
@test "yq is in required_deps on both macOS and Linux install branches" {
  # The two `local required_deps=(...)` declarations (one per OS branch)
  # must both list yq. macOS includes docker inline; Linux installs
  # docker via a separate path — assert only on `yq` being present.
  [[ $(grep -cE 'local required_deps=\([^)]*\byq\b' "$INSTALL_SH") -ge 2 ]]
}
