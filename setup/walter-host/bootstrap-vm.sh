#!/usr/bin/env bash
# bootstrap-vm.sh — provision a Hetzner VM (Ubuntu 24.04) into Walter-VM state.
#
# Idempotent. Safe to re-run on the same machine (skips already-done steps).
#
# Run ON the VM as root:
#   scp setup/walter-host/bootstrap-vm.sh root@<vm-ip>:/tmp/
#   ssh root@<vm-ip> "bash /tmp/bootstrap-vm.sh"
#
# What it does (in order):
#   1. apt update + upgrade
#   2. Install base CLIs + security packages
#   3. Configure unattended-upgrades + fail2ban
#   4. Create 4GB swap if none
#   5. Create `walter` user with sudo (no SSH key — operator adds)
#   6. Install Tailscale (binary only — `tailscale up` separate step)
#   7. Install Docker CE + compose plugin (walter added to docker group)
#   8. Install Caddy
#   9. Configure UFW firewall (22 / 80 / 443 / 41641-udp / tailscale0)
#  10. Initial Caddyfile
#  11. /opt/walter-vm directory layout + master docker-compose.yml skeleton
#
# What it does NOT do (intentional — needs user input):
#   - tailscale up (needs auth key)
#   - SSH lockdown (needs walter pubkey first to avoid lockout)
#   - Service deployments (Vaultwarden, Plane, etc.) — separate scripts in
#     setup/walter-host/services/<name>/
#
# After this script:
#   1. Add walter SSH pubkey: cat YOUR_PUBKEY | ssh root@vm "tee /home/walter/.ssh/authorized_keys >/dev/null && chmod 600 /home/walter/.ssh/authorized_keys && chown walter:walter /home/walter/.ssh/authorized_keys"
#   2. Verify walter SSH works: ssh walter@vm "id"
#   3. tailscale up: ssh root@vm "tailscale up --auth-key=tskey-..." OR ssh interactive
#   4. Lock down SSH: see setup/walter-host/lock-ssh.sh

set -euo pipefail

