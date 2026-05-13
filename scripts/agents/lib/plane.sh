#!/usr/bin/env bash
# scripts/agents/lib/plane.sh — Plane API helpers used by the agent
# runner. Sourced (not exec'd). Caller must set:
#
#   PLANE_API_TOKEN   — from secrets / Infisical
#   PLANE_API_URL     — e.g. https://plane.${WALTER_DOMAIN}/api/v1
#   PLANE_WORKSPACE   — workspace slug (e.g. walter-os)
#   PLANE_PROJECT     — project ID (UUID)
#
# All functions return 0 on success, non-zero on error. They write
# their HTTP response body to stdout for the caller to parse with jq.
# Errors go to stderr.

# shellcheck disable=SC2034 # used by callers via source
WALTER_PLANE_LIB_VERSION=1

_plane_check_env() {
  local missing=()
  for v in PLANE_API_TOKEN PLANE_API_URL PLANE_WORKSPACE PLANE_PROJECT; do
    [[ -z "${!v:-}" ]] && missing+=("$v")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "plane.sh: missing env vars: ${missing[*]}" >&2
    return 2
  fi
  return 0
}

_plane_curl() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -m 15 -X "$method" \
      -H "X-Api-Key: $PLANE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${PLANE_API_URL}/workspaces/${PLANE_WORKSPACE}/projects/${PLANE_PROJECT}${path}"
  else
    curl -fsS -m 15 -X "$method" \
      -H "X-Api-Key: $PLANE_API_TOKEN" \
      "${PLANE_API_URL}/workspaces/${PLANE_WORKSPACE}/projects/${PLANE_PROJECT}${path}"
  fi
}

# plane_issue_get <issue_id> → JSON body on stdout
plane_issue_get() {
  _plane_check_env || return $?
  _plane_curl GET "/issues/$1/"
}

# plane_issue_labels <issue_id> → newline-separated label names
plane_issue_labels() {
  _plane_check_env || return $?
  _plane_curl GET "/issues/$1/" | jq -r '.label_names // [] | .[]'
}

# plane_issue_has_label <issue_id> <label> → exit 0 yes, 1 no
plane_issue_has_label() {
  plane_issue_labels "$1" 2>/dev/null | grep -qx "$2"
}

# plane_issue_comment <issue_id> <body> → POST a comment
plane_issue_comment() {
  _plane_check_env || return $?
  local issue_id="$1" body="$2"
  local payload
  payload=$(jq -nc --arg c "$body" '{comment_html: $c, comment_stripped: $c}')
  _plane_curl POST "/issues/$issue_id/comments/" "$payload" >/dev/null
}

# plane_issue_set_state <issue_id> <state_name>
# Plane states are project-scoped. We look up the state UUID by name.
plane_issue_set_state() {
  _plane_check_env || return $?
  local issue_id="$1" state_name="$2"
  local state_id
  state_id=$(_plane_curl GET "/states/" | jq -r --arg n "$state_name" \
    '.results[] | select(.name == $n) | .id' | head -1)
  if [[ -z "$state_id" || "$state_id" == "null" ]]; then
    echo "plane_issue_set_state: state '$state_name' not found in project" >&2
    return 3
  fi
  _plane_curl PATCH "/issues/$issue_id/" "$(jq -nc --arg s "$state_id" '{state: $s}')" >/dev/null
}

# plane_issue_add_label <issue_id> <label_name>
plane_issue_add_label() {
  _plane_check_env || return $?
  local issue_id="$1" label_name="$2"
  local label_id
  label_id=$(_plane_curl GET "/labels/" | jq -r --arg n "$label_name" \
    '.results[] | select(.name == $n) | .id' | head -1)
  if [[ -z "$label_id" || "$label_id" == "null" ]]; then
    echo "plane_issue_add_label: label '$label_name' not found in project" >&2
    return 3
  fi
  # PATCH the issue's labels list (Plane's API expects full replacement)
  local current
  current=$(_plane_curl GET "/issues/$issue_id/" | jq -c '.label_ids // []')
  local new
  new=$(jq -nc --argjson cur "$current" --arg add "$label_id" \
    '$cur + [$add] | unique')
  _plane_curl PATCH "/issues/$issue_id/" "$(jq -nc --argjson l "$new" '{label_ids: $l}')" >/dev/null
}

# plane_issue_create <title> <description> <lane_label> → issue ID on stdout
# Creates a new Plane issue. Returns the issue UUID on success.
plane_issue_create() {
  _plane_check_env || return $?
  local title="$1" description="$2" lane_label="$3"
  local payload
  payload="$(jq -nc \
    --arg name "$title" \
    --arg description "$description" \
    '{name: $name, description_html: $description, description_stripped: $description}')"
  local response
  response="$(_plane_curl POST "/issues/" "$payload")" || return $?
  local issue_id
  issue_id="$(echo "$response" | jq -r '.id // empty')"
  if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
    echo "plane_issue_create: API response missing 'id' field" >&2
    return 3
  fi
  # Attach the lane label if provided
  if [[ -n "$lane_label" ]]; then
    plane_issue_add_label "$issue_id" "$lane_label" 2>/dev/null || true
  fi
  echo "$issue_id"
}

# plane_issue_clear_assignee <issue_id>
# Clears all assignees from a Plane issue (used when re-queuing a zombie).
plane_issue_clear_assignee() {
  _plane_check_env || return $?
  local issue_id="$1"
  _plane_curl PATCH "/issues/$issue_id/" \
    "$(jq -nc '{assignee_ids: []}')" >/dev/null
}

