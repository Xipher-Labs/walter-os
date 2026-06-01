#!/usr/bin/env bash
# scripts/upgrade.sh — one-command Walter-OS upgrade workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WALTER_OS_BIN="${WALTER_OS_BIN:-${REPO_ROOT}/bin/walter-os}"
WALTER_BIN="${WALTER_BIN:-${REPO_ROOT}/bin/walter}"

mode="local"
dry_run=0
target=""
snapshot=0
skip_audit=0
skip_doctor=0
assume_yes=0
vm_host="walter-vm"
vm_repo="${WALTER_VM_REPO:-/opt/walter-os}"
services=()

usage() {
  cat <<'EOF'
Usage: walter-os upgrade [--local|--vm|--all] [options]

Modes:
  --local              Upgrade the local Walter-OS checkout (default)
  --vm                 Upgrade the Walter-VM Walter-OS checkout/config
  --all                Run local upgrade, then Walter-VM checkout/config

Options:
  --dry-run            Print the planned commands without running them
  --target <git-ref>   Checkout a specific tag/branch/commit before install
  --snapshot           Take a Walter-VM snapshot before VM service updates
  --yes                Confirm paid/remote side effects such as snapshots
  --service <name>     Explicit Docker service rollout; repeatable
  --skip-audit         Do not run walter-os audit after local upgrade
  --skip-doctor        Do not run walter-os doctor after local upgrade
  -h, --help           Show this help
EOF
}

log() {
  printf '%s\n' "$*"
}

err() {
  printf 'walter-os upgrade: %s\n' "$*" >&2
}

print_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

shell_quote() {
  printf "%q" "$1"
}

single_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

validate_service_name() {
  local service="$1"
  [[ "$service" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

run_cmd() {
  print_cmd "$@"
  if [[ "$dry_run" -eq 1 ]]; then
    return 0
  fi
  "$@"
}

ensure_clean_tree() {
  if [[ "$dry_run" -eq 1 ]]; then
    print_cmd git -C "$REPO_ROOT" status --porcelain
    return 0
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    err "working tree dirty. Commit or stash local changes before upgrading."
    git status --short >&2
    exit 2
  fi
}

fast_forward_checkout() {
  if [[ "$dry_run" -eq 1 ]]; then
    print_cmd git -C "$REPO_ROOT" fetch --quiet
    log "  # would compare HEAD with upstream and abort if ahead/diverged/no-upstream"
    print_cmd git -C "$REPO_ROOT" pull --ff-only --quiet
    return 0
  fi

  git fetch --quiet

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    err "current branch has no upstream. Set one or use --target <git-ref>."
    exit 2
  fi

  local local_sha remote_sha base_sha
  local_sha="$(git rev-parse @)"
  remote_sha="$(git rev-parse '@{u}')"
  base_sha="$(git merge-base @ '@{u}')"

  if [[ "$local_sha" == "$remote_sha" ]]; then
    log "  already up to date with ${upstream}"
  elif [[ "$local_sha" == "$base_sha" ]]; then
    run_cmd git -C "$REPO_ROOT" pull --ff-only --quiet
  elif [[ "$remote_sha" == "$base_sha" ]]; then
    err "local branch is ahead of ${upstream}; refusing to upgrade from unpublished commits."
    exit 2
  else
    err "local branch diverged from ${upstream}; resolve manually before upgrading."
    exit 2
  fi
}

run_local_upgrade() {
  log "==> Local Walter-OS checkout"
  cd "$REPO_ROOT"

  ensure_clean_tree

  if [[ -n "$target" ]]; then
    run_cmd git -C "$REPO_ROOT" fetch --all --tags --quiet
    run_cmd git -C "$REPO_ROOT" checkout "$target"
  else
    fast_forward_checkout
  fi

  run_cmd bash "${REPO_ROOT}/install.sh" --upgrade

  if [[ "$skip_audit" -eq 0 ]]; then
    run_cmd "$WALTER_OS_BIN" audit
  fi
  if [[ "$skip_doctor" -eq 0 ]]; then
    run_cmd "$WALTER_OS_BIN" doctor
  fi
}

run_vm_upgrade() {
  log "==> Walter-VM checkout"

  if [[ "$snapshot" -eq 1 ]]; then
    log "  snapshot warning: Hetzner snapshots may create a monthly storage cost."
    if [[ "$dry_run" -eq 0 && "$assume_yes" -ne 1 ]]; then
      err "--snapshot requires --yes in non-dry-run mode."
      exit 2
    fi
    local snapshot_name
    snapshot_name="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    run_cmd "$WALTER_BIN" vm snapshot "$snapshot_name"
  fi

  local remote_repo
  remote_repo="$(shell_quote "$vm_repo")"

  local remote_payload remote_cmd
  remote_payload="cd ${remote_repo} && test -z \"\$(git status --porcelain)\" && git fetch --quiet && git pull --ff-only --quiet && bash ./install.sh --upgrade && ./bin/walter-os audit && ./bin/walter-os doctor"
  remote_cmd="bash -lc $(single_quote "$remote_payload")"
  run_cmd ssh "$vm_host" "$remote_cmd"

  local service
  for service in "${services[@]}"; do
    log "==> Walter-VM service: ${service}"
    run_cmd "$WALTER_BIN" deploy "$service"
  done

  run_cmd "$WALTER_BIN" status
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) mode="local"; shift ;;
    --vm) mode="vm"; shift ;;
    --all) mode="all"; shift ;;
    --dry-run) dry_run=1; shift ;;
    --target)
      [[ $# -ge 2 ]] || { err "--target requires a git ref"; exit 2; }
      target="$2"; shift 2
      ;;
    --snapshot) snapshot=1; shift ;;
    --yes|-y) assume_yes=1; shift ;;
    --service)
      [[ $# -ge 2 ]] || { err "--service requires a service name"; exit 2; }
      validate_service_name "$2" || { err "unsafe service name: $2"; exit 2; }
      services+=("$2"); shift 2
      ;;
    --skip-audit|--no-audit) skip_audit=1; shift ;;
    --skip-doctor|--no-doctor) skip_doctor=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [[ "$mode" == "local" && "${#services[@]}" -gt 0 ]]; then
  err "--service requires --vm or --all."
  exit 2
fi

if [[ "$mode" == "vm" && -n "$target" ]]; then
  err "--target applies only to local upgrades; use --local or --all."
  exit 2
fi

if [[ "$mode" == "local" && "$snapshot" -eq 1 ]]; then
  err "--snapshot requires --vm or --all."
  exit 2
fi

if [[ "$snapshot" -eq 1 && "$dry_run" -eq 0 && "$assume_yes" -ne 1 ]]; then
  err "--snapshot requires --yes in non-dry-run mode."
  exit 2
fi

log "Walter-OS upgrade plan"
log "  mode: ${mode}"
[[ "$dry_run" -eq 1 ]] && log "  dry-run: yes"
[[ -n "$target" ]] && log "  target: ${target}"
[[ "$snapshot" -eq 1 ]] && log "  vm snapshot: yes"
if [[ "$mode" == "vm" || "$mode" == "all" ]]; then
  log "  vm host: ${vm_host}"
  log "  vm repo: ${vm_repo}"
fi
if [[ "${#services[@]}" -gt 0 ]]; then
  log "  explicit service rollouts: ${services[*]}"
fi
log ""

case "$mode" in
  local) run_local_upgrade ;;
  vm) run_vm_upgrade ;;
  all)
    run_local_upgrade
    run_vm_upgrade
    ;;
  *)
    err "invalid mode: $mode"
    exit 2
    ;;
esac
