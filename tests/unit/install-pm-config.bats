#!/usr/bin/env bats
# Tests for write_pm_release_age() in install.sh [AC-3, AC-10]

INSTALL_SH="${BATS_TEST_DIRNAME}/../../install.sh"
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
  # Override HOME so ~/.bunfig.toml and ~/.config/pnpm/rc go to temp
  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
  # Override WALTER_CONFIG to temp dir (no env file)
  FAKE_WALTER_CONFIG="$(mktemp -d)"
  export FAKE_WALTER_CONFIG
  mkdir -p "$FAKE_HOME/.config/pnpm"
  # Create a minimal repo dir with a walter-os.toml
  REPO_DIR="$(mktemp -d)"
  export REPO_DIR
}

teardown() {
  rm -rf "$TMPDIR" "$FAKE_HOME" "$FAKE_WALTER_CONFIG" "$REPO_DIR"
}

_run_pm_config() {
  local level="${1:-staging}"
  cat > "$REPO_DIR/walter-os.toml" <<EOF
[walter]
protection = "${level}"
EOF
  # Source the install.sh functions in a subshell with overridden HOME
  bash -c "
    export HOME=\"$FAKE_HOME\"
    export WALTER_CONFIG=\"$FAKE_WALTER_CONFIG\"
    export REPO_ROOT=\"$REPO_ROOT\"
    export DRY_RUN=0
    export UPGRADE=0
    export UNINSTALL=0

    # Source helpers from install.sh
    source <(grep -A50 'say()' \"$INSTALL_SH\" | head -60 || true)

    # Source the write_pm_release_age function directly
    source <(awk '/^write_pm_release_age\(\)/,/^}$/ {print}' \"$INSTALL_SH\" 2>/dev/null)

    # Run the function if it exists, else exit 1
    if declare -f write_pm_release_age > /dev/null 2>&1; then
      write_pm_release_age \"$REPO_DIR\"
    else
      echo 'write_pm_release_age not found' >&2
      exit 1
    fi
  "
}

_invoke_write_pm() {
  # Create a minimal harness script that defines the required helpers
  # and then sources install.sh's write_pm_release_age function.
  local harness; harness="$(mktemp /tmp/pm-harness-XXXXXX.sh)"
  cat > "$harness" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

# Stubs for install.sh helpers
c_reset=''; c_dim=''; c_b=''; c_green=''; c_yellow=''; c_red=''; c_blue=''
say()  { :; }
ok()   { :; }
warn() { printf 'WARN: %s\n' "\$*" >&2; }
err()  { printf 'ERR: %s\n' "\$*" >&2; }
step() { :; }
dry()  { :; }
DRY_RUN=0
UPGRADE=0
REPO_ROOT="${REPO_ROOT}"
run() { if [[ \$DRY_RUN -eq 1 ]]; then dry "\$*"; else eval "\$@"; fi; }
run_args() { if [[ \$DRY_RUN -eq 1 ]]; then dry "\$*"; else "\$@"; fi; }

HARNESS

  # Extract the write_pm_release_age function body using python
  python3 - "$INSTALL_SH" >> "$harness" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    text = f.read()

# Find the function
m = re.search(r'\nwrite_pm_release_age\(\) \{(.+?)\n\}', text, re.DOTALL)
if not m:
    print("echo 'write_pm_release_age not found' >&2; exit 127")
    sys.exit(0)

print(f"\nwrite_pm_release_age() {{{m.group(1)}\n}}")
PYEOF

  echo "write_pm_release_age \"$REPO_DIR\"" >> "$harness"
  chmod +x "$harness"

  HOME="$FAKE_HOME" WALTER_CONFIG="$FAKE_WALTER_CONFIG" REPO_ROOT="$REPO_ROOT" \
    bash "$harness"
  local ret=$?
  rm -f "$harness"
  return $ret
}

@test "fresh install writes correct seconds to ~/.bunfig.toml for staging (14d)" {
  cat > "$REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "staging"
EOF
  run _invoke_write_pm
  # Must not exit 127 (function missing)
  [ "$status" -ne 127 ]
  # 14 days * 86400 = 1209600 seconds
  [ -f "$FAKE_HOME/.bunfig.toml" ]
  grep -q "1209600" "$FAKE_HOME/.bunfig.toml"
}

@test "fresh install writes correct minutes to ~/.config/pnpm/rc for staging (14d)" {
  cat > "$REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "staging"
EOF
  run _invoke_write_pm
  [ "$status" -ne 127 ]
  # 14 days * 1440 = 20160 minutes
  [ -f "$FAKE_HOME/.config/pnpm/rc" ]
  grep -q "20160" "$FAKE_HOME/.config/pnpm/rc"
}

@test "experimental level sets 0 in bunfig.toml" {
  cat > "$REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "experimental"
EOF
  run _invoke_write_pm
  [ "$status" -ne 127 ]
  # experimental = 0 days = 0 seconds
  [ -f "$FAKE_HOME/.bunfig.toml" ]
  grep -q 'minimumReleaseAge.*=.*"0s"' "$FAKE_HOME/.bunfig.toml"
}

@test "idempotent re-run does not duplicate key in bunfig.toml" {
  cat > "$REPO_DIR/walter-os.toml" <<'EOF'
[walter]
protection = "production"
EOF
  _invoke_write_pm 2>/dev/null || true
  _invoke_write_pm 2>/dev/null || true
  run _invoke_write_pm
  [ "$status" -ne 127 ]
  # Key should appear exactly once
  local count; count="$(grep -c "minimumReleaseAge" "$FAKE_HOME/.bunfig.toml" 2>/dev/null || echo 0)"
  [ "$count" -eq 1 ]
}
