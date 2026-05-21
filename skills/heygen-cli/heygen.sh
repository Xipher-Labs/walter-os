#!/usr/bin/env bash
# skills/heygen-cli/heygen.sh
#
# Function library for HeyGen avatar-video REST API.
# Source this file from another script:
#
#   source "$WALTER_OS_HOME/skills/heygen-cli/heygen.sh"
#   heygen_list_avatars
#
# Required env: HEYGEN_API_KEY (pulled via `walter-os secrets-pull`).
# Required tools: curl, jq.

# Internal — every public function calls this first.
_heygen_preflight() {
  if [[ -z "${HEYGEN_API_KEY:-}" ]]; then
    echo "heygen-cli: HEYGEN_API_KEY not set — run walter-os secrets-pull" >&2
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
      # Honor Retry-After if present.
      local retry_after
      retry_after="$(printf '%s' "$body_only" | jq -r '.retry_after // empty' 2>/dev/null)"
      echo "heygen-cli: 429 rate-limited (retry_after=${retry_after:-unknown})" >&2
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --avatar)     avatar="$2"; shift 2 ;;
      --voice)      voice="$2"; shift 2 ;;
      --script)     script="$2"; shift 2 ;;
      --background) background="$2"; shift 2 ;;
      --ratio)      ratio="$2"; shift 2 ;;
      *) echo "heygen-cli: unknown flag $1" >&2; return 2 ;;
    esac
  done

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
      --variables) variables="$2"; shift 2 ;;
      *) echo "heygen-cli: unknown flag $1" >&2; return 2 ;;
    esac
  done
  if [[ -z "$template_id" ]]; then
    echo "heygen-cli: template_id required" >&2
    return 2
  fi
  _heygen_request POST "/v2/template/${template_id}/generate" "$variables"
}
