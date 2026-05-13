#!/usr/bin/env bash
# 02-create-tunnel.sh — create the Walter-VM Cloudflare Tunnel + service CNAMEs.
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

for sub in vault llm plane git status home secrets uptime; do
  add_cname "${sub}.${DOMAIN}"
done

echo
echo "==> Generate cloudflared config.yml..."
mkdir -p /tmp/walter-cf
cat > /tmp/walter-cf/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: vault.${DOMAIN}
    service: http://127.0.0.1:8222
  - hostname: llm.${DOMAIN}
    service: http://127.0.0.1:4000
  - hostname: plane.${DOMAIN}
    service: http://127.0.0.1:8090
  - hostname: git.${DOMAIN}
    service: http://127.0.0.1:3000
  - hostname: status.${DOMAIN}
    service: http://127.0.0.1:3001
  - hostname: home.${DOMAIN}
    service: http://127.0.0.1:3010
  - hostname: secrets.${DOMAIN}
    service: http://127.0.0.1:8800
  - hostname: uptime.${DOMAIN}
    service: http://127.0.0.1:3001
  - service: http_status:404
EOF

echo "Config saved to /tmp/walter-cf/config.yml"
echo "TUNNEL_ID=$TUNNEL_ID" > /tmp/walter-cf/.env
echo
echo "==> Next: bash 03-install-cloudflared.sh <vm-ip>"
