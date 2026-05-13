#!/usr/bin/env bash
# agent-memory-setup.sh — wire Claude Code agent-memory into a Syncthing folder.
#
# Layout this script enforces:
#
#   ~/sync/agent-memory/                         (Syncthing-shared folder)
#   ├── shared/                                  (cross-project: reviewer/security-auditor notes)
#   │   ├── reviewer/
#   │   ├── security-auditor/
#   │   └── tech-writer/
#   └── projects/<encoded-project>/
#       └── memory/
#
# Symlinks created on the local machine:
#
#   ~/.claude/agent-memory/<agent>             →  ~/sync/agent-memory/shared/<agent>
#   ~/.claude/projects/<encoded>/memory        →  ~/sync/agent-memory/projects/<encoded>/memory
#
# Operator's machine A and B each run this script; both end up symlinked to
# their local ~/sync/agent-memory/, which Syncthing keeps in sync via the
# walter-vm hub. Result: agent-memory follows you across machines.
#
# Subcommands:
#   setup          — create dirs + symlinks (idempotent)
#   status         — show what's wired and what's drift
#   migrate        — copy existing ~/.claude/agent-memory/ INTO the sync folder
#                    before symlinking (one-time, on first machine)
#
# Usage:
#   walter-os agent-memory setup
#   walter-os agent-memory status

set -euo pipefail

ACTION="${1:-status}"
SYNC_ROOT="${HOME}/sync/agent-memory"
CLAUDE_HOME="${HOME}/.claude"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

# Agents we share state for (durable cross-project notes).
SHARED_AGENTS=(reviewer security-auditor tech-writer architect)

case "$ACTION" in
  setup)
    step "Ensure local sync root exists"
    mkdir -p "${SYNC_ROOT}/shared" "${SYNC_ROOT}/projects"
    ok "local: $SYNC_ROOT"

    step "Migrate existing ~/.claude/agent-memory/* (if any)"
    if [[ -d "${CLAUDE_HOME}/agent-memory" && ! -L "${CLAUDE_HOME}/agent-memory" ]]; then
      for agent_dir in "${CLAUDE_HOME}/agent-memory"/*/; do
        [[ -d "$agent_dir" ]] || continue
        agent="$(basename "$agent_dir")"
        target="${SYNC_ROOT}/shared/${agent}"
        if [[ ! -d "$target" ]]; then
          mkdir -p "${SYNC_ROOT}/shared"
          mv "$agent_dir" "$target"
          ok "migrated: $agent → ${target}"
        else
          # Both exist — copy non-conflicting files, keep operator's data on both sides.
          rsync -a --ignore-existing "$agent_dir" "${target}/" 2>/dev/null || true
          rm -rf "$agent_dir"
          info "merged + removed local $agent (target had pre-existing data)"
        fi
      done
      rmdir "${CLAUDE_HOME}/agent-memory" 2>/dev/null || true
    else
      info "no pre-existing ~/.claude/agent-memory/ to migrate"
    fi

    step "Create shared/<agent> dirs (durable cross-project notes)"
    for agent in "${SHARED_AGENTS[@]}"; do
      mkdir -p "${SYNC_ROOT}/shared/${agent}"
      info "shared/${agent}/"
    done

    step "Symlink ~/.claude/agent-memory → sync/shared"
    if [[ -L "${CLAUDE_HOME}/agent-memory" ]]; then
      info "already symlinked"
    elif [[ -e "${CLAUDE_HOME}/agent-memory" ]]; then
      warn "${CLAUDE_HOME}/agent-memory exists and is not a symlink. Backing up."
      mv "${CLAUDE_HOME}/agent-memory" "${CLAUDE_HOME}/agent-memory.bak.$(date +%s)"
      ln -s "${SYNC_ROOT}/shared" "${CLAUDE_HOME}/agent-memory"
      ok "linked (with backup of existing dir)"
    else
      mkdir -p "$CLAUDE_HOME"
      ln -s "${SYNC_ROOT}/shared" "${CLAUDE_HOME}/agent-memory"
      ok "linked: ~/.claude/agent-memory → ${SYNC_ROOT}/shared"
    fi

    step "Symlink per-project memory dirs (~/.claude/projects/<id>/memory)"
    if [[ -d "${CLAUDE_HOME}/projects" ]]; then
      local_count=0
      for proj_dir in "${CLAUDE_HOME}/projects"/*/; do
        [[ -d "$proj_dir" ]] || continue
        proj_id="$(basename "$proj_dir")"
        local_mem="${proj_dir}memory"
        sync_mem="${SYNC_ROOT}/projects/${proj_id}/memory"

        # If local memory dir exists with content, migrate.
        if [[ -d "$local_mem" && ! -L "$local_mem" ]]; then
          if [[ ! -d "$sync_mem" ]]; then
            mkdir -p "${SYNC_ROOT}/projects/${proj_id}"
            mv "$local_mem" "$sync_mem"
            ok "migrated project: ${proj_id}"
          else
            rsync -a --ignore-existing "$local_mem/" "$sync_mem/" 2>/dev/null || true
            rm -rf "$local_mem"
            info "merged + removed local ${proj_id} memory"
          fi
        elif [[ -L "$local_mem" ]]; then
          info "skip: ${proj_id} already symlinked"
          continue
        else
          mkdir -p "$sync_mem"
        fi

        # Link.
        ln -sfn "$sync_mem" "$local_mem"
        ok "linked: projects/${proj_id}/memory → sync"
        local_count=$((local_count + 1))
      done
      info "${local_count} project memory dirs wired"
    else
      info "no ~/.claude/projects/ yet (will be created by Claude Code on first use)"
    fi

    cat <<NEXT

