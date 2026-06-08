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
  WALTER_SESSION_LOCK_WAIT_SEC
  WALTER_MODEL_BACKEND_REVIEW
  WALTER_MODEL_FRONTEND
  WALTER_MODEL_LONGFORM
  WALTER_MODEL_QUICK_REFACTOR
  WALTER_MODEL_PHI
  WALTER_MODEL_BRAINSTORM
  WALTER_MODEL_DEFAULT
  WALTER_MODEL_OVERRIDE
)

_walter_env_key_dangerous() {
  case "$1" in
    BASH_ENV|ENV|LD_*|DYLD_*) return 0 ;;
    *) return 1 ;;
  esac
}

_walter_env_key_protected() {
  local key="$1"
  case " ${WALTER_ENV_PROTECTED_KEYS:-} " in
    *" $key "*) return 0 ;;
  esac
  return 1
}

# Returns 0 if $1 is in the allowlist (built-in + operator override file).
_walter_env_key_allowed() {
  local key="$1" override_file="${2:-}"
  local allowed
  _walter_env_key_dangerous "$key" && return 1
  for allowed in "${WALTER_ENV_ALLOWLIST[@]}"; do
    [[ "$key" == "$allowed" ]] && return 0
  done
  # Operator-extended allowlist
  if [[ -n "$override_file" && -f "$override_file" ]]; then
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

  local allowlist_root override_file
  allowlist_root="${WALTER_ENV_ALLOWLIST_ROOT:-${WALTER_CONFIG:-$HOME/.config/walter-os}}"
  override_file="${allowlist_root}/env-allowlist.txt"

  local line key value
  local lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"

    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"

    # Skip blanks + comments
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    # Must match `KEY=...` or `export KEY=...` where KEY is
    # [A-Z_][A-Z0-9_]*.
    if [[ ! "$line" =~ ^(export[[:space:]]+)?([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      echo "walter-env-loader: WARN line $lineno: not a KEY=VALUE pair, ignored." >&2
      continue
    fi
    key="${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]}"

    # Strip surrounding quotes (single OR double) — do NOT interpret content.
    # We deliberately do not parse escape sequences. `\n` stays as the two
    # characters `\` + `n`. Operators who need a newline should not use
    # this file.
    if [[ "${#value}" -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${#value}" -ge 2 && "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    if _walter_env_key_protected "$key"; then
      echo "walter-env-loader: WARN line $lineno: $key is protected by the caller, ignored." >&2
      continue
    fi

    if _walter_env_key_dangerous "$key"; then
      echo "walter-env-loader: WARN line $lineno: $key is a dangerous shell/runtime key and cannot be loaded from Walter env files, ignored." >&2
      continue
    fi

    if ! _walter_env_key_allowed "$key" "$override_file"; then
      echo "walter-env-loader: WARN line $lineno: $key is not in the env allowlist, ignored. Add it to ${override_file} if you really need it." >&2
      continue
    fi

    # `export -- VAR=value` makes the value-side literal — no expansion.
    export -- "$key=$value"
  done < "$env_file"
}
