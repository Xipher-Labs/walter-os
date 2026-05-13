#!/usr/bin/env bash
# 01-create-zone.sh — create the Cloudflare zone for a domain + import DNS records.
#
# Required env (source from ~/.config/walter-os/secrets.env):
#   CF_EMAIL, CF_KEY, CF_ACCOUNT
#
# Args:
#   $1 = domain (e.g. example.com)
#
# What it does:
#   1. Creates the zone in CF (if not present)
#   2. Outputs the assigned NS pair (set them at your registrar)
#   3. Queries the current authoritative nameservers for existing records
#   4. Imports A / AAAA / MX / CNAME / TXT records (skipping NS, SOA, and any
#      misconfigured DMARC at zone apex)
#
# Idempotent: safe to re-run. Records already in CF are skipped.

set -euo pipefail

: "${CF_EMAIL:?must set CF_EMAIL}"
: "${CF_KEY:?must set CF_KEY}"
: "${CF_ACCOUNT:?must set CF_ACCOUNT}"

DOMAIN="${1:?usage: $0 <domain>}"

cf() {
  curl -sS -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" -H "Content-Type: application/json" "$@"
}

echo "==> Checking if zone $DOMAIN already exists in CF..."
existing=$(cf "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN&account.id=$CF_ACCOUNT")
ZONE_ID=$(echo "$existing" | jq -r '.result[0].id // empty')

if [[ -z "$ZONE_ID" ]]; then
  echo "==> Creating zone $DOMAIN..."
  resp=$(cf -X POST "https://api.cloudflare.com/client/v4/zones" \
    -d "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT\"},\"jump_start\":false,\"type\":\"full\"}")
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    echo "ERROR: $(echo "$resp" | jq -r '.errors')"
    exit 1
  fi
  ZONE_ID=$(echo "$resp" | jq -r '.result.id')
fi

NS_PAIR=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" | jq -r '.result.name_servers | join(", ")')
STATUS=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" | jq -r '.result.status')

echo
echo "Zone:    $DOMAIN"
echo "ZoneID:  $ZONE_ID"
echo "Status:  $STATUS"
echo "NS pair: $NS_PAIR"
echo

# Save zone id for later scripts
echo "$ZONE_ID" > "/tmp/walter-cf-${DOMAIN}-zone-id"

echo "==> Querying existing records from current authoritative DNS..."
# Get existing NS to find authoritative server
auth_ns=$(dig +short NS "$DOMAIN" | head -1)
if [[ -z "$auth_ns" ]]; then
  echo "ERROR: no NS records found for ${DOMAIN}. Pass an explicit authoritative server with --ns <fqdn> or configure DNS before running this script." >&2
  exit 1
fi
echo "Using $auth_ns to read existing records"
echo

# Helper: add record to CF if not already present (matches by type + name + content prefix)
add_record_idempotent() {
  local type="$1" name="$2" content="$3" ttl="${4:-900}" priority="${5:-}" proxied="${6:-false}"

  # Check if record already exists
  local existing=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$type&name=$name" \
    | jq -r '.result[]? | "\(.type)\t\(.name)\t\(.content[0:40])"')
  local content_prefix=$(echo "$content" | head -c 40)

  if echo "$existing" | grep -qF "$content_prefix"; then
    echo "  - $type $name (already present)"
    return 0
  fi

  local payload="{\"type\":\"$type\",\"name\":\"$name\",\"content\":$(echo "$content" | jq -Rs .),\"ttl\":$ttl,\"proxied\":$proxied"
  [[ -n "$priority" ]] && payload+=",\"priority\":$priority"
  payload+="}"

  local result=$(cf -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -d "$payload")
  if [[ "$(echo "$result" | jq -r '.success')" == "true" ]]; then
    echo "  ✓ $type $name"
  else
    echo "  ✗ $type $name — $(echo "$result" | jq -r '.errors[0].message')"
  fi
}

# Read all relevant record types and import. Skip NS (CF replaces) and SOA (CF generates).
# Skip DMARC at apex if present (misconfig — DMARC belongs at _dmarc subdomain).

echo "==> Importing A records..."
dig @"$auth_ns" "$DOMAIN" A +short | while read -r ip; do
  [[ -n "$ip" ]] && add_record_idempotent A "$DOMAIN" "$ip"
done

echo "==> Importing MX records..."
dig @"$auth_ns" "$DOMAIN" MX +short | while read -r priority host; do
  [[ -n "$host" ]] && add_record_idempotent MX "$DOMAIN" "${host%.}" 900 "$priority"
done

echo "==> Importing TXT records (apex)..."
dig @"$auth_ns" "$DOMAIN" TXT +short | while IFS= read -r txt; do
  [[ -z "$txt" ]] && continue
  # Skip DMARC at apex (misconfig — must be at _dmarc.<domain>)
  if [[ "$txt" == *DMARC1* ]]; then
    echo "  - skipping DMARC at apex (must be at _dmarc.$DOMAIN — duplicated/misconfigured)"
    continue
  fi
  # Strip outer quotes from dig output
  txt_clean=$(echo "$txt" | sed 's/^"//; s/"$//')
  add_record_idempotent TXT "$DOMAIN" "$txt_clean"
done

echo "==> Importing TXT records (_dmarc)..."
dig @"$auth_ns" "_dmarc.$DOMAIN" TXT +short | while IFS= read -r txt; do
  [[ -z "$txt" ]] && continue
  txt_clean=$(echo "$txt" | sed 's/^"//; s/"$//')
  add_record_idempotent TXT "_dmarc.$DOMAIN" "$txt_clean"
done

echo "==> Importing common DKIM CNAMEs (mailchimp k2/k3, google) ..."
for sub in k1 k2 k3 google._domainkey selector1._domainkey selector2._domainkey; do
  cname=$(dig @"$auth_ns" "${sub}._domainkey.$DOMAIN" CNAME +short 2>/dev/null || true)
  [[ -z "$cname" ]] && continue
  add_record_idempotent CNAME "${sub}._domainkey.$DOMAIN" "${cname%.}"
done

# Mailchimp uses k2/k3 directly (without _domainkey suffix in their CNAMEs)
for sub in k2._domainkey k3._domainkey; do
  cname=$(dig @"$auth_ns" "${sub}.$DOMAIN" CNAME +short 2>/dev/null || true)
  [[ -z "$cname" ]] && continue
  add_record_idempotent CNAME "${sub}.$DOMAIN" "${cname%.}"
done

echo
echo "==> Done. Zone: $DOMAIN (status: $STATUS)"
echo "==> NEXT STEP: change nameservers at your registrar to:"
echo "    $NS_PAIR"
echo "==> Then wait for status to become 'active' (CF auto-detects NS change)."
echo "==> Verify with: curl -sS -H \"X-Auth-Email: $CF_EMAIL\" -H \"X-Auth-Key: $CF_KEY\" \\"
echo "       https://api.cloudflare.com/client/v4/zones/$ZONE_ID | jq .result.status"
