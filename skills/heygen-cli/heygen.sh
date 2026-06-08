#!/usr/bin/env bash
# skills/heygen-cli/heygen.sh
#
# Function library for HeyGen avatar-video REST API.
# Source this file from another script:
#
#   source "$WALTER_OS_HOME/skills/heygen-cli/heygen.sh"
#   heygen_list_avatars
#
# Required env: HEYGEN_API_KEY (set via your secrets manager —
# Infisical, macOS Keychain, etc. Note: `walter-os secrets-pull` is the
# DEPRECATED Bitwarden/Vaultwarden bridge and is NOT the canonical
# sync path for new secrets. See SKILL.md "Setup" for the current
# secrets-manager flows).
# Required tools: curl, jq.

# Internal — every public function calls this first.
_heygen_preflight() {
  if [[ -z "${HEYGEN_API_KEY:-}" ]]; then
    echo "heygen-cli: HEYGEN_API_KEY not set — populate via your secrets manager (see skills/heygen-cli/SKILL.md)" >&2
    return 2
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "heygen-cli: curl required" >&2
    return 3
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "heygen-cli: jq required (install: brew install jq)" >&2
    return 3
  fi
  return 0
}

_heygen_require_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "heygen-cli: $flag requires a value" >&2
    return 2
  fi
  return 0
}

_heygen_urlencode() {
  jq -nr --arg value "$1" '$value | @uri'
}

_heygen_validate_json_object() {
  local label="$1" value="$2"
  if ! printf '%s' "$value" | jq -ce 'type == "object"' >/dev/null 2>&1; then
    echo "heygen-cli: $label must be a JSON object" >&2
    return 2
  fi
  return 0
}

# Internal — wrap curl with consistent headers + error handling.
# Args: <method> <path> [body-as-json-string]
_heygen_request() {
  local method="$1" path="$2" body="${3:-}"
  local url="https://api.heygen.com${path}"
  local response http_code body_only
  local curl_args=(
    -sS
    --connect-timeout 10
    --max-time 60
    -w $'\n%{http_code}'
    -X "$method"
    -H "x-api-key: ${HEYGEN_API_KEY}"
  )

  if [[ -n "$body" ]]; then
    curl_args+=(
      -H 'Content-Type: application/json'
      --data-raw "$body"
    )
  fi

  if ! response="$(curl "${curl_args[@]}" "$url")"; then
    echo "heygen-cli: transport error calling ${method} ${path}" >&2
    return 6
  fi

  http_code="$(printf '%s' "$response" | tail -n1)"
  body_only="$(printf '%s' "$response" | sed '$d')"
  if [[ ! "$http_code" =~ ^[0-9][0-9][0-9]$ ]]; then
    echo "heygen-cli: transport error calling ${method} ${path} (missing HTTP status)" >&2
    printf '%s\n' "$body_only" >&2
    return 6
  fi

  case "$http_code" in
    2*) printf '%s\n' "$body_only" ;;
    401) echo "heygen-cli: 401 unauthorized — check HEYGEN_API_KEY" >&2; return 4 ;;
    429)
      # Rate-limited. We do NOT auto-retry. We surface the `retry_after`
      # field from the JSON response body (HeyGen's documented field for
      # rate-limit responses; the HTTP `Retry-After` header is NOT parsed
      # — that would require curl `-D -` header-dump plumbing this skill
      # doesn't do today) so the operator can decide whether to back off.
      # The caller gets a non-zero exit; re-invocation is an explicit
      # operator action. Paid-API back-pressure is the operator's call,
      # not the script's — automatic retry on a paid endpoint is a
      # recipe for runaway spend.
      local retry_after
      retry_after="$(printf '%s' "$body_only" | jq -r '.retry_after // empty' 2>/dev/null)"
      echo "heygen-cli: 429 rate-limited (retry_after=${retry_after:-unknown}). Re-run after backoff." >&2
      return 4
      ;;
    *)
      echo "heygen-cli: HTTP ${http_code}" >&2
      printf '%s\n' "$body_only" >&2
      return 5
      ;;
  esac
}

# ----- Read-only (free) -----

heygen_list_avatars() {
  _heygen_preflight || return $?
  _heygen_request GET /v2/avatars
}

