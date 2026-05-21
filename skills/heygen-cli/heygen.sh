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

# Internal — wrap curl with consistent headers + error handling.
# Args: <method> <path> [body-as-json-string]
_heygen_request() {
  local method="$1" path="$2" body="${3:-}"
  local url="https://api.heygen.com${path}"
  local response http_code

  if [[ -n "$body" ]]; then
    response="$(curl -sS -w '\n%{http_code}' \
      -X "$method" \
      -H "x-api-key: ${HEYGEN_API_KEY}" \
      -H 'Content-Type: application/json' \
      -d "$body" \
      "$url")"
  else
    response="$(curl -sS -w '\n%{http_code}' \
      -X "$method" \
      -H "x-api-key: ${HEYGEN_API_KEY}" \
      "$url")"
  fi

  http_code="$(printf '%s' "$response" | tail -n1)"
  body_only="$(printf '%s' "$response" | sed '$d')"

  case "$http_code" in
    2*) printf '%s\n' "$body_only" ;;
    401) echo "heygen-cli: 401 unauthorized — check HEYGEN_API_KEY" >&2; return 4 ;;
    429)
      # Rate-limited. We do NOT auto-retry. We surface the HTTP Retry-After
      # header (or `retry_after` field in the response body if present) so
      # the operator can decide whether to back off. The caller gets a
      # non-zero exit; re-invocation is an explicit operator action.
      # Per the skill's design note: paid-API back-pressure is the
      # operator's call, not the script's — automatic retry on a paid
      # endpoint is a recipe for runaway spend.
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
  _heygen_request GET "/v1/video_status.get?video_id=${video_id}"
}

# ----- State-changing (paid — approval-gate enforces high tier) -----

# heygen_generate_video --avatar X --voice Y --script Z [--background HEX] [--ratio 16:9]
heygen_generate_video() {
  _heygen_preflight || return $?
  local avatar="" voice="" script="" background="#0a0a0a" ratio="16:9"

  # Helper: require a value follows the flag, then shift past both. Copilot
  # R1 flagged that bare `shift 2` would silently mis-parse if a flag was
  # passed without its argument (e.g., `--avatar --voice ID`).
  _require_value() {
    local flag="$1" value="$2"
    if [[ -z "$value" || "$value" == --* ]]; then
      echo "heygen-cli: $flag requires a value" >&2
      return 2
    fi
    return 0
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --avatar)     _require_value "$1" "${2:-}" || return $?; avatar="$2"; shift 2 ;;
      --voice)      _require_value "$1" "${2:-}" || return $?; voice="$2"; shift 2 ;;
      --script)     _require_value "$1" "${2:-}" || return $?; script="$2"; shift 2 ;;
      --background) _require_value "$1" "${2:-}" || return $?; background="$2"; shift 2 ;;
      --ratio)      _require_value "$1" "${2:-}" || return $?; ratio="$2"; shift 2 ;;
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
        else                       { width: 1920, height: 1080 }
        end
      )
    }')"

  _heygen_request POST /v2/video/generate "$body"
}

# heygen_generate_from_template <template_id> --variables '{...}'
heygen_generate_from_template() {
  _heygen_preflight || return $?
  local template_id="${1:-}"
  shift || true
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
  if [[ -z "$template_id" ]]; then
    echo "heygen-cli: template_id required" >&2
    return 2
  fi
  _heygen_request POST "/v2/template/${template_id}/generate" "$variables"
}
