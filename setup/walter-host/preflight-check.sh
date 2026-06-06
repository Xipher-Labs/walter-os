#!/usr/bin/env bash
# preflight-check.sh - capacity gate for Walter-host profiles.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup/walter-host/preflight-check.sh [floor|medium|full]

Environment:
  WALTER_HOST_PROFILE             Default profile when no argument is provided.
  WALTER_PREFLIGHT_ALLOW_UNDERSIZED=1
                                  Warn instead of failing on undersized hosts.
  WALTER_PREFLIGHT_RAM_MB         Test/automation override for detected RAM.
  WALTER_PREFLIGHT_VCPU           Test/automation override for detected vCPU.
  WALTER_PREFLIGHT_DISK_GB        Test/automation override for detected disk.
  WALTER_PREFLIGHT_SKIP_PROC=1    Test/debug override: skip /proc/meminfo RAM detection.
EOF
}

profile="${1:-${WALTER_HOST_PROFILE:-medium}}"

case "$profile" in
  floor)
    required_vcpu=4
    required_ram_mb=8192
    required_disk_gb=80
    profile_label="floor"
    ;;
  medium)
    required_vcpu=8
    required_ram_mb=16384
    required_disk_gb=160
    profile_label="medium"
    ;;
  full)
    required_vcpu=16
    required_ram_mb=32768
    required_disk_gb=320
    profile_label="full"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown Walter-host profile: $profile" >&2
    usage >&2
    exit 2
    ;;
esac

profile_label_upper="$(printf '%s' "$profile_label" | tr '[:lower:]' '[:upper:]')"

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

require_uint() {
  local name="$1"
  local value="$2"

  if ! is_uint "$value"; then
    echo "ERROR: ${name} must be numeric; got '${value:-<empty>}'." >&2
    exit 2
  fi
}

detect_ram_mb() {
  if [[ -n "${WALTER_PREFLIGHT_RAM_MB:-}" ]]; then
    echo "$WALTER_PREFLIGHT_RAM_MB"
    return
  fi

  if [[ -r /proc/meminfo && "${WALTER_PREFLIGHT_SKIP_PROC:-}" != "1" ]]; then
    awk '/MemTotal:/ { printf "%.0f\n", $2 / 1024 }' /proc/meminfo
    return
  fi

  if command -v sysctl >/dev/null 2>&1; then
    local mem_bytes
    mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
    if [[ "$mem_bytes" =~ ^[0-9]+$ ]]; then
      awk -v bytes="$mem_bytes" 'BEGIN { printf "%.0f\n", bytes / 1024 / 1024 }'
      return
    fi
  fi

  echo 0
}

detect_vcpu() {
  if [[ -n "${WALTER_PREFLIGHT_VCPU:-}" ]]; then
    echo "$WALTER_PREFLIGHT_VCPU"
    return
  fi

  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0
}

detect_disk_gb() {
  if [[ -n "${WALTER_PREFLIGHT_DISK_GB:-}" ]]; then
    echo "$WALTER_PREFLIGHT_DISK_GB"
    return
  fi

  local disk_mb
  disk_mb="$(df -Pm / 2>/dev/null | awk 'NR == 2 { print $2 }' || true)"
  if is_uint "$disk_mb"; then
    awk -v mb="$disk_mb" 'BEGIN { printf "%.0f\n", mb / 1024 }'
    return
  fi

  echo 0
}

ram_mb="$(detect_ram_mb)"
vcpu="$(detect_vcpu)"
disk_gb="$(detect_disk_gb)"
failed=0

require_uint "WALTER_PREFLIGHT_RAM_MB/detected RAM" "$ram_mb"
require_uint "WALTER_PREFLIGHT_VCPU/detected vCPU" "$vcpu"
require_uint "WALTER_PREFLIGHT_DISK_GB/detected disk" "$disk_gb"

echo "Walter-host capacity preflight: profile=${profile_label}"
echo "Detected: vCPU=${vcpu}, RAM=$((ram_mb / 1024)) GB, disk=${disk_gb} GB"
echo "Required: vCPU=${required_vcpu}, RAM=$((required_ram_mb / 1024)) GB, disk=${required_disk_gb} GB"

if (( vcpu < required_vcpu )); then
  echo "ERROR: ${profile_label_upper} profile requires at least ${required_vcpu} vCPU; detected ${vcpu}." >&2
  failed=1
fi

if (( ram_mb < required_ram_mb )); then
  echo "ERROR: ${profile_label_upper} profile requires at least $((required_ram_mb / 1024)) GB RAM; detected $((ram_mb / 1024)) GB." >&2
  failed=1
fi

if (( disk_gb < required_disk_gb )); then
  echo "ERROR: ${profile_label_upper} profile requires at least ${required_disk_gb} GB disk; detected ${disk_gb} GB." >&2
  failed=1
fi

if (( failed == 1 )); then
  if [[ "${WALTER_PREFLIGHT_ALLOW_UNDERSIZED:-}" == "1" ]]; then
    echo "WARNING: override accepted via WALTER_PREFLIGHT_ALLOW_UNDERSIZED=1."
    exit 0
  fi

  if [[ "$profile_label" == "full" ]]; then
    echo "FULL profile is intended for CX53-class hosts (16 vCPU / 32 GB RAM / 320 GB disk)." >&2
  fi
  exit 1
fi

echo "capacity preflight passed"
