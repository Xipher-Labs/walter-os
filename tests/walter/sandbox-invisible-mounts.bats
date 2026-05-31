#!/usr/bin/env bats
# tests/walter/sandbox-invisible-mounts.bats
#
# OSS Trust A-5 invisible secret-bearing mounts coverage.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SANDBOX_LIB="$REPO_ROOT/scripts/walter/lib/sandbox.sh"
  TMP_HOME="$(mktemp -d "$REPO_ROOT/.tmp-sandbox-invisible.XXXXXX")"
  MOCK_BIN="$TMP_HOME/bin"
  export HOME="$TMP_HOME/home"
  export WALTER_CONFIG="$TMP_HOME/home/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_RUNTIME_DIR="$TMP_HOME/runtime"
  export GIT_CEILING_DIRECTORIES="$REPO_ROOT"
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  PROJECT_DIR="$TMP_HOME/project"
  mkdir -p "$MOCK_BIN" "$HOME/.ssh" "$HOME/.docker" "$WALTER_CONFIG/overlay/work" "$WALTER_CONFIG/state" "$WALTER_RUNTIME_DIR" "$PROJECT_DIR"
  printf 'secret\n' > "$HOME/.ssh/id_rsa"
  printf 'token\n' > "$WALTER_CONFIG/overlay/personal.env"
  printf 'docker\n' > "$HOME/.docker/config.json"
  printf 'visible\n' > "$WALTER_CONFIG/overlay/work/AGENTS.md"
}

teardown() {
  [[ -n "${TMP_HOME:-}" ]] || return 0
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    "$REPO_ROOT"/.tmp-sandbox-invisible.*) rm -rf "$TMP_HOME" ;;
  esac
}

_mode() {
  if stat -f %Lp "$1" >/dev/null 2>&1; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
}

_mock_provider() {
  cat > "$MOCK_BIN/nsjail" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${WALTER_SANDBOX_PROVIDER_LOG:?}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --config)
      cp "$2" "${WALTER_SANDBOX_PROVIDER_CONFIG_COPY:?}"
      shift 2
      ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
exec "$@"
EOF
  chmod +x "$MOCK_BIN/nsjail"
}

_mock_uname() {
  cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
  chmod +x "$MOCK_BIN/uname"
}

@test "A-5: default invisible path list is tagged" {
  defaults="$REPO_ROOT/setup/sandbox-profiles/invisible-paths.default.txt"

  grep -q '^~/.ssh/:dir$' "$defaults"
  grep -q '^~/.aws/:dir$' "$defaults"
  grep -q '^~/.gnupg/:dir$' "$defaults"
  # shellcheck disable=SC2016 # Match literal env-var syntax in the default path list.
  grep -q '^\$WALTER_CONFIG/state/:dir$' "$defaults"
  # shellcheck disable=SC2016
  grep -q '^\$WALTER_CONFIG/overlay/personal.env:file$' "$defaults"
  grep -q '^~/.docker/config.json:file$' "$defaults"
}

