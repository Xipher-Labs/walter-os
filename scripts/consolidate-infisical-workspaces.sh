#!/usr/bin/env bash
# consolidate-infisical-workspaces.sh — one-time cleanup of duplicated workspaces
# and mis-routed envs after the initial bulk migration.
#
# What it does:
#   1. Move secrets from hackaton/{frontend,backend} ([Project B]) → [project-b]-prod/dev
#   2. Move secrets from hackaton/{templates,js} ([Company]) → [company]/prod
#      (prefixed with monad_ / debug_ to avoid name collisions)
#   3. Rename hackaton/{web,api,worker} → barrio-{web,api,worker}
#   4. Delete now-empty hackaton envs.
#   5. Rename [project-b]-prod → [project-b], [project-a]-prod → [project-a].
#   6. Delete empty workspaces: walter-os-meta, [company]-devrel,
#      [project-b]-staging, [project-a]-staging.
#
# Idempotent. Safe to re-run (skips moves that don't apply).
#
# Requires: infisical CLI logged in.

set -euo pipefail

INFISICAL_HOST="${INFISICAL_HOST:-https://secrets.${WALTER_DOMAIN}}"
TOKEN=$(infisical user get token 2>&1 | awk '/Token:/ {print $2}')
[[ -z "$TOKEN" ]] && { echo "no Infisical session"; exit 2; }

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" "$INFISICAL_HOST/api$path" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -fsS -X "$method" "$INFISICAL_HOST/api$path" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

ws_id() {
  api GET "/v1/workspace" | jq -r --arg n "$1" '.workspaces[] | select(.name==$n) | .id' | head -1
}

env_exists() {
  local proj_id="$1" slug="$2"
  api GET "/v1/workspace/$proj_id" | jq -e --arg s "$slug" '.workspace.environments[] | select(.slug==$s)' >/dev/null 2>&1
}

ensure_env() {
  local proj_id="$1" slug="$2" name="$3"
  if ! env_exists "$proj_id" "$slug"; then
    api POST "/v1/workspace/$proj_id/environments" \
      "{\"name\":\"$name\",\"slug\":\"$slug\"}" >/dev/null 2>&1 || true
  fi
}

list_secrets() {
  local proj_id="$1" env_slug="$2"
  api GET "/v3/secrets/raw?workspaceId=$proj_id&environment=$env_slug&secretPath=%2F" \
    | jq -r '.secrets[] | "\(.secretKey)\t\(.secretValue)"'
}

push_secret() {
  local proj_id="$1" env_slug="$2" key="$3" value="$4"
  local body
  body=$(jq -nc --arg w "$proj_id" --arg e "$env_slug" --arg v "$value" \
    '{workspaceId:$w, environment:$e, type:"shared", secretValue:$v, secretComment:"", secretPath:"/"}')
  local url_safe_key resp
  url_safe_key=$(printf '%s' "$key" | jq -sRr @uri)
  resp=$(curl -sS -X POST "$INFISICAL_HOST/api/v3/secrets/raw/$url_safe_key" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$body" -o /dev/null -w "%{http_code}")
  case "$resp" in
    200|201) return 0 ;;
    400|404|409)
      resp=$(curl -sS -X PATCH "$INFISICAL_HOST/api/v3/secrets/raw/$url_safe_key" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d "$body" -o /dev/null -w "%{http_code}")
      [[ "$resp" == "200" || "$resp" == "201" ]] && return 0 || return 1 ;;
    429) sleep 5; return 1 ;;
    *) return 1 ;;
  esac
}

delete_secret() {
  local proj_id="$1" env_slug="$2" key="$3"
  local url_safe_key
  url_safe_key=$(printf '%s' "$key" | jq -sRr @uri)
  local body
  body=$(jq -nc --arg w "$proj_id" --arg e "$env_slug" \
    '{workspaceId:$w, environment:$e, secretPath:"/"}')
  curl -sS -X DELETE "$INFISICAL_HOST/api/v3/secrets/raw/$url_safe_key" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$body" -o /dev/null -w "%{http_code}\n"
}

move_env_to_workspace() {
  # Move all secrets from src/$src_env to dst/$dst_env, optionally key-prefixing.
  local src_id="$1" src_env="$2" dst_id="$3" dst_env="$4" prefix="${5:-}"
  echo "    moving $src_env → workspace $dst_id env $dst_env (prefix='$prefix')"
  local ok=0 fail=0
  while IFS=$'\t' read -r k v; do
    [[ -z "$k" ]] && continue
    new_key="${prefix}${k}"
    if push_secret "$dst_id" "$dst_env" "$new_key" "$v"; then
      ok=$((ok + 1))
      sleep 0.15
    else
      fail=$((fail + 1))
      echo "      ✗ $k"
    fi
  done < <(list_secrets "$src_id" "$src_env")
  echo "      pushed $ok ok, $fail fail"
  echo "$ok|$fail"
}

delete_env_secrets() {
  local proj_id="$1" env_slug="$2"
  while IFS=$'\t' read -r k _; do
    [[ -z "$k" ]] && continue
    delete_secret "$proj_id" "$env_slug" "$k" >/dev/null
    sleep 0.1
  done < <(list_secrets "$proj_id" "$env_slug")
}

delete_env() {
  local proj_id="$1" env_slug="$2"
  api DELETE "/v1/workspace/$proj_id/environments/$env_slug" >/dev/null 2>&1 || true
}

