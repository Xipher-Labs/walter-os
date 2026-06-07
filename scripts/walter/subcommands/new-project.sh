#!/usr/bin/env bash
# walter new project <type> [name]
# type: hackaton | work | personal
#
# Discovery flow + scaffold:
#   1. Prompt for name (if not given) + one-line pitch
#   2. Two-pass thinking-model discovery (12 + 6 questions)
#   3. Pro model synthesizes functional doc → docs/specs/<name>.md
#   4. Bootstrap: git repo + GitHub repo + Plane project + Infisical env
#      + Obsidian KB folder + initial commit + Telegram ping

set -euo pipefail

WALTER_OS_HOME="${WALTER_OS_HOME:?WALTER_OS_HOME required — set in personal.env or export. Default: /opt/walter-os}"
WALTER_LIB="$WALTER_OS_HOME/scripts/walter"
# shellcheck source=/dev/null
source "$WALTER_LIB/lib/log.sh"
# shellcheck source=/dev/null
source "$WALTER_LIB/lib/prompt.sh"
# shellcheck source=/dev/null
source "$WALTER_LIB/lib/litellm.sh"
# shellcheck source=/dev/null
source "$WALTER_LIB/lib/model-router.sh"
# Load operator overlay (canonical personal-config location, sourced by bin/walter as well)
# shellcheck source=/dev/null
[[ -f "$HOME/.config/walter-os/overlay/personal.env" ]] && { set +u; source "$HOME/.config/walter-os/overlay/personal.env"; set -u; }
# Load local secrets if present (separate from personal.env)
# shellcheck source=/dev/null
[[ -f "$HOME/.config/walter-os/secrets.env" ]] && { set +u; source "$HOME/.config/walter-os/secrets.env"; set -u; }

# ---------- args ----------
type="${1:-}"; name="${2:-}"

if [[ "$type" =~ ^(-h|--help|help)$ ]]; then
  cat <<'NP_USAGE'
Usage: walter new project <type> [name]

Types:
  projects  Software projects you build for yourself
            ([Project A], [Project B], WIHT, etc.)
            Lives at: $WALTER_PROJECTS_PATH (default: ~/Projects-Personal)
  hackaton  Short-lived hackathon entries
            Lives at: $WALTER_HACKATON_PATH (default: ~/Projects-Personal/Hackatons)
  work      [Company] / employer projects (compliance-gated)
            Lives at: $WALTER_WORK_PATH (default: ~/work)
  personal  Non-dev personal life (finance, health, journaling)
            Lives at: $WALTER_PERSONAL_PATH (default: ~/personal)

What this command does (idempotent steps, each can be skipped):
  1. Creates host directory ($host_dir/$name)
  2. Initializes git repo + writes initial README.md
  3. Optionally runs the AI discovery flow (LiteLLM gateway, 2-pass)
  4. Creates GitHub repo (private, $WALTER_GITHUB_ORG)
  5. Creates Plane project in workspace 'walter-os'
     (label `context:<projects-personal|work|personal>` per type)
  6. Creates Infisical env named after the project under workspace 'walter-os'
  7. Creates Obsidian KB folder if a vault is detected
  8. Telegram ping if WALTER_TELEGRAM_BOT_TOKEN is set

Examples:
  walter new project projects my-app
  walter new project hackaton grant-categorizer
  walter new project work [company]-grpc-bench

Aliases: project → projects; projects-personal → projects;
         hackathon → hackaton.
NP_USAGE
  exit 0
fi

if [[ -z "$type" ]]; then
  type=$(prompt_choose "Project type:" "projects" "hackaton" "work" "personal")
fi
# Aliases — operator may type "personal" thinking "for myself" but `personal`
# means non-dev personal life (finance/health/journaling). Software projects
# for the operator's own use go in `projects` (= ~/Projects-Personal).
case "$type" in
  # Common typos / alternate names
  project)                    type="projects" ;;
  projects-personal)          type="projects" ;;
  hackathon)                  type="hackaton" ;;
esac

