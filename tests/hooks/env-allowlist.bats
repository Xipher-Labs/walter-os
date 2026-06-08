#!/usr/bin/env bats
# shellcheck disable=SC2016
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
  cd "$BATS_TEST_DIRNAME" || true
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
WALTER_SESSION_LOCK_WAIT_SEC=45
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_SESSION_MAX_HOURS:-UNSET}|\${WALTER_SESSION_MAX_IDLE_MIN:-UNSET}|\${WALTER_SESSION_LOCK_WAIT_SEC:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"8|60|45"* ]]
}

@test "A-2: OpenSSL executable override is not loaded from data env" {
  echo 'WALTER_OPENSSL_BIN=/opt/homebrew/opt/openssl@3/bin/openssl' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"\${WALTER_OPENSSL_BIN:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"UNSET"* ]]
  [[ "$output" == *"not in the env allowlist"* ]]
}

@test "A-4: operator env cannot override active PHI mode" {
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_PHI_MODE=0
ENV

  run bash -c "export WALTER_PHI_MODE=1; source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>/dev/null; echo \"\${WALTER_PHI_MODE:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == "1" ]]
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

@test "P1-09: env file cannot redirect override allowlist mid-parse" {
  evil_cfg="$TMP_HOME/evil-config"
  mkdir -p "$evil_cfg"
  echo 'BASH_ENV' > "$evil_cfg/env-allowlist.txt"
  cat > "$TMP_CFG/env" <<ENV
WALTER_CONFIG=$evil_cfg
BASH_ENV=$TMP_HOME/evil.sh
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"BASH_ENV=\${BASH_ENV:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"BASH_ENV=UNSET"* ]]
  [[ "$output" == *"$TMP_CFG/env-allowlist.txt"* ]]
}

@test "P1-09: override allowlist cannot permit shell startup hooks" {
  cat > "$TMP_CFG/env-allowlist.txt" <<'ENV'
BASH_ENV
ENV
  echo "BASH_ENV=$TMP_HOME/evil.sh" > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"BASH_ENV=\${BASH_ENV:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"BASH_ENV=UNSET"* ]]
}

@test "P1-09: protected keys are not overwritten when caller freezes roots" {
  echo 'WALTER_CONFIG=/tmp/evil' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; WALTER_ENV_PROTECTED_KEYS='WALTER_CONFIG WALTER_OS_HOME' walter_env_load_allowlist '$TMP_CFG/env' 2>&1; echo \"WALTER_CONFIG=\$WALTER_CONFIG\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"WALTER_CONFIG=$TMP_CFG"* ]]
}

@test "P1-09: export-prefixed installer env lines are accepted" {
  echo 'export WALTER_OS_HOME=/opt/walter-os' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo \"\${WALTER_OS_HOME:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/walter-os"* ]]
}

@test "P1-09: malformed warnings redact raw line content" {
  cat > "$TMP_CFG/env" <<'ENV'
export TOKEN super-secret-value
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not a KEY=VALUE pair"* ]]
  [[ "$output" != *"super-secret-value"* ]]
}

@test "P1-09: unmatched quote values do not abort parsing" {
  echo 'WALTER_TIMEZONE="' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; printf '%s' \"\${WALTER_TIMEZONE:-UNSET}\""

  [ "$status" -eq 0 ]
  [[ "$output" == '"' ]]
}

@test "P1-09: CRLF line endings do not leak carriage returns into values" {
  printf 'WALTER_DOMAIN=walter.test\r\n' > "$TMP_CFG/env"

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; printf '%q' \"\$WALTER_DOMAIN\""

  [ "$status" -eq 0 ]
  [[ "$output" == "walter.test" ]]
}

@test "P1-09: WALTER_MODEL_* routing keys are allowlisted" {
  cat > "$TMP_CFG/env" <<'ENV'
WALTER_MODEL_BACKEND_REVIEW=codex
WALTER_MODEL_FRONTEND=claude
WALTER_MODEL_LONGFORM=claude
WALTER_MODEL_QUICK_REFACTOR=codex
WALTER_MODEL_PHI=local-ollama
WALTER_MODEL_BRAINSTORM=claude,codex
WALTER_MODEL_DEFAULT=claude
WALTER_MODEL_OVERRIDE=gemini
ENV

  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env' 2>&1; printf '%s|%s|%s' \"\$WALTER_MODEL_BACKEND_REVIEW\" \"\$WALTER_MODEL_BRAINSTORM\" \"\$WALTER_MODEL_OVERRIDE\""

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex|claude,codex|gemini"* ]]
  [[ "$output" != *"not in the env allowlist"* ]]
}

@test "P1-09: missing env file is a no-op (not an error)" {
  # No env file created.
  run bash -c "source '$LOADER'; walter_env_load_allowlist '$TMP_CFG/env'; echo done"

  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
}
