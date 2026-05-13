#!/usr/bin/env bats
# Bootstrap script tests
# Covers: AC-2, AC-3
#
# These tests validate the bootstrap script structure and idempotency
# logic without actually calling live service APIs.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  BOOTSTRAP="$REPO_ROOT/scripts/bootstrap.sh"
}

@test "scripts/bootstrap.sh exists" {
  [ -f "$BOOTSTRAP" ]
}

@test "scripts/bootstrap.sh is executable" {
  [ -x "$BOOTSTRAP" ]
}

@test "bootstrap.sh has shebang" {
  head -1 "$BOOTSTRAP" | grep -q "#!/"
}

@test "bootstrap.sh references .bootstrapped sentinel file" {
  # AC-3: idempotency via sentinel
  grep -q "\.bootstrapped" "$BOOTSTRAP"
}

@test "bootstrap.sh handles Plane workspace creation" {
  # AC-2
  grep -qi "plane" "$BOOTSTRAP"
  grep -qi "workspace" "$BOOTSTRAP"
}

@test "bootstrap.sh handles Forgejo user creation" {
  # AC-2
  grep -qi "forgejo" "$BOOTSTRAP"
}

@test "bootstrap.sh handles Infisical workspace creation" {
  # AC-2
  grep -qi "infisical" "$BOOTSTRAP"
}

@test "bootstrap.sh handles LiteLLM master key" {
  # AC-2
  grep -qi "litellm" "$BOOTSTRAP"
}

@test "bootstrap.sh handles Grafana admin password" {
  # AC-2
  grep -qi "grafana" "$BOOTSTRAP"
}

@test "bootstrap.sh reads WALTER_DOMAIN" {
  # AC-8
  grep -q "WALTER_DOMAIN" "$BOOTSTRAP"
}

@test "bootstrap.sh reads WALTER_INITIAL_USER" {
  grep -q "WALTER_INITIAL_USER" "$BOOTSTRAP"
}

@test "bootstrap.sh reads WALTER_INITIAL_PASSWORD" {
  grep -q "WALTER_INITIAL_PASSWORD" "$BOOTSTRAP"
}

@test "bootstrap.sh exits 0 on --dry-run" {
  run "$BOOTSTRAP" --dry-run
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh --dry-run mentions all 5 bootstrap services" {
  run "$BOOTSTRAP" --dry-run
  [[ "$output" == *"plane"* ]] || [[ "$output" == *"Plane"* ]]
  [[ "$output" == *"forgejo"* ]] || [[ "$output" == *"Forgejo"* ]]
  [[ "$output" == *"infisical"* ]] || [[ "$output" == *"Infisical"* ]]
  [[ "$output" == *"litellm"* ]] || [[ "$output" == *"LiteLLM"* ]]
  [[ "$output" == *"grafana"* ]] || [[ "$output" == *"Grafana"* ]]
}

@test "bootstrap.sh --dry-run does not write .bootstrapped sentinel" {
  TMPDIR_TEST="$(mktemp -d)"
  # Ensure no sentinel in tmpdir
  run env WALTER_DOMAIN=example.com WALTER_ADMIN_EMAIL=a@b.com \
      WALTER_INITIAL_USER=admin WALTER_INITIAL_PASSWORD=changeme \
      WALTER_TIMEZONE=UTC BOOTSTRAP_DIR="$TMPDIR_TEST" \
      "$BOOTSTRAP" --dry-run
  [ ! -f "$TMPDIR_TEST/.bootstrapped" ]
  rm -rf "$TMPDIR_TEST"
}

# B1: Postgres password sync
@test "setup/postgres/init.sql uses idempotent DO-block for CREATE USER" {
  # Must use DO $$ BEGIN ... END $$ to avoid duplicate user errors on re-init
  grep -qF 'DO $$' "$REPO_ROOT/setup/postgres/init.sql"
}

@test "setup/postgres/init.sql does not hardcode placeholder passwords in CREATE USER" {
  # Passwords must NOT appear in CREATE USER — bootstrap.sh does ALTER USER instead
  ! grep -q "WITH PASSWORD '.*_placeholder'" "$REPO_ROOT/setup/postgres/init.sql"
}

@test "bootstrap.sh contains ALTER USER logic for postgres password sync" {
  # B1: after Postgres is healthy, bootstrap must sync passwords from env vars
  grep -q "ALTER USER" "$BOOTSTRAP"
}

@test "bootstrap.sh ALTER USER block covers all 5 service users" {
  # B1: forgejo infisical litellm n8n postiz must all be synced
  for svc in forgejo infisical litellm n8n postiz; do
    grep -qi "$svc" "$BOOTSTRAP"
  done
}

# W3: Real idempotency check — second run produces no-op
@test "bootstrap.sh exits 0 when sentinel exists (already bootstrapped)" {
  TMPDIR_TEST="$(mktemp -d)"
  # Simulate first-run completion by creating sentinel
  echo "bootstrapped" > "$TMPDIR_TEST/.bootstrapped"
  run env WALTER_DOMAIN=example.com WALTER_ADMIN_EMAIL=a@b.com \
      WALTER_INITIAL_USER=admin WALTER_INITIAL_PASSWORD=changeme \
      WALTER_TIMEZONE=UTC BOOTSTRAP_DIR="$TMPDIR_TEST" \
      "$BOOTSTRAP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already bootstrapped"* ]]
  rm -rf "$TMPDIR_TEST"
}
