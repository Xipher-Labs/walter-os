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
#                            # (interactive: prompts to restore the
#                            # operator's pre-Walter-OS files from
#                            # the OLDEST `.pre-walter-os.<ts>` backup.
#                            # Add --restore-backups for non-interactive
#                            # yes; --no-restore-backups for non-
#                            # interactive no. Closes #191.)
#   ./install.sh --uninstall --restore-backups      # auto-restore on uninstall
#   ./install.sh --uninstall --no-restore-backups   # never restore on uninstall
#   ./install.sh --cursor-rules
#     opt-in: generate <cwd>/.cursor/rules/walter-os.mdc from the
#     AGENTS.md cascade (Cursor MDC adapter). Recent Cursor versions
#     read AGENTS.md natively — this materialises the rules in the
#     IDE's "Rules for AI" panel. Verify with `walter-os doctor --cursor`.
#     Spec: docs/specs/cursor-adapter-completion.md
#   ./install.sh --antigravity-rules
#     opt-in: generate <cwd>/.agent/rules/walter-os.md from the
#     AGENTS.md cascade (Antigravity adapter). Antigravity v1.20.3+
#     reads AGENTS.md natively — this materialises the rules for
#     operators who want a stable per-tool mirror. Verify with
#     `walter-os doctor --antigravity`.
#     Spec: docs/specs/antigravity-adapter.md
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
# Allow env-set overrides BEFORE the readonly is fixed. This makes the
# script testable in isolation (bats can point CLAUDE_HOME at a tmpdir
# without writing to the operator's real ~/.claude) and also lets
# packagers redirect install paths when invoking from a wrapper.
# Operator-set values take precedence; sensible defaults otherwise.
# Copilot R1 #201.
readonly CLAUDE_HOME="${CLAUDE_HOME:-${HOME}/.claude}"
readonly CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
readonly WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
readonly LAUNCH_AGENTS="${LAUNCH_AGENTS:-${HOME}/Library/LaunchAgents}"
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
CURSOR_RULES_ONLY=0  # if 1, only run the Cursor MDC generator and exit
ANTIGRAVITY_RULES_ONLY=0  # if 1, only run the Antigravity adapter and exit
RESTORE_BACKUPS="${RESTORE_BACKUPS:-}"  # yes/no/prompt — see _restore_oldest_backup
                                        # (default: prompt when TTY, skip when non-TTY)

