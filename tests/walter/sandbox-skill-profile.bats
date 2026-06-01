#!/usr/bin/env bats
# tests/walter/sandbox-skill-profile.bats
#
# OSS Trust A-3 process isolation sandbox — AC-3 skill profile coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SANDBOX_LIB="$REPO_ROOT/scripts/walter/lib/sandbox.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-sandbox-skill.XXXXXX")"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_RUNTIME_DIR="$TMP_HOME/runtime"
  export GIT_CEILING_DIRECTORIES="$REPO_ROOT"
  PROJECT_PARENT="$TMP_HOME/projects"
  PROJECT_DIR="$PROJECT_PARENT/app"
  OUTSIDE_DIR="$TMP_HOME/outside/walter-os"
  mkdir -p "$HOME/.ssh" "$HOME/Desktop" "$WALTER_CONFIG/state" "$WALTER_RUNTIME_DIR"
  mkdir -p "$PROJECT_DIR" "$OUTSIDE_DIR"
  printf 'project\n' > "$PROJECT_DIR/README.md"
  printf 'outside\n' > "$OUTSIDE_DIR/README.md"
  printf 'client-key\n' > "$PROJECT_PARENT/client.pem"
  printf 'home-key\n' > "$HOME/private.pem"
  printf 'local-key\n' > "$PROJECT_DIR/local.key"
  printf 'secret\n' > "$HOME/.ssh/id_rsa"
  printf 'session-secret\n' > "$WALTER_CONFIG/state/session-test.key"
  printf 'session-temp-secret\n' > "$WALTER_CONFIG/state/session-test.key.tmp"
  mkdir -p "$WALTER_CONFIG/keys"
  printf 'config-key\n' > "$WALTER_CONFIG/keys/operator.pem"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-sandbox-skill.*) rm -rf "$TMP_HOME" ;;
  esac
}

_mode() {
  if stat -f %Lp "$1" >/dev/null 2>&1; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
}

@test "AC-3: nsjail skill profile declares workspace scope and signal isolation" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-skill-default.nsjail.conf"

  grep -q 'cwd: "@WALTER_SANDBOX_CWD@"' "$profile"
  grep -q 'rlimit_as: 1024' "$profile"
  grep -q 'PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin' "$profile"
  grep -q 'src: "@WALTER_NSJAIL_ROOT@"' "$profile"
  grep -A4 'dst: "/"' "$profile" | grep -q 'rw: false'
  grep -q 'src: "@WALTER_SANDBOX_PARENT@"' "$profile"
  grep -q 'dst: "@WALTER_SANDBOX_PARENT@"' "$profile"
  grep -q 'rw: true' "$profile"
  grep -q '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$profile"
  grep -q 'src: "@WALTER_CONFIG@"' "$profile"
  grep -q 'rw: false' "$profile"
  grep -q '@WALTER_NSJAIL_CONFIG_KEY_MASKS@' "$profile"
  grep -q '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$profile"
  grep -q 'dst: "@HOME@/.ssh"' "$profile"
  grep -q 'dst: "@HOME@/.aws"' "$profile"
  grep -q 'dst: "@HOME@/.gnupg"' "$profile"
  grep -q 'src: "/etc/passwd"' "$profile"
  grep -A4 'dst: "/etc/passwd"' "$profile" | grep -q 'rw: false'
  run grep -q 'src: "/etc"$' "$profile"
  [ "$status" -ne 0 ]
  grep -q 'clone_newpid: true' "$profile"
  grep -q 'clone_newcgroup: true' "$profile"
  grep -q 'clone_newnet: true' "$profile"
}