TMP_FILES=()
cleanup() {
  if [[ "${#TMP_FILES[@]}" -gt 0 ]]; then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

# Output helpers
c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

# Require root
if [[ $EUID -ne 0 ]]; then
  err "Run as root (or via sudo)."
  exit 1
fi

# Verify Ubuntu 24.04
if ! grep -q '^VERSION_ID="24.04"' /etc/os-release; then
  warn "Not Ubuntu 24.04 — script tested on Noble Numbat only. Continuing at your risk."
fi

export DEBIAN_FRONTEND=noninteractive

# ---------- 1. apt update + upgrade ----------

step "System update"
apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
ok "apt up to date"

# ---------- 2. Base packages ----------

step "Base packages"
apt-get install -y -qq \
  curl wget gnupg lsb-release ca-certificates apt-transport-https \
  software-properties-common ufw fail2ban unattended-upgrades \
  vim tmux htop iotop ncdu jq git rsync ripgrep age restic rclone \
  build-essential
ok "base CLIs + security packages installed"

# ---------- 3. unattended-upgrades + fail2ban ----------

step "Auto-upgrades + fail2ban"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF
systemctl enable --now unattended-upgrades >/dev/null 2>&1
systemctl enable --now fail2ban >/dev/null 2>&1
ok "unattended-upgrades + fail2ban active"

# ---------- 4. Swap ----------

step "Swap (4GB)"
if [[ ! -f /swapfile ]]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "vm.swappiness=10" > /etc/sysctl.d/99-walter.conf
  sysctl -p /etc/sysctl.d/99-walter.conf >/dev/null
  ok "4G swap created at /swapfile"
else
  ok "swap already present"
fi

# ---------- 5. walter user ----------

step "walter non-root user"
if ! id walter >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo walter
  echo "walter ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/walter
  chmod 440 /etc/sudoers.d/walter
  mkdir -p /home/walter/.ssh
  chmod 700 /home/walter/.ssh
  chown -R walter:walter /home/walter
  ok "walter user created (no SSH key — operator must add)"
else
  ok "walter exists"
fi

# ---------- 6. Tailscale (binary only) ----------

step "Tailscale install"
if ! command -v tailscale >/dev/null 2>&1; then
  tailscale_installer="$(mktemp -t tailscale-install.XXXXXX)"
  TMP_FILES+=("$tailscale_installer")
  curl -fsSL https://tailscale.com/install.sh -o "$tailscale_installer"
  sh "$tailscale_installer" 2>&1 | tail -3
fi
ok "tailscale: $(tailscale version | head -1)"
warn "Run 'tailscale up' separately with your auth key."

# ---------- 7. Docker ----------

step "Docker + compose"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
ok "docker: $(docker --version | head -1)"
ok "compose: $(docker compose version | head -1)"
usermod -aG docker walter
ok "walter in docker group"

# ---------- 8. Caddy ----------

step "Caddy"
if ! command -v caddy >/dev/null 2>&1; then
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi
ok "caddy: $(caddy version | head -1)"

# ---------- 9. UFW firewall ----------

step "UFW firewall"
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp comment "SSH" >/dev/null
ufw allow 80/tcp comment "HTTP-Caddy" >/dev/null
ufw allow 443/tcp comment "HTTPS-Caddy" >/dev/null
ufw allow 41641/udp comment "Tailscale" >/dev/null
ufw allow in on tailscale0 comment "Tailnet trusted" 2>/dev/null || true
ufw --force enable >/dev/null
ok "UFW active: $(ufw status numbered | grep -c "^\[" || true) rules"

# ---------- 10. Caddyfile ----------

step "Caddyfile (initial)"
if [[ ! -s /etc/caddy/Caddyfile ]] || ! grep -q "Walter-VM" /etc/caddy/Caddyfile; then
  cat > /etc/caddy/Caddyfile <<'EOF'
# Walter-VM Caddyfile
# Each service block proxies to a docker-compose service.
# TLS via Tailscale (tailscale cert) once tailscale is up + DNS configured.

:80 {
  respond "Walter-VM — service not configured for this hostname" 404
}

# Service blocks added per service deployed.
# Example:
# vault.<tailnet>.ts.net {
#   reverse_proxy 127.0.0.1:8222
# }
EOF
  caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1
  systemctl reload caddy
fi
ok "Caddyfile in place"

# ---------- 11. /opt/walter-vm layout ----------

step "/opt/walter-vm layout"
mkdir -p /opt/walter-vm/{services,caddy,backups,data}
chown -R walter:walter /opt/walter-vm

if [[ ! -f /opt/walter-vm/docker-compose.yml ]]; then
  cat > /opt/walter-vm/docker-compose.yml <<'EOF'
# Walter-VM master docker-compose.
# Services live in services/<name>/compose.yml and are included here.

name: walter-vm

include:
  # Activated incrementally — uncomment as each service deployed:
  # - services/vaultwarden/compose.yml
  # - services/litellm/compose.yml
  # - services/plane/compose.yml
  # - services/forgejo/compose.yml
  # - services/uptime-kuma/compose.yml
  # - services/homepage/compose.yml

networks:
  walter:
    name: walter
    driver: bridge

volumes:
  walter-shared: {}
EOF
  chown walter:walter /opt/walter-vm/docker-compose.yml
fi
ok "/opt/walter-vm/ ready"

# ---------- summary ----------

step "Summary"
cat <<EOF

VM bootstrap complete.

Tools:
  tailscale: $(tailscale version | head -1)
  docker:    $(docker --version | head -1)
  compose:   $(docker compose version | head -1)
  caddy:     $(caddy version | head -1)

Services (active):
$(systemctl is-active fail2ban unattended-upgrades caddy docker tailscaled 2>&1 | sed 's/^/  /')

Firewall: $(ufw status | head -1)
Swap: $(free -h | awk '/^Swap/ {print $2}')

NEXT STEPS (operator must do):

  1. Add SSH pubkey to walter user:
     cat ~/.ssh/id_ed25519.pub | ssh root@<vm-ip> "tee /home/walter/.ssh/authorized_keys >/dev/null && chmod 600 /home/walter/.ssh/authorized_keys && chown walter:walter /home/walter/.ssh/authorized_keys"

  2. Verify walter SSH:
     ssh walter@<vm-ip> "id"

  3. Tailscale up (needs auth key from https://login.tailscale.com/admin/settings/keys):
     ssh root@<vm-ip> "tailscale up --auth-key=tskey-... --hostname=walter-vm --ssh"

  4. Lock down SSH (only after step 1-3 verified):
     bash setup/walter-host/lock-ssh.sh   (separate script)

  5. Deploy first service:
     bash setup/walter-host/services/vaultwarden/deploy.sh   (TBD)
EOF
