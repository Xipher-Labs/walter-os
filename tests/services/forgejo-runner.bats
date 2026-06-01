#!/usr/bin/env bats
# Static-analysis assertions for the optional Forgejo Actions runner profile.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER_DIR="$REPO_ROOT/setup/walter-host/services/forgejo-runner"
  COMPOSE_FILE="$RUNNER_DIR/compose.yml"
  ENV_TEMPLATE="$RUNNER_DIR/.env.template"
  README_FILE="$RUNNER_DIR/README.md"
  CONFIG_TEMPLATE="$RUNNER_DIR/config.yml.template"
}

@test "forgejo runner service files exist" {
  [[ -f "$COMPOSE_FILE" ]]
  [[ -f "$ENV_TEMPLATE" ]]
  [[ -f "$README_FILE" ]]
  [[ -f "$CONFIG_TEMPLATE" ]]
}

@test "compose gates the runner behind the forgejo-runner profile" {
  grep -q "profiles:" "$COMPOSE_FILE"
  grep -q "forgejo-runner" "$COMPOSE_FILE"
}

@test "compose uses the official pinned Forgejo runner image" {
  grep -q "code.forgejo.org/forgejo/runner:12.10.2" "$COMPOSE_FILE"
}

@test "compose requires registration token at runtime" {
  grep -qE '\$\{FORGEJO_RUNNER_REGISTRATION_TOKEN:\?' "$COMPOSE_FILE"
}

@test "env template does not contain a real registration token" {
  grep -q "FORGEJO_RUNNER_REGISTRATION_TOKEN=" "$ENV_TEMPLATE"
  ! grep -qE 'FORGEJO_RUNNER_REGISTRATION_TOKEN=.+[A-Za-z0-9]{20,}' "$ENV_TEMPLATE"
}

@test "runner state persists in a named volume" {
  grep -q "forgejo-runner-data:" "$COMPOSE_FILE"
  grep -q "forgejo-runner-data:/data" "$COMPOSE_FILE"
}

@test "docker socket mount is explicit and documented as high risk" {
  grep -q "/var/run/docker.sock:/var/run/docker.sock" "$COMPOSE_FILE"
  grep -qi "docker socket" "$README_FILE"
  grep -qi "high-risk" "$README_FILE"
}

@test "compose includes no-new-privileges hardening" {
  grep -q "no-new-privileges:true" "$COMPOSE_FILE"
}

@test "service files do not use latest tags" {
  ! grep -R --line-number -E '(:latest|@latest)' "$RUNNER_DIR"
}

@test "readme mentions runner credentials and labels" {
  grep -q ".runner" "$README_FILE"
  grep -q "docker:docker://node:20-bullseye" "$README_FILE"
}
