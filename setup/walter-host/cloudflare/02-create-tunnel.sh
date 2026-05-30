#!/usr/bin/env bash
# 02-create-tunnel.sh — create the Walter-VM Cloudflare Tunnel + service CNAMEs.
#
# Architecture (closes #174 — operator-reported "grafana / matrix / posthog
# / element / etc unreachable on Walter-VM prod, 2026-05-22"):
#
#       internet                cloudflared        Caddy            container
#       --------                -----------        -----            ---------
#       https://...  --(TLS)--> :443 inside  -->  127.0.0.1:80 -->  forgejo:3000
#                                tunnel             (host port)      grafana:3000
#                                                                    matrix:8008
#                                                                    ...
#
# Cloudflared is the public TLS edge; Caddy is the internal reverse proxy
# that already knows the canonical subdomain → container map (see
# setup/caddy/Caddyfile.template). Routing through Caddy means the
# subdomain table lives in ONE place — no risk of cloudflared and Caddy
# drifting (the old config routed 8 subdomains directly to per-service
# host ports and left 15+ others publicly unreachable).
#
# Required env: CF_EMAIL, CF_KEY, CF_ACCOUNT, ZONE_ID
# Args: $1 = primary domain (e.g. example.com)
#
# Outputs:
#   /tmp/walter-cf/credentials.json — for upload to VM:/etc/cloudflared/
#   /tmp/walter-cf/config.yml       — for upload to VM:/etc/cloudflared/

set -euo pipefail

: "${CF_EMAIL:?must set CF_EMAIL}"
: "${CF_KEY:?must set CF_KEY}"
: "${CF_ACCOUNT:?must set CF_ACCOUNT}"
: "${ZONE_ID:?must set ZONE_ID}"

DOMAIN="${1:-${WALTER_DOMAIN:-example.com}}"
TUNNEL_NAME="${TUNNEL_NAME:-walter-vm}"

# ---------------------------------------------------------------------------
# Canonical subdomain list — single source of truth for what is publicly
# reachable. Must match site blocks in setup/caddy/Caddyfile.template
# (Caddy is the one that actually dispatches to the right container, so
# adding a subdomain here without a matching Caddy block makes Caddy
# return its default 404 — "no matching site" — for that hostname; a
# 502 only appears if a Caddy block DOES exist but its upstream
# container is unreachable).
#
# To add a new public service:
#   1. Add a site block in setup/caddy/Caddyfile.template
#   2. Add the subdomain to this list
#   3. tests/cloudflare/tunnel-ingress-caddy-routing.bats asserts parity
# ---------------------------------------------------------------------------
SUBDOMAINS=(
  chat
  chat-matrix
  claw
  draw
  git
  grafana
  headscale
  headscale-admin
  home
  llm
  matrix
  metabase
  n8n
  penpot
  plane
  posthog
  postiz
  secrets
  status
  sync
  tower
  vpn
)

cf() {
  curl -sS -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" "$@"
}

echo "==> Check if tunnel '$TUNNEL_NAME' exists..."
existing=$(cf "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false")
TUNNEL_ID=$(echo "$existing" | jq -r '.result[0].id // empty')

if [[ -n "$TUNNEL_ID" ]]; then
  echo "Tunnel exists: $TUNNEL_ID (re-using; can't reissue secret unless deleted)"
  echo "If you need fresh creds, delete the tunnel first via dashboard."
else
  TUNNEL_SECRET=$(openssl rand -base64 32)
  echo "==> Create tunnel '$TUNNEL_NAME'..."
  resp=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/cfd_tunnel" \
    -d "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$TUNNEL_SECRET\",\"config_src\":\"cloudflare\"}")
  TUNNEL_ID=$(echo "$resp" | jq -r '.result.id')
  if [[ -z "$TUNNEL_ID" || "$TUNNEL_ID" == "null" ]]; then
    echo "ERROR: $(echo "$resp" | jq -r '.errors')"
    exit 1
  fi

  mkdir -p /tmp/walter-cf
  cat > /tmp/walter-cf/credentials.json <<EOF
{
  "AccountTag": "$CF_ACCOUNT",
  "TunnelID": "$TUNNEL_ID",
  "TunnelSecret": "$TUNNEL_SECRET"
}
EOF
  chmod 600 /tmp/walter-cf/credentials.json
  echo "Tunnel created: $TUNNEL_ID"
  echo "Credentials saved to /tmp/walter-cf/credentials.json"
fi

echo
echo "==> Create CNAME records for service hostnames → tunnel..."
add_cname() {
  local name="$1"
  # idempotent — check first
  local existing=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$name&type=CNAME" \
    | jq -r '.result[0].id // empty')
  if [[ -n "$existing" ]]; then
    printf "  - %s (already exists)\n" "$name"
    return 0
  fi
  local r=$(cf -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -d "{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
  if [[ "$(echo "$r" | jq -r '.success')" == "true" ]]; then
    printf "  ✓ %s\n" "$name"
  else
    printf "  ✗ %s — %s\n" "$name" "$(echo "$r" | jq -r '.errors[0].message')"
  fi
}

# Iterate the canonical SUBDOMAINS array (single source of truth — keep
# in sync with the Caddyfile.template site blocks;
# tests/cloudflare/tunnel-ingress-caddy-routing.bats enforces).
# Same array also drives the ingress generation below — so CNAMEs and
# ingress can never silently drift. Tracking: issue #174 (Copilot R1).
for sub in "${SUBDOMAINS[@]}"; do
  add_cname "${sub}.${DOMAIN}"
done

echo
echo "==> Generate cloudflared config.yml..."
mkdir -p /tmp/walter-cf

# Emit one ingress entry per subdomain pointing at Caddy on host port 80.
# Caddy then dispatches via the Host header to the correct container
# (see setup/caddy/Caddyfile.template). All routing decisions live in
# Caddy — cloudflared only does TLS termination and host-based fan-in.
#
# Per-service overrides:
#   PostHog ships its own proxy on host port 8100. Its inner Caddy matches
#   `Host: localhost:8000`, so the tunnel must bypass the central Caddy for
#   this one service and rewrite the Host header. Keep the rest of the stack
#   routed through central Caddy on host port 80.
ingress_service_for() {
  case "$1" in
    posthog) printf 'http://127.0.0.1:8100' ;;
    *) printf 'http://127.0.0.1:80' ;;
  esac
}

ingress_origin_request_for() {
  case "$1" in
    posthog) printf '    originRequest:\n      httpHostHeader: localhost:8000\n' ;;
  esac
}

{
  printf 'tunnel: %s\n' "$TUNNEL_ID"
  printf 'credentials-file: /etc/cloudflared/credentials.json\n\n'
  printf 'ingress:\n'
  for sub in "${SUBDOMAINS[@]}"; do
    service_url="$(ingress_service_for "$sub")"
    printf '  - hostname: %s.%s\n' "$sub" "$DOMAIN"
    printf '    service: %s\n' "$service_url"
    ingress_origin_request_for "$sub"
  done
  printf '  - service: http_status:404\n'
} > /tmp/walter-cf/config.yml

echo "Config saved to /tmp/walter-cf/config.yml"
echo "TUNNEL_ID=$TUNNEL_ID" > /tmp/walter-cf/.env
echo
echo "==> Next: bash 03-install-cloudflared.sh <vm-ip>"