heygen_list_voices() {
  _heygen_preflight || return $?
  _heygen_request GET /v2/voices
}

heygen_list_templates() {
  _heygen_preflight || return $?
  _heygen_request GET /v1/template.list
}

# heygen_get_video_status <video_id>
heygen_get_video_status() {
  _heygen_preflight || return $?
  local video_id="${1:-}"
  if [[ -z "$video_id" ]]; then
    echo "heygen-cli: video_id required" >&2
    return 2
  fi
  _heygen_request GET "/v1/video_status.get?video_id=$(_heygen_urlencode "$video_id")"
}

# ----- State-changing (paid — operator-confirmation in chat required) -----
# These functions spend money. The walter-os approval-gate hook does NOT
# carry a dedicated `heygen-*` CATEGORY_MIN_TIER entry today (see SKILL.md
# §Money-spending for the follow-up). Guardrail is the explicit-confirm
# convention from the multi-agent autonomy spec §7.1.

# heygen_generate_video --avatar X --voice Y --script Z [--background HEX] [--ratio 16:9]
heygen_generate_video() {
  _heygen_preflight || return $?
  local avatar="" voice="" script="" background="#0a0a0a" ratio="16:9"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --avatar)     _heygen_require_value "$1" "${2:-}" || return $?; avatar="$2"; shift 2 ;;
      --voice)      _heygen_require_value "$1" "${2:-}" || return $?; voice="$2"; shift 2 ;;
      --script)     _heygen_require_value "$1" "${2:-}" || return $?; script="$2"; shift 2 ;;
      --background) _heygen_require_value "$1" "${2:-}" || return $?; background="$2"; shift 2 ;;
      --ratio)      _heygen_require_value "$1" "${2:-}" || return $?; ratio="$2"; shift 2 ;;
      *) echo "heygen-cli: unknown flag $1" >&2; return 2 ;;
    esac
  done

  # Fail-fast on invalid --ratio. Previously the jq `else` branch silently
  # produced 16:9 dimensions for any unknown value, which is risky on a
  # paid endpoint (caller thinks they got 9:16, gets billed for 16:9).
  case "$ratio" in
    16:9|9:16|1:1) ;;
    *)
      echo "heygen-cli: --ratio must be one of 16:9 | 9:16 | 1:1 (got: $ratio)" >&2
      return 2
      ;;
  esac

  if [[ -z "$avatar" || -z "$voice" || -z "$script" ]]; then
    echo "heygen-cli: --avatar, --voice, --script all required" >&2
    return 2
  fi

  # Build body via jq so script can contain anything safely.
  local body
  body="$(jq -n \
    --arg avatar "$avatar" \
    --arg voice "$voice" \
    --arg script "$script" \
    --arg background "$background" \
    --arg ratio "$ratio" \
    '{
      video_inputs: [
        {
          character: { type: "avatar", avatar_id: $avatar, avatar_style: "normal" },
          voice:     { type: "text",   input_text: $script, voice_id: $voice },
          background: { type: "color", value: $background }
        }
      ],
      dimension: (
        if   $ratio == "16:9" then { width: 1920, height: 1080 }
        elif $ratio == "9:16" then { width: 1080, height: 1920 }
        elif $ratio == "1:1"  then { width: 1080, height: 1080 }
        end
      )
    }')"

  _heygen_request POST /v2/video/generate "$body"
}

# heygen_generate_from_template <template_id> --variables '{...}'
heygen_generate_from_template() {
  _heygen_preflight || return $?
  local template_id="${1:-}"
  if [[ -z "$template_id" || "$template_id" == --* ]]; then
    echo "heygen-cli: template_id required" >&2
    return 2
  fi
  shift
  local variables="{}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --variables)
        if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
          echo "heygen-cli: --variables requires a JSON value" >&2
          return 2
        fi
        variables="$2"
        shift 2
        ;;
      *) echo "heygen-cli: unknown flag $1" >&2; return 2 ;;
    esac
  done
  _heygen_validate_json_object "--variables" "$variables" || return $?
  variables="$(printf '%s' "$variables" | jq -c '.')"
  _heygen_request POST "/v2/template/$(_heygen_urlencode "$template_id")/generate" "$variables"
}
