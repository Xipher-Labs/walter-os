#!/usr/bin/env bash
# audit.sh — daily supply-chain audit for Walter-OS
# Exit codes: 0=clean, 1=info, 2=high, 3=critical
# Detailed report at ~/.config/walter-os/audit-YYYY-MM-DD.md

set -uo pipefail
# Note: not using -e because we want to collect ALL findings, not bail on first.

readonly WALTER_CONFIG="${HOME}/.config/walter-os"
readonly BASELINES_DIR="${WALTER_CONFIG}/baselines"
readonly TODAY="$(date +%Y-%m-%d)"
readonly REPORT="${WALTER_CONFIG}/audit-${TODAY}.md"
readonly STATUS="${WALTER_CONFIG}/audit-status.json"
readonly CLAUDE_HOME="${HOME}/.claude"
readonly CODEX_HOME="${HOME}/.codex"

mkdir -p "${WALTER_CONFIG}" "${BASELINES_DIR}"

# Severity tracking
SEVERITY=0    # 0 clean, 1 info, 2 high, 3 critical
FINDINGS=()
INFO_COUNT=0
HIGH_COUNT=0
CRIT_COUNT=0

bump() {
  local level="$1"
  case "$level" in
    info) (( INFO_COUNT++ )); (( SEVERITY < 1 )) && SEVERITY=1 ;;
    high) (( HIGH_COUNT++ )); (( SEVERITY < 2 )) && SEVERITY=2 ;;
    crit) (( CRIT_COUNT++ )); (( SEVERITY < 3 )) && SEVERITY=3 ;;
  esac
}

finding() {
  local level="$1" id="$2" desc="$3" action="${4:-investigate manually}"
  bump "$level"
  FINDINGS+=("- **[${level^^}]** \`${id}\` — ${desc}")
  FINDINGS+=("  - Action: ${action}")
}

# ---------- 0. Tool versions ----------

check_versions() {
  if command -v claude >/dev/null 2>&1; then
    local v
    v="$(claude --version 2>/dev/null | awk '{print $NF}' || echo unknown)"
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
      local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}" pat="${BASH_REMATCH[3]}"
      if (( maj < 2 || (maj == 2 && min == 0 && pat < 65) )); then
        finding crit "CVE-2025-59536" \
          "Claude Code $v is below 2.0.65, vulnerable to hooks injection RCE" \
          "Run: claude update"
      fi
    fi
  else
    finding info "no-claude-cli" "Claude Code not installed" "Install if you use it"
  fi

  if command -v codex >/dev/null 2>&1; then
    : # version check rules go here when CVEs publish
  fi
}

# ---------- 1. Config drift ----------

check_config_drift() {
  for cfg in "${CLAUDE_HOME}/settings.json" "${CODEX_HOME}/config.toml"; do
    [[ -f "$cfg" ]] || continue
    local name; name="$(basename "$cfg")"
    local baseline="${BASELINES_DIR}/${name}.sha256"
    local current; current="$(shasum -a 256 "$cfg" | awk '{print $1}')"
    if [[ -f "$baseline" ]]; then
      local stored; stored="$(cat "$baseline")"
      if [[ "$current" != "$stored" ]]; then
        finding high "config-drift-${name}" \
          "Config $cfg has been modified since last baseline" \
          "Review the diff. If intentional, run: walter-os baseline $cfg"
      fi
    else
      # First run — just record the baseline.
      echo "$current" > "$baseline"
    fi
  done
}

# ---------- 2. Plaintext secrets in configs ----------

check_secrets_in_configs() {
  local pattern='(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}|xoxb-|AKIA[0-9A-Z]{16})'
  for cfg in "${CLAUDE_HOME}/settings.json" "${CODEX_HOME}/config.toml" \
             $(find "${HOME}" -maxdepth 4 -name '.mcp.json' 2>/dev/null); do
    [[ -f "$cfg" ]] || continue
    if grep -qE "$pattern" "$cfg" 2>/dev/null; then
      finding crit "plaintext-secret" \
        "Plaintext-looking secret found in $cfg" \
        "Move secret to env var, replace in config with \${ENV_VAR_NAME}"
    fi
  done
}

# ---------- 3. Hooks integrity ----------

