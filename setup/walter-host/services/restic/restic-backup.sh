#!/usr/bin/env bash
# restic-backup.sh — Walter-VM nightly backup.
#
# Two repos, defense-in-depth:
#   PRIMARY:   /mnt/walter-vm-data/restic-local        (Cloud Volume — fast restore, same DC)
#   SECONDARY: rclone:gdrive:walter-vm-backup          (off-provider, real off-site)
#
# Schedule: every night 02:00 BA (cron). Daily incremental + weekly prune.
# Verifies once a month with --read-data-subset=10%.
#
# Install:
#   sudo cp restic-backup.sh /opt/walter-vm/services/restic/
#   sudo cp /etc/cron.d/walter-restic restic-cron.example   # see end of this file
#
# Required env (in /etc/walter-vm/restic.env):
#   RESTIC_PASSWORD              — encryption passphrase (KEEP SAFE; loss = unrecoverable backup)
#   RESTIC_REPO_LOCAL            — /mnt/walter-vm-data/restic-local
#   RESTIC_REPO_REMOTE           — rclone:gdrive:walter-vm-backup
#   RESTIC_CACHE_DIR             — /mnt/walter-vm-data/restic-cache
#   WALTER_TELEGRAM_BOT_TOKEN    — for completion / failure alerts
#   WALTER_TELEGRAM_CHAT_ID

set -euo pipefail

ENV_FILE="${WALTER_RESTIC_ENV:-/etc/walter-vm/restic.env}"
[[ -f "$ENV_FILE" ]] || { echo "missing env: $ENV_FILE"; exit 2; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${RESTIC_PASSWORD:?required}"
: "${RESTIC_REPO_LOCAL:?required}"
: "${RESTIC_REPO_REMOTE:?required}"
: "${RESTIC_CACHE_DIR:?required}"

# Same passphrase for source + destination repos (restic `copy` needs both).
RESTIC_FROM_PASSWORD="$RESTIC_PASSWORD"
export RESTIC_PASSWORD RESTIC_FROM_PASSWORD RESTIC_CACHE_DIR

LOG_DIR="/var/log/walter-vm-restic"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%F).log"

notify() {
  local msg="$1"
  if [[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]]; then
    curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$msg" \
      -d "parse_mode=Markdown" >/dev/null 2>&1 || true
  fi
}

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

# ---------- what to back up ----------
TARGETS=(
  /var/lib/docker/volumes
  /opt/walter-vm
  /etc/walter-vm
  /etc/cloudflared
  /etc/letsencrypt
  /etc/caddy
  /etc/fstab
  /etc/passwd
  /etc/group
  /etc/shadow
  /home/walter
)

EXCLUDES=(
  --exclude='*.log'
  --exclude='*.pid'
  --exclude='*.sock'
  --exclude='/var/lib/docker/volumes/backingFsBlockDev'
  --exclude='/var/lib/docker/volumes/metadata.db*'
  --exclude='*/node_modules'
  --exclude='*/.cache'
  --exclude='*/restic-cache/**'   # don't back up the cache (recursive)
  --exclude-caches
)

# ---------- INIT repos if first run ----------
init_if_needed() {
  local repo="$1"
  if ! restic -r "$repo" snapshots >/dev/null 2>&1; then
    log "init repo: $repo"
    restic -r "$repo" init
  fi
}

# ---------- backup ----------
mode="${1:-daily}"       # daily | weekly | verify

case "$mode" in
  daily)
    log "==> backup START (mode=daily)"
    init_if_needed "$RESTIC_REPO_LOCAL"

    log "→ backup to PRIMARY ($RESTIC_REPO_LOCAL)"
    restic -r "$RESTIC_REPO_LOCAL" backup \
      --tag walter-vm --tag daily \
      "${EXCLUDES[@]}" \
      "${TARGETS[@]}" 2>&1 | tee -a "$LOG_FILE"

    log "→ forget+prune PRIMARY (keep last 7 daily, 4 weekly, 12 monthly)"
    restic -r "$RESTIC_REPO_LOCAL" forget \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 12 \
      --tag walter-vm --prune 2>&1 | tee -a "$LOG_FILE"

    log "→ mirror PRIMARY → SECONDARY (rclone copy)"
    init_if_needed "$RESTIC_REPO_REMOTE"
    restic -r "$RESTIC_REPO_REMOTE" copy \
      --from-repo "$RESTIC_REPO_LOCAL" \
      --tag walter-vm 2>&1 | tee -a "$LOG_FILE"

    log "✅ backup OK"
    notify "✅ *Walter-VM backup* complete ($(date +%F))"
    ;;

  verify)
    log "==> integrity check (10% subset)"
    restic -r "$RESTIC_REPO_LOCAL" check --read-data-subset=10% 2>&1 | tee -a "$LOG_FILE"
    restic -r "$RESTIC_REPO_REMOTE" check 2>&1 | tee -a "$LOG_FILE"
    log "✅ verify OK"
    notify "✅ *Walter-VM restic verify* complete"
    ;;

  weekly)
    log "==> SECONDARY repo prune (Drive)"
    restic -r "$RESTIC_REPO_REMOTE" forget \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 12 \
      --tag walter-vm --prune 2>&1 | tee -a "$LOG_FILE"
    log "✅ weekly prune OK"
    ;;

  *)
    echo "Usage: $0 {daily|verify|weekly}" >&2
    exit 2 ;;
esac

# Trap failure
trap 'rc=$?; log "✗ FAILED (exit $rc)"; notify "🚨 *Walter-VM backup FAILED* — see $LOG_FILE"; exit $rc' ERR
