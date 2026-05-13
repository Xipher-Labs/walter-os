#!/usr/bin/env bash
# skills/project-induction/scripts/induction.sh
# Project induction interview — generates a bootstrap spec, AGENTS.md,
# and a Plane epic for a new project.
#
# Usage:
#   induction.sh [options]
#   induction.sh --non-interactive --answers-file <path.yml> [options]
#
# Options:
#   --non-interactive          Skip interactive prompts; requires --answers-file
#   --answers-file <path>      YAML file with pre-filled answers (see fixtures)
#   --project-type <type>      Override project type (webapp|service|solana|hackathon|personal)
#   --project-name <name>      Override project name
#   --output-dir <path>        Write outputs to this directory (default: docs/specs/)
#   --skip-plane               Skip Plane epic creation (for offline/test use)
#   -h|--help                  Show this help
#
# Spec: docs/specs/walter-council-v2.md — Improvement 6 (T-23)

set -uo pipefail

# ---------- arg parsing ----------

NON_INTERACTIVE=0
ANSWERS_FILE=""
PROJECT_TYPE_OVERRIDE=""
PROJECT_NAME_OVERRIDE=""
OUTPUT_DIR=""
SKIP_PLANE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive)   NON_INTERACTIVE=1; shift ;;
    --answers-file)      ANSWERS_FILE="$2"; shift 2 ;;
    --project-type)      PROJECT_TYPE_OVERRIDE="$2"; shift 2 ;;
    --project-name)      PROJECT_NAME_OVERRIDE="$2"; shift 2 ;;
    --output-dir)        OUTPUT_DIR="$2"; shift 2 ;;
    --skip-plane)        SKIP_PLANE=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "induction.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ---------- validation ----------

VALID_TYPES=(webapp service solana hackathon personal)

_validate_type() {
  local t="$1"
  for valid in "${VALID_TYPES[@]}"; do
    [[ "$t" == "$valid" ]] && return 0
  done
  echo "induction.sh: invalid project type '$t'." >&2
  echo "  Valid types: ${VALID_TYPES[*]}" >&2
  return 2
}

_validate_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "induction.sh: project name is required." >&2
    return 2
  fi
  if ! echo "$name" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9-]{0,49}$'; then
    echo "induction.sh: project name must be alphanumeric+hyphens, ≤ 50 chars." >&2
    return 2
  fi
  return 0
}

# ---------- YAML reader — uses python3+yaml when available, grep+sed fallback ----------