check_hooks() {
  local settings="${CLAUDE_HOME}/settings.json"
  [[ -f "$settings" ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    finding high "no-jq" "jq not installed; can't verify hooks" "brew install jq"
    return 0
  fi
  local hook_count
  hook_count="$(jq '[.hooks // {} | .. | objects | select(has("command"))] | length' "$settings" 2>/dev/null || echo 0)"
  if [[ "$hook_count" -gt 0 ]]; then
    local checksums="${WALTER_CONFIG}/hook-checksums.json"
    if [[ ! -f "$checksums" ]]; then
      # First run: silently snapshot. Future runs compare against this.
      jq '[.hooks // {} | .. | objects | select(has("command")) | .command]' "$settings" > "$checksums"
    else
      local current; current="$(jq '[.hooks // {} | .. | objects | select(has("command")) | .command]' "$settings")"
      local stored; stored="$(cat "$checksums")"
      if [[ "$current" != "$stored" ]]; then
        finding high "hooks-modified" \
          "Hooks in $settings differ from baseline" \
          "Inspect new hooks for malicious commands. If safe: walter-os baseline-hooks"
      fi
    fi
  fi
}

# ---------- 4. MCP scanners ----------

check_mcp_scanners() {
  if command -v mcp-scan >/dev/null 2>&1; then
    local out; out="$(mcp-scan --json 2>/dev/null || echo '{}')"
    local crit; crit="$(echo "$out" | jq '[.findings[]?|select(.severity=="critical")]|length' 2>/dev/null || echo 0)"
    local high; high="$(echo "$out" | jq '[.findings[]?|select(.severity=="high")]|length' 2>/dev/null || echo 0)"
    if [[ "$crit" -gt 0 ]]; then
      finding crit "mcp-scan-critical" \
        "Snyk mcp-scan found $crit critical issue(s)" \
        "Run: mcp-scan for full report"
    fi
    if [[ "$high" -gt 0 ]]; then
      finding high "mcp-scan-high" \
        "Snyk mcp-scan found $high high-severity issue(s)" \
        "Run: mcp-scan for full report"
    fi
  fi
  # If mcp-scan not installed, we silently skip — surfacing this as info every
  # day creates alert fatigue. It's documented in the SKILL.md as optional.
}

# ---------- 5. Tool definition drift ----------

check_tool_definitions() {
  # Snapshot today's tool defs from each connected MCP, diff against yesterday.
  # Implementation depends on how MCPs are listed locally.
  local snapdir="${WALTER_CONFIG}/mcp-snapshots"
  mkdir -p "$snapdir"
  # Phase 2: query each MCP for its tool list, diff against snapdir/yesterday.
  # Until then this is a no-op rather than a noisy finding.
}

# ---------- 6. Minimum release age check ----------

check_min_release_age() {
  # Resolve protection level for the current repo.
  # Respects WALTER_AUDIT_REPO_DIR env var; falls back to cwd.
  local repo_dir="${WALTER_AUDIT_REPO_DIR:-$(pwd)}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local walter_home="${WALTER_OS_HOME:-$(cd "$script_dir/../../.." && pwd)}"
  local parser="${walter_home}/scripts/parse-manifest.py"
  local age_checker="${walter_home}/skills/daily-supply-chain-audit/scripts/check-release-age.py"
  local justify_log="${WALTER_CONFIG}/justify-log.jsonl"
  local cache_file="${WALTER_CONFIG}/release-date-cache.json"

  if [[ ! -f "$parser" ]]; then
    finding info "release-age-no-parser" \
      "parse-manifest.py not found at $parser; skipping release-age check" \
      "Run install.sh to reinstall walter-os"
    return 0
  fi

  if [[ ! -f "$age_checker" ]]; then
    finding info "release-age-no-checker" \
      "check-release-age.py not found at $age_checker; skipping release-age check" \
      "Run install.sh to reinstall walter-os"
    return 0
  fi

  # Get resolved protection level
  local config_json
  config_json="$(python3 "$parser" --repo-dir "$repo_dir" 2>/dev/null)" || {
    finding info "release-age-parse-error" \
      "Failed to parse protection level for $repo_dir" \
      "Check walter-os.toml in repo root"
    return 0
  }

  local min_age_days audit_gate
  min_age_days="$(echo "$config_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('minReleaseAgeDays',0))" 2>/dev/null || echo 0)"
  audit_gate="$(echo "$config_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('auditGate','info'))" 2>/dev/null || echo info)"

  # Skip if experimental (minReleaseAgeDays=0)
  if [[ "$min_age_days" -eq 0 ]]; then
    return 0
  fi

  # Collect npm packages from MCP servers in settings.json
  local settings="${HOME}/.claude/settings.json"
  local pkg_specs=()
  if [[ -f "$settings" ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r spec; do
      [[ -n "$spec" ]] && pkg_specs+=("$spec")
    done < <(jq -r '
      .mcpServers // {} | to_entries[] |
      select(.value.command == "npx") |
      .value.args[]? |
      select(test("^[a-zA-Z@][^\\s]*@[0-9]"))
    ' "$settings" 2>/dev/null || true)
  fi

  # Also check any .mcp.json in scope
  for mcp_json in "${HOME}/.mcp.json" "${repo_dir}/.mcp.json"; do
    if [[ -f "$mcp_json" ]] && command -v jq >/dev/null 2>&1; then
      while IFS= read -r spec; do
        [[ -n "$spec" ]] && pkg_specs+=("$spec")
      done < <(jq -r '
        .mcpServers // {} | to_entries[] |
        select(.value.command == "npx") |
        .value.args[]? |
        select(test("^[a-zA-Z@][^\\s]*@[0-9]"))
      ' "$mcp_json" 2>/dev/null || true)
    fi
  done

  if [[ "${#pkg_specs[@]}" -eq 0 ]]; then
    return 0
  fi

  # Determine effective finding severity
  local finding_severity="info"
  case "$audit_gate" in
    high|high+drift) finding_severity="high" ;;
    warn)           finding_severity="info" ;;
    info)           finding_severity="info" ;;
  esac

  # Build checker arguments
  local checker_args=()
  checker_args+=(--min-age-days "$min_age_days")
  checker_args+=(--cache-file "$cache_file")
  checker_args+=(--justify-log "$justify_log")
  checker_args+=(--ecosystem npm)

  # WA_SKIP_NETWORK=1 simulates offline mode by making the checker unavailable
  # We simulate this by blocking all network in the checker via a proxy that
  # immediately refuses. For simplicity, we set an env that check-release-age.py
  # reads to skip actual network calls and report network_error.
  if [[ "${WA_SKIP_NETWORK:-0}" == "1" ]]; then
    checker_args+=(--skip-network)
  fi

  local findings_json
  findings_json="$(python3 "$age_checker" "${pkg_specs[@]}" "${checker_args[@]}" 2>/dev/null)" || true

  if [[ -z "$findings_json" ]]; then
    return 0
  fi

  # Parse findings JSON into TAB-separated rows: <severity>\t<id>\t<pkg_spec>\t<rest>
  # The pkg_spec is emitted as a separate field so the remediation `action`
  # can suggest the correct `walter-os justify <pkg>@<version>` command
  # (LOW from R2: previously we built the action with the finding id, which
  # is not a valid justify argument).
  local release_age_rows
  release_age_rows="$(python3 -c "
import sys, json

findings_json = sys.argv[1]
finding_severity = sys.argv[2]

try:
    findings = json.loads(findings_json)
except Exception as e:
    print(f'INFO\trelease-age-parse-error\t-\t{e}', file=sys.stderr)
    sys.exit(0)

rows = []
for f in findings:
    pkg = f.get('pkg', 'unknown')
    if f.get('network_error'):
        rows.append(f'INFO\trelease-age-network-error\t{pkg}\tregistry unreachable for {pkg}')
    elif f.get('justified'):
        expires = f.get('expires','?')
        rows.append(f'INFO\trelease-age-justified\t{pkg}\t{pkg} (expires: {expires})')
    elif not f.get('ok'):
        age = f.get('age_days', '?')
        min_a = f.get('min_age_days', '?')
        rows.append(f'{finding_severity.upper()}\trelease-age-young\t{pkg}\t{pkg} age={age}d min={min_a}d')

for r in rows:
    print(r)
" "$findings_json" "$finding_severity" 2>/dev/null || true)"

  # CRITICAL: do NOT pipe into `while read` here. In bash, a pipe creates a
  # subshell for the right-hand side, so any FINDINGS/SEVERITY mutations
  # inside the loop are lost when the subshell exits. (HIGH-2 from PR #56
  # Codex R2 — release-age findings used to silently disappear.) Use process
  # substitution `< <(...)` instead, which keeps the loop in the parent shell.
  while IFS=$'\t' read -r sev id pkg_spec rest; do
    [[ -z "$sev" ]] && continue
    local justify_target="$pkg_spec"
    [[ "$justify_target" == "-" || -z "$justify_target" ]] && justify_target="<pkg>@<version>"
    case "${sev,,}" in
      info) finding info "$id" "$rest" \
              "Use 'walter-os justify ${justify_target} --reason=...' to exempt" ;;
      high) finding high "$id" "$rest" \
              "Use 'walter-os justify ${justify_target} --reason=...' to exempt, or wait for min age" ;;
    esac
  done < <(printf '%s\n' "$release_age_rows")
}