# plane_issues_list_by_state <state_name> → newline-delimited issue IDs
# Returns 0 on success (even if the list is empty), 3 if state not found.
# LIMIT: Plane API returns max 100 issues per page. Pagination not implemented.
# For projects with >100 claimed issues, only the first page is checked.
# TODO: add pagination when watchdog is deployed at scale.
plane_issues_list_by_state() {
  _plane_check_env || return $?
  local state_name="$1"
  # Resolve state name → UUID
  local state_id
  state_id="$(_plane_curl GET "/states/" | jq -r --arg n "$state_name" \
    '.results[] | select(.name == $n) | .id' | head -1)"
  if [[ -z "$state_id" || "$state_id" == "null" ]]; then
    echo "plane_issues_list_by_state: state '$state_name' not found in project" >&2
    return 3
  fi
  # Fetch issues filtered by state UUID
  _plane_curl GET "/issues/?state=$state_id" \
    | jq -r '.results[]? | .id'
}

# plane_issue_set_state_consensus <issue_id> <vote_result_json>
# Transitions a Plane issue out of `awaiting-consensus`:
#   - vote_result.quorum_met == true  → set state to `ready` + post vote comment
#   - vote_result.quorum_met == false → call plane_issue_set_state_awaiting_human
# Spec: docs/specs/walter-council-v2.md — Improvement 9 (T-35)
plane_issue_set_state_consensus() {
  _plane_check_env || return $?
  local issue_id="$1" vote_result_json="${2:-{}}"
  command -v jq >/dev/null 2>&1 || { echo "plane_issue_set_state_consensus: jq required" >&2; return 2; }

  local quorum_met
  quorum_met=$(echo "$vote_result_json" | jq -r '.quorum_met // false' 2>/dev/null || echo "false")

  # Build vote summary comment
  local yes_count no_count abstain_count
  yes_count=$(echo "$vote_result_json" | jq -r '.yes // 0' 2>/dev/null || echo 0)
  no_count=$(echo "$vote_result_json" | jq -r '.no // 0' 2>/dev/null || echo 0)
  abstain_count=$(echo "$vote_result_json" | jq -r '.abstain // 0' 2>/dev/null || echo 0)

  local voter_summary=""
  while IFS= read -r voter_line; do
    local v_agent v_vote v_reason
    v_agent=$(echo "$voter_line" | jq -r '.agent // "?"' 2>/dev/null)
    v_vote=$(echo "$voter_line" | jq -r '.vote // "?"' 2>/dev/null)
    v_reason=$(echo "$voter_line" | jq -r '.reason // ""' 2>/dev/null)
    voter_summary="${voter_summary}"$'\n'"- ${v_agent}: **${v_vote}** — ${v_reason}"
  done < <(echo "$vote_result_json" | jq -c '.voters[]?' 2>/dev/null || true)

  if [[ "$quorum_met" == "true" ]]; then
    local comment
    comment="Council consensus reached: **auto-approved** (yes=${yes_count}, no=${no_count}, abstain=${abstain_count}).${voter_summary}"
    plane_issue_comment "$issue_id" "$comment" 2>/dev/null || true
    plane_issue_set_state "$issue_id" "ready" 2>/dev/null || return $?
  else
    local comment
    comment="Council consensus FAILED: quorum not met (yes=${yes_count}, no=${no_count}, abstain=${abstain_count}). Escalating to operator.${voter_summary}"
    plane_issue_comment "$issue_id" "$comment" 2>/dev/null || true
    plane_issue_set_state_awaiting_human "$issue_id" "$vote_result_json" || return $?
  fi
}

# plane_issue_set_state_awaiting_human <issue_id> <vote_result_json>
# Sets the issue to `awaiting-human` state (operator must manually approve).
# Fails loudly if the `awaiting-human` state doesn't exist in the project.
# Spec: docs/specs/walter-council-v2.md — Improvement 9 (T-35)
plane_issue_set_state_awaiting_human() {
  _plane_check_env || return $?
  local issue_id="$1" vote_result_json="${2:-{}}"

  # Attempt to set state. plane_issue_set_state fails with exit 3 if state not found.
  if ! plane_issue_set_state "$issue_id" "awaiting-human" 2>/dev/null; then
    cat >&2 <<'PREREQ_MSG'
plane_issue_set_state_awaiting_human: state 'awaiting-human' not found in Plane project.
Operator prereq T-prereq-2: create this state in Plane UI before activating consensus mode.
See: docs/operational/council-v2-prereqs.md
PREREQ_MSG
    return 3
  fi
}

# plane_issue_claim <issue_id> <agent_name>
# Atomic-ish claim: PATCH assignee only if currently empty.
# Returns 0 if claimed by us, 4 if someone else already has it.
plane_issue_claim() {
  _plane_check_env || return $?
  local issue_id="$1" agent="$2"
  local current_assignees
  current_assignees=$(_plane_curl GET "/issues/$issue_id/" | jq -r '.assignee_ids // [] | length')
  if [[ "$current_assignees" -gt 0 ]]; then
    echo "plane_issue_claim: issue $issue_id already claimed (assignees=$current_assignees)" >&2
    return 4
  fi
  # NOTE: Plane assignees are user UUIDs, not free-text agent names.
  # We use a sentinel agent-user (created at workspace setup) for each
  # agent. WALTER_AGENT_USER_ID env var (or env file) provides the UUID.
  if [[ -z "${WALTER_AGENT_USER_ID:-}" ]]; then
    echo "plane_issue_claim: WALTER_AGENT_USER_ID not set (need agent-as-user UUID)" >&2
    return 5
  fi
  _plane_curl PATCH "/issues/$issue_id/" \
    "$(jq -nc --arg u "$WALTER_AGENT_USER_ID" '{assignee_ids: [$u]}')" >/dev/null
  echo "plane_issue_claim: $agent claimed $issue_id"
}
