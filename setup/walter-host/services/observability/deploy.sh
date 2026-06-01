#!/usr/bin/env bash
# deploy.sh — bring up Grafana + Prometheus + Loki + Promtail + node-exporter + cAdvisor
set -euo pipefail

SVC_DIR="${SVC_DIR:-/opt/walter-vm/services/observability}"
ENV_FILE="$SVC_DIR/.env"

cd "$SVC_DIR"

# 1. Generate .env if missing
if [[ ! -f "$ENV_FILE" ]]; then
  cp .env.template "$ENV_FILE"
  GF_PASS=$(openssl rand -hex 16)
  sed -i "s|^GF_ADMIN_PASSWORD=.*|GF_ADMIN_PASSWORD=$GF_PASS|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Grafana admin password generated:
  user: admin
  pass: $GF_PASS

Save to Infisical workspace=walter-vm-internal env=prod key=GF_ADMIN_PASSWORD.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
fi

if [[ -z "${OBSERVABILITY_DATA_DIR:-}" ]]; then
  OBSERVABILITY_DATA_DIR="$(sed -n 's/^OBSERVABILITY_DATA_DIR=//p' "$ENV_FILE" | tail -n 1)"
fi
export OBSERVABILITY_DATA_DIR="${OBSERVABILITY_DATA_DIR:-/mnt/walter-vm-data/observability}"
DATA_DIR="$OBSERVABILITY_DATA_DIR"

# 2. Make sure data dirs exist on the volume + UID match
sudo install -d -m 755 "$DATA_DIR" \
  "$DATA_DIR/prometheus" \
  "$DATA_DIR/loki" \
  "$DATA_DIR/grafana"
sudo install -d -m 700 "$DATA_DIR/promtail"
# Loki container runs as 10001:10001
sudo chown -R 10001:10001 "$DATA_DIR/loki"
# Grafana container runs as 472:472
sudo chown -R 472:472 "$DATA_DIR/grafana"
# Prometheus container runs as 65534:65534 (nobody)
sudo chown -R 65534:65534 "$DATA_DIR/prometheus"
# Promtail used /tmp/promtail-positions.yaml before the positions file moved
# onto the host data volume. Preserve it once when upgrading an existing
# container so redeploys do not re-tail already-scraped logs.
if sudo test ! -f "$DATA_DIR/promtail/promtail-positions.yaml" \
  && sudo docker container inspect promtail >/dev/null 2>&1; then
  if sudo docker cp promtail:/tmp/promtail-positions.yaml "$DATA_DIR/promtail/promtail-positions.yaml" 2>/dev/null; then
    echo "→ migrated promtail positions to $DATA_DIR/promtail/promtail-positions.yaml"
  else
    echo "→ no legacy /tmp/promtail-positions.yaml found; promtail will create a new positions file"
  fi
fi

# 3. Bring up
sudo docker compose --env-file "$ENV_FILE" up -d

# 4. Wait for Grafana healthy
echo "→ waiting for Grafana healthy..."
for _ in $(seq 1 30); do
  status=$(sudo docker inspect --format '{{.State.Health.Status}}' grafana 2>/dev/null || echo unknown)
  [[ "$status" == "healthy" ]] && break
  sleep 5
done
[[ "$status" != "healthy" ]] && { echo "✗ grafana not healthy"; sudo docker logs --tail 30 grafana; exit 1; }

cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Observability stack up.

Endpoints:
  Grafana:    https://grafana.${WALTER_DOMAIN}   (CF Access → @${WALTER_DOMAIN})
  Prometheus: internal only (obs_net), targets via Grafana
  Loki:       internal only

Datasources auto-provisioned (Prometheus + Loki).
Dashboards: import from Grafana.com IDs:
  1860  — Node Exporter Full
  893   — Docker / cAdvisor
  20712 — Loki logs explorer
  3590  — Loki logs panel

Telegram alerting: Grafana Settings → Notification policies → add Telegram
contact point with bot token + chat_id (already in /etc/walter-vm/alerting.env)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
