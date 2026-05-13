#!/usr/bin/env bash
# migrate-env-to-infisical.sh — find every .env across operator's project roots,
# preview their key surface, push to Infisical via REST API, move originals to
# a backup directory.
#
# Usage:
#   migrate-env-to-infisical.sh [--dry-run] [--non-interactive] [--root <path>]
#                                [--workspace-default <name>]
#                                [--zshrc-extract]
#
# Defaults:
#   roots:              ~/Projects-Personal, ~/work
#   workspace-default:  hackaton
#   backup dir:         ~/.config/walter-os/migrated-envs/<YYYY-MM-DD>/
#   API host:           https://secrets.${WALTER_DOMAIN}
#
# Behavior:
#   1. Get a JWT from `infisical user get token` (you must be logged in).
#   2. List workspaces, build a name→id mapping.
#   3. Find all .env files (NOT .env.example, .env.template).
#   4. For each: preview keys (NEVER values), pick workspace + env, upload via API,
#      move original to backup dir.
#   5. With --zshrc-extract, also pull [Company] creds out of ~/.zshrc into
#      workspace=[company] env=prod (operator can rotate later).
#
# Requires: infisical CLI (logged in), jq, curl, awk.

set -euo pipefail

# ---------- defaults ----------
DRY_RUN=0
NON_INTERACTIVE=0
ZSHRC_EXTRACT=0
ROOTS=()
WORKSPACE_DEFAULT="hackaton"
BACKUP_BASE="${HOME}/.config/walter-os/migrated-envs/$(date +%F)"
INFISICAL_HOST="${INFISICAL_HOST:-https://secrets.${WALTER_DOMAIN}}"

# ---------- arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --zshrc-extract) ZSHRC_EXTRACT=1; shift ;;
    --root) ROOTS+=("$2"); shift 2 ;;
    --workspace-default) WORKSPACE_DEFAULT="$2"; shift 2 ;;
    --host) INFISICAL_HOST="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ ${#ROOTS[@]} -eq 0 ]] && ROOTS=("${HOME}/Projects-Personal" "${HOME}/work")

# ---------- preflight ----------
for cmd in infisical jq curl awk; do
  command -v "$cmd" >/dev/null || { echo "✗ $cmd not in PATH" >&2; exit 2; }
done

if [[ "$DRY_RUN" -eq 0 ]]; then
  TOKEN=$(infisical user get token 2>&1 | awk '/Token:/ {print $2}')
  if [[ -z "$TOKEN" || "${#TOKEN}" -lt 100 ]]; then
    echo "✗ No Infisical session. Run: infisical login --domain $INFISICAL_HOST" >&2
    exit 2
  fi
fi

mkdir -p "$BACKUP_BASE"

# ---------- API helpers ----------
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

list_projects_json() {
  api GET "/v1/workspace" | jq '.workspaces'
}

resolve_project_id() {
  # Lookup by name; if not found, return empty.
  local name="$1"
  echo "$PROJECTS_JSON" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' | head -1
}

ensure_env() {
  # Make sure environment with `slug` exists in the project; create if missing.
  local proj_id="$1" slug="$2"
  local existing
  existing=$(api GET "/v1/workspace/$proj_id" 2>/dev/null | jq -r --arg s "$slug" '.workspace.environments[]? | select(.slug==$s) | .slug' | head -1)
  if [[ -z "$existing" ]]; then
    # Create env if missing — needs name + slug
    api POST "/v1/workspace/$proj_id/environments" \
      "{\"name\":\"$slug\",\"slug\":\"$slug\"}" >/dev/null 2>&1 || true
  fi
}

push_secret() {
  # Push one secret. Upsert: POST first, fallback to PATCH on 4xx.
  # Handles rate limiting (429) with exponential backoff.
  local proj_id="$1" env_slug="$2" key="$3" value="$4"
  local body
  body=$(jq -nc --arg w "$proj_id" --arg e "$env_slug" --arg k "$key" --arg v "$value" \
    '{workspaceId:$w, environment:$e, type:"shared", secretValue:$v, secretComment:"", secretPath:"/"}')
  local resp tries=0 max_tries=4 backoff=2
  local url_safe_key
  # URL-encode the key (basic — only handles common chars)
  url_safe_key=$(printf '%s' "$key" | jq -sRr @uri)
  while [[ $tries -lt $max_tries ]]; do
    resp=$(curl -sS -X POST "$INFISICAL_HOST/api/v3/secrets/raw/$url_safe_key" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$body" -o /tmp/inf-pushresp -w "%{http_code}")
    case "$resp" in
      200|201) return 0 ;;
      429)
        sleep "$backoff"; backoff=$((backoff * 2)); tries=$((tries + 1)); continue ;;
      400|404|409)
        # Already exists or other validation issue; try PATCH
        resp=$(curl -sS -X PATCH "$INFISICAL_HOST/api/v3/secrets/raw/$url_safe_key" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$body" -o /tmp/inf-pushresp -w "%{http_code}")
        case "$resp" in
          200|201) return 0 ;;
          429) sleep "$backoff"; backoff=$((backoff * 2)); tries=$((tries + 1)); continue ;;
          *) return 1 ;;
        esac
        ;;
      *) return 1 ;;
    esac
  done
  return 1
}

