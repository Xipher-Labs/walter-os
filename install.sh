#!/usr/bin/env bash
# install.sh — Walter-OS interactive install wizard
#
# Runs 9 steps to take a fresh clone to a working Walter-OS deployment.
# Step 0 (symlinks + hooks) always runs first; it is the legacy upgrade path.
#
# Usage:
#   ./install.sh             # full wizard (steps 0–9, interactive)
#   ./install.sh --check     # check minimum local requirements, no writes
#   ./install.sh --dry-run   # preview all 9 steps, no changes
#   ./install.sh --upgrade   # step 0 only (symlink + config regen)
#   ./install.sh --step N    # run only step N (1–9, for recovery)
#   ./install.sh --step N --dry-run   # preview step N only
#   ./install.sh --uninstall # remove all symlinks and launchd job
#   ./install.sh --help      # this help text
#
# Steps:
#   1  Detect OS + install missing deps (brew/apt)
#   2  Prompt bootstrap env vars → write .env.local
#   3  Personal overlay init (W-5)
#   4  Plane workspace + custom states via API
#   5  Provision Postgres databases
#   6  docker compose up + bootstrap
#   7  n8n workflow template import
#   8  Infisical workspace + Machine Identity
#   9  walter doctor + next-steps banner
#
# Refs: docs/specs/phase-w-6-install-wizard.md

set -euo pipefail

print_install_help() {
  awk 'NR == 1 { next } /^[^#]/ && NR > 1 { exit } /^#( |$)/ { sub(/^# ?/, ""); print }' "$0"
}

# ---------- config ----------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT
readonly CLAUDE_HOME="${HOME}/.claude"
readonly CODEX_HOME="${HOME}/.codex"
readonly WALTER_CONFIG="${HOME}/.config/walter-os"
readonly LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
readonly DAILY_AUDIT_LABEL="com.walter-os.daily-audit"

# Env file where wizard-collected vars are written (step 2)
# WALTER_ENV_LOCAL overrides the path (used by tests for isolation)
ENV_LOCAL="${WALTER_ENV_LOCAL:-${WALTER_CONFIG}/env.local}"

# ---------- args ----------

DRY_RUN="${WALTER_INSTALL_DRY_RUN:-0}"  # env var OR --dry-run flag (defense-in-depth)
CHECK_ONLY=0
UPGRADE=0
UNINSTALL=0
STEP_ONLY=""     # if set, run only this step number (1-9)

_args=("$@")
i=0
while [[ $i -lt ${#_args[@]} ]]; do
  arg="${_args[$i]}"
  case "$arg" in
    --check)     CHECK_ONLY=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    --upgrade)   UPGRADE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --step)
      i=$(( i + 1 ))
      if [[ $i -ge ${#_args[@]} ]]; then
        echo "Error: --step requires a step number (1-9)" >&2
        exit 2
      fi
      STEP_ONLY="${_args[$i]}"
      if ! [[ "$STEP_ONLY" =~ ^[1-9]$ ]]; then
        echo "Error: --step value must be 1-9, got: $STEP_ONLY" >&2
        exit 2
      fi
      ;;
    -h|--help)
      print_install_help
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
  i=$(( i + 1 ))
done

# ---------- pretty ----------

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_b=$'\033[1m'
c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_blue=$'\033[34m'

say()  { printf "%s\n" "$*"; }
ok()   { printf "${c_green}✓${c_reset} %s\n" "$*"; }
warn() { printf "${c_yellow}!${c_reset} %s\n" "$*"; }
err()  { printf "${c_red}✗${c_reset} %s\n" "$*" >&2; }
step() { printf "\n${c_b}${c_blue}==>${c_reset} ${c_b}%s${c_reset}\n" "$*"; }
dry()  { printf "${c_dim}[dry-run]${c_reset} %s\n" "$*"; }

_requirement_failures=0

check_required_tool() {
  local tool="$1" install_hint="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool: $(command -v "$tool")"
  else
    err "$tool missing"
    say "  Install: $install_hint" >&2
    _requirement_failures=$((_requirement_failures + 1))
  fi
}

check_optional_tool() {
  local tool="$1" install_hint="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool: $(command -v "$tool")"
  else
    warn "$tool missing (optional)"
    warn "  Install: $install_hint"
  fi
}

check_requirements() {
  step "Requirements check"
  _requirement_failures=0

  case "$(uname -s)" in
    Darwin)
      ok "OS: macOS ($(uname -m))"
      check_optional_tool brew "https://brew.sh"
      ;;
    Linux)
      ok "OS: Linux"
      check_optional_tool apt-get "Use your distribution package manager if apt-get is unavailable"
      ;;
    *)
      err "Unsupported OS: $(uname -s). Walter-OS is tested on macOS and Linux."
      _requirement_failures=$((_requirement_failures + 1))
      ;;
  esac

  say
  say "${c_b}Required for the installer:${c_reset}"
  check_required_tool git "brew install git  # or: sudo apt-get install -y git"
  check_required_tool curl "brew install curl  # or: sudo apt-get install -y curl"
  check_required_tool jq "brew install jq  # or: sudo apt-get install -y jq"
  # yq is a hard dependency for approval-gate.sh + trust-tier evaluation
  # (audit P1-05). The hook fails CLOSED if yq is missing, so a degraded
  # install is worse than no install — blocking here is correct.
  check_required_tool yq "brew install yq  # or: sudo snap install yq"

  say
  say "${c_b}Required for full walter-host stack:${c_reset}"
  check_required_tool docker "Install Docker Desktop/OrbStack on macOS, or Docker Engine on Linux"

  say
  say "${c_b}Expected for local development and CI parity:${c_reset}"
  check_optional_tool gh "brew install gh  # or: see https://cli.github.com"
  check_optional_tool rg "brew install ripgrep  # or: sudo apt-get install -y ripgrep"
  check_optional_tool bats "brew install bats-core  # or: sudo apt-get install -y bats"
  check_optional_tool shellcheck "brew install shellcheck  # or: sudo apt-get install -y shellcheck"
  check_optional_tool gitleaks "brew install gitleaks"
  check_optional_tool node "Use mise: mise install node@22"
  check_optional_tool pnpm "Use mise: mise install pnpm@9"
  check_optional_tool python3 "brew install python  # or: sudo apt-get install -y python3"
  check_optional_tool uvx "Use mise: mise install uv"

  say
  say "${c_b}Expected agent CLIs:${c_reset}"
  check_optional_tool claude "Install Claude Code: https://claude.com/code"
  check_optional_tool codex "npm i -g @openai/codex-cli"

  say
  say "${c_b}Expected for secrets runtime:${c_reset}"
  check_optional_tool infisical "brew install infisical/get-cli/infisical  # Linux: see Infisical CLI docs"
  case "$(uname -s)" in
    Darwin)
      check_optional_tool security "built into macOS; verify /usr/bin/security exists"
      check_optional_tool ykman "optional hardware-key tooling: brew install ykman"
      ;;
    Linux)
      if command -v secret-tool >/dev/null 2>&1; then
        ok "secret-tool: $(command -v secret-tool)"
      elif command -v pass >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
        ok "pass+gpg: $(command -v pass), $(command -v gpg)"
      else
        warn "No Linux credential store found for secrets runtime"
        warn "  Install: sudo apt-get install -y libsecret-tools gnome-keyring"
        warn "  Or:      sudo apt-get install -y pass gnupg"
      fi
      ;;
  esac

  if [[ $_requirement_failures -gt 0 ]]; then
    err "Requirements check failed with $_requirement_failures missing required tool(s)."
    return 1
  fi

  ok "Minimum requirements satisfied"
}