_yaml_get() {
  local file="$1" key="$2" default="${3:-}"
  if [[ ! -f "$file" ]]; then
    echo "$default"
    return 0
  fi

  # Preferred: python3 yaml.safe_load — handles colons, special chars, multiline.
  # Values passed via sys.argv to avoid single-quote injection through ${file}/${key}/${default}.
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
    local val
    val=$(python3 -c "
import yaml, sys
filepath = sys.argv[1]
key = sys.argv[2]
default = sys.argv[3]
try:
    with open(filepath) as f:
        d = yaml.safe_load(f.read())
    v = d.get(key, default) if d else default
    if v is None:
        v = default
    # Normalize Python booleans to lowercase strings (True -> 'true', False -> 'false')
    if isinstance(v, bool):
        v = 'true' if v else 'false'
    print(v)
except Exception:
    print(default)
" "$file" "$key" "$default" 2>/dev/null)
    if [[ -z "$val" || "$val" == "None" ]]; then
      echo "$default"
    else
      echo "$val"
    fi
    return 0
  fi

  # Fallback: grep+sed (works for simple key: value, breaks on colons in values)
  local val
  val=$(grep -E "^${key}:" "$file" | head -1 | sed "s/^${key}: *//" | sed 's/^[\"'"'"']//' | sed 's/[\"'"'"']$//' | xargs 2>/dev/null || echo "")
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

# ---------- load answers ----------

PROJECT_NAME=""
PROJECT_TYPE=""
DESCRIPTION=""
STACK=""
NON_NEGOTIABLE=""
CRITICAL_INTEGRATIONS=""
SUCCESS_KPIS=""
PHI_DATA="false"
FINANCIAL_DATA="false"

if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
  if [[ -z "$ANSWERS_FILE" ]]; then
    echo "induction.sh: --non-interactive requires --answers-file." >&2
    exit 2
  fi
  if [[ ! -f "$ANSWERS_FILE" ]]; then
    echo "induction.sh: answers file not found: $ANSWERS_FILE" >&2
    exit 2
  fi

  PROJECT_NAME="$(_yaml_get "$ANSWERS_FILE" "project_name")"
  PROJECT_TYPE="$(_yaml_get "$ANSWERS_FILE" "project_type")"
  DESCRIPTION="$(_yaml_get "$ANSWERS_FILE" "description")"
  STACK="$(_yaml_get "$ANSWERS_FILE" "stack")"
  NON_NEGOTIABLE="$(_yaml_get "$ANSWERS_FILE" "non_negotiable_rules")"
  CRITICAL_INTEGRATIONS="$(_yaml_get "$ANSWERS_FILE" "critical_integrations")"
  SUCCESS_KPIS="$(_yaml_get "$ANSWERS_FILE" "success_kpis")"
  PHI_DATA="$(_yaml_get "$ANSWERS_FILE" "phi_data" "false")"
  FINANCIAL_DATA="$(_yaml_get "$ANSWERS_FILE" "financial_data" "false")"
  # Normalize YAML boolean representations (True/False/yes/no/1/0 → true/false)
  # Python yaml.safe_load returns Python bool which prints as "True"/"False" on
  # older code paths; grep+sed fallback may return "yes"/"True". Normalize here.
  [[ "${PHI_DATA,,}" == "true" || "$PHI_DATA" == "1" || "${PHI_DATA,,}" == "yes" ]] \
    && PHI_DATA="true" || PHI_DATA="false"
  [[ "${FINANCIAL_DATA,,}" == "true" || "$FINANCIAL_DATA" == "1" || "${FINANCIAL_DATA,,}" == "yes" ]] \
    && FINANCIAL_DATA="true" || FINANCIAL_DATA="false"
else
  # Interactive mode
  echo "=== Walter OS — Project Induction ==="
  echo
  read -r -p "Q1: What does this project do? (1-3 sentences) " DESCRIPTION
  read -r -p "Q2: Project name (alphanumeric+hyphens, ≤50 chars): " PROJECT_NAME
  read -r -p "Q3: Project type [webapp|service|solana|hackathon|personal]: " PROJECT_TYPE
  read -r -p "Q4: Tech stack (or press Enter for type defaults): " STACK
  read -r -p "Q5: Non-negotiable rules? (compliance, perf, legal — or Enter to skip): " NON_NEGOTIABLE
  read -r -p "Q6: Critical integrations? (DBs, APIs, 3rd party — or Enter to skip): " CRITICAL_INTEGRATIONS
  read -r -p "Q7: How will you know this project succeeded? (KPIs): " SUCCESS_KPIS
  read -r -p "Q8: Does this project handle medical/health data? [y/N]: " _phi_ans
  read -r -p "Q9: Does this project handle financial transactions? [y/N]: " _fin_ans
  [[ "$_phi_ans" =~ ^[Yy] ]] && PHI_DATA="true"
  [[ "$_fin_ans" =~ ^[Yy] ]] && FINANCIAL_DATA="true"
fi

# Apply CLI overrides
[[ -n "$PROJECT_TYPE_OVERRIDE" ]] && PROJECT_TYPE="$PROJECT_TYPE_OVERRIDE"
[[ -n "$PROJECT_NAME_OVERRIDE" ]] && PROJECT_NAME="$PROJECT_NAME_OVERRIDE"

# Validate
_validate_name "$PROJECT_NAME" || exit 2
_validate_type "$PROJECT_TYPE" || exit 2

# ---------- stack defaults ----------

if [[ -z "$STACK" ]]; then
  case "$PROJECT_TYPE" in
    webapp)    STACK="Next.js 15 + Supabase + Vercel + Tailwind" ;;
    service)   STACK="Node.js/Rust + Postgres + Docker" ;;
    solana)    STACK="Anchor + TypeScript SDK + solana-test-validator" ;;
    hackathon) STACK="Next.js 15 + Supabase (quick-start)" ;;
    personal)  STACK="Obsidian + local scripts" ;;
  esac