# ---------- 7. Pin check (formerly 6) ----------

check_pinning() {
  # Inspect ~/.claude/settings.json mcpServers for unpinned versions.
  #
  # Detection logic lives in scripts/check-pinning.py so it can be tested in
  # isolation against fixture settings.json files (tests/audit/check-pinning.bats).
  # Previous jq-based filter falsely flagged every npx server because its regex
  # matched the `-y` flag — see commit history for the rewrite.
  local settings="${CLAUDE_HOME}/settings.json"
  [[ -f "$settings" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local helper="${BASH_SOURCE[0]%/*}/check-pinning.py"
  [[ -f "$helper" ]] || return 0

  local unpinned
  unpinned="$(python3 "$helper" "$settings" 2>/dev/null | paste -sd, -)"

  if [[ -n "$unpinned" ]]; then
    finding high "unpinned-mcps" \
      "MCP servers without pinned versions: ${unpinned}" \
      "Use exact semver only ('package@x.y.z' for npm, 'package==x.y.z' for uvx, or 'pkg#<commit-sha>' for git). Ranges, dist-tags ('@latest', '@beta'), and PEP-440 operators other than '==' are rejected."
  fi
}

# ---------- 8. Skill static checks ----------

check_skill_scripts() {
  for skills_dir in "${CLAUDE_HOME}/skills" "${CODEX_HOME}/skills"; do
    [[ -d "$skills_dir" ]] || continue
    while IFS= read -r script; do
      # Check for dangerous patterns
      if grep -qE 'curl[^|]*\|\s*(bash|sh|zsh)' "$script" 2>/dev/null; then
        finding crit "curl-pipe-bash" \
          "Skill script $script does curl | bash" \
          "Pin and inline the script, or remove this skill"
      fi
      # shellcheck disable=SC2088 # this is a regex pattern matched against script CONTENT, not a path
      if grep -qE '~/\.ssh|/etc/passwd|/etc/shadow' "$script" 2>/dev/null; then
        finding high "sensitive-fs-access" \
          "Skill script $script references sensitive paths" \
          "Audit the script's intent before allowing it to run"
      fi
    done < <(find "$skills_dir" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) 2>/dev/null)
  done
}

# ---------- 9. Notifications ----------

notify() {
  local summary="$1"
  if [[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]]; then
    curl -sS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
      -d "text=Walter-OS audit ${TODAY}: ${summary}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WALTER_SLACK_WEBHOOK:-}" ]]; then
    curl -sS -X POST "${WALTER_SLACK_WEBHOOK}" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"Walter-OS audit ${TODAY}: ${summary}\"}" >/dev/null 2>&1 || true
  fi
}

