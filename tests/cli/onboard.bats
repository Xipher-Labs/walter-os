#!/usr/bin/env bats
# tests/cli/onboard.bats
#
# Covers: docs/specs/onboarding-planner.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_DIR="$(mktemp -d)"
  MUTATION_LOG="$TMP_DIR/mutations.log"
  export HOME="$TMP_DIR/home"
  export WALTER_CONFIG="$TMP_DIR/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  export MUTATION_LOG
  mkdir -p "$HOME" "$WALTER_CONFIG" "$TMP_DIR/bin"

  for cmd in cloudflared curl docker docker-compose docker-compose-v2 docker compose \
    forgejo headscale infisical npx ntfy pnpm syncthing tailscale tea; do
    cat > "$TMP_DIR/bin/$cmd" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MUTATION_LOG"
exit 99
SH
    chmod +x "$TMP_DIR/bin/$cmd"
  done
  export PATH="$TMP_DIR/bin:/usr/bin:/bin"
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || exit
  case "$TMP_DIR" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_DIR" ;;
  esac
}

assert_no_mutations() {
  if [[ -s "$MUTATION_LOG" ]]; then
    cat "$MUTATION_LOG" >&2
    return 1
  fi
}

assert_no_secret_values() {
  local text="$1"
  [[ "$text" != *"token="* ]]
  [[ "$text" != *"api_key"* ]]
  [[ "$text" != *"secret="* ]]
  [[ "$text" != *"password="* ]]
  [[ "$text" != *"-----BEGIN"* ]]
}

assert_referenced_docs_exist() {
  local text="$1" path
  while IFS= read -r path; do
    [[ -f "$REPO_ROOT/$path" ]]
  done < <(grep -Eo 'docs/[^ ]+\\.md' <<<"$text" | sort -u)
}

@test "device dry-run prints second-device plan without side effects" {
  run bash "$WALTER_OS_BIN" onboard device --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Second-device onboarding"* ]]
  [[ "$output" == *"secrets identity"* ]]
  [[ "$output" == *"profile bootstrap"* ]]
  [[ "$output" == *"agent memory"* ]]
  [[ "$output" == *"Syncthing"* ]]
  [[ "$output" == *"Headscale"* ]]
  [[ "$output" == *"doctor/status"* ]]
  assert_no_secret_values "$output"
  assert_referenced_docs_exist "$output"
  assert_no_mutations
}

@test "teammate dry-run prints teammate plan and optional modules" {
  run bash "$WALTER_OS_BIN" onboard teammate --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Teammate onboarding"* ]]
  [[ "$output" == *"Cloudflare Access"* ]]
  [[ "$output" == *"Authentik"* ]]
  [[ "$output" == *"Forgejo"* ]]
  [[ "$output" == *"Plane"* ]]
  [[ "$output" == *"ntfy"* ]]
  [[ "$output" == *"role boundaries"* ]]
  [[ "$output" == *"Forgejo Actions Runner"* ]]
  [[ "$output" == *"Renovate"* ]]
  [[ "$output" == *"Langfuse"* ]]
  [[ "$output" == *"Listmonk"* ]]
  [[ "$output" == *"knowledge/bookmarking"* ]]
  assert_no_secret_values "$output"
  assert_referenced_docs_exist "$output"
  assert_no_mutations
}

@test "onboard requires explicit dry-run" {
  run bash "$WALTER_OS_BIN" onboard device

  [ "$status" -eq 2 ]
  [[ "$output" == *"--dry-run"* ]]
  assert_no_mutations
}

@test "onboard rejects unknown target" {
  run bash "$WALTER_OS_BIN" onboard pet --dry-run

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown target"* ]]
  assert_no_mutations
}