rename_workspace() {
  local proj_id="$1" new_name="$2"
  api PATCH "/v1/workspace/$proj_id" "{\"name\":\"$new_name\"}" >/dev/null 2>&1 || true
}

delete_workspace() {
  local proj_id="$1"
  api DELETE "/v2/workspace/$proj_id" >/dev/null 2>&1 || \
    api DELETE "/v1/workspace/$proj_id" >/dev/null 2>&1 || true
}

# ===========================================================================
echo "==> Step 1: [Project B] frontend + backend → [project-b]-prod/dev"
HACKATON=$(ws_id "hackaton")
PROJECT_B_WS=$(ws_id "[project-b]-prod")
[[ -z "$HACKATON" || -z "$PROJECT_B_WS" ]] && { echo "missing required workspaces"; exit 2; }
echo "  hackaton=$HACKATON  [project-b]-prod=$PROJECT_B_WS"

ensure_env "$PROJECT_B_WS" "dev" "Development"

if env_exists "$HACKATON" "frontend"; then
  echo "  → moving hackaton/frontend → [project-b]-prod/dev"
  move_env_to_workspace "$HACKATON" "frontend" "$PROJECT_B_WS" "dev" ""
fi
if env_exists "$HACKATON" "backend"; then
  echo "  → moving hackaton/backend → [project-b]-prod/dev"
  move_env_to_workspace "$HACKATON" "backend" "$PROJECT_B_WS" "dev" ""
fi

# ===========================================================================
echo "==> Step 2: [Company] monad templates + rpc-debug js → [company]/prod"
WORK_WS=$(ws_id "[company]")
[[ -z "$WORK_WS" ]] && { echo "missing [company] workspace"; exit 2; }

if env_exists "$HACKATON" "templates"; then
  echo "  → moving hackaton/templates → [company]/prod (prefix=monad_)"
  move_env_to_workspace "$HACKATON" "templates" "$WORK_WS" "prod" "MONAD_"
fi
if env_exists "$HACKATON" "js"; then
  echo "  → moving hackaton/js → [company]/prod (prefix=DEBUG_)"
  move_env_to_workspace "$HACKATON" "js" "$WORK_WS" "prod" "DEBUG_"
fi

# ===========================================================================
echo "==> Step 3: rename barrio envs (web/api/worker → barrio-{web,api,worker})"
for old_new in "web|barrio-web" "api|barrio-api" "worker|barrio-worker"; do
  old="${old_new%|*}"
  new="${old_new#*|}"
  if env_exists "$HACKATON" "$old"; then
    echo "  → migrating hackaton/$old → hackaton/$new"
    ensure_env "$HACKATON" "$new" "$new"
    move_env_to_workspace "$HACKATON" "$old" "$HACKATON" "$new" ""
    echo "  → deleting old env hackaton/$old"
    delete_env_secrets "$HACKATON" "$old"
    delete_env "$HACKATON" "$old"
  fi
done

# ===========================================================================
echo "==> Step 4: delete now-empty migrated hackaton envs"
for env_slug in frontend backend templates js; do
  if env_exists "$HACKATON" "$env_slug"; then
    echo "  → deleting hackaton/$env_slug (already moved)"
    delete_env_secrets "$HACKATON" "$env_slug"
    delete_env "$HACKATON" "$env_slug"
  fi
done

# ===========================================================================
echo "==> Step 5: rename workspaces"
PROJECT_A_WS=$(ws_id "[project-a]-prod")
[[ -n "$PROJECT_A_WS" ]] && { echo "  [project-a]-prod → [project-a]"; rename_workspace "$PROJECT_A_WS" "[project-a]"; }
[[ -n "$PROJECT_B_WS" ]]     && { echo "  [project-b]-prod → [project-b]"; rename_workspace "$PROJECT_B_WS" "[project-b]"; }

# ===========================================================================
echo "==> Step 6: delete empty duplicated workspaces"
for ws in walter-os-meta [company]-devrel [project-b]-staging [project-a]-staging; do
  ID=$(ws_id "$ws")
  if [[ -n "$ID" ]]; then
    # Check it has zero secrets across all envs first (safety)
    total=$(api GET "/v1/workspace/$ID" | jq -r '.workspace.environments[]? | .slug' | while read -r s; do
      cnt=$(api GET "/v3/secrets/raw?workspaceId=$ID&environment=$s&secretPath=%2F" | jq '.secrets | length')
      echo "${cnt:-0}"
    done | awk '{s+=$1} END {print s+0}')
    if [[ "$total" == "0" ]]; then
      echo "  $ws is empty → deleting"
      delete_workspace "$ID"
    else
      echo "  $ws has $total secrets — NOT deleting (manual review needed)"
    fi
  fi
done

# ===========================================================================
echo
echo "==> Final state:"
ALL=$(api GET "/v1/workspace")
echo "$ALL" | jq -r '.workspaces[] | "\(.id)\t\(.name)"' | while IFS=$'\t' read -r id name; do
  envs_resp=$(api GET "/v1/workspace/$id")
  echo "$envs_resp" | jq -r '.workspace.environments[]? | .slug' | while read -r slug; do
    [[ -z "$slug" ]] && continue
    cnt=$(api GET "/v3/secrets/raw?workspaceId=$id&environment=$slug&secretPath=%2F" | jq '.secrets | length' 2>/dev/null)
    [[ "$cnt" == "null" || -z "$cnt" ]] && cnt=0
    [[ "$cnt" -gt 0 ]] && printf "  %-22s / %-25s = %s\n" "$name" "$slug" "$cnt"
  done
done
echo "Done."