# ---------- main ----------

main() {
  check_versions
  check_config_drift
  check_secrets_in_configs
  check_hooks
  check_mcp_scanners
  check_tool_definitions
  check_pinning
  check_min_release_age
  check_skill_scripts

  # Write report
  {
    echo "# Walter-OS Supply Chain Audit"
    echo
    echo "**Date**: ${TODAY}"
    echo "**Severity**: ${SEVERITY} (0=clean, 1=info, 2=high, 3=critical)"
    echo "**Counts**: info=${INFO_COUNT}, high=${HIGH_COUNT}, critical=${CRIT_COUNT}"
    echo
    echo "## Findings"
    echo
    if [[ ${#FINDINGS[@]} -eq 0 ]]; then
      echo "_No findings. System clean._"
    else
      for f in "${FINDINGS[@]}"; do
        echo "$f"
      done
    fi
    echo
    echo "## Triage"
    echo
    case "$SEVERITY" in
      0) echo "✅ Proceed with work." ;;
      1) echo "ℹ️  Informational only. No action required to start work." ;;
      2) echo "⚠️  HIGH-severity findings. Acknowledge with \`walter-os ack <id>\` or fix before continuing." ;;
      3) echo "🚨 CRITICAL findings. WORK BLOCKED. Triage manually." ;;
    esac
  } > "$REPORT"

  # Status JSON
  cat > "$STATUS" <<EOF
{
  "date": "${TODAY}",
  "severity": ${SEVERITY},
  "info": ${INFO_COUNT},
  "high": ${HIGH_COUNT},
  "critical": ${CRIT_COUNT},
  "report": "${REPORT}"
}
EOF

  local summary="severity=${SEVERITY} info=${INFO_COUNT} high=${HIGH_COUNT} critical=${CRIT_COUNT}"
  echo "$summary"
  echo "Report: $REPORT"

  if [[ "$SEVERITY" -ge 2 ]]; then
    notify "$summary — see $REPORT"
  fi

  exit "$SEVERITY"
}

main "$@"
