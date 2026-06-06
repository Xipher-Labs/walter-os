#!/usr/bin/env bash
# Print or apply a Hetzner Cloud Firewall rule for break-glass SSH access.
#
# Default mode is dry-run. Pass --apply only when the operator has confirmed the
# server and CIDR for this specific recovery action.

set -euo pipefail

ACTION="plan"
FIREWALL_NAME="${WALTER_BREAK_GLASS_FIREWALL:-walter-vm-break-glass-ssh}"
SERVER="${HCLOUD_SERVER_NAME:-}"
CIDR="${WALTER_BREAK_GLASS_SSH_CIDR:-}"
DESCRIPTION="${WALTER_BREAK_GLASS_DESCRIPTION:-Walter-OS break-glass SSH recovery}"

usage() {
  cat <<'EOF'
Usage:
  hetzner-break-glass-ssh.sh --server <server-name-or-id> --cidr <ip-or-cidr> [--firewall <name>] [--apply]
  hetzner-break-glass-ssh.sh --server <server-name-or-id> [--firewall <name>] --remove

Environment alternatives:
  HCLOUD_SERVER_NAME
  WALTER_BREAK_GLASS_SSH_CIDR
  WALTER_BREAK_GLASS_FIREWALL
  WALTER_BREAK_GLASS_DESCRIPTION

Default mode prints the hcloud commands without executing them.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      ACTION="apply"
      shift
      ;;
    --remove)
      ACTION="remove"
      shift
      ;;
    --server)
      SERVER="${2:-}"
      shift 2
      ;;
    --cidr)
      CIDR="${2:-}"
      shift 2
      ;;
    --firewall)
      FIREWALL_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$SERVER" ]]; then
  echo "missing required --server or HCLOUD_SERVER_NAME" >&2
  usage
  exit 2
fi

create_cmd=(hcloud firewall create --name "$FIREWALL_NAME" --label walter-os=break-glass --label purpose=ssh-recovery)
rule_cmd=(hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 22 --source-ips "$CIDR" --description "$DESCRIPTION")
apply_cmd=(hcloud firewall apply-to-resource "$FIREWALL_NAME" --type server --server "$SERVER")
remove_cmd=(hcloud firewall remove-from-resource "$FIREWALL_NAME" --type server --server "$SERVER")

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

if [[ "$ACTION" == "remove" ]]; then
  echo "DRY RUN: remove break-glass firewall from server $SERVER"
  print_cmd "${remove_cmd[@]}"
  echo "Run with --apply is intentionally not supported for removal; copy the command after verifying active access."
  exit 0
fi

if [[ -z "$CIDR" ]]; then
  echo "missing required --cidr or WALTER_BREAK_GLASS_SSH_CIDR" >&2
  usage
  exit 2
fi

if [[ "$CIDR" != */* ]]; then
  echo "CIDR must include a prefix length, for example 203.0.113.10/32" >&2
  exit 2
fi

if [[ "$CIDR" == "0.0.0.0/0" || "$CIDR" == "::/0" ]]; then
  echo "refusing world-open SSH source range: $CIDR" >&2
  exit 2
fi

if [[ "$ACTION" != "apply" ]]; then
  echo "DRY RUN: create/apply break-glass firewall for server $SERVER from $CIDR"
  print_cmd "${create_cmd[@]}"
  print_cmd "${rule_cmd[@]}"
  print_cmd "${apply_cmd[@]}"
  echo "Re-run with --apply only for an operator-approved recovery action."
  exit 0
fi

command -v hcloud >/dev/null 2>&1 || {
  echo "hcloud CLI is required for --apply" >&2
  exit 127
}

if ! hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
  "${create_cmd[@]}"
fi

"${rule_cmd[@]}"
"${apply_cmd[@]}"

cat <<EOF
Break-glass SSH firewall applied.

Server:   $SERVER
Firewall: $FIREWALL_NAME
Source:   $CIDR

After recovery, remove the firewall from the server:
$(print_cmd "${remove_cmd[@]}")
EOF
