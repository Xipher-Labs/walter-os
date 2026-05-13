#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/secrets-identity-init.sh"
  MOCKBIN="$BATS_TEST_TMPDIR/mockbin"
  MOCK_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$MOCKBIN" "$MOCK_LOG_DIR"
  export PATH="$MOCKBIN:$PATH"
  export MOCK_LOG_DIR
  export USER="test-user"
  unset INFISICAL_DOMAIN WALTER_INFISICAL_DOMAIN WALTER_DOMAIN
  unset WALTER_SECRETS_PASS_ENTRY INFISICAL_VERIFY_RC INFISICAL_HTTP_STATUS MOCK_UNAME

  write_uname "Darwin"
  write_infisical
  write_curl
}

write_mock() {
  local name="$1"
  local body="$2"
  printf "%s\n" "$body" > "$MOCKBIN/$name"
  chmod +x "$MOCKBIN/$name"
}

write_uname() {
  local os="$1"
  write_mock uname '#!/usr/bin/env bash
printf "%s\n" "${MOCK_UNAME:-'"$os"'}"'
}

write_infisical() {
  write_mock infisical '#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo "infisical mock 0.0.0"
    ;;
  *)
    echo "unexpected infisical invocation: $*" >&2
    exit 9
    ;;
esac'
}

write_curl() {
  write_mock curl '#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/curl.log"
cat > "${MOCK_LOG_DIR}/curl.body"
printf "%s" "${INFISICAL_HTTP_STATUS:-200}"
exit "${INFISICAL_VERIFY_RC:-0}"'
}

write_security() {
  write_mock security '#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  find-generic-password)
    [[ -f "${MOCK_LOG_DIR}/security.exists" ]]
    ;;
  delete-generic-password)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/security-delete.log"
    rm -f "${MOCK_LOG_DIR}/security.exists"
    ;;
  add-generic-password)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/security-add.log"
    cat > "${MOCK_LOG_DIR}/security.secret"
    touch "${MOCK_LOG_DIR}/security.exists"
    ;;
  *)
    echo "unexpected security invocation: $*" >&2
    exit 9
    ;;
esac'
}

write_secret_tool() {
  write_mock secret-tool '#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  lookup)
    [[ -f "${MOCK_LOG_DIR}/secret-tool.exists" ]] && cat "${MOCK_LOG_DIR}/secret-tool.secret"
    ;;
  clear)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/secret-tool-clear.log"
    rm -f "${MOCK_LOG_DIR}/secret-tool.exists" "${MOCK_LOG_DIR}/secret-tool.secret"
    ;;
  store)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/secret-tool-store.log"
    cat > "${MOCK_LOG_DIR}/secret-tool.secret"
    touch "${MOCK_LOG_DIR}/secret-tool.exists"
    ;;
  *)
    echo "unexpected secret-tool invocation: $*" >&2
    exit 9
    ;;
esac'
}

write_secret_tool_unavailable() {
  write_mock secret-tool '#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/secret-tool-unavailable.log"
exit 1'
}

write_pass() {
  write_mock pass '#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  show)
    [[ -f "${MOCK_LOG_DIR}/pass.exists" ]] && cat "${MOCK_LOG_DIR}/pass.secret"
    ;;
  rm)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/pass-rm.log"
    rm -f "${MOCK_LOG_DIR}/pass.exists" "${MOCK_LOG_DIR}/pass.secret"
    ;;
  insert)
    printf "%s\n" "$*" >> "${MOCK_LOG_DIR}/pass-insert.log"
    cat > "${MOCK_LOG_DIR}/pass.secret"
    touch "${MOCK_LOG_DIR}/pass.exists"
    ;;
  *)
    echo "unexpected pass invocation: $*" >&2
    exit 9
    ;;
esac'
}

write_gpg() {
  write_mock gpg '#!/usr/bin/env bash
echo "gpg mock"'
}

run_with_creds() {
  local args="$1"
  run bash -c "printf 'client-id\nclient-secret\n' | '$SCRIPT' $args"
}

@test "macOS auto backend succeeds without ykman" {
  write_uname "Darwin"
  write_security
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store auto --yes"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Credential store: macos-keychain"* ]]
  [[ -f "$MOCK_LOG_DIR/security-add.log" ]]
  [[ -f "$MOCK_LOG_DIR/security.secret" ]]
  grep -q '"client_secret":"client-secret"' "$MOCK_LOG_DIR/security.secret"
  grep -q '"domain":"https://secrets.example.test"' "$MOCK_LOG_DIR/security.secret"
  ! grep -q 'client-secret' "$MOCK_LOG_DIR/security-add.log"
  grep -q '"clientSecret":"client-secret"' "$MOCK_LOG_DIR/curl.body"
  ! grep -q 'client-secret' "$MOCK_LOG_DIR/curl.log"
}