_args=("$@")
i=0
while [[ $i -lt ${#_args[@]} ]]; do
  arg="${_args[$i]}"
  case "$arg" in
    --check)     CHECK_ONLY=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    --upgrade)   UPGRADE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --restore-backups)
      # During --uninstall, automatically restore the operator's
      # pre-Walter-OS file from the OLDEST `.pre-walter-os.<ts>`
      # backup (and clean up stale Walter-OS-captured copies).
      # See _restore_oldest_backup. Closes #191 Gap 1.
      RESTORE_BACKUPS=yes
      ;;
    --no-restore-backups)
      # During --uninstall, leave all backup files in place — never
      # restore. Useful when the operator already manually restored
      # what they wanted and just wants a clean uninstall.
      RESTORE_BACKUPS=no
      ;;
    --cursor-rules)
      # Generate the project-local Cursor MDC adapter at
      # <repo-root>/.cursor/rules/walter-os.mdc from the AGENTS.md cascade.
      # See ADR / spec: docs/specs/cursor-adapter-completion.md
      # Opt-in only — recent Cursor versions read AGENTS.md natively.
      CURSOR_RULES_ONLY=1
      ;;
    --antigravity-rules)
      # Generate the project-local Antigravity adapter at
      # <repo-root>/.agent/rules/walter-os.md from the AGENTS.md cascade.
      # See spec: docs/specs/antigravity-adapter.md
      # Opt-in only — Antigravity v1.20.3+ reads AGENTS.md natively at
      # the repo root. The .agent/rules/ mirror is for operators who
      # want isolation from third-party AGENTS.md edits OR who need to
      # distribute team-specific Walter-OS rules across multiple
      # AGENTS.md hierarchies.
      ANTIGRAVITY_RULES_ONLY=1
      ;;
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
  # Codex R3 #125: --check (which calls check_requirements) was passing on
  # any `yq` on PATH, including apt's kislyuk/yq which is the wrong tool.
  # Add the flavor check inline so --check reports the same wrong-flavor
  # exit as the install path.
  if command -v yq >/dev/null 2>&1; then
    if ! (yq --version 2>&1 | grep -qi 'mikefarah'); then
      err "yq is installed but is NOT mikefarah/yq (required by hooks)"
      say "  Detected: $(yq --version 2>&1 | head -1)" >&2
      say "  Fix: sudo apt-get remove -y yq && sudo snap install yq" >&2
      _requirement_failures=$((_requirement_failures + 1))
    fi
  fi

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
#
# Zero-arg guard (Copilot R3 #128): with `set -euo pipefail`, an empty
# "$@" expansion becomes a no-op that silently succeeds, which can mask
# bugs at call sites that built an argv array incorrectly. Return 2 with
# a clear message so the misuse fails loudly.
run_args() {
  [[ $# -ge 1 ]] || { echo "run_args: requires at least 1 argument (the command + args)" >&2; return 2; }
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
    # Pipe the snippet to `bash -s` via stdin (Copilot R3 #128). The
    # snippet bytes pass through `printf '%s\n'` verbatim — no outer-
    # shell re-interpretation of quotes/backslashes/$-substitutions, and
    # no inner `eval` layer. `set -euo pipefail` prepended as the first
    # script line keeps strict-mode parity with install.sh.
    #
    # Previous patterns + why they were rejected:
    #   bash -c "set -euo pipefail; $1"
    #     R2 finding: outer "" re-interpolates $1's contents.
    #   bash -c 'set -euo pipefail; eval "$1"' bash "$1"
    #     R3 finding: extra eval layer adds quoting surprises +
    #     re-parsing risk on operator-controlled snippets.
    printf '%s\n' 'set -euo pipefail' "$1" | bash -s
  fi
}

# write_file — replaces the `cat > '$dest' <<EOF ... EOF` pattern. Takes
# a destination path and content as separate args, writes via printf
# (no eval, no second-pass variable expansion). Issue #119.
#
# Arg-count guard parallels run_sh's (Copilot R3 #128) — `set -u` would
# otherwise produce an unhelpful unbound-parameter error on missing args.
#
# Trailing-newline restoration (Copilot R3 #128, MAJOR): when callers
# build $content via `content="$(cat <<EOF ... )"`, bash command
# substitution strips trailing newlines. The previous direct-heredoc
# form (`cat > file <<EOF ... EOF`) produced ONE trailing newline.
# `printf '%s\n'` here re-adds that single trailing newline to keep
# the written file byte-equivalent to the original heredoc output
# (env files + plists both end with one newline by convention; tools
# like systemd/launchd and the env-file consumers expect it).
write_file() {
  [[ $# -eq 2 ]] || { echo "write_file: requires exactly 2 arguments (dest + content)" >&2; return 2; }
  local dest="$1" content="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "write_file: $dest ($(printf '%s\n' "$content" | wc -c | tr -d ' ') bytes)"
  else
    printf '%s\n' "$content" > "$dest"
  fi
}

# _shell_quote — bash-safe quoting for a single value that will be
# interpolated into a shell file (e.g. env file with `export X=$val`).
# Uses printf '%q' which handles single quotes, backslashes, newlines,
# and metacharacters. Closes issue #133: previously REPO_ROOT was
# interpolated into `export WALTER_OS_HOME='${REPO_ROOT}'` with a
# literal single-quoted form, which broke + injected commands if
# REPO_ROOT contained a single quote character.
_shell_quote() {
  printf '%q' "$1"
}

# _xml_escape — escape the 5 XML-reserved characters in a single value
# so it's safe to interpolate inside `<string>...</string>` (and
# attribute values). Closes issue #134: previously $audit_script (a
# path) was interpolated raw into the launchd plist; a clone path
# containing `<`, `>`, `&`, `'`, or `"` would break the XML structure
# or — worse — let an attacker close a `<string>` tag early and inject
# new <key>/<string> pairs that launchd would honor on every audit run.
#
# Order matters: '&' must be replaced FIRST (before introducing other
# &entities;), otherwise we'd double-escape the entities we just added.
_xml_escape() {
  local v="$1"
  # bash 5.2+ enables `patsub_replacement` by default — under that
  # shopt, an unescaped `&` in the replacement of `${var//pat/repl}`
  # is interpreted as "the matched text". `${v//</&lt;}` then produces
  # `<lt;` instead of `&lt;` (the `&` gets eaten). Locally disable the
  # shopt so substitutions work identically on bash 5.1 (macOS Homebrew,
  # older Ubuntu) and 5.2+ (Ubuntu 24.04+, current GitHub Actions runners).
  # Found by PR #141 CI failure on bash 5.2; without this shopt the
  # plist render would have silently produced broken XML on every
  # operator install running bash 5.2+.
  shopt -u patsub_replacement 2>/dev/null || true
  v="${v//&/&amp;}"
  v="${v//</&lt;}"
  v="${v//>/&gt;}"
  v="${v//\"/&quot;}"
  v="${v//\'/&apos;}"
  printf '%s' "$v"
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

  # yq presence handling (Codex R2-R6 #125 — flavor check + ordering):
  # Three cases the preflight needs to disambiguate. Codex R6 collapsed
  # the previous (a) warn-then-step1-installs path: run_step_0 writes
  # the approval-gate hook BEFORE step_1 ever runs, so a step_1 failure
  # mid-install would leave the operator with a broken hook (closed-by-
  # default on yq-missing). Now: missing yq is always a hard-fail in
  # preflight regardless of mode — operator installs once, re-runs.
  #   (a) yq missing entirely: hard-exit with install hint (DRY_RUN
  #       still warn-only, so the install plan can be previewed).
  #   (b) yq present + mikefarah flavor: ok, proceed.
  #   (c) yq present + WRONG flavor (kislyuk/Python yq from apt): hard-exit
  #       with remediation. Without this check, an apt-yq machine would
  #       pass preflight + fail at hook-runtime when approval-gate.sh
  #       tries mikefarah-only syntax.
  if ! command -v yq >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "yq missing (would be required on real install). ${_pkg_hint_yq}"
      warn "DRY-RUN: continuing past the missing yq so the install plan can be previewed."
    else
      # Codex R6 #125 BLOCKER fix: previous version warned-and-continued
      # in full-install mode hoping step_1 would install yq. But
      # run_step_0 writes the approval-gate hook BEFORE step_1 ever
      # runs — and if step_1 fails for any reason (no Docker, no brew,
      # no snap, network/package error), the operator is left with the
      # hook in place + no yq, which fails closed on every claude/codex
      # invocation. Better: hard-fail in preflight on missing yq.
      # Operator installs it once, then re-runs. Aligns with --check's
      # behavior + AGENTS.md "fail fast" pattern.
      err "yq required (approval-gate hard dep) and not installed."
      err "  Install yq first, then re-run install.sh: ${_pkg_hint_yq}"
      err "  (mikefarah/yq, not apt's kislyuk/yq — they share a name but"
      err "   only mikefarah/yq has the syntax our hooks use)"
      exit 4
    fi
  else
    # Flavor check using the same helper Step 1's install path uses.
    # Defined inline here so check_preflight doesn't depend on
    # _install_deps_linux being sourced first.
    if ! (yq --version 2>&1 | grep -qi 'mikefarah'); then
      err "yq is installed but NOT mikefarah/yq (Walter-OS hooks require it)."
      err "  Detected: $(yq --version 2>&1 | head -1)"
      err "  Fix:"
      err "    sudo apt-get remove -y yq     # Debian/Ubuntu: drop kislyuk/yq"
      err "    sudo snap install yq          # then install mikefarah/yq"
      err "  Or download the binary: https://github.com/mikefarah/yq/releases"
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

# _restore_oldest_backup <dest>
#
# After uninstall removes a Walter-OS symlink at $dest, look for a
# `${dest}.pre-walter-os.<timestamp>` sibling that link_safe() created
# the FIRST time Walter-OS overwrote this path. Restore it (the
# operator's pristine pre-install file) and remove redundant copies.
#
# Behaviour:
#   RESTORE_BACKUPS=yes   -> always restore the oldest backup, no prompt
#   RESTORE_BACKUPS=no    -> never restore (leave backups in place)
#   RESTORE_BACKUPS=prompt (default for interactive TTY)
#                         -> ask y/N; default is yes
#   RESTORE_BACKUPS=prompt (no TTY)
#                         -> skip (don't restore — operator would not
#                            see the prompt; surface backup paths instead)
#
# Closes #191 Gap 1 + Gap 3 (the new ISO-timestamp naming sorts
# lexicographically, so `ls -1 <dest>.pre-walter-os.*` returns oldest
# first).
_restore_oldest_backup() {
  local dest="$1"
  local backups
  # Glob match with nullglob-style fallback (`|| true` so 0 matches is
  # not an error). The OLDEST is `head -1` of the sorted listing —
  # both naming schemes (legacy `.<unix>` and new
  # `.<iso>.<unix>`) sort the operator's pristine file first because
  # it has the SMALLEST timestamp.
  backups=$(ls -1 "${dest}".pre-walter-os.* 2>/dev/null || true)
  [[ -n "$backups" ]] || return 0

  local oldest
  oldest="$(echo "$backups" | head -1)"
  local backup_count
  backup_count="$(echo "$backups" | wc -l | tr -d ' ')"

  local choice="${RESTORE_BACKUPS:-prompt}"
  if [[ "$choice" == "prompt" ]]; then
    if [[ -t 0 ]] && [[ -t 1 ]]; then
      printf "  ? Restore %s\n" "$dest"
      printf "    from %s (operator's pre-Walter-OS file)? [Y/n] " "$oldest"
      local answer
      read -r answer
      case "${answer,,}" in
        n|no) choice="no" ;;
        *)    choice="yes" ;;
      esac
    else
      # No TTY (CI / scripted invocation). Don't restore silently;
      # surface the backup paths so the operator can do it themselves.
      warn "  Found ${backup_count} backup(s) for $dest (oldest: $oldest)."
      warn "  Skipping restore (no TTY). To restore: mv $oldest $dest"
      warn "  Use --restore-backups to restore non-interactively."
      return 0
    fi
  fi

  case "$choice" in
    yes)
      # Safer multi-backup handling (Copilot R1 #201 #1 + #5).
      #
      # In multi-install/uninstall cycles, EXTRA backups beyond the
      # oldest are NOT guaranteed to be stale Walter-OS captures —
      # they can be legitimate operator snapshots from a subsequent
      # reinstall (operator restored, edited the file, reinstalled
      # walter-os, and link_safe captured the edited version as a
      # backup). Unconditionally deleting them risks data loss.
      #
      # When multiple backups exist AND they have distinct content,
      # restore the oldest but RENAME the later ones with a clear
      # ".kept-on-uninstall" suffix so the operator can review/recover
      # them at leisure. When all backups have IDENTICAL content
      # (likely all from a single install run), the extras are safe
      # to remove — they're literal duplicates.
      if [[ $DRY_RUN -eq 1 ]]; then
        dry "restore $oldest → $dest (${backup_count} backup(s) total)"
        return 0
      fi
      run_args mv -- "$oldest" "$dest"
      ok "Restored $dest from $oldest"
      if [[ "$backup_count" -gt 1 ]]; then
        local oldest_sha
        if command -v sha256sum >/dev/null 2>&1; then
          oldest_sha="$(sha256sum "$dest" | awk '{print $1}')"
        elif command -v shasum >/dev/null 2>&1; then
          oldest_sha="$(shasum -a 256 "$dest" | awk '{print $1}')"
        else
          oldest_sha=""  # no hashing available; treat extras as distinct
        fi
        local extras
        extras=$(echo "$backups" | tail -n +2)
        while IFS= read -r extra; do
          [[ -n "$extra" ]] || continue
          local extra_sha=""
          if [[ -n "$oldest_sha" ]]; then
            if command -v sha256sum >/dev/null 2>&1; then
              extra_sha="$(sha256sum "$extra" | awk '{print $1}')"
            else
              extra_sha="$(shasum -a 256 "$extra" | awk '{print $1}')"
            fi
          fi
          if [[ -n "$oldest_sha" ]] && [[ "$oldest_sha" == "$extra_sha" ]]; then
            # Literal duplicate of the restored file — safe to remove.
            run_args rm -- "$extra"
            ok "Removed duplicate of restored content: $extra"
          else
            # Distinct content — could be a legitimate later operator
            # snapshot. Rename to `.kept-on-uninstall.` so it's
            # obvious to the operator but not silently deleted.
            local kept="${extra%.pre-walter-os.*}.kept-on-uninstall.${extra##*.pre-walter-os.}"
            run_args mv -- "$extra" "$kept"
            warn "Kept distinct backup (could be later operator content): $kept"
          fi
        done <<< "$extras"
      fi
      ;;
    no)
      warn "  Kept ${backup_count} backup(s) for $dest (oldest: $oldest)"
      warn "  To restore manually: mv $oldest $dest"
      ;;
  esac
}

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
      # Gap 1 from #191: restore the operator's pristine pre-Walter-OS
      # file. link_safe() (line 603) creates a `.pre-walter-os.<stamp>`
      # whenever it's about to overwrite operator content. The OLDEST
      # one is the operator's original — newer ones are previous
      # Walter-OS links that link_safe captured during accumulated
      # --upgrade runs (this is largely mitigated by the link-safe
      # symlink-skip in the same commit, but historical operator state
      # may have accumulated extras). We pick the OLDEST via `ls -1`
      # alphabetical order — works because the new naming scheme uses
      # ISO-8601 UTC datestamps which sort lexicographically.
      _restore_oldest_backup "$f"
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
    # Existing symlink points elsewhere. If it points into REPO_ROOT
    # (i.e., it's a previous Walter-OS link from another commit), we
    # can replace it WITHOUT making a backup — the "operator content"
    # this would back up is just an older Walter-OS symlink, not
    # operator-authored content. Gap 2 from #191: avoid the rolling
    # `.pre-walter-os.<n>` files that accumulate across upgrades.
    if [[ "$current" == "$REPO_ROOT/"* ]]; then
      warn "Replacing existing Walter-OS symlink: $dest (was → $current)"
    else
      warn "Replacing existing symlink: $dest (was → $current)"
    fi
    run_args rm -- "$dest"
  elif [[ -e "$dest" ]]; then
    # Backup naming combines a human-readable UTC datestamp with the
    # unix seconds for guaranteed uniqueness within the same second.
    # Gap 3 from #191: `.pre-walter-os.1712345678` was opaque; the
    # new `.pre-walter-os.2026-05-23T11-04-22Z.1712345678` is
    # immediately recognizable to an operator browsing `~/.claude/`.
    # Single `date` call for both stamps — guarantees they agree even
    # if the wall-clock second rolls between sub-calls (Copilot R1 #201
    # avoids the implied lexicographic == chronological invariant
    # breaking on second boundaries).
    # ISO-8601 with colons replaced by `-` (legal in all filesystems
    # incl. SMB shares + Windows-formatted volumes the operator may
    # have mounted).
    local stamp_iso stamp_unix
    read -r stamp_iso stamp_unix < <(date -u +"%Y-%m-%dT%H-%M-%SZ %s")
    local backup="${dest}.pre-walter-os.${stamp_iso}.${stamp_unix}"
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
  #   3. network-gate.sh   → default-deny network egress (#122 OSS Trust
  #      A-2). Blocks any outbound network call whose host isn't in the
  #      operator's egress-allowlist.txt. Composes with approval-gate
  #      (WHAT vs WHERE). Last of the gates because it's the only one
  #      that needs the loader to source + per-call host extraction.
  #   4. branch-flow-guard.sh → blocks pushes that violate the
  #      configured branch flow (single-tier vs three-stage).
  #   5. pre-commit-tests.sh → runs tests/lint/typecheck on commits.
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
          { type: "command", command: ($repo + "/hooks/network-gate.sh"),     _walter_os: true },
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
  #
  # _shell_quote on REPO_ROOT (closes #133): the clone path lands inside
  # an `export VAR=...` directive in this env file. The file is sourced
  # by interactive shells (operator's `source ~/.config/walter-os/env`
  # in their .zshrc per the warn-line below) + the walter-os CLI's env
  # bootstrap. Note: hooks/daily-audit-gate.sh deliberately does NOT
  # source this file — it uses walter_env_load_allowlist for a more
  # restricted env surface (Copilot R1 #138 catch). The injection
  # vector still applies wherever the file IS sourced. A single quote
  # in REPO_ROOT (`/tmp/foo'; touch X #`) would break out of the previous
  # literal `'${REPO_ROOT}'` form and inject commands. printf '%q'
  # produces a bash-safe quoted form (`/tmp/foo\'\;\ touch\ X\ \#`)
  # that re-sources to exactly the original value, no injection.
  local q_repo_root
  q_repo_root=$(_shell_quote "$REPO_ROOT")
  local content
  content="$(cat <<EOF_WALTER_ENV
# Walter-OS env — sourced by the walter-os CLI + interactive shells.
# Hooks use walter_env_load_allowlist instead (restricted env surface).
# Generated by install.sh. Re-run 'walter-os sync' or './install.sh --upgrade'
# to refresh.

export WALTER_OS_HOME=${q_repo_root}
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
  #
  # _xml_escape on every path interpolated into <string> elements
  # (closes #134): if any of these values contains `<`, `>`, `&`,
  # `'`, or `"`, the previous raw interpolation broke the plist XML.
  # In the worst case an attacker who could influence REPO_ROOT (and
  # therefore audit_script) or WALTER_CONFIG could close `<string>`
  # early and inject additional <key>/<string> pairs — launchd reads
  # the plist on every load, so the injection persists across logins.
  local x_label   x_audit   x_stdout   x_stderr
  x_label=$(_xml_escape "$DAILY_AUDIT_LABEL")
  x_audit=$(_xml_escape "$audit_script")
  x_stdout=$(_xml_escape "$WALTER_CONFIG/audit.log")
  x_stderr=$(_xml_escape "$WALTER_CONFIG/audit.err")
  local plist_content
  plist_content="$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${x_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${x_audit}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>8</integer>
    <key>Minute</key><integer>30</integer>
  </dict>
  <key>StandardOutPath</key><string>${x_stdout}</string>
  <key>StandardErrorPath</key><string>${x_stderr}</string>
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
  # yq is REQUIRED (not optional): approval-gate.sh fails CLOSED without it.
  # The previous mismatch — Step 1 marked yq optional while --check and
  # the preflight required it — caused fresh installs to skip the install
  # in Step 1 and then trip on the missing tool the next time
  # approval-gate.sh ran on a hook event (the failure surfaces as a
  # blocked hook, not a Step-1 abort; see issue #120 for the full trace).
  local required_deps=(git curl jq yq docker bats)
  local optional_deps=(python3)

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
      # Codex R3 #125: --step 1 bypasses check_preflight, so the macOS
      # branch must also flavor-check yq when already-installed. Without
      # this, `./install.sh --step 1` on a kislyuk/yq machine would
      # report ok + leave hooks broken at runtime.
      if [[ "$dep" == "yq" ]] && ! (yq --version 2>&1 | grep -qi 'mikefarah'); then
        err "yq is installed but NOT mikefarah/yq (Walter-OS hooks require it)."
        err "  Detected: $(yq --version 2>&1 | head -1)"
        err "  Fix on macOS: brew uninstall yq && brew install yq"
        err "  (Homebrew's 'yq' is mikefarah/yq — the conflict is when both"
        err "   were installed via different sources)."
        exit 1
      fi
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
  # yq REQUIRED: see comment in _install_deps_macos above + issue #120.
  local required_deps=(git curl jq yq bats)
  local optional_deps=(python3)

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

  # _yq_is_mikefarah — validate the locally-installed yq is mikefarah/yq
  # (Go-based; the YAML processor Walter-OS hooks expect), not the
  # Python-based kislyuk/yq that Debian/Ubuntu's `apt install yq` ships.
  # The two share a binary name but have incompatible syntax — the wrong
  # one makes approval-gate.sh fail closed at runtime, which is exactly
  # the breakage this dep guard is supposed to prevent. Copilot R2 #125.
  _yq_is_mikefarah() {
    yq --version 2>&1 | grep -qi 'mikefarah'
  }

  # Codex R4 #125: enforce yq flavor BEFORE the apt-get-missing early
  # return. The previous order let `--step 1` on a non-Debian Linux
  # (Arch, Fedora, Alpine, NixOS, etc.) hit the apt-get-missing branch,
  # print "install manually", exit 0 — leaving wrong-flavor yq on
  # PATH and hooks broken. Hard-fail here so the operator can't proceed
  # with the bad state.
  if command -v yq >/dev/null 2>&1 && ! _yq_is_mikefarah; then
    err "yq is installed but is NOT mikefarah/yq (Walter-OS hooks require it)."
    err "  Detected: $(yq --version 2>&1 | head -1)"
    err "  Remove the wrong yq first, then install mikefarah/yq:"
    err "    sudo apt-get remove -y yq    # Debian/Ubuntu"
    err "    sudo dnf remove -y yq        # Fedora/RHEL"
    err "    sudo pacman -R yq            # Arch"
    err "  Then download mikefarah/yq directly:"
    err "    https://github.com/mikefarah/yq/releases (look for yq_linux_*)"
    exit 1
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found. Only Debian/Ubuntu Linux is supported for auto-install."
    warn "Install manually: ${required_deps[*]}"
    # If yq is missing entirely on a non-Debian Linux, surface that
    # explicitly so the operator doesn't think the warn-and-return
    # means everything's OK. Codex R4 #125.
    if ! command -v yq >/dev/null 2>&1; then
      err "yq is REQUIRED at runtime and not installed."
      err "  Install mikefarah/yq for your distro before re-running."
      exit 1
    fi
    return 0
  fi

  for dep in "${required_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      # yq pre-installed flavor check — see _yq_is_mikefarah above.
      if [[ "$dep" == "yq" ]] && ! _yq_is_mikefarah; then
        err "yq is installed but is NOT mikefarah/yq. Walter-OS hooks require the Go-based mikefarah/yq, not the Python-based kislyuk/yq."
        err "  Detected: $(yq --version 2>&1 | head -1)"
        err "  Fix on Debian/Ubuntu:"
        err "    sudo apt-get remove -y yq    # drop the wrong one"
        err "    sudo snap install yq         # install mikefarah/yq"
        err "  Or install the binary directly:"
        err "    https://github.com/mikefarah/yq/releases (look for yq_linux_*)"
        exit 1
      fi
      ok "$dep already installed"
    else
      # yq install — Debian/Ubuntu's `apt install yq` is a different tool
      # (kislyuk/yq, Python-based) than the Go-based mikefarah/yq that
      # Walter-OS hooks expect. Use snap (which serves the correct flavor)
      # in the auto-install path; print a concrete binary-download fallback
      # if snap is unavailable (common on minimal Debian/Ubuntu images).
      # Copilot R2 #125.
      if [[ "$dep" == "yq" ]]; then
        # _yq_arch — map `uname -m` to the mikefarah/yq release-asset name.
        # arm64/aarch64 systems were previously told to download _amd64,
        # which silently installs the wrong binary (Copilot R3 #125).
        local _yq_arch
        case "$(uname -m)" in
          x86_64|amd64)   _yq_arch="amd64" ;;
          aarch64|arm64)  _yq_arch="arm64" ;;
          armv7l|armv7)   _yq_arch="arm" ;;
          ppc64le)        _yq_arch="ppc64le" ;;
          s390x)          _yq_arch="s390x" ;;
          *)              _yq_arch="amd64" ;;  # best-effort default
        esac
        if [[ $DRY_RUN -eq 1 ]]; then
          dry "would run: sudo snap install yq  (mikefarah/yq — NOT apt's yq)"
        elif command -v snap >/dev/null 2>&1; then
          say "Installing $dep via snap (mikefarah/yq)..."
          sudo snap install yq
          # Post-install verification (Copilot R3 #125): snap puts yq at
          # /snap/bin/yq, which may not be on PATH yet in the current
          # shell. Refresh + flavor-check before claiming success so an
          # operator on a system where snap's PATH wiring is broken
          # isn't told "Installed" only to find the gate still missing yq.
          hash -r 2>/dev/null || true
          if ! command -v yq >/dev/null 2>&1; then
            err "yq install succeeded but 'yq' is not on PATH yet."
            err "  Add snap's bin to PATH and re-source your shell:"
            err "    export PATH=\"/snap/bin:\$PATH\""
            exit 1
          fi
          if ! _yq_is_mikefarah; then
            err "yq is on PATH but is not mikefarah/yq."
            err "  Detected: $(yq --version 2>&1 | head -1)"
            err "  Check 'which yq' — another binary may shadow snap's yq."
            exit 1
          fi
          ok "Installed $dep ($(yq --version 2>&1 | head -1))"
        else
          err "yq install path needs snap, but snap is not installed."
          err "  Option A (preferred): enable snap, then re-run:"
          err "    sudo apt-get install -y snapd  # Debian/Ubuntu"
          err "  Option B (direct binary download for this arch — ${_yq_arch}):"
          err "    sudo curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${_yq_arch} \\"
          err "      -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq"
          err "  Verify after either: yq --version  # must say 'mikefarah'"
          exit 1
        fi
      else
        if [[ $DRY_RUN -eq 1 ]]; then
          dry "would run: sudo apt-get install -y $dep"
        else
          say "Installing $dep via apt-get..."
          sudo apt-get install -y "$dep"
          ok "Installed $dep"
        fi
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