case "$type" in
  hackaton|work|projects|personal) ;;
  *)
    log_err "Invalid type: $type"
    log_err "  Valid types:"
    log_err "    projects  — software projects you build ([Project A], [Project B], WIHT, etc.)"
    log_err "                Lives at: \$WALTER_PROJECTS_PATH (~/Projects-Personal)"
    log_err "    hackaton  — short-lived hackathon entries"
    log_err "                Lives at: \$WALTER_HACKATON_PATH (~/Projects-Personal/Hackatons)"
    log_err "    work      — [Company] / employer projects"
    log_err "                Lives at: \$WALTER_WORK_PATH (~/work)"
    log_err "    personal  — non-dev personal life (finance, health, journaling)"
    log_err "                Lives at: \$WALTER_PERSONAL_PATH (~/personal)"
    log_err ""
    log_err "  If you meant a software project, use 'projects' instead of 'personal'."
    exit 2
    ;;
esac

# Map type → host directory + Plane label (NOT workspace — Walter-OS uses a
# single Plane workspace `walter-os` with `context:*` labels for filtering,
# per the multi-agent autonomy spec §2 / Plane workspace decision).
# Paths are env-var driven (set in ~/.zshrc or ~/.config/walter-os/env):
#   WALTER_HACKATON_PATH (default: ~/Projects-Personal/Hackatons)
#   WALTER_WORK_PATH      (default: ~/work)
#   WALTER_PROJECTS_PATH  (default: ~/Projects-Personal)
#   WALTER_PERSONAL_PATH  (default: ~/personal)
plane_ws="${WALTER_PLANE_WORKSPACE:-walter-os}"
case "$type" in
  hackaton)  host_dir="${WALTER_HACKATON_PATH:-$HOME/Projects-Personal/Hackatons}"; plane_context="projects-personal" ;;
  work)      host_dir="${WALTER_WORK_PATH:-$HOME/work}";                            plane_context="work" ;;
  projects)  host_dir="${WALTER_PROJECTS_PATH:-$HOME/Projects-Personal}";           plane_context="projects-personal" ;;
  personal)  host_dir="${WALTER_PERSONAL_PATH:-$HOME/personal}";                    plane_context="personal" ;;
esac

# Ensure parent dir exists
[[ -d "$host_dir" ]] || mkdir -p "$host_dir"

# ---------- name ----------
if [[ -z "$name" ]]; then
  name=$(prompt_input "Project slug (kebab-case)")
fi
# Validate slug
if [[ ! "$name" =~ ^[a-z][a-z0-9-]+$ ]]; then
  log_err "Invalid slug: '$name' (must be kebab-case, lowercase, start with letter)"
  exit 2
fi
project_dir="$host_dir/$name"

if [[ -e "$project_dir" ]]; then
  log_err "Already exists: $project_dir"
  exit 2
fi

# ---------- summary + confirm ----------
# Operator identity REQUIRED here (after --help / arg validation, before any
# action that actually needs the value). First-time users can still discover
# usage via `walter new project --help` even when the overlay isn't set up.
: "${WALTER_GITHUB_ORG:?WALTER_GITHUB_ORG required — set in ~/.config/walter-os/overlay/personal.env (see contexts/_examples/personal.env.example)}"

log_step "Walter — new project"
echo "  Type:             $type"
echo "  Name:             $name"
echo "  Host directory:   $project_dir"
echo "  GitHub repo:      $WALTER_GITHUB_ORG/$name (private)"
echo "  Plane:            workspace='$plane_ws'  context label='context:$plane_context'"
echo "  Infisical env:    $plane_ws/$name"
# Resolve Obsidian vault path (env-var driven; skip cleanly if not configured)
obsidian_vault="${WALTER_OBSIDIAN_VAULT:-$HOME/Obsidian/personal-vault}"
[[ -d "$obsidian_vault" ]] || obsidian_vault="${WALTER_OBSIDIAN_VAULT:-$HOME/Obsidian/vault}"
echo "  Obsidian KB:      $obsidian_vault/projects/$name $([ ! -d "${WALTER_OBSIDIAN_VAULT:-$HOME/Obsidian/personal-vault}" ] && [ ! -d "$HOME/Obsidian/vault" ] && echo '(skipped — vault not found)')"
echo

prompt_confirm "Proceed?" || { log_warn "Aborted."; exit 0; }

# ---------- create local repo ----------
log_step "Local scaffold"
mkdir -p "$project_dir"
cd "$project_dir"