@test "AC-3: macOS skill profile constrains paths and secrets" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-skill-default.sb"

  grep -q '(allow default)' "$profile"
  grep -q '(deny signal' "$profile"
  grep -q '(require-not (target self))' "$profile"
  grep -q '(require-not (target children))' "$profile"
  grep -q '(allow signal (target self))' "$profile"
  grep -q '(allow signal (target children))' "$profile"
  grep -q 'require-not (subpath "@WALTER_SANDBOX_PARENT@")' "$profile"
  grep -q 'require-not (subpath "@WALTER_SANDBOX_SCRATCH@")' "$profile"
  grep -q '@WALTER_SANDBOX_PARENT@' "$profile"
  grep -q '@WALTER_SANDBOX_SCRATCH@' "$profile"
  grep -q '@WALTER_CONFIG_REGEX@/state/session-' "$profile"
  grep -Fq '[.]key[.]tmp' "$profile"
  grep -q '@HOME@/.ssh' "$profile"
  grep -q '(subpath "@WALTER_SANDBOX_PARENT@")' "$profile"
  grep -q '(subpath "@WALTER_CONFIG@")' "$profile"
  grep -q '(subpath "@HOME@")' "$profile"
  grep -Fq 'regex #".*[.]pem$"' "$profile"
  grep -Fq 'regex #".*[.]key$"' "$profile"
}

@test "AC-3: firejail skill profile constrains paths and secrets" {
  profile="$REPO_ROOT/setup/sandbox-profiles/walter-skill-default.firejail.profile"

  grep -q '^net none$' "$profile"
  grep -q '^read-only /$' "$profile"
  grep -q '^whitelist @WALTER_SANDBOX_PARENT@$' "$profile"
  grep -q '^read-write @WALTER_SANDBOX_PARENT@$' "$profile"
  grep -q '^whitelist @WALTER_CONFIG@$' "$profile"
  grep -q '^read-only @WALTER_CONFIG@$' "$profile"
  grep -q '^@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@$' "$profile"
  grep -q '^@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@$' "$profile"
  grep -q '^@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@$' "$profile"
  grep -q '^blacklist @HOME@/.ssh$' "$profile"
  grep -q '^blacklist @WALTER_CONFIG@/state/session-\*.key$' "$profile"
  grep -q '^blacklist @WALTER_CONFIG@/state/session-\*.key.tmp$' "$profile"
  run grep -q '^blacklist @HOME@/\*' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: sandbox materializes workspace scope placeholders" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  [[ "$profile" == "$WALTER_RUNTIME_DIR"/sandbox/walter-skill-default.sandbox-exec.* ]]
  grep -q "$PROJECT_DIR" "$profile"
  grep -q "$(cd "${profile}.scratch" && pwd -P)" "$profile"

  run grep -q '@WALTER_SANDBOX_PARENT@' "$profile"
  [ "$status" -ne 0 ]
  run grep -q '@WALTER_SANDBOX_SCRATCH@' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: sandbox uses git worktree root as workspace scope" {
  command -v git >/dev/null || skip "git not installed"
  git -C "$PROJECT_DIR" init >/dev/null 2>&1
  mkdir -p "$PROJECT_DIR/subdir"

  run bash -c "cd '$PROJECT_DIR/subdir'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "$PROJECT_DIR" "$profile"
  run grep -q "$PROJECT_DIR/subdir" "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: sandbox materialization refuses root workspace scope" {
  run bash -c "cd /; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing root workspace scope"* ]]
}

@test "AC-3: sandbox materialization rejects quoted paths" {
  QUOTED_PARENT="$TMP_HOME/quoted\"parent"
  QUOTED_PROJECT="$QUOTED_PARENT/app"
  mkdir -p "$QUOTED_PROJECT"

  run bash -c "cd '$QUOTED_PROJECT'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -ne 0 ]
  [[ "$output" == *"double quote"* ]]
}

@test "AC-3: nsjail root scaffold rejects parent-directory paths" {
  CONFIG_WITH_PARENT="$TMP_HOME/home/.config/../walter-os"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_CONFIG='$CONFIG_WITH_PARENT' walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing parent-directory component"* ]]
}