# ---------------------------------------------------------------------------
# Egress allowlist first-run prompt (#122 OSS Trust A-2 / AC-5)
# ---------------------------------------------------------------------------
#
# Walter-OS ships a default-deny network egress gate
# (hooks/network-gate.sh — registered by merge_claude_settings above).
# Without an allowlist, EVERY outbound network call from the agent is
# blocked. The bundled example at
# contexts/_examples/egress-allowlist.example.txt is the recommended
# starting set (GitHub, npm/pypi, the supported LLM APIs, NTP, plus
# llm./secrets. under ${WALTER_DOMAIN}).
#
# This prompt:
#   - Only fires on first install (allowlist file absent).
#   - Only fires when STDIN + STDOUT are both a TTY.
#   - Skipped under DRY_RUN, CHECK_ONLY, UNINSTALL.
#   - Always prints a hint on how to import later (`walter-os egress import …`).
#
# Spec: docs/specs/network-egress-allowlist.md
prompt_egress_import() {
  local cfg="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
  local allowlist="$cfg/egress-allowlist.txt"
  local example="$REPO_ROOT/contexts/_examples/egress-allowlist.example.txt"

  step "Egress allowlist (#122 OSS Trust A-2)"

  if [[ ! -f "$example" ]]; then
    warn "  Bundled allowlist example missing at $example — skipping prompt."
    return 0
  fi

  if [[ -f "$allowlist" ]]; then
    say "  Allowlist already at $allowlist — leaving as is."
    say "  Edit directly OR use: walter-os egress {add,remove,list,import}"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would offer to import $example → $allowlist"
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "  No TTY — skipping import prompt. To opt in later:"
    warn "    walter-os egress import \"${example}\""
    return 0
  fi

  say "  Walter-OS ships a DEFAULT-DENY network egress gate. The bundled"
  say "  allowlist covers GitHub, npm/pypi, the supported LLM APIs, NTP,"
  say "  plus llm./secrets. under \${WALTER_DOMAIN}."
  say ""
  printf "  Import the bundled allowlist now? [Y/n] "
  local answer
  read -r answer
  case "$answer" in
    n|N|no|NO)
      warn "  Skipped — every outbound call from the agent is BLOCKED until"
      warn "  you import an allowlist. To opt in later:"
      warn "    walter-os egress import \"${example}\""
      return 0
      ;;
    *)
      mkdir -p "$cfg"
      local walter_os_bin="${REPO_ROOT}/bin/walter-os"
      if [[ ! -x "$walter_os_bin" ]]; then
        err "  walter-os CLI not found at $walter_os_bin — cannot import. Re-run after install completes."
        return 1
      fi
      # NOT `cmd && ok || warn` — that would also fire `warn` if `ok`
      # returns non-zero (shellcheck SC2015). Explicit if/else.
      if WALTER_OS_HOME="$REPO_ROOT" WALTER_CONFIG="$cfg" \
          "$walter_os_bin" egress import "$example"; then
        ok "  Imported $(wc -l < "$allowlist" | tr -d ' ') line(s) into $allowlist"
      else
        warn "  Import failed — review stderr above. Retry with: walter-os egress import \"$example\""
      fi
      ;;
  esac
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
  prompt_egress_import
}