# Initial files
cat > README.md <<EOF
# $name

> $(prompt_input "One-line pitch")

Created $(date +%F) via \`walter new project $type $name\`.

## Structure

- \`docs/specs/$name.md\` — functional spec (generated from discovery flow)
- (more as the project grows)
EOF

cat > .gitignore <<'EOF'
node_modules/
dist/
build/
.next/
.env
.env.*
!.env.example
!.env.template
*.log
.DS_Store
.idea/
.vscode/
EOF

cat > .env.example <<'EOF'
# Add this file's keys to Infisical via:
#   walter secrets set <key> <value>
EOF

mkdir -p docs/specs

git init -q -b main
git add -A
git commit -q -m "chore: initial scaffold via walter CLI"
log_ok "Repo initialized"

# ---------- Discovery flow (two passes + synth) ----------
log_step "Discovery — Phase -1"
log_dim "(uses LiteLLM gateway with Walter model routing)"

pitch=$(prompt_input "Brief pitch (1 sentence)")

if prompt_confirm "Run the 2-pass AI discovery flow now? (skip with 'n')"; then
  discovery_model=""
  synth_model=""
  walter_model_select_primary brainstorm discovery_model
  walter_model_select_primary longform synth_model

  log_info "Pass 1: generating 12 sharp questions..."

  pass1_prompt="You are a senior product strategist + technical co-founder.

The operator has proposed: \"$pitch\"

Pass 1 of 2: ask exactly 8-12 sharp questions that surface critical
unknowns. Focus on:
  - target user (specific role, not demographic)
  - exact pain point (what they do today that's broken)
  - existing alternatives (what they currently use)
  - distribution channel (how they'll find the product)
  - monetization model (price, frequency)
  - regulatory / compliance constraints
  - technical risks (most likely failure modes)
  - 90-second demo script: what does the judge see?

Output as numbered questions only — no preamble, no commentary.
Keep each question 1 sentence."

  questions1=$(litellm_chat "$pass1_prompt" "$discovery_model")
  echo "$questions1" > docs/specs/discovery-pass-1-questions.md

  log_ok "Pass 1 questions saved to docs/specs/discovery-pass-1-questions.md"
  log_info "Opening editor for you to answer..."
  answers1=$(prompt_editor "$questions1

---

# Your answers below (one per question)

" "md")
  echo "$answers1" > docs/specs/discovery-pass-1.md

  log_info "Pass 2: followup questions exposing risk..."

  pass2_prompt="Pass 2: Given the answers below, ask the FOLLOWUP questions
that expose the riskiest assumptions. Specifically:
  - 3 things that COULD make this not-work
  - the smallest thing the operator could build first that would
    falsify the riskiest assumption
  - what would success look like at hour 48 / week 1 (concrete, observable)
  - what's the ONE feature that, if cut, the project still ships
    and demos credibly

Output as numbered questions only.

# Pass 1 Q+A

$answers1"

  questions2=$(litellm_chat "$pass2_prompt" "$discovery_model")
  answers2=$(prompt_editor "$questions2

---

# Your answers below

" "md")
  echo "$answers2" > docs/specs/discovery-pass-2.md

  log_info "Synthesizing functional document with opus..."

  synth_prompt="Synthesize the discovery answers below into a single,
opinionated functional specification. Format:

# $name — Functional Specification

## 1. Business idea (≤200 words)
   Problem · User · Solution one-liner · Why now

## 2. Definition of Done (SDD)
   Outcome 1: <user can do X, observe Y>
   ...

## 3. Stack
   Frontend / Backend / Database / Auth / Infra
   1-line justification per choice

## 4. Architecture (ASCII diagram + 1 paragraph)

## 5. Test strategy
   Unit / Integration / E2E / DoD validator

## 6. Plan (8-15 tasks, each ≤30 min)
   T1: <file path> · <acceptance check>
   ...

## 7. Demo script (90s)

## 8. Risks + mitigations

# Discovery answers

## Pass 1
$answers1

## Pass 2
$answers2"

  spec=$(litellm_chat "$synth_prompt" "$synth_model")
  echo "$spec" > "docs/specs/$name.md"
  log_ok "Functional spec written to docs/specs/$name.md"

  git add -A
  git commit -q -m "docs: discovery + functional spec via walter"
  log_ok "Spec committed"
else
  log_warn "Skipping discovery flow — you can run it later with: walter discover"
fi

# ---------- GitHub repo ----------
log_step "GitHub repo"
if command -v gh >/dev/null 2>&1; then
  if gh repo create "$WALTER_GITHUB_ORG/$name" --private --source . --remote origin --push 2>&1 | tail -3; then
    log_ok "GitHub repo created + pushed"
  else
    log_warn "gh repo create failed (already exists or permission?)"
  fi
else
  log_warn "gh CLI not found — skip GitHub create. Install via Brewfile."
fi

# ---------- Plane project ----------
log_step "Plane project"

PLANE_API_URL="${PLANE_API_URL:-https://plane.${WALTER_DOMAIN}/api/v1}"
PLANE_API_TOKEN="${PLANE_API_TOKEN:-}"

if [[ -z "$PLANE_API_TOKEN" ]]; then
  # Fetch from Infisical workspace=walter-os env=dev
  PLANE_API_TOKEN=$(infisical secrets get PLANE_API_TOKEN \
    --domain="https://secrets.${WALTER_DOMAIN}" \
    --projectId=8b4d37fa-8a03-4176-9787-69cf4f171324 \
    --env=dev --plain 2>/dev/null || true)
fi

if [[ -z "$PLANE_API_TOKEN" ]]; then
  log_warn "PLANE_API_TOKEN not in Infisical (workspace=walter-os env=dev)."
  log_dim "  Generate at: https://plane.${WALTER_DOMAIN}/profile/api-tokens"
  log_dim "  Then: walter secrets set walter-os dev PLANE_API_TOKEN <token>"
  log_dim "Skipping Plane project creation. Manual create:"
  log_dim "  https://plane.${WALTER_DOMAIN} → workspace '$plane_ws' → New Project"
else
  # Create project + initial issues from spec
  ws_slug="$plane_ws"
  log_info "Creating Plane project '$name' in workspace '$ws_slug'..."
  proj_payload=$(jq -nc --arg n "$name" --arg id "$name" \
    '{name:$n, identifier:($id | ascii_upcase | gsub("[^A-Z0-9]"; "") | .[:5]), network:0}')

  resp=$(curl -sS -X POST "$PLANE_API_URL/workspaces/$ws_slug/projects/" \
    -H "X-API-Key: $PLANE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$proj_payload" 2>&1)
  proj_id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null)

  if [[ -n "$proj_id" ]]; then
    log_ok "Plane project created — id=$proj_id"

    # Tag with context label so Walter Council agents pick it up correctly.
    log_dim "  → applying context label 'context:$plane_context' (manual via web UI; API flow varies by Plane version)"

    # Try to seed issues from docs/specs/<name>.md if exists (plan section)
    if [[ -f "docs/specs/$name.md" ]]; then
      log_info "Seeding initial issues from spec plan section..."
      # Naive: extract lines under "## 6. Plan" → "T1: ...", "T2: ..."
      awk '/## 6\. Plan/,/## 7/' "docs/specs/$name.md" \
        | grep -E '^\s*T[0-9]+:' \
        | head -15 \
        | while read -r line; do
          title=$(echo "$line" | sed -E 's/^\s*T[0-9]+:\s*//')
          issue_payload=$(jq -nc --arg t "$title" \
            '{name:$t, description_html:"", priority:"none", state:null}')
          curl -fsS -X POST "$PLANE_API_URL/workspaces/$ws_slug/projects/$proj_id/issues/" \
            -H "X-API-Key: $PLANE_API_TOKEN" -H "Content-Type: application/json" \
            -d "$issue_payload" >/dev/null && log_ok "  + $title"
          sleep 0.2
        done
    fi
  else
    err_detail=$(echo "$resp" | jq -c '.error // .message // .detail // "unknown"' 2>/dev/null)
    [[ "$err_detail" == "\"unknown\"" || -z "$err_detail" ]] && err_detail="(non-JSON response: $(echo "$resp" | head -c 200))"
    log_warn "Plane create failed: $err_detail"
    log_dim "  Workspace '$ws_slug' may not exist. Manual create:"
    log_dim "  https://plane.${WALTER_DOMAIN} → workspace '$ws_slug' → New Project"
    log_dim "  → after creating, label issues with 'context:$plane_context'"
  fi
fi

# ---------- Infisical env ----------
log_step "Infisical env"
if command -v infisical >/dev/null 2>&1; then
  # Walter-OS uses ONE Infisical workspace named 'walter-os' with multiple
  # environments. We add the project's name as a new ENV under that one
  # workspace, NOT a new workspace per project (operator decision in §2 of
  # the multi-agent autonomy spec).
  infisical_ws="${WALTER_INFISICAL_WORKSPACE:-walter-os}"
  log_info "Creating env '$name' in Infisical workspace '$infisical_ws'..."
  TOKEN=$(infisical user get token 2>&1 | awk '/Token:/ {print $2}')
  WS_ID=$(curl -fsS -H "Authorization: Bearer $TOKEN" "https://secrets.${WALTER_DOMAIN}/api/v1/workspace" 2>/dev/null \
    | jq -r --arg n "$infisical_ws" '.workspaces[]? | select(.name==$n) | .id' | head -1)
  if [[ -n "$WS_ID" ]]; then
    if curl -sS -X POST "https://secrets.${WALTER_DOMAIN}/api/v1/workspace/$WS_ID/environments" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\",\"slug\":\"$name\"}" >/dev/null 2>&1; then
      log_ok "Infisical env created: $infisical_ws/$name"
    else
      log_warn "Infisical env create failed (may already exist; harmless)"
    fi
  else
    log_warn "Workspace '$infisical_ws' not found in Infisical (does it exist? operator may need to create it)"
  fi
else
  log_warn "infisical CLI not found"
fi

# ---------- Obsidian KB folder ----------
log_step "Obsidian KB"
# Vault path is env-var driven. Try the personal-vault name first (most
# common in Walter-OS setups), then the generic 'vault' fallback.
obsidian_vault="${WALTER_OBSIDIAN_VAULT:-}"
if [[ -z "$obsidian_vault" ]]; then
  for candidate in "$HOME/Obsidian/personal-vault" "$HOME/Obsidian/vault" "$HOME/sync/obsidian-vault"; do
    [[ -d "$candidate" ]] && { obsidian_vault="$candidate"; break; }
  done
fi
if [[ -n "$obsidian_vault" && -d "$obsidian_vault" ]]; then
  obsidian_dir="$obsidian_vault/projects/$name"
  mkdir -p "$obsidian_dir"
  cat > "$obsidian_dir/README.md" <<EOF
# $name

[Repo](https://github.com/$WALTER_GITHUB_ORG/$name) · [Plane](https://plane.${WALTER_DOMAIN}) · [Spec](../../$WALTER_OS_HOME/docs/specs/$name.md)

## Daily progress

- $(date +%F) — Project created via walter
EOF
  log_ok "KB folder: $obsidian_dir"
else
  log_warn "Obsidian vault not found. Tried: \$WALTER_OBSIDIAN_VAULT, ~/Obsidian/personal-vault, ~/Obsidian/vault, ~/sync/obsidian-vault — skipping"
  log_dim "  Set WALTER_OBSIDIAN_VAULT=/path/to/vault to enable."
fi

# ---------- Telegram ping ----------
if [[ -n "${WALTER_TELEGRAM_BOT_TOKEN:-}" && -n "${WALTER_TELEGRAM_CHAT_ID:-}" ]]; then
  msg="🆕 *New project*: \`$name\` ($type)
Repo: https://github.com/$WALTER_GITHUB_ORG/$name
Local: \`$project_dir\`"
  curl -fsS -X POST "https://api.telegram.org/bot${WALTER_TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${WALTER_TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$msg" \
    -d "parse_mode=Markdown" >/dev/null && log_ok "Telegram ping sent"
fi

# ---------- summary ----------
log_step "Done"
echo "  Local:    $project_dir"
echo "  GitHub:   https://github.com/$WALTER_GITHUB_ORG/$name"
echo "  Plane:    https://plane.${WALTER_DOMAIN} (manual create)"
echo "  Obsidian: $obsidian_dir"
echo "  Spec:     docs/specs/$name.md (if discovery ran)"
echo
echo "Next:"
echo "  cd $project_dir"
echo "  cursor ."
