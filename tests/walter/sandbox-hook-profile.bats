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
  grep -q 'src: "/dev/null"' "$profile"
  grep -q 'dst: "/dev/null"' "$profile"
  grep -q 'src: "/dev/urandom"' "$profile"
  grep -q 'dst: "/dev/urandom"' "$profile"
  grep -q 'iface_no_lo: true' "$profile"
  run grep -q 'cap: ""' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-2: sed replacement escaping preserves backslashes" {
  run bash -c "source '$SANDBOX_LIB'; _walter_sandbox_sed_escape 'path\\name&/x'"

  [ "$status" -eq 0 ]
  [ "$output" = 'path\\name\&\/x' ]
}

@test "AC-2: nsjail placeholder escaping preserves literal quotes and backslashes" {
  overlay_dir="$WALTER_CONFIG/overlay/sandbox-profiles"
  mkdir -p "$overlay_dir"
  printf 'mount { src: "@WALTER_OS_HOME@" dst: "@WALTER_OS_HOME@" }\n' > "$overlay_dir/quote-test.nsjail.conf"
  quoted_root="$TMP_HOME/path\"with\\chars"
  mkdir -p "$quoted_root"

  run bash -c "source '$SANDBOX_LIB'; WALTER_OS_HOME='$quoted_root' walter_sandbox_materialize_profile quote-test nsjail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq 'src: "'"$TMP_HOME"'/path\"with\\chars"' "$profile"
  grep -Fq 'dst: "'"$TMP_HOME"'/path\"with\\chars"' "$profile"
}

@test "AC-2: sandbox-exec placeholder escaping preserves literal quotes and backslashes" {
  overlay_dir="$WALTER_CONFIG/overlay/sandbox-profiles"
  mkdir -p "$overlay_dir"
  printf '(allow file-read* (subpath "@WALTER_OS_HOME@"))\n' > "$overlay_dir/quote-test.sb"
  quoted_root="$TMP_HOME/path\"with\\chars"
  mkdir -p "$quoted_root"

  run bash -c "source '$SANDBOX_LIB'; WALTER_OS_HOME='$quoted_root' walter_sandbox_materialize_profile quote-test sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq '(subpath "'"$TMP_HOME"'/path\"with\\chars")' "$profile"
}

@test "AC-2: sed replacement escaping rejects newlines" {
  run bash -c "source '$SANDBOX_LIB'; _walter_sandbox_sed_escape \$'bad\npath'"

  [ "$status" -ne 0 ]
  [[ "$output" == *"path contains newline characters"* ]]
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

  grep -q '(deny default)' "$profile"
  grep -q '(allow process\*)' "$profile"
  grep -q '(allow file-read\*)' "$profile"
  grep -q '(allow file-write\* (subpath "@WALTER_SANDBOX_SCRATCH@"))' "$profile"
  grep -q '(allow file-write\* (literal "/dev/null"))' "$profile"
  grep -q '(deny network\*)' "$profile"
  grep -q '@HOME@/.ssh' "$profile"
  grep -q '@HOME@/.gnupg' "$profile"
  grep -q '@HOME@/.aws' "$profile"
}

@test "AC-2: firejail hook profile blocks network and sensitive homes" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-hook-default.firejail.profile"

  grep -q '^net none$' "$profile"
  grep -q '^private-tmp$' "$profile"
  grep -q '^read-only /$' "$profile"
  grep -q '^whitelist @WALTER_OS_HOME@$' "$profile"
  grep -q '^whitelist @WALTER_CONFIG@$' "$profile"
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

@test "AC-2: sandbox materializes private scratch placeholders" {
  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  [[ "$profile" == "$WALTER_RUNTIME_DIR"/sandbox/walter-hook-default.sandbox-exec.* ]]
  [ -d "${profile}.scratch" ]
  [ "$(_mode "${profile}.scratch")" = "700" ]
  grep -q "$(cd "${profile}.scratch" && pwd -P)" "$profile"

  run grep -q '@WALTER_SANDBOX_SCRATCH@' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-2: sandbox materializes quoted scratch placeholders safely" {
  quoted_runtime="$TMP_HOME/runtime\"quoted"
  mkdir -p "$quoted_runtime"

  run env WALTER_RUNTIME_DIR="$quoted_runtime" bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq 'runtime\"quoted' "$profile"
}

@test "AC-2: placeholder detection handles dash-prefixed profile paths" {
  dash_profile="$TMP_HOME/-profile.sb"
  printf '(allow file-read* (subpath "@HOME@"))\n' > "$dash_profile"

  run bash -c "cd '$TMP_HOME'; source '$SANDBOX_LIB'; _walter_sandbox_profile_has_placeholders -profile.sb"

  [ "$status" -eq 0 ]
}

