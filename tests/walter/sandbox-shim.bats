#!/usr/bin/env bats
# tests/walter/sandbox-shim.bats
#
# OSS Trust A-3 process isolation sandbox — AC-1 coverage.
# shellcheck disable=SC2030,SC2031

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SANDBOX_LIB="$REPO_ROOT/scripts/walter/lib/sandbox.sh"
  TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/walter-sandbox-shim.XXXXXX")"
  MOCK_BIN="$TMP_HOME/bin"
  mkdir -p "$MOCK_BIN"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

_mock_uname() {
  export WALTER_MOCK_UNAME="$1"
  cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${WALTER_MOCK_UNAME:?}"
EOF
  chmod +x "$MOCK_BIN/uname"
}

_mock_provider() {
  local name="$1"
  cat > "$MOCK_BIN/$name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "${WALTER_SANDBOX_PROVIDER_LOG:?}"
case "$(basename "$0")" in
  sandbox-exec)
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -f) shift 2 ;;
        --) shift; break ;;
        *) shift ;;
      esac
    done
    ;;
  nsjail)
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --config) shift 2 ;;
        --) shift; break ;;
        *) shift ;;
      esac
    done
    ;;
  firejail)
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --profile=*) shift ;;
        --) shift; break ;;
        *) shift ;;
      esac
    done
    ;;
esac
exec "$@"
EOF
  chmod +x "$MOCK_BIN/$name"
}

@test "AC-1: Darwin uses sandbox-exec" {
  _mock_uname Darwin

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_provider"

  [ "$status" -eq 0 ]
  [ "$output" = "sandbox-exec" ]
}

@test "AC-1: Linux uses nsjail by default" {
  _mock_uname Linux

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_provider"

  [ "$status" -eq 0 ]
  [ "$output" = "nsjail" ]
}

@test "AC-1: Linux can opt into firejail" {
  _mock_uname Linux
  export WALTER_SANDBOX_PROVIDER=firejail

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_provider"

  [ "$status" -eq 0 ]
  [ "$output" = "firejail" ]
}

@test "AC-1: unsupported OS fails closed" {
  _mock_uname FreeBSD

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_provider"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no supported sandbox provider"* ]]
}

@test "AC-1: sandbox check fails when provider binary is missing" {
  _mock_uname Linux

  run bash -c "command() { if [[ \"\$1\" == -v && \"\$2\" == nsjail ]]; then return 1; fi; builtin command \"\$@\"; }; source '$SANDBOX_LIB'; walter_sandbox_check walter-hook-default"

  [ "$status" -ne 0 ]
  [[ "$output" == *"provider missing: nsjail"* ]]
}

@test "AC-1: sandbox run executes the provider path resolved before profile lookup" {
  _mock_uname Linux
  _mock_provider nsjail
  local shadow_bin="$TMP_HOME/shadow-bin"
  mkdir -p "$shadow_bin"
  cat > "$shadow_bin/nsjail" <<'EOF'
#!/usr/bin/env bash
printf 'shadowed'
exit 42
EOF
  chmod +x "$shadow_bin/nsjail"
  export WALTER_SANDBOX_PROVIDER_LOG="$TMP_HOME/provider.log"

  run bash -c "
    source '$SANDBOX_LIB'
    walter_sandbox_check() {
      PATH='$shadow_bin':\$PATH
      hash -r
      return 0
    }
    walter_sandbox_profile_path() {
      printf '%s\n' '$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.nsjail.conf'
    }
    walter_sandbox_run walter-hook-default bash -c 'printf trusted'
  "

  [ "$status" -eq 0 ]
  [ "$output" = "trusted" ]
  grep -q '/nsjail' "$WALTER_SANDBOX_PROVIDER_LOG"
}

@test "AC-1: bundled profile lookup is stable outside repo" {
  _mock_uname Linux
  _mock_provider nsjail
  mkdir -p "$TMP_HOME/outside"

  run bash -c "unset WALTER_OS_HOME; cd '$TMP_HOME/outside'; source '$SANDBOX_LIB'; walter_sandbox_check walter-hook-default"

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "AC-1: sandbox run preserves stdout and exit code through provider" {
  _mock_uname Linux
  _mock_provider nsjail
  export WALTER_SANDBOX_PROVIDER_LOG="$TMP_HOME/provider.log"

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default bash -c 'printf ok; exit 17'"

  [ "$status" -eq 17 ]
  [ "$output" = "ok" ]
  grep -q -- '--config' "$WALTER_SANDBOX_PROVIDER_LOG"
  grep -q -- 'walter-hook-default.nsjail.conf' "$WALTER_SANDBOX_PROVIDER_LOG"
}