# Print a numbered wizard step header, e.g. "Step 1/9: OS detect + deps"
wizard_step() {
  local num="$1" label="$2"
  printf "\n${c_b}${c_blue}┌─ Step %s/9: %s${c_reset}\n" "$num" "$label"
}

run() {
  # DEPRECATED — use run_args (array form) for new code. Kept for backward
  # compatibility with existing call sites that need shell-snippet semantics
  # (heredocs, redirects, conditional chains). Issue #119 / external review F9.
  #
  # CAUTION: eval expansion of "$@" makes this dangerous if any argument is
  # derived from user input. Today's callers pass interpolations of $REPO_ROOT,
  # $HOME, and operator-controlled config — all trusted — but the function
  # itself is an injection vector waiting for a misuse. Prefer:
  #   - run_args cmd "$arg1" "$arg2"   for direct command execution
  #   - run_sh '...'                   when shell-snippet semantics are unavoidable
  #   - write_file "$dest" "$content"  for the "cat > file <<EOF" pattern
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "$*"
  else
    # shellcheck disable=SC2294
    eval "$@"
  fi
}

# run_args — preferred form. Takes an argv array; each arg passed verbatim
# to exec without shell interpretation. Safe even if args contain ';', '|',
# '$(...)', backticks, etc. Issue #119.
run_args() {
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "$*"
  else
    "$@"
  fi
}

# run_sh — explicit shell-snippet evaluator. ONLY for redirects, pipes,
# heredocs, conditional chains that genuinely require shell semantics.
# Argument is a single string passed to `bash -c`. Every call site MUST
# include an inline comment justifying the shell-snippet need + confirming
# all interpolated values are operator-controlled / sanitized. Issue #119.
run_sh() {
  # Arg-count guard: prevents `set -u` surprises and unexpected behavior
  # if the caller forgets the snippet or passes the snippet as multiple
  # arguments instead of a single quoted string. Copilot R2 #128.
  [[ $# -eq 1 ]] || { echo "run_sh: requires exactly 1 argument (the snippet)" >&2; return 2; }
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "$1"
  else
    # Pass the snippet as a positional argument to bash -c rather than
    # interpolating it into the script string. This keeps the outer
    # shell from re-interpreting any quotes, backslashes, or newlines
    # inside the snippet before the inner bash sees it. The inner bash
    # script applies strict mode (same semantics as install.sh) and
    # eval's $1 — run_sh explicitly accepts shell-snippet semantics
    # (redirects, pipes, glob), so eval-inside is by design.
    # Copilot R1 #128 R1.2 (strict mode) + R2 #128 R2.3 (quoting).
    bash -c 'set -euo pipefail; eval "$1"' bash "$1"
  fi
}

# write_file — replaces the `cat > '$dest' <<EOF ... EOF` pattern. Takes
# a destination path and content as separate args, writes via printf
# (no eval, no second-pass variable expansion). Issue #119.
write_file() {
  local dest="$1" content="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "write_file: $dest ($(printf '%s' "$content" | wc -c | tr -d ' ') bytes)"
  else
    printf '%s' "$content" > "$dest"
  fi
}

# ---------- load operator personal config (overlay) ----------

_OVERLAY_PERSONAL_ENV_LOADED=0
load_overlay_personal_env() {
  # Load operator personal config from overlay (out-of-repo, persistent across checkouts).
  # Sourced before .env.local so that .env.local can override overlay values.
  # Guard: only load once per invocation (load_env_local may be called multiple times).
  [[ "$_OVERLAY_PERSONAL_ENV_LOADED" -eq 1 ]] && return 0
  local overlay_env="${HOME}/.config/walter-os/overlay/personal.env"
  if [[ -f "$overlay_env" ]]; then
    set +u
    # shellcheck source=/dev/null
    source "$overlay_env"
    set -u
    ok "Loaded operator config from $overlay_env"
  fi
  _OVERLAY_PERSONAL_ENV_LOADED=1
}

# ---------- load env.local ----------

load_env_local() {
  # Load overlay personal config first so .env.local can override it.
  load_overlay_personal_env
  if [[ -f "$ENV_LOCAL" ]]; then
    set +u
    # shellcheck source=/dev/null
    source "$ENV_LOCAL"
    set -u
  fi
}

# ---------- preflight (step 0) ----------

check_preflight() {
  step "Preflight"

  if [[ "$(uname)" != "Darwin" ]]; then
    warn "Not running on macOS. The installer will skip launchd setup; symlinks still work on Linux."
  fi

  if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found in PATH. Install Claude Code first: https://claude.com/code"
  else
    local v
    v="$(claude --version 2>/dev/null | awk '{print $NF}' || echo unknown)"
    ok "Claude Code: $v"
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
      local major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
      if (( major < 2 || (major == 2 && minor == 0 && patch < 65) )); then
        err "Claude Code $v is below 2.0.65 — vulnerable to CVE-2025-59536/CVE-2026-21852."
        err "Update before continuing: claude update"
        exit 3
      fi
    fi
  fi

  if ! command -v codex >/dev/null 2>&1; then
    warn "Codex CLI not found. Install: npm i -g @openai/codex-cli"
  else
    ok "Codex CLI: $(codex --version 2>/dev/null || echo unknown)"
  fi

  # Hard-dependency preflight. `--check` does NOT go through this code
  # path — it returns from main() via check_requirements() before
  # reaching here, with its own (correct) hard-fail semantics. This
  # block runs on install AND on `--dry-run` (no --check). Under
  # --dry-run we WARN about missing YQ so the operator can preview
  # the install plan on a machine that doesn't yet have it (yq is
  # only required at RUNTIME by approval-gate.sh — dry-run doesn't
  # run that hook). jq stays a HARD exit even under --dry-run
  # because downstream step-0 helpers (merge_claude_mcp_servers,
  # merge_claude_hooks at install.sh:461 and :526) hard-`return 1`
  # without jq, and `set -e` would propagate that as a script-level
  # abort — so warning here would just delay the failure to a less
  # obvious point. Better to fail fast with a clear message.
  #
  # OS-specific install hints: pick brew vs apt/snap based on
  # `uname -s` so the hint matches the operator's machine.
  local _pkg_hint_jq _pkg_hint_yq
  case "$(uname -s)" in
    Darwin)
      _pkg_hint_jq="brew install jq"
      _pkg_hint_yq="brew install yq"
      ;;
    Linux)
      _pkg_hint_jq="sudo apt install jq  # or: sudo dnf install jq"
      _pkg_hint_yq="sudo snap install yq  # or: see https://github.com/mikefarah/yq#install"
      ;;
    *)
      _pkg_hint_jq="install jq via your OS package manager"
      _pkg_hint_yq="install yq via your OS package manager"
      ;;
  esac

  if ! command -v jq >/dev/null 2>&1; then
    err "jq required. ${_pkg_hint_jq}"
    exit 4
  fi

  if ! command -v yq >/dev/null 2>&1; then
    # Hard dependency at RUNTIME (approval-gate.sh fails CLOSED if yq
    # is missing — audit P1-05). At install-plan time (--dry-run),
    # only warn so the operator can still preview the plan.
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "yq missing (would be required on real install). ${_pkg_hint_yq}"
      warn "DRY-RUN: continuing past the missing yq so the install plan"
      warn "         can be previewed. A real install would have exited here."
    else
      err "yq required (approval-gate hard dep). ${_pkg_hint_yq}"
      exit 4
    fi
  fi

  local missing=()
  for t in mise gh rg; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Optional tools missing: ${missing[*]}"
    warn "  Install all at once: ./setup/bootstrap.sh"
  fi

  ok "Preflight clean"
}

