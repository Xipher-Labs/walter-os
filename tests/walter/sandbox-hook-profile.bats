#!/usr/bin/env bats
# tests/walter/sandbox-hook-profile.bats
#
# OSS Trust A-3 process isolation sandbox — AC-2 hook profile coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SANDBOX_LIB="$REPO_ROOT/scripts/walter/lib/sandbox.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-sandbox-hook.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_RUNTIME_DIR="$TMP_HOME/runtime"
  mkdir -p "$HOME" "$WALTER_CONFIG" "$WALTER_RUNTIME_DIR"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-sandbox-hook.*) rm -rf "$TMP_HOME" ;;
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
}

_mode() {
  if stat -f %Lp "$1" >/dev/null 2>&1; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
}

@test "AC-2: nsjail hook profile declares resource limits and no-network posture" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.nsjail.conf"

  grep -q 'rlimit_as: 512' "$profile"
  grep -q 'rlimit_cpu: 30' "$profile"
  grep -q 'rlimit_fsize: 100' "$profile"
  grep -q 'rlimit_nofile: 64' "$profile"
  grep -q 'clone_newnet: true' "$profile"
  grep -q 'clone_newpid: true' "$profile"
  grep -q 'keep_caps: false' "$profile"
  grep -q 'dst: "/"' "$profile"
  grep -q 'fstype: "tmpfs"' "$profile"
  grep -q 'iface_no_lo: true' "$profile"
  run grep -q 'cap: ""' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-2: nsjail hook profile mounts Walter roots read-only" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.nsjail.conf"

  grep -q 'src: "@WALTER_OS_HOME@"' "$profile"
  grep -q 'dst: "@WALTER_OS_HOME@"' "$profile"
  grep -q 'src: "@WALTER_CONFIG@"' "$profile"
  grep -q 'dst: "@WALTER_CONFIG@"' "$profile"
  grep -q 'rw: false' "$profile"
}

@test "AC-2: macOS hook profile blocks network, writes, and sensitive reads" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.sb"

  grep -q '(deny network\*)' "$profile"
  grep -q '(deny file-write\* (subpath "@HOME@"))' "$profile"
  grep -q '(deny file-write\* (subpath "@WALTER_OS_HOME@"))' "$profile"
  grep -q '(deny file-write\* (subpath "@WALTER_CONFIG@"))' "$profile"
  grep -q '@HOME@/.ssh' "$profile"
  grep -q '@HOME@/.gnupg' "$profile"
  grep -q '@HOME@/.aws' "$profile"
}

@test "AC-2: firejail hook profile blocks network and sensitive homes" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.firejail.profile"

  grep -q '^net none$' "$profile"
  grep -q '^private-tmp$' "$profile"
  grep -q '^read-only /$' "$profile"
  grep -q '^whitelist-ro @WALTER_OS_HOME@$' "$profile"
  grep -q '^whitelist-ro @WALTER_CONFIG@$' "$profile"
  grep -q '^read-only @WALTER_OS_HOME@$' "$profile"
  grep -q '^read-only @WALTER_CONFIG@$' "$profile"
  grep -q '^blacklist @HOME@/.ssh$' "$profile"
  grep -q '^blacklist @HOME@/\*/\*.pem$' "$profile"
  grep -q '^blacklist @HOME@/\*/\*/\*.key$' "$profile"
}

@test "AC-2: sandbox materializes hook profile placeholders safely" {
  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default nsjail"

  [ "$status" -eq 0 ]
  first_profile="$output"
  [[ "$first_profile" == "$WALTER_RUNTIME_DIR"/sandbox/walter-hook-default.nsjail.* ]]
  grep -q "src: \"$WALTER_OS_HOME\"" "$first_profile"
  grep -q "src: \"$WALTER_CONFIG\"" "$first_profile"

  run grep -q '@WALTER_OS_HOME@' "$first_profile"
  [ "$status" -ne 0 ]
  run grep -q '@WALTER_CONFIG@' "$first_profile"
  [ "$status" -ne 0 ]

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default nsjail"
  [ "$status" -eq 0 ]
  [ "$output" != "$first_profile" ]
}

@test "AC-2: repo root helper does not change caller cwd" {
  mkdir -p "$TMP_HOME/outside"

  run bash -c "source '$SANDBOX_LIB'; unset WALTER_OS_HOME; cd '$TMP_HOME/outside'; before=\"\$PWD\"; walter_sandbox_repo_root >/dev/null; [[ \"\$PWD\" = \"\$before\" ]]"

  [ "$status" -eq 0 ]
}

@test "AC-2: runtime dir materialization preserves caller-provided root mode" {
  chmod 755 "$WALTER_RUNTIME_DIR"

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default nsjail"

  [ "$status" -eq 0 ]
  [ "$(_mode "$WALTER_RUNTIME_DIR")" = "755" ]
  [ "$(_mode "$WALTER_RUNTIME_DIR/sandbox")" = "700" ]
}

@test "AC-2: runtime dir rejects symlink roots" {
  target="$TMP_HOME/runtime-target"
  link="$TMP_HOME/runtime-link"
  mkdir -p "$target"
  ln -s "$target" "$link"

  run bash -c "source '$SANDBOX_LIB'; WALTER_RUNTIME_DIR='$link' walter_sandbox_runtime_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe runtime path"* ]]
}

@test "AC-2: sandbox-exec hook profile enforces read/write/network boundaries when available" {
  command -v sandbox-exec >/dev/null || skip "sandbox-exec not installed"
  sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "sandbox-exec cannot apply profiles in this environment"
  mkdir -p "$HOME/.ssh"
  printf 'secret\n' > "$HOME/.ssh/id_rsa"

  profile="$(bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default sandbox-exec")"

  run sandbox-exec -f "$profile" /bin/cat "$WALTER_OS_HOME/README.md"
  [ "$status" -eq 0 ]

  run sandbox-exec -f "$profile" /bin/sh -c "printf x > '$WALTER_OS_HOME/.sandbox-write-test'"
  [ "$status" -ne 0 ]
  [ ! -e "$WALTER_OS_HOME/.sandbox-write-test" ]

  run sandbox-exec -f "$profile" /bin/sh -c 'tmp="$(mktemp)"; printf ok > "$tmp"; cat "$tmp"; : >/dev/null'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run sandbox-exec -f "$profile" /bin/cat "$HOME/.ssh/id_rsa"
  [ "$status" -ne 0 ]

  if command -v curl >/dev/null; then
    run sandbox-exec -f "$profile" curl --connect-timeout 2 https://example.com
    [ "$status" -ne 0 ]
  fi
}