@test "AC-2: sandbox materialization cleans early path failures" {
  run bash -c "source '$SANDBOX_LIB'; WALTER_CONFIG=\$'bad\npath' walter_sandbox_materialize_profile walter-hook-default sandbox-exec"

  [ "$status" -ne 0 ]
  run find "$WALTER_RUNTIME_DIR/sandbox" -maxdepth 1 -name 'walter-hook-default.sandbox-exec.*' -print
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "AC-2: sandbox materialization fails closed when generated profile chmod fails" {
  run bash -c "source '$SANDBOX_LIB'; chmod() { if [[ \"\$1\" == 600 ]]; then return 1; fi; command chmod \"\$@\"; }; walter_sandbox_materialize_profile walter-hook-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to chmod generated profile"* ]]
  run find "$WALTER_RUNTIME_DIR/sandbox" -maxdepth 1 -name 'walter-hook-default.nsjail.*' -print
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
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

@test "AC-2: runtime dir rejects group-writable roots" {
  chmod 775 "$WALTER_RUNTIME_DIR"

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"runtime path is group/other-writable"* ]]
}

@test "AC-2: runtime dir fails closed when current uid cannot be read" {
  run bash -c "source '$SANDBOX_LIB'; id() { return 1; }; walter_sandbox_runtime_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to determine current uid"* ]]
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

@test "AC-2: firejail materialization escapes spaces in paths" {
  overlay_dir="$WALTER_CONFIG/overlay/sandbox-profiles"
  mkdir -p "$overlay_dir"
  cat > "$overlay_dir/space-test.firejail.profile" <<'EOF'
whitelist @WALTER_OS_HOME@
read-only @WALTER_OS_HOME@
blacklist @HOME@/.ssh
EOF
  spaced_home="$TMP_HOME/Walter OS"
  mkdir -p "$spaced_home"

  run bash -c "source '$SANDBOX_LIB'; WALTER_OS_HOME='$spaced_home' walter_sandbox_materialize_profile space-test firejail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q '^whitelist .*/Walter\\ OS$' "$profile"
  grep -q '^read-only .*/Walter\\ OS$' "$profile"
  run grep -q 'Walter OS' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-2: hook profile materialization does not require live cwd" {
  dead_cwd="$TMP_HOME/deleted-cwd"
  mkdir -p "$dead_cwd"

  run bash -c "cd '$dead_cwd'; rmdir '$dead_cwd'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-hook-default sandbox-exec"

  [ "$status" -eq 0 ]
  [[ "$output" == "$WALTER_RUNTIME_DIR"/sandbox/walter-hook-default.sandbox-exec.* ]]
}

@test "AC-2: sandbox-exec hook profile enforces read/write/network boundaries when available" {
  command -v sandbox-exec >/dev/null || skip "sandbox-exec not installed"
  sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "sandbox-exec cannot apply profiles in this environment"
  mkdir -p "$HOME/.ssh"
  printf 'secret\n' > "$HOME/.ssh/id_rsa"

  outside_write="$REPO_ROOT/../.sandbox-outside-write-test.$$"
  rm -f "$outside_write"

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default /bin/cat '$WALTER_OS_HOME/README.md'"
  [ "$status" -eq 0 ]

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default /bin/sh -c \"printf x > '$WALTER_OS_HOME/.sandbox-write-test'\""
  [ "$status" -ne 0 ]
  [ ! -e "$WALTER_OS_HOME/.sandbox-write-test" ]

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default /bin/sh -c 'tmp=\"\$(mktemp)\"; printf ok > \"\$tmp\"; cat \"\$tmp\"; : >/dev/null'"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default /bin/sh -c \"printf x > '$outside_write'\""
  [ "$status" -ne 0 ]
  [ ! -e "$outside_write" ]

  run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default /bin/cat '$HOME/.ssh/id_rsa'"
  [ "$status" -ne 0 ]

  if command -v curl >/dev/null; then
    run bash -c "source '$SANDBOX_LIB'; walter_sandbox_run walter-hook-default curl --connect-timeout 2 https://example.com"
    [ "$status" -ne 0 ]
  fi

  run find "$WALTER_RUNTIME_DIR/sandbox" -maxdepth 1 -name 'walter-hook-default.sandbox-exec.*' -print
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "AC-2: sandbox run cleans profiles after failures under errexit" {
  command -v sandbox-exec >/dev/null || skip "sandbox-exec not installed"
  sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "sandbox-exec cannot apply profiles in this environment"

  run bash -c "set -e; source '$SANDBOX_LIB'; if walter_sandbox_run walter-hook-default /bin/sh -c 'exit 42'; then exit 99; else rc=\"\$?\"; fi; [ \"\$rc\" -eq 42 ]"

  [ "$status" -eq 0 ]
  run find "$WALTER_RUNTIME_DIR/sandbox" -maxdepth 1 -name 'walter-hook-default.sandbox-exec.*' -print
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
