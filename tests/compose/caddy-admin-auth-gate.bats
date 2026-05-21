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
ADMIN_SITES="plane git secrets llm grafana n8n status home sync headscale-admin vpn tower postiz metabase penpot draw claw"

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
# AC2: snippet's deny logic requires NEITHER an internal IP NOR a
# valid CF-edge-IP + CF-Access-header pair. Refined for Copilot R2
# #130 R2.3: assert all three deny paths exist (not in tailnet, CF
# edge without header, IPv6 coverage). Old broad-grep version could
# pass even if the assertions moved out of the snippet.
# -----------------------------------------------------------------------
@test "AC2: deny path 1 — request from outside tailnet AND outside CF edge → 403" {
  grep -qE '@deny_not_in_any_allowlist' "$CADDYFILE"
  grep -qE 'not remote_ip.*WALTER_TAILNET_CIDR.*WALTER_LAN_CIDR' "$CADDYFILE"
}

@test "AC2: deny path 2 — CF edge IP without CF Access header → 403" {
  grep -qE '@deny_cf_edge_without_header' "$CADDYFILE"
  grep -qE 'not header CF-Access-Authenticated-User-Email' "$CADDYFILE"
}

@test "AC2: CF IPv4 ranges (representative samples) present in compose default" {
  # CF ranges are now sourced from WALTER_CF_EDGE_RANGES (defined with
  # defaults in compose.yml). The Caddyfile uses {$WALTER_CF_EDGE_RANGES}
  # in both matchers, so verify the live default list lives in compose.
  local compose="$REPO_ROOT/compose.yml"
  [[ -f "$compose" ]] || skip "compose.yml missing"
  grep -qE '173\.245\.48\.0/20' "$compose"
  grep -qE '104\.16\.0\.0/13' "$compose"
  grep -qE '162\.158\.0\.0/15' "$compose"
}

@test "AC2: snippet includes CF IPv6 ranges (via WALTER_CF_EDGE_RANGES env var)" {
  # The Caddyfile references the ranges by env var; the actual list
  # lives in compose.yml as the default for WALTER_CF_EDGE_RANGES.
  # Assert (a) Caddyfile uses the env var in both matchers, and
  # (b) compose.yml's default list contains representative IPv6 ranges.
  grep -qE '\{\$WALTER_CF_EDGE_RANGES\}' "$CADDYFILE"
  local compose="$REPO_ROOT/compose.yml"
  [[ -f "$compose" ]] || skip "compose.yml missing"
  grep -qE '2400:cb00::/32' "$compose"
  grep -qE '2606:4700::/32' "$compose"
}

# AC2: Tailscale IPv6 ULA (Headscale default) included so v6 tailnet
# clients aren't denied at the auth gate. Copilot R3 #130 finding.
@test "AC2: WALTER_TAILNET_CIDR default covers Tailscale IPv6 ULA" {
  local compose="$REPO_ROOT/compose.yml"
  [[ -f "$compose" ]] || skip "compose.yml missing"
  grep -qE 'WALTER_TAILNET_CIDR.*fd7a:115c:a1e0::/48' "$compose"
}

# Codex R2 #130 MINOR: 172.16.0.0/12 (RFC1918) was missing from the
# default LAN CIDR, leaving common corporate LAN ranges denied even on
# the operator's own network.
@test "AC2: WALTER_LAN_CIDR default covers all 3 RFC1918 ranges" {
  local compose="$REPO_ROOT/compose.yml"
  [[ -f "$compose" ]] || skip "compose.yml missing"
  # 10/8 is in the snippet's static allowlist; 192.168/16 + 172.16/12
  # are the configurable WALTER_LAN_CIDR default.
  grep -qE 'WALTER_LAN_CIDR.*192\.168\.0\.0/16.*172\.16\.0\.0/12' "$compose"
}

# Codex R2 #130 BLOCKER: scripts/bootstrap.sh used envsubst without an
# allowlist, which would also expand Caddy's native `{$VAR}` placeholders
# (turning them into `{}` or `{<literal-value>}` and breaking matchers).
# Lock in the fix: envsubst gets a SHELL-FORMAT positional arg restricting
# expansion to only the bootstrap-time vars (WALTER_DOMAIN + ADMIN_EMAIL).
@test "AC2: bootstrap.sh envsubst uses explicit SHELL-FORMAT allowlist" {
  local bs="$REPO_ROOT/scripts/bootstrap.sh"
  [[ -f "$bs" ]] || skip "bootstrap.sh missing"
  # The envsubst invocation must pass an explicit '$VAR_LIST' argument
  # so non-listed $-references (Caddy's `{$VAR}` placeholders) survive.
  grep -qE "envsubst '\\\$WALTER_DOMAIN \\\$WALTER_ADMIN_EMAIL'" "$bs"
}

# -----------------------------------------------------------------------
# AC3: every admin site imports admin_auth_gate
# -----------------------------------------------------------------------
@test "AC3: every admin site imports admin_auth_gate" {
  # Extract each site block from the opening `<site>.${WALTER_DOMAIN} {`
  # line up to the matching closing `}` on its own line. Copilot R3 #130:
  # the previous fixed-window awk (n<4) was brittle — adding a directive
  # (e.g. header_up) inside an admin block could push `import` past the
  # window and silently break the test even with the import intact.
  missing=""
  for site in $ADMIN_SITES; do
    block=$(awk -v site="$site" '
      $0 ~ "^" site "\\.\\$\\{WALTER_DOMAIN\\} \\{" {flag=1}
      flag {print}
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
  # Same full-block extraction as AC3 (Copilot R3 #130) — robust to site
  # blocks growing additional directives over time.
  contaminated=""
  for site in $PUBLIC_SITES; do
    block=$(awk -v site="$site" '
      $0 ~ "^" site "\\.\\$\\{WALTER_DOMAIN\\} \\{" {flag=1}
      flag {print}
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
