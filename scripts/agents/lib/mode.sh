#!/usr/bin/env bash
# scripts/agents/lib/mode.sh — Walter Council operating mode management.
# Sourced (not exec'd) by bin/walter-os and any script that reads/writes mode.
#
# Manages ~/.config/walter-os/mode.json:
#   {
#     "consensus": true|false,
#     "since": "<ISO-8601 timestamp>",
#     "voting_threshold": <int, default 3>
#   }
#
# Functions:
#   mode_consensus_get         → prints current mode.json, or '{}' if missing
#   mode_consensus_is_on       → exit 0 if ON, exit 1 if OFF
#   mode_consensus_set <on|off> [--threshold N]
#                              → write/update mode.json
#   summary_since <timestamp>  → read consensus-votes.log since <ts>
#
# Spec: docs/specs/walter-council-v2.md — Improvement 9 (T-32)
# Refs: T-32, T-36b

# shellcheck disable=SC2034 # used by callers
WALTER_MODE_LIB_VERSION=1

WALTER_CONFIG="${WALTER_CONFIG:-${HOME}/.config/walter-os}"
MODE_FILE="${WALTER_MODE_FILE:-${WALTER_CONFIG}/mode.json}"
CONSENSUS_VOTES_LOG="${WALTER_CONSENSUS_VOTES_LOG:-/var/log/walter-council/consensus-votes.log}"

# mode_consensus_get → prints mode.json content (or '{}' if missing)
mode_consensus_get() {
  if [[ -f "$MODE_FILE" ]]; then
    cat "$MODE_FILE"
  else
    echo '{}'
  fi
}

# mode_consensus_is_on → exit 0 if consensus mode is ON, 1 if OFF
mode_consensus_is_on() {
  local val
  val=$(jq -r '.consensus // false' "$MODE_FILE" 2>/dev/null || echo "false")
  [[ "$val" == "true" ]]
}

# mode_consensus_set <on|off> [--threshold N]
# Writes or updates mode.json atomically.
mode_consensus_set() {
  local state="${1:-}"
  local threshold=3
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold) threshold="${2:-3}"; shift 2 ;;
      *) shift ;;
    esac
  done

  case "$state" in
    on)
      local since
      since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      mkdir -p "$(dirname "$MODE_FILE")"
      local tmp
      tmp="$(mktemp "${MODE_FILE}.XXXXXX")"
      jq -n \
        --argjson consensus true \
        --arg since "$since" \
        --argjson threshold "$threshold" \
        '{consensus: $consensus, since: $since, voting_threshold: $threshold}' \
        > "$tmp" \
        && mv "$tmp" "$MODE_FILE"
      ;;
    off)
      mkdir -p "$(dirname "$MODE_FILE")"
      local tmp
      tmp="$(mktemp "${MODE_FILE}.XXXXXX")"
      if [[ -f "$MODE_FILE" ]]; then
        jq '.consensus = false' "$MODE_FILE" > "$tmp" && mv "$tmp" "$MODE_FILE"
      else
        jq -n '{consensus: false}' > "$tmp" && mv "$tmp" "$MODE_FILE"
      fi
      ;;
    *)
      echo "mode.sh: invalid state '$state'. Use: on | off" >&2
      return 2
      ;;
  esac
}

# summary_since <ISO-date-or-timestamp>
# Reads consensus-votes.log and events.log since <since>.
# Prints: approved count, awaiting-human count, failed-consensus count.
# Returns JSON on stdout.
summary_since() {
  local since="${1:-}"
  [[ -z "$since" ]] && { echo "mode.sh: summary_since requires a timestamp" >&2; return 2; }

  local approved=0 awaiting_human=0 failed_consensus=0
  local approved_links=() awaiting_links=() failed_links=()

  if [[ -f "$CONSENSUS_VOTES_LOG" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ts event issue
      ts=$(echo "$line" | jq -r '.ts // ""' 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      # Simple string comparison for ISO dates (lexicographic order works)
      [[ "$ts" < "$since" ]] && continue
      event=$(echo "$line" | jq -r '.event // ""' 2>/dev/null || echo "")
      issue=$(echo "$line" | jq -r '.issue_id // ""' 2>/dev/null || echo "")
      case "$event" in
        consensus_approved)
          approved=$((approved + 1))
          [[ -n "$issue" ]] && approved_links+=("$issue")
          ;;
        consensus_failed)
          failed_consensus=$((failed_consensus + 1))
          [[ -n "$issue" ]] && failed_links+=("$issue")
          ;;
        awaiting_human)
          awaiting_human=$((awaiting_human + 1))
          [[ -n "$issue" ]] && awaiting_links+=("$issue")
          ;;
      esac
    done < "$CONSENSUS_VOTES_LOG"
  fi

  jq -n \
    --argjson approved "$approved" \
    --argjson failed_consensus "$failed_consensus" \
    --argjson awaiting_human "$awaiting_human" \
    --argjson approved_links "$(printf '%s\n' "${approved_links[@]}" | jq -Rnc '[inputs]')" \
    --argjson awaiting_links "$(printf '%s\n' "${awaiting_links[@]}" | jq -Rnc '[inputs]')" \
    --argjson failed_links "$(printf '%s\n' "${failed_links[@]}" | jq -Rnc '[inputs]')" \
    '{
      consensus_approved: $approved,
      awaiting_human: $awaiting_human,
      failed_consensus: $failed_consensus,
      approved_issues: $approved_links,
      awaiting_issues: $awaiting_links,
      failed_issues: $failed_links
    }'
}
