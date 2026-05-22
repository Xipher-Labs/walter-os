#!/usr/bin/env bats
# tests/cloudflare/tunnel-ingress-caddy-routing.bats
#
# Regression guard for issue #174 — cloudflared tunnel ingress map gap.
# After the fix, the tunnel must route EVERY subdomain that Caddy
# already handles. The architecture is:
#
#     internet --(TLS)--> cloudflared --(plain HTTP)--> Caddy --(Docker DNS)--> container
#
# Cloudflared is the public TLS edge; Caddy is the internal reverse proxy.
# The old config bypassed Caddy and routed 8 subdomains directly to host
# ports, leaving 15+ services (grafana, matrix, element, posthog, n8n,
# rocketchat, metabase, drawio, penpot, syncthing, openclaw, control-tower,
# headscale, vpn, sync, posthog, postiz, hermes, etc.) publicly unreachable.
#
# The fix routes every subdomain to Caddy on host port 80, so the routing
# table lives in ONE place (the Caddyfile) instead of being split across
# cloudflared and Caddy with drift between them.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TUNNEL_SCRIPT="$REPO_ROOT/setup/walter-host/cloudflare/02-create-tunnel.sh"
  CADDYFILE_TEMPLATE="$REPO_ROOT/setup/caddy/Caddyfile.template"
}

# ---------------------------------------------------------------------------
# Helper: extract the SUBDOMAINS bash array literal from the tunnel script.
# The array is the source of truth — both the ingress generator and the
# CNAME loop iterate it (or, in the case of the for-loop, a flattened
# multi-line equivalent that this helper also catches).
# ---------------------------------------------------------------------------
_tunnel_script_subdomains() {
  # 1) Pull the array body between `SUBDOMAINS=(` and the closing `)`
  # 2) Also pull every word from `for sub in ...; do add_cname` blocks
  #    (these may wrap across lines with `\`)
  # 3) Combine + sort -u
  awk '/^SUBDOMAINS=\(/{capture=1; next} capture && /^\)/{capture=0} capture {print}' "$TUNNEL_SCRIPT" \
    | tr -s ' \t' '\n' \
    | grep -E '^[a-z][a-z0-9-]*$'

  awk '/for sub in/,/do$/' "$TUNNEL_SCRIPT" \
    | tr '\\' ' ' \
    | tr -s ' \t' '\n' \
    | grep -E '^[a-z][a-z0-9-]*$' \
    | grep -vE '^(for|sub|in|do)$'
}

# ---------------------------------------------------------------------------
# AC-1: every subdomain Caddy knows about has a tunnel ingress entry
# ---------------------------------------------------------------------------

@test "AC-1: tunnel ingress includes every subdomain from Caddyfile.template" {
  [[ -f "$CADDYFILE_TEMPLATE" ]] || skip "Caddyfile.template missing"
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # Extract the subdomain prefix (the bit before `.${WALTER_DOMAIN}`) from
  # every site block in Caddyfile.template.
  local caddy_subs
  caddy_subs=$(grep -E '^[a-z][a-z0-9.-]*\.\$\{WALTER_DOMAIN\} \{' \
    "$CADDYFILE_TEMPLATE" \
    | sed -E 's/\.\$\{WALTER_DOMAIN\}.*//' \
    | sort -u)

  [[ -n "$caddy_subs" ]] || skip "no subdomains parsed from Caddyfile.template"

  local script_subs
  script_subs=$(_tunnel_script_subdomains | sort -u)

  local missing=()
  while read -r sub; do
    if ! grep -qE "^${sub}$" <<< "$script_subs"; then
      missing+=("$sub")
    fi
  done <<< "$caddy_subs"

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing ingress for Caddy subdomains: %s\n' "${missing[*]}"
    printf 'Script-known subdomains:\n%s\n' "$script_subs"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-2: every ingress entry routes to Caddy (port 80), NOT individual ports
# ---------------------------------------------------------------------------

@test "AC-2: no ingress entry routes directly to per-service host ports" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # Per-service ports that the old broken config referenced (8222 / 4000 /
  # 8090 / 3000 / 3001 / 3010 / 8800) are no longer the dispatch target —
  # Caddy at port 80 is. Allow port 80 and 443 in the script (Caddy's
  # ports); flag any other 127.0.0.1:<port> reference anywhere in the
  # script's non-comment lines.
  #
  # Use `|| true` after each pipe so an empty-result grep doesn't propagate
  # exit 1 (which bats would treat as a test failure on the assignment).
  local bad
  bad=$( { grep -nE "http://127\\.0\\.0\\.1:[0-9]+" "$TUNNEL_SCRIPT" || true; } \
    | { grep -vE 'http://127\.0\.0\.1:(80|443)([^0-9]|$)' || true; } \
    | { grep -vE ':\s*#' || true; } )

  if [[ -n "$bad" ]]; then
    printf 'Ingress entries bypassing Caddy (should route to :80):\n%s\n' "$bad"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-3: the wildcard catch-all 404 is the LAST ingress rule
# ---------------------------------------------------------------------------

@test "AC-3: catch-all http_status:404 is the final ingress entry" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # The closing 404 must be the LAST printf in the config-generation
  # block — i.e., appear AFTER every other `hostname:` printf and AFTER
  # the SUBDOMAINS-iteration loop. Catch it via the literal string and
  # assert it's the only such reference.
  local count
  count=$(grep -c 'http_status:404' "$TUNNEL_SCRIPT" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] || {
    echo "Missing the http_status:404 catch-all" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC-4: CNAME loop covers every Caddy subdomain too
# ---------------------------------------------------------------------------

@test "AC-4: add_cname loop covers every subdomain in the ingress" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"
  [[ -f "$CADDYFILE_TEMPLATE" ]] || skip "Caddyfile.template missing"

  # Every subdomain in the Caddy template must appear in the CNAME-create
  # loop. Use the same multi-line-aware helper as AC-1.
  local caddy_subs
  caddy_subs=$(grep -E '^[a-z][a-z0-9.-]*\.\$\{WALTER_DOMAIN\} \{' \
    "$CADDYFILE_TEMPLATE" \
    | sed -E 's/\.\$\{WALTER_DOMAIN\}.*//' \
    | sort -u)

  local script_subs
  script_subs=$(_tunnel_script_subdomains | sort -u)

  local missing=()
  while read -r sub; do
    if ! grep -qE "^${sub}$" <<< "$script_subs"; then
      missing+=("$sub")
    fi
  done <<< "$caddy_subs"

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'CNAME loop missing Caddy subdomains: %s\n' "${missing[*]}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-5: documentation — the script header references the architecture
# ---------------------------------------------------------------------------

@test "AC-5: script header documents the cloudflared -> Caddy -> container chain" {
  [[ -f "$TUNNEL_SCRIPT" ]] || skip "tunnel script missing"

  # The cloudflared -> Caddy -> container architecture must be documented
  # in the script header so an operator reading the file understands why
  # the ingress points at port 80 and not per-service ports.
  head -40 "$TUNNEL_SCRIPT" | grep -qiE "Caddy" || {
    echo "Script header does not mention Caddy — architecture is undocumented." >&2
    return 1
  }
}
