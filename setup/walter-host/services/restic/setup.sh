#!/usr/bin/env bash
# setup.sh — one-shot setup for restic on Walter-VM.
# Run on the VM after rclone:gdrive remote is configured (see RCLONE-SETUP.md).
#
#   ssh walter-vm 'sudo bash -s' < setup.sh
#
# Prereqs (already done by bootstrap-vm.sh):
#   - restic + rclone installed
#   - /mnt/walter-vm-data Cloud Volume mounted
#
# Operator must do BEFORE running this:
#   1. `rclone config` on the VM, create remote named `gdrive` (Google Drive),
#      OAuth headless via paste-token. See RCLONE-SETUP.md.
#   2. Create a strong restic passphrase, save in 1Password / Bitwarden / Infisical.
#      Loss = total backup loss. NO recovery.

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then echo "must run as root"; exit 1; fi

WALTER_DATA="/mnt/walter-vm-data"
[[ -d "$WALTER_DATA" ]] || { echo "Volume not mounted at $WALTER_DATA"; exit 2; }

# 1. Layout dirs
install -d -m 700 -o walter -g walter \
  "$WALTER_DATA/restic-local" \
  "$WALTER_DATA/restic-cache" \
  /opt/walter-vm/services/restic
install -d -m 700 /etc/walter-vm

# 2. Verify rclone gdrive remote is set up
if ! sudo -u walter rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
  cat <<'EOF'
✗ rclone remote 'gdrive' not found. Configure first:

   sudo -u walter rclone config

   - n) New remote
   - name: gdrive
   - type: drive
   - client_id: (leave blank — uses rclone's, fine for personal)
   - scope: drive
   - root_folder_id: (leave blank, or paste a specific folder ID)
   - service_account_file: (blank)
   - auto config: NO (headless — paste token from another machine)
   - On your Mac, run: rclone authorize "drive"
     it opens a browser, gets a token, prints it. Paste back in VM.
   - Configure as Shared Drive: NO (use personal)

After that, re-run: sudo bash setup.sh
EOF
  exit 2
fi

# 3. Verify the gdrive folder exists (or create)
if ! sudo -u walter rclone lsd gdrive: 2>/dev/null | grep -q walter-vm-backup; then
  echo "→ creating gdrive:walter-vm-backup folder"
  sudo -u walter rclone mkdir gdrive:walter-vm-backup
fi

# 4. Generate restic.env if missing
ENV_FILE="/etc/walter-vm/restic.env"
if [[ ! -f "$ENV_FILE" ]]; then
  PASS=$(openssl rand -hex 32)
  cat > "$ENV_FILE" <<EOF
# Walter-VM restic config — DO NOT commit. Loss of RESTIC_PASSWORD = unrecoverable.
RESTIC_PASSWORD=$PASS
RESTIC_REPO_LOCAL=$WALTER_DATA/restic-local
RESTIC_REPO_REMOTE=rclone:gdrive:walter-vm-backup
RESTIC_CACHE_DIR=$WALTER_DATA/restic-cache

# Telegram alerts (populated by alerting setup)
WALTER_TELEGRAM_BOT_TOKEN=
WALTER_TELEGRAM_CHAT_ID=
EOF
  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"

  cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✗ ATTENTION: a new restic password was generated:

  $PASS

Copy it NOW to:
  - 1Password / Bitwarden / Infisical (workspace=walter-vm-internal env=prod
    key=RESTIC_PASSWORD)
  - A printed note in your safe (literal physical paper)

Loss of this password = backups become unrecoverable. Restic encrypts
client-side; we (you) hold the only key.

Press ENTER to continue (this output is NOT logged elsewhere).
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
  read -r
fi

# 5. Drop the backup script in place
install -m 750 -o root -g root restic-backup.sh /opt/walter-vm/services/restic/

# 6. Initial backup (also initializes both repos)
echo "→ Running initial daily backup (creates repos + first snapshot)..."
WALTER_RESTIC_ENV="$ENV_FILE" /opt/walter-vm/services/restic/restic-backup.sh daily

# 7. Cron
cat > /etc/cron.d/walter-restic <<'EOF'
# Walter-VM restic backups (system cron, root)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WALTER_RESTIC_ENV=/etc/walter-vm/restic.env

# Daily 02:00 BA (UTC-3 → 05:00 UTC)
0 5 * * * root /opt/walter-vm/services/restic/restic-backup.sh daily >> /var/log/walter-vm-restic/cron.log 2>&1

# Weekly extended prune Sundays 03:00 BA (06:00 UTC)
0 6 * * 0 root /opt/walter-vm/services/restic/restic-backup.sh weekly >> /var/log/walter-vm-restic/cron.log 2>&1

# Monthly verify on the 1st 04:00 BA (07:00 UTC)
0 7 1 * * root /opt/walter-vm/services/restic/restic-backup.sh verify >> /var/log/walter-vm-restic/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/walter-restic
systemctl reload cron 2>/dev/null || systemctl restart cron

echo "✅ Restic setup complete"
echo "   Logs:    /var/log/walter-vm-restic/"
echo "   Manual:  /opt/walter-vm/services/restic/restic-backup.sh daily"
echo "   Verify:  /opt/walter-vm/services/restic/restic-backup.sh verify"