Done. Agent memory now lives at:
  ${SYNC_ROOT}

To activate cross-device sync:
  1. walter-os syncthing-bootstrap   — registers folder on the VM hub
  2. Open https://sync.${WALTER_DOMAIN}, share folder 'agent-memory' with your
     local device ID (Syncthing UI: Add Folder → Folder ID 'agent-memory' →
     point to ${SYNC_ROOT}).
  3. Repeat (1) and (2) on machine B with the same folder ID.

Verify:
  walter-os agent-memory status
NEXT
    ;;

  status)
    step "Walter-OS agent-memory status"
    echo
    if [[ -d "$SYNC_ROOT" ]]; then
      ok "sync root: $SYNC_ROOT"
      shared_count=$(find "${SYNC_ROOT}/shared" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      proj_count=$(find "${SYNC_ROOT}/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      info "shared agents: $shared_count"
      info "projects:      $proj_count"
    else
      err "sync root missing — run: walter-os agent-memory setup"
    fi

    echo
    if [[ -L "${CLAUDE_HOME}/agent-memory" ]]; then
      target="$(readlink "${CLAUDE_HOME}/agent-memory")"
      if [[ "$target" == "${SYNC_ROOT}/shared" ]]; then
        # shellcheck disable=SC2088 # display label, not a path
        ok '~/.claude/agent-memory → sync/shared'
      else
        # shellcheck disable=SC2088
        warn "~/.claude/agent-memory points elsewhere: $target"
      fi
    elif [[ -d "${CLAUDE_HOME}/agent-memory" ]]; then
      # shellcheck disable=SC2088
      warn '~/.claude/agent-memory is a real dir — run setup to migrate + symlink'
    else
      # shellcheck disable=SC2088
      info '~/.claude/agent-memory does not exist yet'
    fi

    echo
    if [[ -d "${CLAUDE_HOME}/projects" ]]; then
      linked=0
      total=0
      for d in "${CLAUDE_HOME}/projects"/*/; do
        [[ -d "$d" ]] || continue
        total=$((total + 1))
        if [[ -L "${d}memory" ]]; then linked=$((linked + 1)); fi
      done
      info "projects: $linked/$total memory dirs symlinked"
    fi
    ;;

  *)
    echo "Usage: walter-os agent-memory {setup|status}" >&2
    exit 2
    ;;
esac
