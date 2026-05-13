#!/usr/bin/env bash
# deploy.sh — Synapse + element-web base. Bridges deployed separately.
set -euo pipefail

: "${WALTER_DOMAIN:?WALTER_DOMAIN required for Synapse deploy — source .env.local or secrets.env first}"
WALTER_MATRIX_USER="${WALTER_MATRIX_USER:-admin}"

SVC=/opt/walter-vm/services/synapse
cd "$SVC"

# 1. Generate .env if missing
if [[ ! -f .env ]]; then
  PASS=$(openssl rand -hex 24)
  cat > .env <<EOF
SYNAPSE_DB_PASS=$PASS
EOF
  chmod 600 .env
  echo "→ .env generated. PG password also pushed to Infisical."
fi

# 2. Generate Synapse homeserver.yaml on first boot
if [[ ! -f "$SVC/data/homeserver.yaml" ]] && [[ ! -d "$SVC/data" ]]; then
  echo "→ generating homeserver.yaml..."
  sudo mkdir -p "$SVC/data"
  sudo docker run --rm \
    -e SYNAPSE_SERVER_NAME="${WALTER_DOMAIN}" \
    -e SYNAPSE_REPORT_STATS=no \
    -v "$SVC/data:/data" \
    matrixdotorg/synapse:v1.119.0 generate
  # Patch homeserver.yaml: switch SQLite → Postgres + disable federation
  SVC="$SVC" WALTER_DOMAIN="$WALTER_DOMAIN" sudo -E python3 <<'PY'
import yaml, os
p = os.environ["SVC"] + "/data/homeserver.yaml"
walter_domain = os.environ["WALTER_DOMAIN"]
with open(p) as fh:
    cfg = yaml.safe_load(fh)
cfg['database'] = {
    'name': 'psycopg2',
    'args': {
        'user': 'synapse',
        'password': os.environ.get('SYNAPSE_DB_PASS'),
        'database': 'synapse',
        'host': 'synapse-db',
        'cp_min': 5,
        'cp_max': 10,
    },
}
cfg['federation_domain_whitelist'] = []
cfg['enable_registration'] = False
cfg['enable_registration_without_verification'] = False
cfg['suppress_key_server_warning'] = True
cfg['public_baseurl'] = f'https://matrix.{walter_domain}'
with open(p, 'w') as fh:
    yaml.dump(cfg, fh, default_flow_style=False, sort_keys=False)
print("homeserver.yaml patched OK")
PY
fi

# 3. Render Element config from template
ELEMENT_TPL="$SVC/element/config.json.template"
ELEMENT_CFG="$SVC/element/config.json"
if [[ -f "$ELEMENT_TPL" ]]; then
  envsubst < "$ELEMENT_TPL" > "$ELEMENT_CFG"
  echo "→ element/config.json rendered from template"
else
  echo "WARNING: $ELEMENT_TPL not found — Element config not rendered" >&2
fi

# 4. Bring up
sudo docker compose --env-file .env up -d
sleep 30

# 5. Status
sudo docker ps --filter 'name=synapse' --filter 'name=element' --format '{{.Names}}\t{{.Status}}'

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Synapse base deployed.

URLs (once cloudflared routes wired):
  https://matrix.${WALTER_DOMAIN}       — Synapse (clients + federation API)
  https://chat-matrix.${WALTER_DOMAIN}  — Element web client

Next steps:
  1. Create operator user:
     sudo docker exec -it synapse register_new_matrix_user \\
       -c /data/homeserver.yaml http://localhost:8008
  2. Add cloudflared routes (handled by parent deploy script).
  3. Login to Element with @${WALTER_MATRIX_USER}:${WALTER_DOMAIN}.

When ready for bridges, deploy mautrix-whatsapp / mautrix-telegram /
mautrix-imessage from setup/walter-host/services/beeper-self-hosted/.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