@test "Linux auto backend uses Secret Service when secret-tool exists" {
  write_uname "Linux"
  write_secret_tool
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store auto --yes"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Credential store: secret-service"* ]]
  grep -q '"client_id":"client-id"' "$MOCK_LOG_DIR/secret-tool.secret"
  grep -q '"client_secret":"client-secret"' "$MOCK_LOG_DIR/secret-tool.secret"
  grep -q '"domain":"https://secrets.example.test"' "$MOCK_LOG_DIR/secret-tool.secret"
}

@test "Linux auto backend falls back to pass when Secret Service is unusable" {
  write_uname "Linux"
  write_secret_tool_unavailable
  write_pass
  write_gpg
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store auto --yes"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Credential store: pass"* ]]
  [[ -f "$MOCK_LOG_DIR/pass.secret" ]]
  [[ ! -f "$MOCK_LOG_DIR/secret-tool.secret" ]]
}

@test "explicit Secret Service backend fails closed when unusable" {
  write_uname "Linux"
  write_secret_tool_unavailable
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store secret-service --yes"

  [ "$status" -eq 4 ]
  [[ "$output" == *"secret-service backend is installed but not usable"* ]]
  [[ ! -f "$MOCK_LOG_DIR/curl.log" ]]
}

@test "Linux pass backend stores identity when explicitly selected" {
  write_uname "Linux"
  write_pass
  write_gpg
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store pass --yes"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Credential store: pass"* ]]
  grep -q '"client_id":"client-id"' "$MOCK_LOG_DIR/pass.secret"
  grep -q "walter-os/infisical-identity" "$MOCK_LOG_DIR/pass-insert.log"
}

@test "Linux auto backend fails closed when no supported store exists" {
  write_uname "Linux"
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run_with_creds "--store auto --yes"

  [ "$status" -eq 3 ]
  [[ "$output" == *"No supported Linux credential store found"* ]]
  [[ ! -f "$MOCK_LOG_DIR/curl.log" ]]
}

@test "missing Infisical domain fails before prompting or storing" {
  write_uname "Darwin"
  write_security

  run_with_creds "--store auto --yes"

  [ "$status" -eq 5 ]
  [[ "$output" == *"Infisical domain is not configured"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
  [[ ! -f "$MOCK_LOG_DIR/curl.log" ]]
}

@test "http Infisical domain fails before prompting or storing" {
  write_uname "Darwin"
  write_security

  run_with_creds "--store auto --yes --domain http://secrets.example.test"

  [ "$status" -eq 5 ]
  [[ "$output" == *"must use https://"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
  [[ ! -f "$MOCK_LOG_DIR/curl.log" ]]
}

@test "failed Infisical verification does not store identity" {
  write_uname "Darwin"
  write_security
  export INFISICAL_DOMAIN="https://secrets.example.test"
  export INFISICAL_VERIFY_RC=22

  run_with_creds "--store auto --yes"

  [ "$status" -eq 7 ]
  [[ "$output" == *"Login failed"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
}

@test "redirected Infisical verification does not store identity" {
  write_uname "Darwin"
  write_security
  export INFISICAL_DOMAIN="https://secrets.example.test"
  export INFISICAL_HTTP_STATUS=302

  run_with_creds "--store auto --yes"

  [ "$status" -eq 7 ]
  [[ "$output" == *"Login failed"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
}

@test "failed replacement keeps existing identity entry" {
  write_uname "Darwin"
  write_security
  touch "$MOCK_LOG_DIR/security.exists"
  export INFISICAL_DOMAIN="https://secrets.example.test"
  export INFISICAL_VERIFY_RC=22

  run bash -c "printf 'y\nclient-id\nclient-secret\n' | '$SCRIPT' --store auto"

  [ "$status" -eq 7 ]
  [[ "$output" == *"Keeping prior entry until the replacement is verified and stored"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-delete.log" ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
  [[ -f "$MOCK_LOG_DIR/security.exists" ]]
}

@test "existing identity replacement requires confirmation" {
  write_uname "Darwin"
  write_security
  touch "$MOCK_LOG_DIR/security.exists"
  export INFISICAL_DOMAIN="https://secrets.example.test"

  run bash -c "printf 'n\nclient-id\nclient-secret\n' | '$SCRIPT' --store auto"

  [ "$status" -eq 0 ]
  [[ "$output" == *"An entry already exists"* ]]
  [[ "$output" == *"Aborted"* ]]
  [[ ! -f "$MOCK_LOG_DIR/security-delete.log" ]]
  [[ ! -f "$MOCK_LOG_DIR/security-add.log" ]]
}