@test "AC-3: sandbox materializes escaped config regex placeholders" {
  CONFIG_WITH_REGEX_META="$TMP_HOME/home/.config/walter-os+(test)"
  mkdir -p "$CONFIG_WITH_REGEX_META/state"
  printf 'session-secret\n' > "$CONFIG_WITH_REGEX_META/state/session-test.key"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_CONFIG='$CONFIG_WITH_REGEX_META' walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq "$CONFIG_WITH_REGEX_META" "$profile"
  grep -Fq '.config/walter-os\+\(test\)/state/session-' "$profile"
}

@test "AC-3: sandbox materializes quoted config regex placeholders safely" {
  CONFIG_WITH_QUOTE="$TMP_HOME/home/.config/walter-os\"quoted"
  mkdir -p "$CONFIG_WITH_QUOTE/state"
  printf 'session-secret\n' > "$CONFIG_WITH_QUOTE/state/session-test.key"

  run env WALTER_CONFIG="$CONFIG_WITH_QUOTE" bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq '.config/walter-os\"quoted/state/session-' "$profile"
}

@test "AC-3: nsjail materialization hides session signing keys" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "cwd: \"$PROJECT_DIR\"" "$profile"
  [ -d "${profile}.root" ]
  [ -d "${profile}.root/tmp" ]
  [ -d "${profile}.root/etc" ]
  [ -f "${profile}.root/etc/passwd" ]
  [ -d "${profile}.root${PROJECT_DIR}" ]
  [ -d "${profile}.root${WALTER_CONFIG}" ]
  grep -q "src: \"${profile}.root\"" "$profile"
  tmp_line="$(grep -n 'dst: "/tmp"' "$profile" | cut -d: -f1 | head -1)"
  scope_line="$(grep -n "dst: \"$PROJECT_DIR\"" "$profile" | cut -d: -f1 | head -1)"
  [ "$tmp_line" -lt "$scope_line" ]
  [ -f "${profile}.deny" ]
  [ "$(_mode "${profile}.deny")" = "0" ]
  grep -q "src: \"${profile}.deny\"" "$profile"
  grep -q 'mandatory: true' "$profile"
  grep -q "dst: \"$WALTER_CONFIG/state/session-test.key\"" "$profile"
  grep -q "dst: \"$WALTER_CONFIG/state/session-test.key.tmp\"" "$profile"
  [ "$(grep -c "dst: \"$WALTER_CONFIG/state/session-test.key\"$" "$profile")" -eq 1 ]
  [ "$(grep -c "dst: \"$WALTER_CONFIG/state/session-test.key.tmp\"$" "$profile")" -eq 1 ]
  grep -q "dst: \"$WALTER_CONFIG/keys/operator.pem\"" "$profile"
  grep -q "dst: \"$PROJECT_DIR/local.key\"" "$profile"
  run grep -q "dst: \"$PROJECT_PARENT/client.pem\"" "$profile"
  [ "$status" -ne 0 ]
  config_bind_line="$(grep -n "dst: \"$WALTER_CONFIG\"" "$profile" | cut -d: -f1 | head -1)"
  config_key_line="$(grep -n "dst: \"$WALTER_CONFIG/keys/operator.pem\"" "$profile" | cut -d: -f1 | head -1)"
  [ "$config_bind_line" -lt "$config_key_line" ]
  run grep -q '}mount' "$profile"
  [ "$status" -ne 0 ]

  run grep -q '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$profile"
  [ "$status" -ne 0 ]
  run grep -q '@WALTER_NSJAIL_CONFIG_KEY_MASKS@' "$profile"
  [ "$status" -ne 0 ]
  run grep -q '@WALTER_NSJAIL_SENSITIVE_KEY_MASKS@' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: nsjail key mask generation rejects newline paths" {
  bad_key="${PROJECT_DIR}/bad"$'\n'"name.key"
  printf 'bad\n' > "$bad_key"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"path contains newline"* ]]
}

@test "AC-3: nsjail key mask generation fails closed on scan budget" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_SANDBOX_KEY_SCAN_MAX_ENTRIES=1 walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive key scan exceeded 1 entries"* ]]
}

