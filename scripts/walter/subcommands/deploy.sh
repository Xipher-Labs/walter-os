#!/usr/bin/env bash
# walter deploy <service>  — pull + recreate a service on Walter-VM
set -euo pipefail
WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
source "$WALTER_OS_HOME/scripts/walter/lib/log.sh"

svc="${1:-}"
if [[ -z "$svc" ]]; then
  log_err "Usage: walter deploy <service>"
  echo "Known services on VM:"
  ssh walter-vm 'ls /opt/walter-vm/services/' 2>/dev/null || true
  exit 2
fi

log_step "Deploy: $svc"

# 1. Push compose if changed
if [[ -d "$WALTER_OS_HOME/setup/walter-host/services/$svc" ]]; then
  log_info "Pushing compose + configs from repo..."
  rsync -aP --exclude='.env' --exclude='._*' \
    "$WALTER_OS_HOME/setup/walter-host/services/$svc/" \
    "walter-vm:/tmp/$svc-deploy/" 2>&1 | tail -5
  ssh walter-vm "sudo rsync -a --exclude='.env' /tmp/$svc-deploy/ /opt/walter-vm/services/$svc/ && rm -rf /tmp/$svc-deploy"
fi

# 2. Pull + up
ssh walter-vm "cd /opt/walter-vm/services/$svc && \
  sudo docker compose pull 2>&1 | tail -3 && \
  if [[ -f .env ]]; then \
    sudo docker compose --env-file .env up -d 2>&1 | tail -5; \
  else \
    sudo docker compose up -d 2>&1 | tail -5; \
  fi"

log_info "Verifying..."
sleep 5
ssh walter-vm "sudo docker ps --filter 'name=$svc' --format '{{.Names}}\t{{.Status}}'"

log_ok "Done"