@test "A-5: high-tier nsjail materialization adds dir and file invisible mounts" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  invisible_root="$(dirname "$profile")/invisible"
  grep -q "dst: \"$HOME/.ssh\"" "$profile"
  grep -q "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$profile"
  grep -A5 "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$profile" | grep -q 'mandatory: true'
  run grep -q "dst: \"$WALTER_CONFIG/overlay/work/AGENTS.md\"" "$profile"
  [ "$status" -ne 0 ]
  ssh_src="$(awk -v dst="$HOME/.ssh" '
    $1 == "src:" { gsub(/"/, "", $2); src=$2 }
    $1 == "dst:" { gsub(/"/, "", $2); if ($2 == dst) print src }
  ' "$profile" | head -1)"
  [[ "$ssh_src" == "$invisible_root"/dir-* ]]
  [ -d "$ssh_src" ]
  [ "$(_mode "$ssh_src")" = "700" ]
  personal_src="$(awk -v dst="$WALTER_CONFIG/overlay/personal.env" '
    $1 == "src:" { gsub(/"/, "", $2); src=$2 }
    $1 == "dst:" { gsub(/"/, "", $2); if ($2 == dst) print src }
  ' "$profile" | tail -1)"
  [[ "$personal_src" == "$invisible_root"/file-* ]]
  [ -f "$personal_src" ]
  [ "$(_mode "$personal_src")" = "600" ]
  [ -d "${profile}.root$HOME/.ssh" ]
  [ -f "${profile}.root$WALTER_CONFIG/overlay/personal.env" ]
}

@test "A-5: normal-tier materialization does not add invisible personal env" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail"

  [ "$status" -eq 0 ]
  profile="$output"
  run grep -q "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$profile"
  [ "$status" -ne 0 ]
  [ ! -e "$(dirname "$profile")/invisible" ]
}

@test "A-5: high-tier materialization fails without provider invisible placeholder" {
  mkdir -p "$WALTER_CONFIG/overlay/sandbox-profiles"
  cat > "$WALTER_CONFIG/overlay/sandbox-profiles/no-invisible.nsjail.conf" <<'EOF'
name: "no-invisible"
EOF

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile no-invisible nsjail 1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing invisible-mount placeholder"* ]]
}

@test "A-5: invisible placeholders are stable across starts" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"
  [ "$status" -eq 0 ]
  first_profile="$output"
  first_src="$(awk -v dst="$WALTER_CONFIG/overlay/personal.env" '
    $1 == "src:" { gsub(/"/, "", $2); src=$2 }
    $1 == "dst:" { gsub(/"/, "", $2); if ($2 == dst) print src }
  ' "$first_profile" | tail -1)"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"
  [ "$status" -eq 0 ]
  second_profile="$output"
  second_src="$(awk -v dst="$WALTER_CONFIG/overlay/personal.env" '
    $1 == "src:" { gsub(/"/, "", $2); src=$2 }
    $1 == "dst:" { gsub(/"/, "", $2); if ($2 == dst) print src }
  ' "$second_profile" | tail -1)"

  [ "$first_src" = "$second_src" ]
}

@test "A-5: nsjail invisible mounts require a prepared root" {
  mkdir -p "$WALTER_CONFIG/overlay/sandbox-profiles"
  cat > "$WALTER_CONFIG/overlay/sandbox-profiles/no-root.nsjail.conf" <<'EOF'
name: "no-root"
@WALTER_NSJAIL_INVISIBLE_MOUNTS@
EOF

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile no-root nsjail 1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"require a prepared nsjail root"* ]]
  [ "$(cat "$WALTER_CONFIG/overlay/personal.env")" = "token" ]
}

@test "A-5: nsjail skips absent optional invisible paths" {
  rm -f "$WALTER_CONFIG/overlay/personal.env"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  run grep -q "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$profile"
  [ "$status" -ne 0 ]
}

@test "A-5: default list follows custom WALTER_CONFIG" {
  custom_config="$HOME/custom-walter"
  mkdir -p "$custom_config/overlay" "$custom_config/state"
  printf 'custom-token\n' > "$custom_config/overlay/personal.env"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; WALTER_CONFIG='$custom_config' walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "dst: \"$custom_config/overlay/personal.env\"" "$profile"
  run grep -q "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$profile"
  [ "$status" -ne 0 ]
}

@test "A-5: macOS high-tier emits file-read-data denies" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default sandbox-exec 1"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq '(deny file-read-data (subpath "'"$HOME/.ssh"'"))' "$profile"
  grep -Fq '(deny file-read-data (subpath "'"$WALTER_CONFIG/overlay/personal.env"'"))' "$profile"
  run grep -Fq "$WALTER_CONFIG/overlay/work/AGENTS.md" "$profile"
  [ "$status" -ne 0 ]
  run grep -Fq '(deny file-read* (subpath "'"$WALTER_CONFIG/overlay/personal.env"'"))' "$profile"
  [ "$status" -ne 0 ]
}

@test "A-5: firejail high-tier blacklists invisible paths" {
  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default firejail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "^blacklist $HOME/.ssh$" "$profile"
  grep -q "^blacklist $WALTER_CONFIG/overlay/personal.env$" "$profile"
  run grep -q "$WALTER_CONFIG/overlay/work/AGENTS.md" "$profile"
  [ "$status" -ne 0 ]
}

@test "A-5: firejail invisible blacklists escape spaces" {
  secret_path="$HOME/Secret Store/token:file"
  mkdir -p "$(dirname "$secret_path")"
  printf 'token\n' > "$secret_path"
  printf '%s:file\n' "$secret_path" > "$WALTER_CONFIG/overlay/sandbox-invisible-paths.txt"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default firejail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -Fq "blacklist $HOME/Secret\\ Store/token:file" "$profile"
}

@test "A-5: sandbox run passes high-tier through materialization" {
  _mock_uname
  _mock_provider
  export WALTER_SANDBOX_PROVIDER=nsjail
  export WALTER_SANDBOX_PROVIDER_LOG="$TMP_HOME/provider.log"
  export WALTER_SANDBOX_PROVIDER_CONFIG_COPY="$TMP_HOME/copied-profile.conf"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_run walter-skill-default --high-tier bash -c 'printf ok'"

  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  grep -q "dst: \"$WALTER_CONFIG/overlay/personal.env\"" "$WALTER_SANDBOX_PROVIDER_CONFIG_COPY"
}

@test "A-5: overlay can add and remove invisible paths" {
  extra="$HOME/secrets/custom.token"
  mkdir -p "$(dirname "$extra")"
  printf 'custom\n' > "$extra"
  cat > "$WALTER_CONFIG/overlay/sandbox-invisible-paths.txt" <<EOF
!~/.docker/config.json/
$extra:file
EOF

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -eq 0 ]
  profile="$output"
  grep -q "dst: \"$extra\"" "$profile"
  run grep -q "dst: \"$HOME/.docker/config.json\"" "$profile"
  [ "$status" -ne 0 ]
}

@test "A-5: invisible path entries require explicit type tags" {
  printf '%s\n' "$HOME/secrets/no-type" > "$WALTER_CONFIG/overlay/sandbox-invisible-paths.txt"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing :dir or :file"* ]]
}

@test "A-5: invisible path type mismatch fails closed" {
  printf '%s\n' "$HOME/.ssh:file" > "$WALTER_CONFIG/overlay/sandbox-invisible-paths.txt"

  run bash -c "cd '$PROJECT_DIR'; source '$SANDBOX_LIB'; walter_sandbox_materialize_profile walter-skill-default nsjail 1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected file but found directory"* ]]
}
