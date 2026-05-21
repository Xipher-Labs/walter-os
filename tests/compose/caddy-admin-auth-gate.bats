#!/usr/bin/env bats
# tests/compose/caddy-admin-auth-gate.bats
#
# Issue #116: every admin dashboard imports admin_auth_gate; sites
# that are deliberately public (Matrix federation, PostHog event
# ingestion, etc.) do NOT have it (so they stay reachable for their
# legitimate use case).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CADDYFILE="$REPO_ROOT/setup/caddy/Caddyfile.template"
  [[ -f "$CADDYFILE" ]] || skip "Caddyfile.template missing"
}

# Sites that MUST import admin_auth_gate (admin / internal-use surfaces).
# Adding a new admin site to the Caddyfile.template means adding it here too.
ADMIN_SITES="plane git secrets llm grafana n8n status home sync headscale-admin vpn postiz metabase penpot draw claw"

# Sites that MUST NOT import admin_auth_gate (genuinely public).
# Reasoning per site captured in issue #116.
PUBLIC_SITES="headscale posthog matrix chat-matrix chat"

# -----------------------------------------------------------------------
# AC1: the admin_auth_gate snippet is defined
# -----------------------------------------------------------------------
@test "AC1: Caddyfile defines (admin_auth_gate) snippet" {
  grep -qE '^\(admin_auth_gate\) \{' "$CADDYFILE"
}

# -----------------------------------------------------------------------
# AC2: snippet has the @not_authed matcher with both negations
# -----------------------------------------------------------------------
@test "AC2: snippet rejects requests without Tailscale IP AND CF Access header" {
  grep -qE 'not remote_ip.*WALTER_TAILNET_CIDR' "$CADDYFILE"
  grep -qE 'not header CF-Access-Authenticated-User-Email' "$CADDYFILE"
}

# -----------------------------------------------------------------------
# AC3: every admin site imports admin_auth_gate
# -----------------------------------------------------------------------
@test "AC3: every admin site imports admin_auth_gate" {
  missing=""
  for site in $ADMIN_SITES; do
    # Look for the site block + check the next 4 lines for the import
    block=$(awk -v site="$site" '
      $0 ~ "^" site "\\.\\$\\{WALTER_DOMAIN\\} \\{" {flag=1; n=0}
      flag && n<4 {print; n++}
      flag && $0 ~ "^\\}$" {flag=0}
    ' "$CADDYFILE")
    if ! grep -qE "import admin_auth_gate" <<<"$block"; then
      missing="${missing} ${site}"
    fi
  done
  if [ -n "$missing" ]; then
    printf "Missing import admin_auth_gate in:%s\n" "$missing" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# AC4: NO public site imports admin_auth_gate (they need to stay public)
# -----------------------------------------------------------------------
@test "AC4: public sites do NOT import admin_auth_gate" {
  contaminated=""
  for site in $PUBLIC_SITES; do
    block=$(awk -v site="$site" '
      $0 ~ "^" site "\\.\\$\\{WALTER_DOMAIN\\} \\{" {flag=1; n=0}
      flag && n<6 {print; n++}
      flag && $0 ~ "^\\}$" {flag=0}
    ' "$CADDYFILE")
    if grep -qE "import admin_auth_gate" <<<"$block"; then
      contaminated="${contaminated} ${site}"
    fi
  done
  if [ -n "$contaminated" ]; then
    printf "Public sites incorrectly have admin_auth_gate:%s\n" "$contaminated" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------
# AC5: total import count = number of admin sites (sanity check)
# -----------------------------------------------------------------------
@test "AC5: import count matches admin site count" {
  count=$(grep -cE 'import admin_auth_gate' "$CADDYFILE" || true)
  expected=$(echo "$ADMIN_SITES" | wc -w | tr -d ' ')
  [ "$count" -eq "$expected" ]
}