fi

# ---------- output dir ----------

if [[ -z "$OUTPUT_DIR" ]]; then
  WALTER_OS_HOME="${WALTER_OS_HOME:-}"
  if [[ -n "$WALTER_OS_HOME" && -d "$WALTER_OS_HOME/docs/specs" ]]; then
    OUTPUT_DIR="$WALTER_OS_HOME/docs/specs"
  else
    OUTPUT_DIR="./docs/specs"
  fi
fi
mkdir -p "$OUTPUT_DIR"

SLUG="${PROJECT_NAME}"
CHARTER_FILE="${OUTPUT_DIR}/${SLUG}-bootstrap.md"
AGENTS_FILE="${OUTPUT_DIR}/AGENTS.md"

# ---------- generate project charter ----------

cat > "$CHARTER_FILE" <<CHARTER_EOF
# ${PROJECT_NAME} — Bootstrap Spec

**Type**: ${PROJECT_TYPE}
**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Skill**: project-induction

## Problem

${DESCRIPTION}

## Stack

${STACK}

## Non-Negotiable Rules

${NON_NEGOTIABLE:-None specified.}

## Critical Integrations

${CRITICAL_INTEGRATIONS:-None specified.}

## Acceptance Criteria (Bootstrap Phase)

- [AC-1] CI pipeline is green (lint + typecheck + unit tests pass).
- [AC-2] First smoke-test endpoint or feature is implemented and tested.
- [AC-3] README.md documents how to run the project locally.
- [AC-4] All secrets managed via env vars (no hardcoded credentials).

## Success KPIs

${SUCCESS_KPIS:-Not defined yet.}

## Non-Goals (Bootstrap)

- Production deployment configuration.
- Performance optimization beyond baseline.
- Full feature set — focus on skeleton + first feature.

## Refs

Spec: docs/specs/${SLUG}-bootstrap.md
Generated by: skills/project-induction/scripts/induction.sh
CHARTER_EOF

# ---------- generate project AGENTS.md ----------

