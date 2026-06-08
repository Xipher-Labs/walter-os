#!/usr/bin/env bats
# Static regression coverage for the root all-in-one Headscale config path.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROOT_CONFIG="$REPO_ROOT/setup/headscale/config.yaml"
  ROOT_TEMPLATE="$REPO_ROOT/setup/headscale/config.yaml.template"
  HOST_TEMPLATE="$REPO_ROOT/setup/walter-host/services/headscale/config.yaml.template"
  HOST_COMPOSE="$REPO_ROOT/setup/walter-host/services/headscale/compose.yml"
  BOOTSTRAP="$REPO_ROOT/scripts/bootstrap.sh"
  COMPOSE="$REPO_ROOT/compose.yml"
  INSTALL="$REPO_ROOT/install.sh"
  CADDY_TEMPLATE="$REPO_ROOT/setup/caddy/Caddyfile.template"
  CF_TUNNEL="$REPO_ROOT/setup/walter-host/cloudflare/02-create-tunnel.sh"
  CF_ACCESS="$REPO_ROOT/setup/walter-host/cloudflare/04-create-access.sh"
  KNOWN_ISSUES="$REPO_ROOT/docs/operational/known-issues.md"
}

@test "root all-in-one Headscale config has a render template" {
  [[ -f "$ROOT_TEMPLATE" ]]
  grep -Fq 'server_url: https://headscale.${WALTER_DOMAIN}' "$ROOT_TEMPLATE"
}

@test "root and walter-host Headscale templates share the canonical server URL" {
  [[ -f "$ROOT_TEMPLATE" ]]
  [[ -f "$HOST_TEMPLATE" ]]

  local root_url host_url
  root_url="$(grep -E '^server_url:' "$ROOT_TEMPLATE")"
  host_url="$(grep -E '^server_url:' "$HOST_TEMPLATE")"

  [[ "$root_url" == "$host_url" ]]
}

@test "root Headscale template renders a concrete server URL" {
  command -v envsubst >/dev/null 2>&1 || skip "envsubst required for render check"
  [[ -f "$ROOT_TEMPLATE" ]]

  local rendered="$BATS_TEST_TMPDIR/headscale-config.yaml"
  WALTER_DOMAIN="example.test" envsubst '$WALTER_DOMAIN' < "$ROOT_TEMPLATE" > "$rendered"

  grep -Fq 'server_url: https://headscale.example.test' "$rendered"
  ! grep -Eq '\$\{[A-Z_][A-Z0-9_]*\}' "$rendered"
}

@test "root Headscale template uses the pinned 0.26 config schema shape" {
  [[ -f "$ROOT_TEMPLATE" ]]

  grep -Fq 'prefixes:' "$ROOT_TEMPLATE"
  grep -Fq 'database:' "$ROOT_TEMPLATE"
  grep -Fq 'type: sqlite' "$ROOT_TEMPLATE"
  grep -Fq 'path: /var/lib/headscale/db.sqlite' "$ROOT_TEMPLATE"
  grep -Fq 'noise:' "$ROOT_TEMPLATE"

  ! grep -Eq '^(ip_prefixes|db_type|db_path|private_key_path):' "$ROOT_TEMPLATE"
}

@test "root committed Headscale config does not hardcode example.com" {
  [[ -f "$ROOT_CONFIG" ]]
  ! grep -Fq 'headscale.example.com' "$ROOT_CONFIG"
}

@test "bootstrap renders the root Headscale config from its template" {
  [[ -f "$BOOTSTRAP" ]]

  grep -Fq 'setup/headscale/config.yaml.template' "$BOOTSTRAP"
  grep -Fq 'setup/headscale/config.yaml' "$BOOTSTRAP"
  grep -Fq 'envsubst "\$WALTER_DOMAIN"' "$BOOTSTRAP"
}

@test "bootstrap dry-run announces the Headscale render step" {
  [[ -f "$BOOTSTRAP" ]]

  local dry_run_block
  dry_run_block="$(sed -n '/DRY RUN/,/Dry-run complete/p' "$BOOTSTRAP")"

  grep -Fq 'Step 0b: Render Headscale config from template' <<<"$dry_run_block"
  grep -Fq "envsubst" <<<"$dry_run_block"
  grep -Fq 'setup/headscale/config.yaml.template > setup/headscale/config.yaml' <<<"$dry_run_block"
}

@test "install renders Headscale config before docker compose up" {
  [[ -f "$INSTALL" ]]

  local render_line compose_line
  render_line="$(grep -n 'setup/headscale/config.yaml.template' "$INSTALL" | head -1 | cut -d: -f1)"
  compose_line="$(grep -n 'docker compose -f "$compose_file" up -d' "$INSTALL" | head -1 | cut -d: -f1)"

  [[ -n "$render_line" ]]
  [[ -n "$compose_line" ]]
  [[ "$render_line" -lt "$compose_line" ]]
}

@test "root compose mounts the rendered Headscale config" {
  [[ -f "$COMPOSE" ]]

  grep -Fq './setup/headscale/config.yaml:/etc/headscale/config.yaml:ro' "$COMPOSE"
}

@test "Headscale service hostnames align across Caddy and Cloudflare" {
  [[ -f "$CADDY_TEMPLATE" ]]
  [[ -f "$CF_TUNNEL" ]]
  [[ -f "$CF_ACCESS" ]]

  grep -Fq 'headscale.${WALTER_DOMAIN}' "$CADDY_TEMPLATE"
  grep -Fq 'headscale-admin.${WALTER_DOMAIN}' "$CADDY_TEMPLATE"
  grep -Fq 'vpn.${WALTER_DOMAIN}' "$CADDY_TEMPLATE"

  grep -Eq '^[[:space:]]+headscale$' "$CF_TUNNEL"
  grep -Eq '^[[:space:]]+headscale-admin$' "$CF_TUNNEL"
  grep -Eq '^[[:space:]]+vpn$' "$CF_TUNNEL"

  local access_loop
  access_loop="$(sed -n '/for sub in /,/; do/p' "$CF_ACCESS")"
  grep -Fq 'headscale-admin' <<<"$access_loop"
  grep -Fq 'vpn' <<<"$access_loop"
  ! grep -Eq '(^|[[:space:]])hs(ui)?([[:space:]]|\\|$)' <<<"$access_loop"
  ! grep -Eq '(^|[[:space:]])wg([[:space:]]|\\|$)' <<<"$access_loop"
}

@test "standalone Headscale compose documents admin and client hostnames" {
  [[ -f "$HOST_COMPOSE" ]]

  grep -Fq 'URL admin: headscale-admin.${WALTER_DOMAIN}' "$HOST_COMPOSE"
  grep -Fq 'URL clients: headscale.${WALTER_DOMAIN}/derp + /key' "$HOST_COMPOSE"
}

@test "Headscale admin known issue uses current hostname" {
  [[ -f "$KNOWN_ISSUES" ]]

  grep -Fq 'https://headscale-admin.${WALTER_DOMAIN}/admin/' "$KNOWN_ISSUES"
  ! grep -Fq 'https://hs.${WALTER_DOMAIN}/admin/' "$KNOWN_ISSUES"
}
