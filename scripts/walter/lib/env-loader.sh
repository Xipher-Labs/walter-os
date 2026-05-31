#!/usr/bin/env bash
# scripts/walter/lib/env-loader.sh
#
# Allowlist key=value parser for Walter-OS env files. Used in place of
# `source <file>` to load operator config without code-execution risk.
#
# Audit ref: docs/operational/security-audit-2026-05-11.md P1-09
#
# Threat model: `~/.config/walter-os/env` is operator-created but not
# integrity-checked. Any attacker who can write to that path (a
# compromised dotfile manager, a path-traversal in a different service,
# a malicious skill that creates files under $HOME) can inject shell
# commands that execute with full operator privileges at every Claude
# Code session start.
#
# This loader reads `KEY=VALUE` lines and:
#   - Ignores lines that don't match `^[A-Z_][A-Z0-9_]*=` (rejects code).
#   - Strips surrounding single or double quotes from VALUE.
#   - Does NOT perform shell expansion, command substitution, arithmetic
#     expansion, brace expansion, or any other interpretation of VALUE.
#   - Only exports keys present in the WALTER_ENV_ALLOWLIST array.
#
# Usage:
#   source "$WALTER_OS_HOME/scripts/walter/lib/env-loader.sh"
#   walter_env_load_allowlist "$WALTER_CONFIG/env"
#
# Override:
#   Operators who genuinely need to load a custom key can add it to
#   ~/.config/walter-os/env-allowlist.txt (one KEY per line). The loader
#   reads that file alongside the built-in allowlist. The override file
#   itself is allow-listed by integrity check in audit.sh (forthcoming).

# Built-in allowlist — the keys Walter-OS itself reads from $WALTER_CONFIG/env.
# Keep in sync with the documented operator config surface.
WALTER_ENV_ALLOWLIST=(
  WALTER_OS_HOME
  WALTER_CONFIG
  WALTER_DOMAIN
  WALTER_BRANCH_FLOW
  WALTER_TIMEZONE
  WALTER_OPERATOR_SCRIPTS_DIR
  WALTER_INITIAL_USER
  WALTER_OVERLAY_DIR
  WALTER_OVERLAY_EDITOR
  WALTER_OVERLAY_OPEN_CMD
  WALTER_VM
  WALTER_METRICS_FILE
  WALTER_TRUST_TIERS
  WALTER_SESSION_MAX_HOURS
  WALTER_SESSION_MAX_IDLE_MIN
  WALTER_OPENSSL_BIN
)

# Returns 0 if $1 is in the allowlist (built-in + operator override file).
_walter_env_key_allowed() {
  local key="$1"
  local allowed
  for allowed in "${WALTER_ENV_ALLOWLIST[@]}"; do
    [[ "$key" == "$allowed" ]] && return 0
  done
  # Operator-extended allowlist
  local override_file="${WALTER_CONFIG:-$HOME/.config/walter-os}/env-allowlist.txt"
  if [[ -f "$override_file" ]]; then
    if grep -qxF "$key" "$override_file" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# walter_env_load_allowlist <env-file>
#
# Reads KEY=VALUE lines from the given file and exports the keys that
# pass the allowlist. Silently ignores blank lines and `#` comments.
# Prints a WARN to stderr for each rejected key so misconfigurations
# are visible.
walter_env_load_allowlist() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  local line key value rest
  local lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))

    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"

    # Skip blanks + comments
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    # Must match `KEY=...` where KEY is [A-Z_][A-Z0-9_]*
    if [[ ! "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      echo "walter-env-loader: WARN line $lineno: not a KEY=VALUE pair, ignored: $line" >&2
      continue
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    # Strip surrounding quotes (single OR double) — do NOT interpret content.
    # We deliberately do not parse escape sequences. `\n` stays as the two
    # characters `\` + `n`. Operators who need a newline should not use
    # this file.
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    if ! _walter_env_key_allowed "$key"; then
      echo "walter-env-loader: WARN line $lineno: $key is not in the env allowlist, ignored. Add it to \${WALTER_CONFIG}/env-allowlist.txt if you really need it." >&2
      continue
    fi

    # `export -- VAR=value` makes the value-side literal — no expansion.
    export -- "$key=$value"
  done < "$env_file"
}