{
  echo "# AGENTS.md — ${PROJECT_NAME}"
  echo
  echo "Generated by project-induction skill. Customize as needed."
  echo
  echo "## Project"
  echo
  echo "**Name**: ${PROJECT_NAME}"
  echo "**Type**: ${PROJECT_TYPE}"
  echo "**Stack**: ${STACK}"
  echo
  echo "## Stack-specific rules"
  echo
  case "$PROJECT_TYPE" in
    webapp)
      echo "- Use Next.js App Router (not Pages Router)."
      echo "- Tailwind for styling. Shadcn/ui as component baseline."
      echo "- Drizzle ORM over raw SQL."
      ;;
    service)
      echo "- Service must be containerizable (Dockerfile required)."
      echo "- Expose health endpoint at /health."
      ;;
    solana)
      echo "- Anchor framework for all on-chain programs."
      echo "- All tests run against solana-test-validator."
      echo "- CU estimates required for every new instruction."
      ;;
    hackathon)
      echo "- Optimize for shipping. Cut features, never tests."
      echo "- 48h timeline discipline applies."
      ;;
    personal)
      echo "- Local-first. Data stays on device unless operator confirms sharing."
      ;;
  esac

  if [[ "$PHI_DATA" == "true" ]]; then
    echo
    echo "## PHI / Medical Data (CRITICAL)"
    echo
    echo "- **medical-data-compliance** skill is MANDATORY for all PRs touching patient data."
    echo "- PHI NEVER leaves the local environment. No external LLM APIs with medical content."
    echo "- Use local Ollama (local LLM node) for any AI assistance on real records."
    echo "- Hashes and ZK proofs are fine. Raw records are not."
    echo "- Argentine Ley 26.529 + Ley 25.326 compliance required."
  fi

  if [[ "$FINANCIAL_DATA" == "true" ]]; then
    echo
    echo "## TODO: Financial data compliance"
    echo
    echo "This project handles financial data. The \`financial-data-compliance\` skill"
    echo "is pending creation. Until then:"
    echo "- Refer to manual PCI-DSS guidelines"
    echo "- All money-moving operations require operator confirmation"
    echo "- Reference: docs/specs/financial-data-compliance.md (TBD)"
  fi

  echo
  echo "## Skills (auto-loaded)"
  echo
  echo "- web-security-baseline"
  echo "- definition-of-done-validator"
  if [[ "$PHI_DATA" == "true" ]]; then
    echo "- medical-data-compliance"
  fi
  if [[ "$PROJECT_TYPE" == "solana" ]]; then
    echo "- solana-program-review"
    echo "- solana-rpc-review"
  fi
} > "$AGENTS_FILE"

echo "induction.sh: charter written to $CHARTER_FILE"
echo "induction.sh: AGENTS.md written to $AGENTS_FILE"

# ---------- create Plane epic (unless --skip-plane) ----------

if [[ "$SKIP_PLANE" -eq 0 ]]; then
  LIB_DIR="${WALTER_OS_HOME}/scripts/agents/lib"
  if [[ -f "${LIB_DIR}/plane.sh" ]]; then
    # shellcheck disable=SC1091
    source "${LIB_DIR}/plane.sh"

    # Check Plane env vars
    if [[ -n "${PLANE_API_TOKEN:-}" && -n "${PLANE_API_URL:-}" ]]; then
      epic_title="Bootstrap: ${PROJECT_NAME}"
      epic_desc="Auto-generated bootstrap epic from project-induction skill.\n\nCharter: ${CHARTER_FILE}"
      epic_id=$(plane_issue_create "$epic_title" "$epic_desc" "" 2>/dev/null || echo "")
      if [[ -n "$epic_id" ]]; then
        echo "induction.sh: Plane epic created: $epic_id"

        # Create 5 bootstrap tasks under the epic
        BOOTSTRAP_TASKS=(
          "Setup CI pipeline"
          "Initial test infrastructure"
          "First feature: ${PROJECT_NAME} skeleton"
          "Setup local dev environment"
          "Write README + getting started guide"
        )
        task_count=0
        # R12: plane_issue_add_label only works for labels of kind "issue".
        # Using a label like bootstrap-epic:${epic_id} fails silently for epics.
        # Fix: embed parent epic reference in the task description instead.
        for task_title in "${BOOTSTRAP_TASKS[@]}"; do
          task_desc="**Parent Epic**: ${epic_id}"$'\n\n'"Bootstrap task for ${PROJECT_NAME}."
          task_id=$(plane_issue_create "$task_title" "$task_desc" "" 2>/dev/null || echo "")
          if [[ -n "$task_id" ]]; then
            task_count=$(( task_count + 1 ))
          fi
        done
        echo "induction.sh: ${task_count} bootstrap tasks created."
      else
        echo "induction.sh: Plane epic creation skipped (API call failed or no response)." >&2
      fi
    else
      echo "induction.sh: Plane env vars not set — skipping epic creation." >&2
    fi
  else
    echo "induction.sh: plane.sh not found at ${LIB_DIR} — skipping epic creation." >&2
  fi
fi

echo "induction.sh: done."
exit 0
