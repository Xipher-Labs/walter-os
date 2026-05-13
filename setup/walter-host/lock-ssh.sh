#!/usr/bin/env bash
# lock-ssh.sh — disable root SSH + password auth on the VM.
#
# RUN THIS ONLY AFTER:
#   1. walter user has SSH key configured
#   2. You've successfully `ssh walter@<vm-ip>` from your machine
#   3. (Optional but recommended) Tailscale is up — gives you a backup path
#
# Otherwise you risk locking yourself out.
#
# Run on the VM as root:
#   ssh root@<vm-ip> "bash" < setup/walter-host/lock-ssh.sh

set -euo pipefail

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }

# Sanity: walter must have at least one authorized key
if [[ ! -s /home/walter/.ssh/authorized_keys ]]; then
  err "REFUSING: walter has no SSH keys. You'd lock yourself out."
  err "First: cat YOUR_PUBKEY | ssh root@vm 'tee /home/walter/.ssh/authorized_keys'"
  exit 1
fi

# Sanity: warn if walter login hasn't been tested
warn "Have you tested 'ssh walter@<vm-ip>' from another terminal? If not, abort with Ctrl-C now."
sleep 5

# Backup
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)

# Drop a config in sshd_config.d (Ubuntu 24.04 standard)
cat > /etc/ssh/sshd_config.d/99-walter-os.conf <<'EOF'
# Walter-OS SSH lockdown
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
LoginGraceTime 30
EOF

sshd -t || { err "sshd config invalid; reverting"; rm -f /etc/ssh/sshd_config.d/99-walter-os.conf; exit 2; }

systemctl reload ssh
ok "SSH locked down. Root login + password auth disabled."
ok "Test from another terminal: ssh walter@<vm-ip>"
warn "Current session stays open until you logout."