# ==========================================================================
# CURSOR ADAPTER (--cursor-rules)
# ==========================================================================
#
# Generates a project-local Cursor MDC rules file from the AGENTS.md cascade.
# See docs/specs/cursor-adapter-completion.md.
#
# Output: <project-root>/.cursor/rules/walter-os.mdc
# Source: <project-root>/AGENTS.md (required — function errors if missing)
#
# The MDC file is a *derived artifact*. AGENTS.md remains the source of truth.
# Re-run `./install.sh --cursor-rules` to refresh after AGENTS.md changes.
# Use `walter-os doctor --cursor` to detect a stale adapter.

generate_cursor_adapter() {
  step "Generating Cursor MDC adapter (--cursor-rules)"

  # Resolve the project root. When called from install.sh the CWD is the
  # operator's repo (or wherever they invoked the script from). Require a
  # local AGENTS.md to anchor the adapter — without it the adapter would
  # have no source of truth.
  local project_root
  project_root="$(pwd)"

  if [[ ! -f "$project_root/AGENTS.md" ]]; then
    err "No AGENTS.md at $project_root. The Cursor adapter needs the"
    err "AGENTS.md cascade to be installed first. Run install.sh from"
    err "the repo root that contains AGENTS.md."
    return 2
  fi

  local cursor_dir="$project_root/.cursor/rules"
  local mdc_file="$cursor_dir/walter-os.mdc"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "mkdir -p $cursor_dir"
    dry "generate $mdc_file from $project_root/AGENTS.md"
    return 0
  fi

  mkdir -p "$cursor_dir"

  # Compute the AGENTS.md content hash so `doctor --cursor` can detect
  # stale adapters. Portable across macOS (shasum) + Linux (sha256sum on
  # Debian/Ubuntu/Alpine images without perl). Match the pattern bin/walter-os
  # already uses (lines 311-314, 440-443).
  local agents_sha
  if command -v sha256sum >/dev/null 2>&1; then
    agents_sha="$(sha256sum "$project_root/AGENTS.md" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    agents_sha="$(shasum -a 256 "$project_root/AGENTS.md" | awk '{print $1}')"
  else
    err "Neither sha256sum nor shasum is available — cannot compute"
    err "AGENTS.md content hash for staleness detection."
    return 2
  fi

  # Generate the MDC file with frontmatter + header + body.
  # Body extraction strategy: copy AGENTS.md whole into the body.  Cursor's
  # rules-file size limit is generous (~500 lines recommended) and the
  # current AGENTS.md is under that; if it grows past the limit, switch to
  # a section-extraction strategy.  Keeping it whole avoids drift between
  # the cascade and the materialized rules.
  {
    printf '%s\n' '---'
    printf '%s\n' 'description: Walter-OS agent discipline contract (derived from AGENTS.md)'
    printf '%s\n' 'globs: ["**/*"]'
    printf '%s\n' 'alwaysApply: true'
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '<!-- Generated by walter-os install.sh --cursor-rules — do not edit manually. Re-run to update. -->'
    printf '%s\n' ''
    cat "$project_root/AGENTS.md"
    printf '%s\n' ''
    printf '<!-- agents-md-sha256: %s -->\n' "$agents_sha"
  } > "$mdc_file"

  ok "Cursor adapter written: $mdc_file"
  say "  source hash: $agents_sha"
  say "  Verify with: walter-os doctor --cursor"
  return 0
}

