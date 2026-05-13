#!/usr/bin/env bash
# walter logs <service> [lines]
set -euo pipefail
svc="${1:-}"; lines="${2:-50}"
[[ -z "$svc" ]] && { echo "Usage: walter logs <container> [lines]"; exit 2; }
ssh walter-vm "sudo docker logs --tail $lines -f $svc 2>&1"
