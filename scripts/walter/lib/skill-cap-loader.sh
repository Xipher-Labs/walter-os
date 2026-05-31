#!/usr/bin/env bash
# scripts/walter/lib/skill-cap-loader.sh
# Auto-mint operator-configured default skill capabilities at session start.

_walter_skill_cap_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_walter_skill_cap_lib_dir}/capability-token.sh"
unset _walter_skill_cap_lib_dir

walter_skill_cap_config_path() {
  local candidate
  if [[ -n "${WALTER_SKILL_CAPABILITIES:-}" ]]; then
    printf '%s\n' "$WALTER_SKILL_CAPABILITIES"
    return 0
  fi
  for candidate in \
    "${WALTER_CONFIG:-${HOME}/.config/walter-os}/overlay/skill-capabilities.yml" \
    "${WALTER_CONFIG:-${HOME}/.config/walter-os}/skill-capabilities.yml"
  do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_walter_skill_cap_write_token() {
  local state_file="$1" nonce="$2" token="$3"
  local caps_dir token_file tmp_file

  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [[ -d "$caps_dir" ]] || {
    echo "walter-skill-caps: caps directory missing: $caps_dir" >&2
    return 1
  }
  [[ "$nonce" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "walter-skill-caps: unsafe nonce" >&2
    return 1
  }

  token_file="${caps_dir}/cap-${nonce}.paseto"
  tmp_file="$(mktemp "${token_file}.XXXXXX")" || {
    echo "walter-skill-caps: failed to create temporary capability token" >&2
    return 1
  }
  if ! printf '%s\n' "$token" > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "walter-skill-caps: failed to write temporary capability token" >&2
    return 1
  fi
  if ! chmod 600 "$tmp_file"; then
    rm -f "$tmp_file"
    echo "walter-skill-caps: failed to lock down temporary capability token" >&2
    return 1
  fi
  if ! mv "$tmp_file" "$token_file"; then
    rm -f "$tmp_file"
    echo "walter-skill-caps: failed to install capability token" >&2
    return 1
  fi
}

_walter_skill_cap_rollback_tokens() {
  local state_file="$1" nonce caps_dir
  shift

  caps_dir="$(jq -r '.capability_tokens_dir' "$state_file")"
  [[ -d "$caps_dir" ]] || return 0

  for nonce in "$@"; do
    [[ "$nonce" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    rm -f "${caps_dir}/cap-${nonce}.paseto"
  done
}

_walter_skill_cap_validate_entry() {
  local config_json="$1" skill="$2"
  jq -e --arg skill "$skill" '
    def string_array:
      type == "array" and all(.[]; type == "string" and length > 0);
    def supported_tool:
      . == "Bash" or . == "Edit" or . == "Write" or . == "MultiEdit" or . == "NotebookEdit";
    .[$skill] as $entry
    | ($entry.scope // {}) as $scope
    | ($scope.paths // []) as $paths
    | ($scope.network // []) as $network
    | ($scope.patterns // []) as $patterns
    | ($entry | type == "object")
    and ((($entry | has("enabled")) | not) or (($entry.enabled | type) == "boolean"))
    and (($entry.tool // "") | type == "string" and supported_tool)
    and (($entry.duration // "") | type == "string" and test("^[1-9][0-9]*[smh]$"))
    and (($entry.scope // {}) | type == "object")
    and ($paths | string_array)
    and ($network | string_array)
    and ($patterns | string_array)
    and (
      if $entry.tool == "Bash" then
        (($paths | length) == 0)
        and ((($network | length) + ($patterns | length)) > 0)
      else
        (($paths | length) > 0)
        and ((($network | length) + ($patterns | length)) == 0)
      end
    )
  ' <<< "$config_json" >/dev/null
}

_walter_skill_cap_entry_enabled() {
  local config_json="$1" skill="$2"
  jq -r --arg skill "$skill" '
    .[$skill] as $entry
    | if ($entry | type) != "object" then
        "true"
      elif (($entry | has("enabled")) | not) then
        "true"
      elif (($entry.enabled | type) == "boolean") then
        ($entry.enabled | tostring)
      else
        "invalid"
      end
  ' <<< "$config_json"
}

walter_skill_caps_mint_defaults() {
  local repo="${1:-$PWD}" config_path="${2:-}" state_file config_json skill enabled
  local tool duration paths network patterns duration_seconds now_epoch now_iso
  local requested_exp session_exp exp_epoch exp_iso nonce session_id claims token
  local minted_nonces=()

  if [[ -z "$config_path" ]]; then
    config_path="$(walter_skill_cap_config_path 2>/dev/null || true)"
  fi
  [[ -n "$config_path" && -f "$config_path" ]] || return 0

  command -v yq >/dev/null 2>&1 || {
    echo "walter-skill-caps: yq required to read $config_path" >&2
    return 1
  }
  _walter_cap_require_runtime || return 1

  state_file="$(walter_session_state_file "$repo")"
  _walter_cap_validate_state "$state_file" || return 1
  _walter_cap_validate_active_session "$state_file" || return 1

  config_json="$(yq -o=json '.skills // {}' "$config_path")" || {
    echo "walter-skill-caps: invalid YAML: $config_path" >&2
    return 1
  }
  jq -e 'type == "object"' <<< "$config_json" >/dev/null || {
    echo "walter-skill-caps: .skills must be a mapping" >&2
    return 1
  }

  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    enabled="$(_walter_skill_cap_entry_enabled "$config_json" "$skill")"
    if [[ "$enabled" == "invalid" ]]; then
      echo "walter-skill-caps: invalid capability entry for skill: $skill" >&2
      return 1
    fi
    [[ "$enabled" == "true" ]] || continue

    if ! _walter_skill_cap_validate_entry "$config_json" "$skill"; then
      echo "walter-skill-caps: invalid capability entry for skill: $skill" >&2
      return 1
    fi

    duration="$(jq -r --arg skill "$skill" '.[$skill].duration' <<< "$config_json")"
    walter_cap_duration_to_seconds "$duration" >/dev/null || return 1
  done < <(jq -r 'keys[]' <<< "$config_json")

  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    enabled="$(_walter_skill_cap_entry_enabled "$config_json" "$skill")"
    if [[ "$enabled" == "invalid" ]]; then
      echo "walter-skill-caps: invalid capability entry for skill: $skill" >&2
      return 1
    fi
    [[ "$enabled" == "true" ]] || continue

    tool="$(jq -r --arg skill "$skill" '.[$skill].tool' <<< "$config_json")"
    duration="$(jq -r --arg skill "$skill" '.[$skill].duration' <<< "$config_json")"
    paths="$(jq -c --arg skill "$skill" '.[$skill].scope.paths // []' <<< "$config_json")"
    network="$(jq -c --arg skill "$skill" '.[$skill].scope.network // []' <<< "$config_json")"
    patterns="$(jq -c --arg skill "$skill" '.[$skill].scope.patterns // []' <<< "$config_json")"

    duration_seconds="$(walter_cap_duration_to_seconds "$duration")" || return 1
    now_epoch="$(_walter_session_now_epoch)"
    now_iso="$(_walter_session_iso "$now_epoch")"
    requested_exp=$((now_epoch + duration_seconds))
    session_exp="$(_walter_cap_session_end_epoch "$state_file")" || {
      echo "walter-skill-caps: cannot derive session expiry" >&2
      return 1
    }
    exp_epoch="$requested_exp"
    if (( exp_epoch > session_exp )); then
      exp_epoch="$session_exp"
    fi
    if (( exp_epoch <= now_epoch )); then
      echo "walter-skill-caps: active session has no remaining lifetime" >&2
      return 1
    fi

    exp_iso="$(_walter_session_iso "$exp_epoch")"
    nonce="$(_walter_session_uuid)"
    session_id="$(jq -r '.session_id' "$state_file")"
    claims="$(jq -ncS \
      --arg session_id "$session_id" \
      --arg skill "$skill" \
      --arg tool "$tool" \
      --arg iat "$now_iso" \
      --arg exp "$exp_iso" \
      --arg nonce "$nonce" \
      --arg sub "${USER:-operator}" \
      --argjson paths "$paths" \
      --argjson network "$network" \
      --argjson patterns "$patterns" \
      '{
        iss:"walter-os",
        sub:$sub,
        session_id:$session_id,
        skill_name:$skill,
        tool:$tool,
        scope:{paths:$paths, network:$network, patterns:$patterns},
        iat:$iat,
        exp:$exp,
        nonce:$nonce
      }')"
    token="$(walter_cap_sign_claims "$state_file" "$claims")" || {
      _walter_skill_cap_rollback_tokens "$state_file" "${minted_nonces[@]}"
      return 1
    }
    if ! _walter_skill_cap_write_token "$state_file" "$nonce" "$token"; then
      _walter_skill_cap_rollback_tokens "$state_file" "${minted_nonces[@]}" "$nonce"
      return 1
    fi
    minted_nonces+=("$nonce")
  done < <(jq -r 'keys[]' <<< "$config_json")
}