# ==========================================================================
# ANTIGRAVITY ADAPTER (--antigravity-rules)
# ==========================================================================
#
# Generates a project-local Antigravity adapter at
# <project-root>/.agent/rules/walter-os.md from the AGENTS.md cascade.
# See docs/specs/antigravity-adapter.md.
#
# Output: <project-root>/.agent/rules/walter-os.md
# Source: <project-root>/AGENTS.md (required — function errors if missing)
#
# Antigravity v1.20.3+ reads AGENTS.md natively at the repo root, so this
# adapter is OPTIONAL. Use it when:
#   - You want to isolate Walter-OS rules from third-party AGENTS.md edits.
#   - You distribute Walter-OS-derived rules across nested project hierarchies
#     (.agent/rules/ supplements per-directory AGENTS.md without replacing).
#   - You want to commit a stable per-tool rule mirror separate from the
#     evolving AGENTS.md.
#
# Caveats baked into the generator:
#   - We DO NOT emit a GEMINI.md (which would take precedence over AGENTS.md
#     in Antigravity and silently shadow it). The probe `walter-os doctor
#     --antigravity` warns if a stray GEMINI.md exists.
#   - The adapter is a *derived artifact*. Re-run after AGENTS.md changes:
#       ./install.sh --antigravity-rules
#   - Use `walter-os doctor --antigravity` to detect a stale adapter.