@test "AC-3: nsjail key scan budget counts flat workspace files" {
  printf 'one\n' > "$PROJECT_DIR/one.txt"
  printf 'two\n' > "$PROJECT_DIR/two.txt"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_SANDBOX_KEY_SCAN_MAX_ENTRIES=2 walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive key scan exceeded 2 entries"* ]]
}

@test "AC-3: key scan uses incremental find traversal" {
  # shellcheck disable=SC2016 # These grep patterns intentionally match shell source literally.
  run grep -q 'for entry in "$dir"/\*' "$SANDBOX_LIB"
  [ "$status" -ne 0 ]
  # shellcheck disable=SC2016
  grep -q 'mkfifo "$fifo"' "$SANDBOX_LIB"
  # shellcheck disable=SC2016
  grep -q 'find "$root" -mindepth 1 -maxdepth "$scan_depth" -print0 > "$fifo"' "$SANDBOX_LIB"
  # shellcheck disable=SC2016
  grep -q 'if wait "$find_pid"; then' "$SANDBOX_LIB"
}

@test "AC-3: key scan creates traversal FIFO with private umask" {
  wrapper_dir="$TMP_HOME/bin"
  umask_file="$TMP_HOME/mkfifo.umask"
  real_mkfifo="$(command -v mkfifo)"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/mkfifo" <<EOF
#!/usr/bin/env bash
umask > "$umask_file"
exec "$real_mkfifo" "\$@"
EOF
  chmod +x "$wrapper_dir/mkfifo"

  run bash -c "umask 000; cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; PATH='$wrapper_dir':\$PATH walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -eq 0 ]
  grep -q '^0077$' "$umask_file"
}

@test "AC-3: key scan fails closed on traversal errors" {
  mkdir -p "$PROJECT_DIR/locked"
  printf 'hidden\n' > "$PROJECT_DIR/locked/hidden.key"
  chmod 111 "$PROJECT_DIR/locked"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail"

  chmod 700 "$PROJECT_DIR/locked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive key scan failed"* ]]
}

@test "AC-3: multiline placeholders tolerate standalone indentation" {
  overlay_dir="$WALTER_CONFIG/overlay/sandbox-profiles"
  mkdir -p "$overlay_dir"
  {
    printf '%s\n' 'name: "walter-skill-indented"'
    printf '%s\n' 'mode: ONCE'
    printf '%s\n' '  @WALTER_NSJAIL_SESSION_KEY_MASKS@  '
  } > "$overlay_dir/walter-skill-indented.nsjail.conf"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-indented nsjail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "dst: \"$WALTER_CONFIG/state/session-test.key\"" "$profile"
  run grep -q '@WALTER_NSJAIL_SESSION_KEY_MASKS@' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: multiline placeholders fail when embedded in text" {
  overlay_dir="$WALTER_CONFIG/overlay/sandbox-profiles"
  mkdir -p "$overlay_dir"
  cat > "$overlay_dir/walter-skill-embedded.nsjail.conf" <<'PROFILE'
name: "walter-skill-embedded"
mode: ONCE
prefix @WALTER_NSJAIL_SESSION_KEY_MASKS@
PROFILE

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-embedded nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"multiline placeholder must be on a standalone line"* ]]
}

@test "AC-3: key scan numeric budgets normalize leading zeroes" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_SANDBOX_KEY_SCAN_MAX_DEPTH=08 WALTER_SANDBOX_KEY_SCAN_MAX_ENTRIES=020 walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -eq 0 ]
}

@test "AC-3: nsjail key scan fails closed on max depth" {
  mkdir -p "$PROJECT_DIR/deep/nested"
  printf 'deep-key\n' > "$PROJECT_DIR/deep/nested/private.key"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_SANDBOX_KEY_SCAN_MAX_DEPTH=1 walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive key scan exceeded max depth 1"* ]]
}

