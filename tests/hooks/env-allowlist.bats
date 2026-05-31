#!/usr/bin/env bats
# tests/hooks/env-allowlist.bats
#
# Audit P1-09 regression coverage. `~/.config/walter-os/env` must NOT
# be loaded via `source` — that would let any attacker who can write
# to that file execute arbitrary shell at session start.
#
# The new loader at `scripts/walter/lib/env-loader.sh` parses KEY=VALUE
# lines, rejects anything not in `WALTER_ENV_ALLOWLIST`, and never
# evaluates values as code.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOADER="$REPO_ROOT/scripts/walter/lib/env-loader.sh"
  [[ -f "$LOADER" ]] || skip "env-loader.sh not present"

  TMP_HOME="$(mktemp -d)"
  TMP_CFG="$TMP_HOME/.config/walter-os"
  mkdir -p "$TMP_CFG"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_CFG"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_HOME" ;;
  esac
  true
}

@test "P1-09: allowlisted key WALTER_OS_HOME is exported" {
  echo 'WALTER_OS_HOME=/opt/walter-os' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_OS_HOME:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/walter-os"* ]]
}

@test "A-4: session timeout keys are exported from Walter env" {
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_SESSION_MAX_HOURS=8
WALTER_SESSION_MAX_IDLE_MIN=60
WALTER_PHI_MODE=1
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_SESSION_MAX_HOURS:-UNSET}|\${WALTER_SESSION_MAX_IDLE_MIN:-UNSET}|\${WALTER_PHI_MODE:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"8|60|1"* ]]
}

@test "P1-09: non-allowlisted key ARBITRARY_VAR is ignored + warning emitted" {
  echo 'ARBITRARY_VAR=baz' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"\${ARBITRARY_VAR:-UNSET}\""

  [ "$status" -eq 0 ]
  # Var must NOT be exported
  [[ "$output" == *"UNSET"* ]]
  # Warning must be emitted
  [[ "$output" == *"not in the env allowlist"* ]]
}

@test "P1-09: command-substitution attempt is parsed as LITERAL string, no exec" {
  # If the loader were calling `source`, this would execute `id` and
  # capture its output. The allowlist parser must treat the entire RHS
  # as a literal string.
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_OS_HOME=$(id)
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_OS_HOME}\""

  [ "$status" -eq 0 ]
  # The variable is exported with the literal string '$(id)', not the
  # output of `id`. So the output must contain `$(id)` verbatim and
  # MUST NOT contain `uid=` (which would prove `id` was executed).
  [[ "$output" == *'$(id)'* ]]
  [[ "$output" != *"uid="* ]]
}

@test "P1-09: backtick-substitution attempt is parsed as LITERAL string, no exec" {
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_DOMAIN=`whoami`
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_DOMAIN}\""

  [ "$status" -eq 0 ]
  # The literal backtick string is exported; `whoami` is NOT executed.
  [[ "$output" == *'`whoami`'* ]]
}

@test "P1-09: malicious 'rm -rf /' on its own line is ignored (not KEY=VALUE)" {
  cat > "$TMP_CFG/env" <<'ENV'
rm -rf /
WALTER_DOMAIN=walter.test
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"\${WALTER_DOMAIN}\""

  [ "$status" -eq 0 ]
  # rm should not run (we're still alive)
  [[ "$output" == *"walter.test"* ]]
  # Warning about the non-KEY=VALUE line
  [[ "$output" == *"not a KEY=VALUE pair"* ]]
}

@test "P1-09: comments + blank lines are ignored silently" {
  cat > "$TMP_CFG/env" <<'ENV'
# This is a comment
   # Indented comment

WALTER_DOMAIN=walter.test
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo done"

  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
  # No warnings about comments or blanks
  [[ "$output" != *"not a KEY=VALUE pair"* ]]
}

@test "P1-09: quoted values have surrounding quotes stripped" {
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_DOMAIN="walter.test"
WALTER_OS_HOME='/opt/walter-os'
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_DOMAIN}|\${WALTER_OS_HOME}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"walter.test|/opt/walter-os"* ]]
}

@test "P1-09: operator override file extends the allowlist" {
  echo 'MY_CUSTOM_VAR' > "$TMP_CFG/env-allowlist.txt"
  echo 'MY_CUSTOM_VAR=hello' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"VAR=\${MY_CUSTOM_VAR:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"VAR=hello"* ]]
}

@test "P1-09: missing env file is a no-op (not an error)" {
  # No env file created.
  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo done"

  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
}