# ---------- uninstall ----------

do_uninstall() {
  step "Uninstall"

  for dir in "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/commands" \
             "$CODEX_HOME/skills"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r link; do
      local target
      target="$(readlink "$link" 2>/dev/null || true)"
      if [[ "$target" == "$REPO_ROOT/"* ]]; then
        run_args rm -- "$link"
        ok "Unlinked $link"
      fi
    done < <(find "$dir" -maxdepth 1 -type l)
  done

  for f in "$CLAUDE_HOME/CLAUDE.md" "$CODEX_HOME/AGENTS.md"; do
    if [[ -L "$f" ]] && [[ "$(readlink "$f")" == "$REPO_ROOT/"* ]]; then
      run_args rm -- "$f"
      ok "Unlinked $f"
    fi
  done

  local settings="${CLAUDE_HOME}/settings.json"
  if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
    local cleaned
    cleaned="$(jq '
      .hooks = (.hooks // {})
      | .hooks |= with_entries(
          .value |= (
            map(.hooks |= map(select(._walter_os != true)))
            | map(select((.hooks // []) | length > 0))
          )
        )
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$settings")"
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would strip walter_os hooks from $settings"
    else
      local backup
      backup="${settings}.pre-walter-os-uninstall.$(date +%s)"
      cp -- "$settings" "$backup"
      echo "$cleaned" | jq . > "$settings"
      ok "Stripped walter_os hooks from $settings (backup: $backup)"
    fi
  fi

  local plist="$LAUNCH_AGENTS/$DAILY_AUDIT_LABEL.plist"
  if [[ -f "$plist" ]]; then
    # `launchctl unload` returns non-zero if the agent isn't loaded —
    # we deliberately ignore that. Wrapping in run_args + || true keeps
    # us out of eval territory (issue #119). $plist is operator/system
    # controlled, but we still avoid the run() eval path on principle.
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "launchctl unload $plist (errors ignored)"
    else
      launchctl unload "$plist" 2>/dev/null || true
    fi
    run_args rm -- "$plist"
    ok "Removed launchd job"
  fi

  ok "Uninstall complete. Manual edits in ~/.claude/settings.json and ~/.codex/config.toml were not touched."
}

# ---------- step-0 helpers (preserved from legacy installer) ----------

ensure_dirs() {
  step "Ensure directories"
  for dir in "$CLAUDE_HOME"/{skills,agents,commands,hooks} \
             "$CODEX_HOME"/skills \
             "$WALTER_CONFIG" \
             "$LAUNCH_AGENTS"; do
    if [[ ! -d "$dir" ]]; then
      run_args mkdir -p "$dir"
      ok "Created $dir"
    fi
  done
}

link_safe() {
  local src="$1" dest="$2"
  if [[ ! -e "$src" ]]; then
    err "Source missing: $src"
    return 1
  fi
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      ok "Already linked: $dest"
      return 0
    fi
    warn "Replacing existing symlink: $dest (was → $current)"
    run_args rm -- "$dest"
  elif [[ -e "$dest" ]]; then
    local backup
    backup="${dest}.pre-walter-os.$(date +%s)"
    warn "Backing up existing $dest → $backup"
    run_args mv -- "$dest" "$backup"
  fi
  run_args ln -s "$src" "$dest"
  ok "Linked: $dest → $src"
}

link_root_files() {
  step "Link root config files"
  link_safe "$REPO_ROOT/AGENTS.md" "$CODEX_HOME/AGENTS.md"
  link_safe "$REPO_ROOT/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
}

link_dir_contents() {
  local src_dir="$1" dest_dir="$2" label="$3"
  step "Link $label"
  for entry in "$src_dir"/*; do
    [[ -e "$entry" ]] || continue
    local name; name="$(basename "$entry")"
    link_safe "$entry" "$dest_dir/$name"
  done
}

link_skills()   { link_dir_contents "$REPO_ROOT/skills"   "$CLAUDE_HOME/skills"   "skills → ~/.claude/skills"
                  link_dir_contents "$REPO_ROOT/skills"   "$CODEX_HOME/skills"    "skills → ~/.codex/skills"; }
link_agents()   { link_dir_contents "$REPO_ROOT/agents"   "$CLAUDE_HOME/agents"   "subagents → ~/.claude/agents"; }
link_commands() { link_dir_contents "$REPO_ROOT/commands" "$CLAUDE_HOME/commands" "slash commands → ~/.claude/commands"; }

# link_walter_cli — ensure `walter-os` resolves on the XDG-standard
# user binary path (`~/.local/bin/`). The canonical CLI stays in the
# clone; we add a symlink so operators don't need to learn a
# Walter-OS-specific PATH convention. See ADR 0014 for the design
# rationale and rejected alternatives.
link_walter_cli() {
  step "Link walter-os CLI → ~/.local/bin/walter-os"
  local local_bin="$HOME/.local/bin"
  local cli_src="$REPO_ROOT/bin/walter-os"

  if [[ ! -x "$cli_src" ]]; then
    warn "CLI source missing or not executable: $cli_src — skipping symlink"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "mkdir -p $local_bin"
    dry "ln -sf $cli_src $local_bin/walter-os"
    return 0
  fi

  mkdir -p "$local_bin"
  link_safe "$cli_src" "$local_bin/walter-os"

  # Heuristic: warn if ~/.local/bin/ isn't on $PATH. The existing
  # ${WALTER_OS_HOME}/bin/ export remains as a fallback regardless.
  case ":$PATH:" in
    *":$local_bin:"*) ;;  # already on PATH, nothing to say
    *)
      warn "  ~/.local/bin/ is not on your \$PATH. Add to your shell rc:"
      warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      ;;
  esac
}

merge_claude_settings() {
  merge_claude_hooks
  merge_claude_mcp_servers
}

merge_claude_mcp_servers() {
  step "Merge MCP servers into ~/.claude/settings.json (default profile)"

  if ! command -v jq >/dev/null 2>&1; then
    err "jq required to merge MCP servers."
    return 1
  fi

  local generator="$REPO_ROOT/scripts/generate-mcp-configs.sh"
  if [[ ! -x "$generator" ]]; then
    warn "MCP generator missing at $generator"
    return 0
  fi

  local high_risk_path="${CLAUDE_HOME}/settings.high-risk.json"
  local high_risk_json; high_risk_json="$("$generator" claude all manual 2>/dev/null || echo '{}')"
  if [[ "$high_risk_json" != '{}' ]] && [[ -n "$high_risk_json" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would write high-risk profile to $high_risk_path"
    else
      jq -n --argjson mcp "$high_risk_json" '{mcpServers: $mcp}' > "$high_risk_path"
      ok "Wrote high-risk profile to $high_risk_path"
      warn "  To activate: mv $high_risk_path ${CLAUDE_HOME}/settings.json"
      warn "  To deactivate: re-run install.sh --upgrade"
    fi
  fi

  local settings="${CLAUDE_HOME}/settings.json"
  local generated; generated="$("$generator" claude all default 2>/dev/null || echo '{}')"
  local current_json='{}'

  if [[ ! -f "$settings" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would create $settings with merged mcpServers"
    else
      mkdir -p "$(dirname "$settings")"
      echo '{}' > "$settings"
    fi
  else
    current_json="$(cat "$settings")"
  fi

  local merged
  merged="$(jq -n \
    --argjson existing "$current_json" \
    --argjson mcp "$generated" '
    $existing | .mcpServers = $mcp
  ')"

  if [[ "$merged" == "$current_json" ]]; then
    ok "MCP servers already up to date in $settings"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would update $settings .mcpServers from servers.json"
  else
    local backup
    backup="${settings}.pre-walter-os-mcp.$(date +%s)"
    cp -- "$settings" "$backup" 2>/dev/null || true
    echo "$merged" | jq . > "$settings"
    ok "Merged mcpServers into $settings"
  fi
}

merge_claude_hooks() {
  step "Merge Walter-OS hooks into ~/.claude/settings.json"

  if ! command -v jq >/dev/null 2>&1; then
    err "jq required to merge hooks. Install: brew install jq"
    return 1
  fi

  local settings="${CLAUDE_HOME}/settings.json"
  local current_json='{}'

  if [[ ! -f "$settings" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would create $settings with empty {} then merge hooks"
    else
      mkdir -p "$(dirname "$settings")"
      echo '{}' > "$settings"
      ok "Created empty $settings"
      current_json='{}'
    fi
  else
    current_json="$(cat "$settings")"
  fi

  local walter_hooks
  # PreToolUse Bash chain (order matters — first hook fires first):
  #   1. bash-denylist.sh  → CHEAP regex match. Blocks RCE patterns
  #      (curl|bash, eval$VAR, bash -c "$(...)", etc.) before any
  #      heavier check. Fails fast; fails closed when jq is missing.
  #   2. approval-gate.sh  → TIER-based approval matrix (P1-05/P1-06).
  #      Decides whether destructive ops / pushes / PRs need operator
  #      confirmation. Consults ~/.config/walter-os/agent-approvals.yml.
  #   3. branch-flow-guard.sh → blocks pushes that violate the
  #      configured branch flow (single-tier vs three-stage).
  #   4. pre-commit-tests.sh → runs tests/lint/typecheck on commits.
  #
  # bash-denylist + approval-gate were ABSENT from this template at
  # one point (Codex R2 MEDIUM M2 caught the regression). The bats
  # test `tests/install/hook-chain-content.bats` pins both presence
  # and ordering — a future template edit that drops either hook
  # will fail CI before reaching main.
  walter_hooks="$(jq -n --arg repo "$REPO_ROOT" '{
    SessionStart: [{
      matcher: "*",
      hooks: [{
        type: "command",
        command: ($repo + "/hooks/daily-audit-gate.sh"),
        _walter_os: true
      }]
    }],
    PreToolUse: [
      {
        matcher: "Bash",
        hooks: [
          { type: "command", command: ($repo + "/hooks/bash-denylist.sh"),    _walter_os: true },
          { type: "command", command: ($repo + "/hooks/approval-gate.sh"),    _walter_os: true },
          { type: "command", command: ($repo + "/hooks/branch-flow-guard.sh"), _walter_os: true },
          { type: "command", command: ($repo + "/hooks/pre-commit-tests.sh"),  _walter_os: true }
        ]
      },
      {
        matcher: "Write|Edit",
        hooks: [
          {
            type: "command",
            command: ($repo + "/hooks/wiki-validator-hook.sh"),
            _walter_os: true
          }
        ]
      }
    ]
  }')"

  local merged
  merged="$(jq -n \
    --argjson existing "$current_json" \
    --argjson walter "$walter_hooks" '
    $existing
    | .hooks = (.hooks // {})
    | .hooks |= with_entries(
        .value |= (
          map(.hooks |= map(select(._walter_os != true)))
          | map(select((.hooks // []) | length > 0))
        )
      )
    | .hooks |= (
        reduce ($walter | to_entries[]) as $event (.;
          .[$event.key] = ((.[$event.key] // []) + $event.value)
        )
      )
  ')"

  if [[ "$merged" == "$current_json" ]]; then
    ok "Hooks already up to date in $settings"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would update $settings with merged hooks"
    echo
    echo "${c_dim}--- diff ---${c_reset}"
    diff <(echo "$current_json" | jq -S .) <(echo "$merged" | jq -S .) || true
    echo "${c_dim}--- end diff ---${c_reset}"
  else
    local backup
    backup="${settings}.pre-walter-os.$(date +%s)"
    cp -- "$settings" "$backup"
    echo "$merged" | jq . > "$settings"
    ok "Merged hooks into $settings"
    ok "Backup at $backup"
  fi
}

write_codex_config() {
  step "Codex config (~/.codex/config.toml)"

  local header="$REPO_ROOT/setup/codex-config.toml.example"
  local generator="$REPO_ROOT/scripts/generate-mcp-configs.sh"
  local dest="$CODEX_HOME/config.toml"

  if [[ ! -f "$header" ]]; then
    warn "No header at $header, skipping codex config generation"
    return 0
  fi

  if [[ ! -x "$generator" ]]; then
    warn "MCP generator missing at $generator, skipping codex config"
    return 0
  fi

  local generated_mcp; generated_mcp="$("$generator" codex all 2>/dev/null || echo "")"

  if [[ -f "$dest" ]] && [[ $UPGRADE -ne 1 ]]; then
    ok "Codex config already exists at $dest (skipping; use --upgrade to regenerate)"
    return 0
  fi

  if [[ -f "$dest" ]]; then
    local backup
    backup="${dest}.bak.$(date +%s)"
    warn "Existing config will be backed up: $backup"
    run_args cp -- "$dest" "$backup"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would write $dest from header + generated MCP block"
  else
    {
      awk '/^\[mcp_servers\./{exit} {print}' "$header"
      echo "# ---------- MCP servers (generated from mcp/servers.json) ----------"
      echo "# Edit walter-os/mcp/servers.json then re-run install.sh --upgrade."
      echo
      echo "$generated_mcp"
    } > "$dest"
    ok "Wrote $dest (header + generated MCP from servers.json)"
  fi
}

write_env_file() {
  step "Walter-OS env file (~/.config/walter-os/env)"
  local dest="${WALTER_CONFIG}/env"
  # write_file pattern — no eval. The heredoc body was previously
  # passed to run "..." which did a SECOND-pass eval, dangerous if any
  # interpolation introduced metacharacters. Issue #119.
  local content
  content="$(cat <<EOF_WALTER_ENV
# Walter-OS env — sourced by hooks, CLI, and helper scripts.
# Generated by install.sh. Re-run 'walter-os sync' or './install.sh --upgrade'
# to refresh.

export WALTER_OS_HOME='${REPO_ROOT}'
export PATH="\${WALTER_OS_HOME}/bin:\${PATH}"
EOF_WALTER_ENV
)"
  write_file "$dest" "$content"
  ok "Wrote $dest (WALTER_OS_HOME=$REPO_ROOT)"
  warn "Add this to ~/.zshrc to make 'walter-os' CLI available everywhere:"
  warn "  [[ -f \$HOME/.config/walter-os/env ]] && source \$HOME/.config/walter-os/env"
}

write_secrets_template() {
  step "Secrets template (legacy — runtime flow is preferred)"
  local dest="$WALTER_CONFIG/secrets.env"
  if [[ -f "$dest" ]]; then
    warn "Legacy plain-text secrets.env found at $dest"
    warn "  This is deprecated. Migrate to the runtime flow:"
    warn "    1. walter-os secrets-identity-init  (one-time, OS credential store)"
    warn "    2. Open new shell — walter_secrets_load runs lazily"
    warn "    3. Once verified working, srm -z $dest"
    return 0
  fi
  ok "No legacy secrets.env (good — using runtime flow)"
  warn "  First-time setup: walter-os secrets-identity-init"
  warn "  See: docs/specs/secrets-runtime-architecture.md"
  return 0
}

sync_work_profiles() {
  step "Sync shared content into *-work profile dirs (if present)"
  local script="$REPO_ROOT/scripts/profile-bootstrap.sh"
  if [[ ! -f "$script" ]]; then
    warn "profile-bootstrap.sh missing at $script; skipping"
    return 0
  fi

  if [[ -d "${HOME}/.claude-work" ]] || [[ -d "${HOME}/.codex-work" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "bash $script sync-shared"
    elif bash "$script" sync-shared >/dev/null 2>&1; then
      ok "Re-synced .claude-work / .codex-work shared content"
    else
      warn "profile sync-shared failed (run manually: walter-os profile-bootstrap sync-shared)"
    fi
  else
    warn "No *-work profile dirs yet — run: walter-os profile-bootstrap init all"
  fi
}

copy_trust_tiers_template() {
  step "Trust tiers config (~/.config/walter-os/trust-tiers.yml)"
  local src="$REPO_ROOT/setup/templates/trust-tiers.yml"
  local dest="$WALTER_CONFIG/trust-tiers.yml"

  if [[ ! -f "$src" ]]; then
    warn "trust-tiers.yml template not found at $src — skipping"
    return 0
  fi

  if [[ -f "$dest" ]]; then
    ok "trust-tiers.yml already present at $dest (not overwriting)"
    return 0
  fi

  run_args cp -- "$src" "$dest"
  ok "Copied trust-tiers.yml to $dest"
  warn "  Review and customise: \$EDITOR $dest"
}

install_daily_audit() {
  step "Daily supply-chain audit launchd job"

  if [[ "$(uname)" != "Darwin" ]]; then
    warn "Not on macOS, skipping launchd setup. Use cron on Linux."
    return 0
  fi

  local plist="$LAUNCH_AGENTS/$DAILY_AUDIT_LABEL.plist"
  local audit_script="$REPO_ROOT/skills/daily-supply-chain-audit/scripts/audit.sh"

  if [[ ! -x "$audit_script" ]]; then
    warn "Audit script not executable yet at $audit_script (skipping launchd registration)"
    return 0
  fi

  # write_file pattern — no eval. The plist body was previously
  # passed to run "..." which did a SECOND-pass eval (issue #119).
  local plist_content
  plist_content="$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DAILY_AUDIT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$audit_script</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>8</integer>
    <key>Minute</key><integer>30</integer>
  </dict>
  <key>StandardOutPath</key><string>$WALTER_CONFIG/audit.log</string>
  <key>StandardErrorPath</key><string>$WALTER_CONFIG/audit.err</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
)"
  write_file "$plist" "$plist_content"
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "launchctl unload $plist (errors ignored)"
  else
    launchctl unload "$plist" 2>/dev/null || true
  fi
  run_args launchctl load "$plist"
  ok "Daily audit scheduled at 08:30"
}

# ==========================================================================
# WIZARD STEPS 1–9
# ==========================================================================

# Required bootstrap vars: name, description, default, required (1/0), secret (1/0)
# shellcheck disable=SC2034
BOOTSTRAP_VARS=(
  "WALTER_DOMAIN:Your public domain (e.g. example.com)::1:0"
  "WALTER_ADMIN_EMAIL:Admin email for TLS + notifications::1:0"
  "WALTER_INITIAL_USER:Initial admin username:admin:0:0"
  "WALTER_INITIAL_PASSWORD:Initial admin password (hidden input)::1:1"
  "WALTER_TIMEZONE:System timezone:$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || echo 'UTC'):0:0"
)

# ---------- Step 1: OS detect + dep install [AC-2] ----------

step_1() {
  wizard_step 1 "OS detect + install deps"

  local os
  os="$(uname -s)"

  case "$os" in
    Darwin)
      ok "macOS detected ($(uname -m))"
      _install_deps_macos
      ;;
    Linux)
      ok "Linux detected"
      _install_deps_linux
      ;;
    *)
      err "Unsupported OS: $os. Only macOS and Linux are supported."
      exit 1
      ;;
  esac
}

_install_deps_macos() {
  local required_deps=(git curl jq docker bats)
  local optional_deps=(yq python3)

  # Hard dependency: docker
  if ! command -v docker >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would require: docker (not installed — see https://www.docker.com/products/docker-desktop/)"
    else
      err "Docker is required but not installed."
      err "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
      err "Or via Homebrew: brew install --cask docker"
      exit 1
    fi
  else
    ok "docker found: $(docker --version 2>/dev/null | head -1)"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would require: brew (not installed — see https://brew.sh)"
    else
      err "Homebrew not found. Install from https://brew.sh then re-run."
      exit 1
    fi
  fi

  for dep in "${required_deps[@]}"; do
    [[ "$dep" == "docker" ]] && continue
    if command -v "$dep" >/dev/null 2>&1; then
      ok "$dep already installed"
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "would run: brew install $dep"
      else
        say "Installing $dep via Homebrew..."
        brew install "$dep"
        ok "Installed $dep"
      fi
    fi
  done

  for dep in "${optional_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      ok "$dep already installed (optional)"
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "would run: brew install $dep (optional)"
      else
        say "Installing optional dep $dep via Homebrew..."
        brew install "$dep" || warn "$dep install failed (optional, continuing)"
      fi
    fi
  done
}

_install_deps_linux() {
  local required_deps=(git curl jq bats)
  local optional_deps=(yq python3)

  # Hard dependency: docker
  if ! command -v docker >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would require: docker (not installed — see https://docs.docker.com/engine/install/)"
    else
      err "Docker is required but not installed."
      err "Install via: https://docs.docker.com/engine/install/"
      exit 1
    fi
  else
    ok "docker found: $(docker --version 2>/dev/null | head -1)"
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found. Only Debian/Ubuntu Linux is supported for auto-install."
    warn "Install manually: ${required_deps[*]}"
    return 0
  fi

  for dep in "${required_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      ok "$dep already installed"
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "would run: sudo apt-get install -y $dep"
      else
        say "Installing $dep via apt-get..."
        sudo apt-get install -y "$dep"
        ok "Installed $dep"
      fi
    fi
  done

  for dep in "${optional_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      ok "$dep already installed (optional)"
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "would run: sudo apt-get install -y $dep (optional)"
      else
        sudo apt-get install -y "$dep" || warn "$dep install failed (optional, continuing)"
      fi
    fi
  done
}

# ---------- Step 2: env var prompts [AC-3] ----------

step_2() {
  wizard_step 2 "Bootstrap env vars → ${ENV_LOCAL}"

  if [[ $DRY_RUN -ne 1 ]] && [[ ! -d "$(dirname "$ENV_LOCAL")" ]]; then
    mkdir -p "$(dirname "$ENV_LOCAL")"
  fi

  # Load existing values
  load_env_local

  for var_spec in "${BOOTSTRAP_VARS[@]}"; do
    IFS=':' read -r var_name var_desc var_default var_required var_secret <<< "$var_spec"

    # Current value (from env or already-loaded env.local)
    local current_val="${!var_name:-}"

    if [[ $DRY_RUN -eq 1 ]]; then
      if [[ -n "$current_val" ]]; then
        if [[ "$var_secret" == "1" ]]; then
          dry "would prompt $var_name (current: [hidden])"
        else
          dry "would prompt $var_name (current: $current_val)"
        fi
      else
        dry "would prompt $var_name (default: ${var_default:-none})"
      fi
      continue
    fi

    local prompt_default
    if [[ -n "$current_val" ]]; then
      if [[ "$var_secret" == "1" ]]; then
        prompt_default="[currently set, press Enter to keep]"
      else
        prompt_default="$current_val"
      fi
    elif [[ -n "$var_default" ]]; then
      prompt_default="$var_default"
    else
      prompt_default=""
    fi

    say ""
    say "${c_b}${var_name}${c_reset} — ${var_desc}"

    local new_val=""
    if [[ "$var_secret" == "1" ]]; then
      # Hidden input with confirmation
      while true; do
        read -r -s -p "  Enter value (hidden)${prompt_default:+ [$prompt_default]}: " new_val
        echo
        if [[ -z "$new_val" ]]; then
          # Keep current
          new_val="$current_val"
          break
        fi
        read -r -s -p "  Confirm value (hidden): " new_val_confirm
        echo
        if [[ "$new_val" == "$new_val_confirm" ]]; then
          break
        else
          warn "  Values do not match, try again."
          new_val=""
        fi
      done
    else
      read -r -p "  Value${prompt_default:+ [$prompt_default]}: " new_val
      if [[ -z "$new_val" ]]; then
        new_val="${current_val:-$var_default}"
      fi
    fi

    # Validation: required vars must be non-empty
    if [[ "$var_required" == "1" ]] && [[ -z "$new_val" ]]; then
      err "$var_name is required. Please re-run step 2 and provide a value."
      exit 1
    fi

    if [[ -n "$new_val" ]]; then
      _write_env_var "$var_name" "$new_val"
    fi
  done

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would write ${ENV_LOCAL} with collected values (mode 0600)"
    return 0
  fi

  if [[ -f "$ENV_LOCAL" ]]; then
    chmod 600 "$ENV_LOCAL"
    ok "Wrote ${ENV_LOCAL} (mode 0600)"
  fi

  # Reload so subsequent steps see the new values
  load_env_local
}

# Write or update a single var in env.local (idempotent)
_write_env_var() {
  local var_name="$1" var_value="$2"
  local escaped
  escaped="$(printf '%s' "$var_value" | sed "s/'/'\\\\''/g")"

  if [[ -f "$ENV_LOCAL" ]] && grep -q "^export ${var_name}=" "$ENV_LOCAL" 2>/dev/null; then
    # Replace existing line
    sed -i.bak "s|^export ${var_name}=.*|export ${var_name}='${escaped}'|" "$ENV_LOCAL"
    rm -f "${ENV_LOCAL}.bak"
  else
    # Append
    echo "export ${var_name}='${escaped}'" >> "$ENV_LOCAL"
  fi
}

# ---------- Step 3: personal overlay init [AC-4] ----------

step_3() {
  wizard_step 3 "Personal overlay init (W-5)"

  local overlay_dir="${HOME}/.config/walter-os/overlay"
  local overlay_script="${REPO_ROOT}/setup/personal-overlay-init.sh"

  if [[ -d "$overlay_dir" ]]; then
    ok "Overlay found at $overlay_dir — skipping init."
    say "  Edit overlay files to personalize your Walter-OS installation."
    return 0
  fi

  if [[ ! -f "$overlay_script" ]]; then
    warn "personal-overlay-init.sh not found at $overlay_script"
    warn "  Skipping overlay init. Run manually after locating the script."
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would call: bash $overlay_script --dry-run"
    dry "would print: Fill in ~/.config/walter-os/overlay/profile.md with your operator profile"
    return 0
  fi

  bash "$overlay_script"
  ok "Personal overlay initialized."
  say "  Next: fill in ${overlay_dir}/profile.md with your operator profile."
}

# ---------- Step 4: Plane workspace + states [AC-5] ----------

step_4() {
  wizard_step 4 "Plane workspace + custom states"

  load_env_local

  local plane_token="${PLANE_API_TOKEN:-}"
  local plane_url="${PLANE_API_URL:-}"

  if [[ -z "$plane_token" ]] || [[ -z "$plane_url" ]]; then
    warn "Plane not configured — skipping."
    warn "  Set PLANE_API_TOKEN and PLANE_API_URL in ${ENV_LOCAL}"
    warn "  Re-run with: ./install.sh --step 4"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would call Plane API at $plane_url to create workspace: walter-os"
    dry "would create states: awaiting-resume, awaiting-consensus, awaiting-human, held_for_vacation"
    return 0
  fi

  # Test Plane reachability
  if ! curl -sf -o /dev/null --max-time 5 \
       -H "x-api-key: $plane_token" \
       "${plane_url}/workspaces/" 2>/dev/null; then
    warn "Plane API not reachable at $plane_url — skipping."
    warn "  Ensure Plane is running, then re-run: ./install.sh --step 4"
    return 0
  fi

  _plane_create_workspace "$plane_token" "$plane_url"
  _plane_create_states "$plane_token" "$plane_url"
}

_plane_create_workspace() {
  local token="$1" base_url="$2"
  local ws_name="walter-os"

  # Check if workspace already exists
  local existing
  existing="$(curl -sf --max-time 10 \
    -H "x-api-key: $token" \
    "${base_url}/workspaces/" 2>/dev/null || echo '{}')"

  if echo "$existing" | jq -e --arg n "$ws_name" \
       '.results[]? | select(.name == $n)' >/dev/null 2>&1; then
    ok "Plane workspace '$ws_name' already exists — skipping creation."
    return 0
  fi

  local resp
  resp="$(curl -sf --max-time 15 \
    -X POST \
    -H "x-api-key: $token" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$ws_name\",\"slug\":\"$ws_name\"}" \
    "${base_url}/workspaces/" 2>/dev/null || echo '{}')"

  if echo "$resp" | jq -e '.id' >/dev/null 2>&1; then
    ok "Created Plane workspace: $ws_name"
  else
    warn "Could not create Plane workspace. Check PLANE_API_URL and PLANE_API_TOKEN."
  fi
}

_plane_create_states() {
  local token="$1" base_url="$2"
  local ws_slug="walter-os"
  local custom_states=("awaiting-resume" "awaiting-consensus" "awaiting-human" "held_for_vacation")

  # Get projects in the workspace
  local projects
  projects="$(curl -sf --max-time 10 \
    -H "x-api-key: $token" \
    "${base_url}/workspaces/${ws_slug}/projects/" 2>/dev/null || echo '{"results":[]}')"

  local project_id
  project_id="$(echo "$projects" | jq -r '.results[0].id // empty' 2>/dev/null || echo '')"

  if [[ -z "$project_id" ]]; then
    warn "No projects found in workspace '$ws_slug' — cannot create states."
    warn "  Create a project in Plane, then re-run: ./install.sh --step 4"
    return 0
  fi

  for state_name in "${custom_states[@]}"; do
    # Check if state exists
    local states_resp
    states_resp="$(curl -sf --max-time 10 \
      -H "x-api-key: $token" \
      "${base_url}/workspaces/${ws_slug}/projects/${project_id}/states/" 2>/dev/null || echo '{"results":[]}')"

    if echo "$states_resp" | jq -e --arg n "$state_name" \
         '.results[]? | select(.name == $n)' >/dev/null 2>&1; then
      ok "Plane state '$state_name' already exists — skipping."
      continue
    fi

    local create_resp
    create_resp="$(curl -sf --max-time 15 \
      -X POST \
      -H "x-api-key: $token" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$state_name\",\"color\":\"#6b7280\",\"group\":\"backlog\"}" \
      "${base_url}/workspaces/${ws_slug}/projects/${project_id}/states/" 2>/dev/null || echo '{}')"

    if echo "$create_resp" | jq -e '.id' >/dev/null 2>&1; then
      ok "Created Plane state: $state_name"
    else
      warn "Could not create state '$state_name'. Check PLANE_API_URL and PLANE_API_TOKEN."
    fi
  done
}

# ---------- Step 5: Provision Postgres DBs [AC-6] ----------

step_5() {
  wizard_step 5 "Provision Postgres databases"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would provision databases: walter_lessons, walter_analytics, walter_control_tower"
    dry "would provision per-service DBs: forgejo, infisical, litellm, n8n, postiz, metabase"
    dry "would run: ${REPO_ROOT}/setup/postgres/init.sql (existing per-service DBs)"
    dry "would add walter_lessons, walter_analytics, walter_control_tower users+DBs"
    return 0
  fi

  # Try docker exec first (for containerized Postgres), then local psql
  # Use compose service label for exact match — avoids false positives from
  # containers that merely have "postgres" in their name.
  local pg_container
  pg_container="$(docker ps --filter label=com.docker.compose.service=postgres \
    --format '{{.Names}}' 2>/dev/null | head -1)"
  pg_container="${pg_container:-${POSTGRES_CONTAINER:-}}"

  local pg_running=0
  [[ -n "$pg_container" ]] && pg_running=1

  local psql_cmd
  if [[ $pg_running -eq 1 ]]; then
    psql_cmd="docker exec -i $pg_container psql -U postgres"
  elif command -v psql >/dev/null 2>&1; then
    psql_cmd="psql -U postgres"
  else
    warn "Postgres not reachable (no running container, no local psql)."
    warn "  Start Postgres, then re-run: ./install.sh --step 5"
    return 0
  fi

  # Test connectivity
  if ! $psql_cmd -c '\q' >/dev/null 2>&1; then
    warn "Postgres not reachable — skipping."
    warn "  Re-run with: ./install.sh --step 5"
    return 0
  fi

  # Run existing init.sql (per-service DBs)
  local init_sql="${REPO_ROOT}/setup/postgres/init.sql"
  if [[ -f "$init_sql" ]]; then
    say "Running ${init_sql}..."
    $psql_cmd < "$init_sql" && ok "Per-service databases initialized from init.sql"
  fi

  # Walter-OS specific databases
  local walter_dbs=(
    "walter_lessons:walter_lessons_user"
    "walter_analytics:walter_analytics_user"
    "walter_control_tower:walter_ct_user"
  )

  for db_spec in "${walter_dbs[@]}"; do
    IFS=':' read -r db_name db_user <<< "$db_spec"
    $psql_cmd <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$db_user') THEN
    CREATE USER $db_user;
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE $db_name OWNER $db_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db_name')\gexec
GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;
SQL
    ok "Provisioned: $db_name (owner: $db_user)"
  done
}

# ---------- Step 6: docker compose up [AC-7] ----------

step_6() {
  wizard_step 6 "docker compose up + bootstrap"

  local compose_file="${COMPOSE_FILE:-${REPO_ROOT}/compose.yml}"

  if [[ ! -f "$compose_file" ]]; then
    warn "Compose file not found at $compose_file"
    warn "  W-1 (Docker compose) must be complete before this step."
    warn "  See: docs/specs/phase-w-1-docker-compose.md"
    warn "  Skipping step 6. Re-run: ./install.sh --step 6"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would run: docker compose -f $compose_file up -d"
    dry "would wait for health checks (max 3 min, 10s intervals)"
    dry "would run: ${REPO_ROOT}/scripts/bootstrap.sh"
    return 0
  fi

  say "Starting services via docker compose..."
  docker compose -f "$compose_file" up -d
  ok "docker compose up -d started"

  # Health check loop: max 18 iterations × 10s = 3 minutes
  say "Waiting for services to become healthy..."
  local max_attempts=18 attempt=0 all_healthy=0
  while [[ $attempt -lt $max_attempts ]]; do
    local unhealthy
    unhealthy="$(docker compose -f "$compose_file" ps --format json 2>/dev/null \
      | jq -r 'select(.Health != "" and .Health != "healthy") | .Name' 2>/dev/null \
      | wc -l | tr -d ' ')"
    if [[ "$unhealthy" -eq 0 ]]; then
      all_healthy=1
      break
    fi
    sleep 10
    attempt=$(( attempt + 1 ))
    say "  Still waiting... ($attempt/$max_attempts)"
  done

  if [[ $all_healthy -eq 1 ]]; then
    ok "All services healthy."
  else
    warn "Some services may not be healthy after 3 minutes. Check: docker compose ps"
  fi

  # Bootstrap script
  local bootstrap="${REPO_ROOT}/scripts/bootstrap.sh"
  if [[ -f "$bootstrap" ]]; then
    say "Running bootstrap.sh..."
    bash "$bootstrap" && ok "bootstrap.sh complete"
  else
    warn "scripts/bootstrap.sh not found — skipping"
  fi
}

# ---------- Step 7: n8n workflow import [AC-8] ----------

step_7() {
  wizard_step 7 "n8n workflow template import"

  local import_script="${REPO_ROOT}/setup/walter-host/services/n8n/import-workflows.sh"

  if [[ ! -f "$import_script" ]]; then
    warn "n8n import script not found at $import_script — skipping."
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would call: bash $import_script"
    dry "would import Tier 1 workflows: YouTube, Plausible, GitHub, Bluesky, X CSV"
    return 0
  fi

  # Test n8n reachability
  load_env_local
  local n8n_url="${N8N_URL:-http://localhost:5678}"
  if ! curl -sf -o /dev/null --max-time 5 "${n8n_url}/healthz" 2>/dev/null; then
    warn "n8n not reachable at $n8n_url — skipping workflow import."
    warn "  Start n8n (step 6), then re-run: ./install.sh --step 7"
    return 0
  fi

  bash "$import_script" && ok "n8n workflow templates imported."
}

# ---------- Step 8: Infisical init [AC-9] ----------

step_8() {
  wizard_step 8 "Infisical workspace + Machine Identity"

  load_env_local
  local infisical_url="${INFISICAL_API_URL:-}"

  if [[ -z "$infisical_url" ]]; then
    warn "INFISICAL_API_URL not set — skipping."
    warn "  Set INFISICAL_API_URL in ${ENV_LOCAL}, then re-run: ./install.sh --step 8"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would call Infisical API at $infisical_url"
    dry "would create workspace: walter-os, project: dev"
    dry "would create Machine Identity: walter-agent (universal auth)"
    dry "would write INFISICAL_CLIENT_ID + INFISICAL_CLIENT_SECRET to ${ENV_LOCAL}"
    return 0
  fi

  # Test Infisical reachability
  if ! curl -sf -o /dev/null --max-time 5 "${infisical_url}/status" 2>/dev/null; then
    warn "Infisical not reachable at $infisical_url — skipping."
    warn "  Ensure Infisical is running, then re-run: ./install.sh --step 8"
    return 0
  fi

  local infisical_token="${INFISICAL_TOKEN:-}"
  if [[ -z "$infisical_token" ]]; then
    warn "INFISICAL_TOKEN not set. Cannot authenticate to create workspace."
    warn "  Set INFISICAL_TOKEN in ${ENV_LOCAL} and re-run: ./install.sh --step 8"
    return 0
  fi

  _infisical_create_workspace "$infisical_url" "$infisical_token"
}

_infisical_create_workspace() {
  local api_url="$1" token="$2"
  local ws_name="walter-os"
  local hostname; hostname="$(hostname -s 2>/dev/null || echo 'localhost')"
  local identity_name="walter-agent-${hostname}"

  # Create workspace
  local ws_resp
  ws_resp="$(curl -sf --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"workspaceName\":\"$ws_name\",\"projectName\":\"dev\"}" \
    "${api_url}/v2/workspace" 2>/dev/null || echo '{}')"

  local ws_id
  ws_id="$(echo "$ws_resp" | jq -r '.workspace.id // empty' 2>/dev/null || echo '')"

  if [[ -n "$ws_id" ]]; then
    ok "Infisical workspace '$ws_name' created (id: $ws_id)"
  else
    # May already exist — try to fetch
    ok "Infisical workspace may already exist (or creation response unclear)."
  fi

  # Create Machine Identity with Universal Auth
  local identity_resp
  identity_resp="$(curl -sf --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$identity_name\",\"organizationRole\":\"member\"}" \
    "${api_url}/v1/identities" 2>/dev/null || echo '{}')"

  local identity_id
  identity_id="$(echo "$identity_resp" | jq -r '.identity.id // empty' 2>/dev/null || echo '')"

  if [[ -z "$identity_id" ]]; then
    warn "Could not create Machine Identity. Check INFISICAL_API_URL and INFISICAL_TOKEN."
    return 0
  fi

  ok "Created Machine Identity: $identity_name (id: $identity_id)"

  # Add Universal Auth to the identity
  local ua_resp
  ua_resp="$(curl -sf --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${api_url}/v1/auth/universal-auth/identities/${identity_id}" 2>/dev/null || echo '{}')"

  local client_id
  client_id="$(echo "$ua_resp" | jq -r '.identityUniversalAuth.clientId // empty' 2>/dev/null || echo '')"

  # Create client secret
  local secret_resp
  secret_resp="$(curl -sf --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{"description":"Created by install.sh wizard","numUsesLimit":0}' \
    "${api_url}/v1/auth/universal-auth/identities/${identity_id}/client-secrets" 2>/dev/null || echo '{}')"

  local client_secret
  client_secret="$(echo "$secret_resp" | jq -r '.clientSecret.clientSecret // empty' 2>/dev/null || echo '')"

  if [[ -n "$client_id" ]] && [[ -n "$client_secret" ]]; then
    _write_env_var "INFISICAL_CLIENT_ID" "$client_id"
    _write_env_var "INFISICAL_CLIENT_SECRET" "$client_secret"
    chmod 600 "$ENV_LOCAL"
    ok "Machine Identity credentials written to ${ENV_LOCAL}"
    warn "  INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET written (one-time)."
    warn "  Store the client secret in Vaultwarden: bw create item ..."
  else
    warn "Could not retrieve Machine Identity credentials. Configure manually in Infisical."
  fi
}

# ---------- Step 9: walter doctor + next-steps banner [AC-10] ----------

step_9() {
  wizard_step 9 "Doctor check + next-steps banner"

  load_env_local
  local domain="${WALTER_DOMAIN:-<your-domain>}"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would run: walter doctor"
    dry "would print next-steps banner with URLs for domain: $domain"
    return 0
  fi

  # Run walter doctor
  local doctor_cmd="${REPO_ROOT}/bin/walter"
  if command -v walter >/dev/null 2>&1 || [[ -x "$doctor_cmd" ]]; then
    local walter_bin
    walter_bin="$(command -v walter 2>/dev/null || echo "$doctor_cmd")"
    say ""
    say "Running: $walter_bin doctor"
    say "─────────────────────────────────────────────────────────"
    "$walter_bin" doctor || warn "walter doctor reported issues — review above output."
    say "─────────────────────────────────────────────────────────"
  else
    warn "walter CLI not found. Skipping doctor check."
    warn "  Add ${REPO_ROOT}/bin to PATH and re-run: ./install.sh --step 9"
  fi

  _print_next_steps "$domain"
}

_print_next_steps() {
  local domain="$1"

  cat <<BANNER

${c_b}${c_green}══════════════════════════════════════════════════════════════${c_reset}
${c_b}${c_green}  Walter-OS installation complete!${c_reset}
${c_b}${c_green}══════════════════════════════════════════════════════════════${c_reset}

${c_b}Your services:${c_reset}
  Control Tower   https://tower.${domain}
  Grafana         https://grafana.${domain}
  Plane           https://plane.${domain}
  Forgejo         https://git.${domain}
  Infisical       https://secrets.${domain}
  n8n             https://n8n.${domain}
  LiteLLM         https://llm.${domain}

${c_b}First commands:${c_reset}
  walter new project --interactive    # scaffold a new project
  walter council status               # check Council agent status
  walter doctor                       # verify installation health

${c_b}Manual steps still needed:${c_reset}
  1. DNS: point *.${domain} to this machine's IP
  2. TLS: Caddy will auto-provision ACME certs on first request
  3. Plane: finish workspace setup at https://plane.${domain}
  4. Infisical: review Machine Identity at https://secrets.${domain}

${c_b}Docs:${c_reset}
  Full prereqs:   ${REPO_ROOT}/docs/operational/council-v2-prereqs.md
  Deployment:     ${REPO_ROOT}/docs/operational/council-v2-deployment-runbook.md
  Specs:          ${REPO_ROOT}/docs/specs/

${c_b}Updates:${c_reset}
  cd ${REPO_ROOT} && git pull && ./install.sh --upgrade

BANNER
}

# ==========================================================================
# STEP-0: Legacy symlink/config install (always runs on full install + --upgrade)
# ==========================================================================

setup_git_hooks() {
  step "Git hooks (gitleaks pre-commit via .githooks/)"

  local script="$REPO_ROOT/scripts/setup-githooks.sh"
  if [[ ! -f "$script" ]]; then
    warn "setup-githooks.sh not found at $script — skipping git hook setup"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "bash $script --dry-run"
    bash "$script" --dry-run
  else
    bash "$script"
  fi
}

run_step_0() {
  check_preflight
  ensure_dirs
  link_root_files
  link_skills
  link_agents
  link_commands
  link_walter_cli
  merge_claude_settings
  write_codex_config
  write_env_file
  write_secrets_template
  copy_trust_tiers_template
  sync_work_profiles
  install_daily_audit
  setup_git_hooks
}

# ==========================================================================
# MAIN
# ==========================================================================

main() {
  if [[ $CHECK_ONLY -eq 1 ]]; then
    check_requirements
    exit $?
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY-RUN mode. No changes will be made."
  fi

  if [[ $UNINSTALL -eq 1 ]]; then
    do_uninstall
    exit 0
  fi

  # --step N: run only that wizard step (for recovery)
  if [[ -n "$STEP_ONLY" ]]; then
    "step_${STEP_ONLY}"
    exit 0
  fi

  # --upgrade: step 0 only (fast path)
  if [[ $UPGRADE -eq 1 ]]; then
    run_step_0
    exit 0
  fi

  # Full wizard: step 0 then steps 1-9
  run_step_0
  step_1
  step_2
  step_3
  step_4
  step_5
  step_6
  step_7
  step_8
  step_9
}

# Only execute main when run as a script (not when sourced — e.g. by
# bats tests that need to invoke individual functions in isolation).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