@test "AC-3: nsjail key scan fails closed on over-depth key files" {
  mkdir -p "$PROJECT_DIR/deep"
  printf 'deep-key\n' > "$PROJECT_DIR/deep/private.key"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_SANDBOX_KEY_SCAN_MAX_DEPTH=1 walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive key scan exceeded max depth 1"* ]]
}

@test "AC-3: firejail materialization blacklists workspace key files" {
  mkdir -p "$HOME/a/b/c/d"
  printf 'home-key\n' > "$HOME/a/b/c/d/private.pem"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default firejail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "blacklist $WALTER_CONFIG/keys/operator.pem" "$profile"
  grep -q "blacklist $HOME/a/b/c/d/private.pem" "$profile"
  grep -q "blacklist $PROJECT_DIR/local.key" "$profile"
  run grep -q "blacklist $PROJECT_PARENT/client.pem" "$profile"
  [ "$status" -ne 0 ]

  run grep -q '@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@' "$profile"
  [ "$status" -ne 0 ]
  run grep -q '@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@' "$profile"
  [ "$status" -ne 0 ]
}

@test "AC-3: firejail materialization escapes workspace paths with spaces" {
  SPACE_PARENT="$TMP_HOME/My Projects"
  SPACE_PROJECT="$SPACE_PARENT/app"
  mkdir -p "$SPACE_PROJECT"

  run bash -c "git() { return 127; }; cd '$SPACE_PROJECT'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default firejail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq "whitelist ${SPACE_PROJECT// /\\ }" "$profile"
  grep -Fq "read-write ${SPACE_PROJECT// /\\ }" "$profile"
}

@test "AC-3: firejail materialization escapes config paths with spaces" {
  CONFIG_WITH_SPACE="$TMP_HOME/home/.config/walter os"
  mkdir -p "$CONFIG_WITH_SPACE/state"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_CONFIG='$CONFIG_WITH_SPACE' walter_sandbox_materialize_profile walter-skill-default firejail"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq "whitelist ${CONFIG_WITH_SPACE// /\\ }" "$profile"
  grep -Fq "read-only ${CONFIG_WITH_SPACE// /\\ }" "$profile"
}

@test "AC-3: firejail materialization rejects glob metacharacters in paths" {
  GLOB_PARENT="$TMP_HOME/project[set]"
  GLOB_PROJECT="$GLOB_PARENT/app"
  mkdir -p "$GLOB_PROJECT"

  run bash -c "cd '$GLOB_PROJECT'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default firejail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"firejail profile paths must not contain glob metacharacters"* ]]
}

@test "AC-3: sandbox-exec skill profile enforces path and signal boundaries when available" {
  command -v sandbox-exec >/dev/null || skip "sandbox-exec not installed"
  sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "sandbox-exec cannot apply profiles in this environment"
  victim_pid="$$"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/sh -c 'printf ok > allowed.txt; cat allowed.txt'"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  [ -f "$PROJECT_DIR/allowed.txt" ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/sh -c \"printf x > '$HOME/Desktop/blocked.txt'\""
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/Desktop/blocked.txt" ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/sh -c \"printf x > '$OUTSIDE_DIR/blocked.txt'\""
  [ "$status" -ne 0 ]
  [ ! -e "$OUTSIDE_DIR/blocked.txt" ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/cat '$HOME/.ssh/id_rsa'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/cat '$WALTER_CONFIG/state/session-test.key'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/cat '$WALTER_CONFIG/state/session-test.key.tmp'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/cat '$HOME/private.pem'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/cat '$PROJECT_DIR/local.key'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/kill -0 '$victim_pid'"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default /bin/sh -c 'sleep 10 & child=\$!; kill \"\$child\"'"
  [ "$status" -eq 0 ]

  run find "$WALTER_RUNTIME_DIR/sandbox" -maxdepth 1 -name 'walter-skill-default.sandbox-exec.*' -print
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
