#!/usr/bin/env bash
# Manage Walter-OS high-risk command wrappers.
# shellcheck disable=SC2016 # Literal shell exports are written for later evaluation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
TOOLS_LIB="${WALTER_OS_HOME}/scripts/walter/lib/high-risk-tools.sh"

if [[ ! -f "$TOOLS_LIB" ]]; then
  echo "walter-os wrappers: missing high-risk tool registry: $TOOLS_LIB" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$TOOLS_LIB"

usage() {
  cat >&2 <<'USAGE'
Usage: walter-os wrappers <setup|status|env> [--dir DIR] [--env-file FILE] [--no-env]

  setup   Create/update high-risk tool wrappers.
  status  Report whether all expected wrappers exist.
  env     Print shell exports for activation.
USAGE
}

sq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

default_wrapper_dir() {
  printf '%s\n' "${WALTER_WRAPPER_DIR:-${WALTER_CONFIG}/wrappers}"
}

default_env_file() {
  printf '%s\n' "${HOME}/.config/walter-os/overlay/personal.env"
}

select_wrapper_bash() {
  local candidate major
  local -a candidates=()
  if [[ -n "${WALTER_WRAPPER_BASH_CANDIDATES_FOR_TESTS:-}" ]]; then
    # shellcheck disable=SC2206 # Test-only override is a space-separated path list.
    candidates=(${WALTER_WRAPPER_BASH_CANDIDATES_FOR_TESTS})
  else
    candidates=(
      "${WALTER_WRAPPER_BASH:-}"
      "${BASH:-}"
      /opt/homebrew/bin/bash
      /usr/local/bin/bash
      "$(command -v bash 2>/dev/null || true)"
      /usr/bin/bash
      /bin/bash
    )
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    major="$("$candidate" -c 'printf "%s" "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || true)"
    if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 4 ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "walter-os wrappers: requires GNU bash >= 4 for gate execution" >&2
  exit 2
}

parse_common() {
  wrapper_dir="$(default_wrapper_dir)"
  env_file="$(default_env_file)"
  write_env=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -ge 2 ]] || { echo "walter-os wrappers: --dir requires a value" >&2; exit 2; }
        wrapper_dir="$2"; shift 2 ;;
      --env-file)
        [[ $# -ge 2 ]] || { echo "walter-os wrappers: --env-file requires a value" >&2; exit 2; }
        env_file="$2"; shift 2 ;;
      --no-env)
        write_env=0; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "walter-os wrappers: unknown argument: $1" >&2
        usage
        exit 2 ;;
    esac
  done
}

write_wrapper() {
  local tool="$1" target="$2" tmp repo_literal config_literal bash_literal bash_path
  repo_literal="$(sq "$WALTER_OS_HOME")"
  config_literal="$(sq "$WALTER_CONFIG")"
  bash_path="$(select_wrapper_bash)"
  bash_literal="$(sq "$bash_path")"
  tmp="${target}.tmp.$$"
cat > "$tmp" <<EOF
#!${bash_path}
set -euo pipefail
WALTER_GENERATED_WRAPPER_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd -P)"
WALTER_OS_HOME=${repo_literal}
WALTER_CONFIG=${config_literal}
WALTER_WRAPPER_DIR="\${WALTER_GENERATED_WRAPPER_DIR}"
WALTER_WRAPPER_BASH=${bash_literal}
export WALTER_OS_HOME WALTER_CONFIG WALTER_WRAPPER_DIR WALTER_WRAPPER_BASH
exec "\${WALTER_WRAPPER_BASH}" "\${WALTER_OS_HOME}/scripts/walter/high-risk-tool-wrapper.sh" "$tool" "\$@"
EOF
  chmod 700 "$tmp"
  mv "$tmp" "$target"
}

write_env_file() {
  local dir="$1" file="$2" tmp
  mkdir -p "$(dirname "$file")"
  tmp="${file}.tmp.$$"
  {
    if [[ -f "$file" ]]; then
      grep -vE '^(export[[:space:]]+)?WALTER_WRAPPER_DIR=|^export[[:space:]]+PATH="\$\{WALTER_WRAPPER_DIR\}:\$PATH"$' "$file" || true
    fi
    printf 'export WALTER_WRAPPER_DIR=%s\n' "$(sq "$dir")"
    printf 'export PATH="${WALTER_WRAPPER_DIR}:$PATH"\n'
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

cmd_setup() {
  local tool count=0 created_dir=0
  parse_common "$@"
  if [[ ! -d "$wrapper_dir" ]]; then
    mkdir -p "$wrapper_dir"
    created_dir=1
  fi
  if [[ "$created_dir" -eq 1 ]]; then
    chmod 700 "$wrapper_dir"
  fi
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    write_wrapper "$tool" "${wrapper_dir}/${tool}"
    count=$((count + 1))
  done < <(walter_high_risk_tools)
  if [[ "$write_env" -eq 1 ]]; then
    write_env_file "$wrapper_dir" "$env_file"
  fi
  echo "walter-os wrappers: created wrappers for ${count} tool(s) in $wrapper_dir"
  if [[ "$write_env" -eq 1 ]]; then
    echo "walter-os wrappers: activation written to $env_file"
  else
    echo "walter-os wrappers: env file unchanged (--no-env)"
  fi
}

cmd_status() {
  local tool missing=0 present=0
  parse_common "$@"
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if [[ -x "${wrapper_dir}/${tool}" && ! -L "${wrapper_dir}/${tool}" ]]; then
      present=$((present + 1))
    else
      echo "missing wrapper: $tool" >&2
      missing=$((missing + 1))
    fi
  done < <(walter_high_risk_tools)
  if [[ "$missing" -eq 0 ]]; then
    echo "walter-os wrappers: wrappers present ($present) in $wrapper_dir"
    return 0
  fi
  echo "walter-os wrappers: wrappers incomplete (${present} present, ${missing} missing) in $wrapper_dir"
  return 1
}

cmd_env() {
  parse_common "$@"
  printf 'export WALTER_WRAPPER_DIR=%s\n' "$(sq "$wrapper_dir")"
  printf 'export PATH="${WALTER_WRAPPER_DIR}:$PATH"\n'
}

sub="${1:-}"
shift || true
case "$sub" in
  setup) cmd_setup "$@" ;;
  status) cmd_status "$@" ;;
  env) cmd_env "$@" ;;
  -h|--help|"") usage; [[ -n "$sub" ]] ;;
  *) echo "walter-os wrappers: unknown subcommand: $sub" >&2; usage; exit 2 ;;
esac