push_envfile() {
  # Walk the file line-by-line, push each KEY=VALUE.
  # Skips Ansible Jinja2 templates (lines starting with {% or {{).
  local proj_id="$1" env_slug="$2" envfile="$3"
  local ok=0 fail=0

  # Detect Ansible template + bail
  if grep -qE '^[[:space:]]*\{[%{]' "$envfile"; then
    echo "    ✗ looks like an Ansible/Jinja2 template, not a real .env — skipping" >&2
    echo "0 1"
    return
  fi

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# || "$line" =~ ^[[:space:]]*$ ]] && continue
    # skip Jinja directives just in case
    [[ "$line" =~ ^[[:space:]]*\{% ]] && continue
    [[ "$line" =~ ^[[:space:]]*\{\{ ]] && continue
    line="${line#export }"
    local k="${line%%=*}"
    local v="${line#*=}"
    [[ "$k" == "$line" ]] && continue
    # Validate key name pattern (must be valid env var)
    [[ ! "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && continue
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    if [[ "$v" != *\"* && "$v" != *\'* ]]; then
      v="${v%%#*}"
      v="${v%"${v##*[![:space:]]}"}"
    fi
    if push_secret "$proj_id" "$env_slug" "$k" "$v"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      echo "    ✗ $k (HTTP $(cat /tmp/inf-pushresp 2>/dev/null | head -c 200 || echo unknown))" >&2
    fi
    # Pace requests to avoid rate limit
    sleep 0.15
  done < "$envfile"
  echo "$ok $fail"
}

# ---------- header ----------
echo "==> Walter-OS .env → Infisical migration"
echo "    host:      $INFISICAL_HOST"
echo "    roots:     ${ROOTS[*]}"
echo "    backup:    $BACKUP_BASE"
echo "    dry-run:   $DRY_RUN"
echo

if [[ "$DRY_RUN" -eq 0 ]]; then
  PROJECTS_JSON=$(list_projects_json)
  PROJECT_COUNT=$(echo "$PROJECTS_JSON" | jq 'length')
  echo "    workspaces visible: $PROJECT_COUNT"
  echo "$PROJECTS_JSON" | jq -r '.[] | "      \(.name) (\(.id))"'
  echo
fi

# ---------- discover .env files ----------
declare -a ENV_FILES
while IFS= read -r f; do ENV_FILES+=("$f"); done < <(
  for root in "${ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" \
      \( -type d \( -name node_modules -o -name .git -o -name .next -o -name target \
                  -o -name dist -o -name build -o -name .venv -o -name venv \
                  -o -name '__pycache__' \) -prune \) -o \
      \( -type f \( -name '.env' -o -name '.env.local' -o -name '.env.development' \
                  -o -name '.env.staging' -o -name '.env.production' \) \
                 -not -name '.env.example' -not -name '.env.template' \
                 -print \) 2>/dev/null
  done
)

if [[ ${#ENV_FILES[@]} -eq 0 && "$ZSHRC_EXTRACT" -eq 0 ]]; then
  echo "No .env files found. Use --zshrc-extract to also pull [Company] creds from ~/.zshrc."
  exit 0
fi

echo "Found ${#ENV_FILES[@]} .env files to consider:"
for f in "${ENV_FILES[@]}"; do echo "  - $f"; done
echo

# ---------- per-file loop ----------
declare -i MIGRATED=0 SKIPPED=0 TOTAL_KEYS_OK=0 TOTAL_KEYS_FAIL=0

for envfile in "${ENV_FILES[@]}"; do
  project_dir="$(dirname "$envfile")"
  project_name="$(basename "$project_dir")"
  envfile_name="$(basename "$envfile")"

  # Determine env slug from filename
  case "$envfile_name" in
    .env|.env.local|.env.development) inferred_env="dev" ;;
    .env.staging)                     inferred_env="staging" ;;
    .env.production)                  inferred_env="prod" ;;
    *)                                inferred_env="dev" ;;
  esac

  # Suggest workspace.
  # Operators can customize project→workspace mapping by editing this case;
  # default falls through to WORKSPACE_DEFAULT.
  case "$project_name" in
    walter-os)  suggested_ws="walter-os" ;;
    *)          suggested_ws="$WORKSPACE_DEFAULT" ;;
  esac

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Project:   $project_name"
  echo "File:      $envfile"
  keys=$(grep -E '^(export +)?[A-Z_][A-Z0-9_]*=' "$envfile" 2>/dev/null | sed 's/^export //' | cut -d= -f1 | sort -u)
  if [[ -z "$keys" ]]; then
    echo "  (no keys detected — skipping)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  key_count=$(echo "$keys" | wc -l | tr -d ' ')
  echo "Keys:      $key_count"
  echo "$keys" | sed 's/^/  - /'
  echo

  # Workspace + env decision
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    ws="$suggested_ws"
    env_name="$inferred_env"
    [[ "$ws" == "hackaton" ]] && env_name="$project_name"
  else
    read -r -p "Workspace [${suggested_ws}] (skip with 'skip'): " ws_input
    ws="${ws_input:-$suggested_ws}"
    if [[ "$ws" == "skip" || "$ws" == "s" ]]; then
      echo "  → skipped"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    read -r -p "Environment [${inferred_env}]: " env_input
    env_name="${env_input:-$inferred_env}"
    if [[ "$ws" == "hackaton" ]]; then
      read -r -p "  Hackaton env path [${project_name}]: " env_input2
      env_name="${env_input2:-$project_name}"
    fi
  fi

  # Resolve workspace ID
  proj_id=$(resolve_project_id "$ws")
  if [[ -z "$proj_id" ]]; then
    echo "  ✗ workspace '$ws' not found in your Infisical org. Create it first in the UI, then re-run."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "Will push to: workspace='$ws' (id=$proj_id) env='$env_name'"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would push $key_count secrets"
    MIGRATED=$((MIGRATED + 1))
    continue
  fi

  if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
    read -r -p "Confirm migrate $key_count secrets? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "  → skipped"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  # Ensure env exists
  ensure_env "$proj_id" "$env_name"

  # Push all keys
  read -r ok fail < <(push_envfile "$proj_id" "$env_name" "$envfile")
  echo "  ✓ pushed $ok / $key_count secrets ($fail failed)"
  TOTAL_KEYS_OK=$((TOTAL_KEYS_OK + ok))
  TOTAL_KEYS_FAIL=$((TOTAL_KEYS_FAIL + fail))

  # Move original to backup if everything (or majority) succeeded
  if [[ "$fail" -eq 0 ]]; then
    backup_path="$BACKUP_BASE/${project_name}_${envfile_name}"
    suffix=1
    while [[ -e "$backup_path" ]]; do
      backup_path="$BACKUP_BASE/${project_name}_${envfile_name}.${suffix}"
      suffix=$((suffix + 1))
    done
    mv "$envfile" "$backup_path"
    echo "  ✓ original moved to: $backup_path"
  else
    echo "  ⚠ keeping original at $envfile (some pushes failed)"
  fi

  MIGRATED=$((MIGRATED + 1))
  echo
done

# ---------- .zshrc extraction ----------
if [[ "$ZSHRC_EXTRACT" -eq 1 ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Extracting [Company]-context creds from ~/.zshrc..."
  work_proj_id=$(resolve_project_id "[company]")
  if [[ -z "$work_proj_id" ]]; then
    echo "  ✗ workspace '[company]' not found — create it in Infisical first"
  else
    ensure_env "$work_proj_id" "prod"
    keys_to_extract=(VAULT_USERNAME VAULT_SSH_USERNAME VAULT_ADDR NOMAD_ADDR NOMAD_TOKEN RD_TOKEN RD_URL PAGERDUTY_TOKEN PAGERDUTY_USER_ID)
    declare -i work_ok=0 work_fail=0
    for k in "${keys_to_extract[@]}"; do
      v=$(grep -E "^(export +|declare -x +)?${k}=" ~/.zshrc 2>/dev/null | head -1 | sed -E "s/^(export +|declare -x +)?${k}=//; s/^[\"']//; s/[\"']\$//")
      if [[ -n "$v" ]]; then
        if push_secret "$work_proj_id" "prod" "$k" "$v"; then
          echo "  ✓ $k"
          work_ok=$((work_ok + 1))
        else
          echo "  ✗ $k"
          work_fail=$((work_fail + 1))
        fi
      fi
    done
    echo "  → [company]/prod: $work_ok ok, $work_fail fail"
  fi
fi

# ---------- summary ----------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary:"
echo "  files migrated: $MIGRATED"
echo "  files skipped:  $SKIPPED"
echo "  keys uploaded:  $TOTAL_KEYS_OK"
echo "  keys failed:    $TOTAL_KEYS_FAIL"
echo "  backups:        $BACKUP_BASE"