generate_antigravity_adapter() {
  step "Generating Antigravity adapter (--antigravity-rules)"

  local project_root
  project_root="$(pwd)"

  if [[ ! -f "$project_root/AGENTS.md" ]]; then
    err "No AGENTS.md at $project_root. The Antigravity adapter needs the"
    err "AGENTS.md cascade to be installed first. Run install.sh from"
    err "the repo root that contains AGENTS.md."
    return 2
  fi

  # Defensive: warn if a GEMINI.md exists in the same directory. GEMINI.md
  # takes precedence over AGENTS.md in Antigravity, so it would silently
  # shadow any rules we emit through the cascade.
  if [[ -f "$project_root/GEMINI.md" ]]; then
    warn "GEMINI.md detected at $project_root — Antigravity gives it precedence"
    warn "over AGENTS.md. If GEMINI.md is operator-managed it will SHADOW the"
    warn "Walter-OS adapter. Either remove GEMINI.md or merge its rules into"
    warn "AGENTS.md before relying on the adapter."
  fi

  local antigravity_dir="$project_root/.agent/rules"
  local md_file="$antigravity_dir/walter-os.md"

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "mkdir -p $antigravity_dir"
    dry "generate $md_file from $project_root/AGENTS.md"
    return 0
  fi

  mkdir -p "$antigravity_dir"

  # Same SHA-based staleness pattern as the Cursor adapter — portable
  # across macOS (shasum) + Linux (sha256sum).
  local agents_sha
  if command -v sha256sum >/dev/null 2>&1; then
    agents_sha="$(sha256sum "$project_root/AGENTS.md" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    agents_sha="$(shasum -a 256 "$project_root/AGENTS.md" | awk '{print $1}')"
  else
    err "Neither sha256sum nor shasum is available — cannot compute"
    err "AGENTS.md content hash for staleness detection."
    return 2
  fi

  # Generate the adapter file. Antigravity reads plain Markdown — no
  # frontmatter required (unlike Cursor's MDC format). Embedding AGENTS.md
  # whole keeps the cascade as the single source of truth.
  {
    printf '%s\n' '<!--'
    printf '%s\n' 'Generated by walter-os install.sh --antigravity-rules — do not edit'
    printf '%s\n' 'manually. Re-run to update after AGENTS.md changes.'
    printf '%s\n' ''
    printf '%s\n' 'This file mirrors AGENTS.md at the repo root. Antigravity v1.20.3+'
    printf '%s\n' 'reads AGENTS.md natively, so this adapter is for operators who want'
    printf '%s\n' 'a stable per-tool mirror or to isolate Walter-OS rules from'
    printf '%s\n' 'third-party AGENTS.md edits.'
    printf '%s\n' '-->'
    printf '%s\n' ''
    printf '%s\n' '# Walter-OS — Antigravity rules (derived from AGENTS.md)'
    printf '%s\n' ''
    cat "$project_root/AGENTS.md"
    printf '%s\n' ''
    printf '<!-- agents-md-sha256: %s -->\n' "$agents_sha"
  } > "$md_file"

  ok "Antigravity adapter written: $md_file"
  say "  source hash: $agents_sha"
  say "  Verify with: walter-os doctor --antigravity"
  return 0
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

  # --cursor-rules: opt-in MDC adapter generation, no other install steps.
  # Recent Cursor versions read AGENTS.md natively; this flag materializes a
  # project-local .cursor/rules/walter-os.mdc for IDE-panel visibility or
  # for Cursor versions that pre-date AGENTS.md support.
  if [[ $CURSOR_RULES_ONLY -eq 1 ]]; then
    generate_cursor_adapter
    exit $?
  fi

  if [[ $ANTIGRAVITY_RULES_ONLY -eq 1 ]]; then
    generate_antigravity_adapter
    exit $?
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
