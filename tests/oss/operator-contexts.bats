#!/usr/bin/env bats
# tests/oss/operator-contexts.bats
# Regression suite for the operator-contexts feature (docs/specs/walter-operator-contexts.md).
# Asserts structural invariants: file existence, content smoke checks, and no operator leaks.
# Does NOT require external services or parse complex content.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ---------------------------------------------------------------------------
# Context structure — all 4 contexts must have the 3 required files
# ---------------------------------------------------------------------------

@test "context work: AGENTS.md exists" {
  [ -f "$REPO_ROOT/contexts/work/AGENTS.md" ]
}

@test "context work: PROMPT.md exists" {
  [ -f "$REPO_ROOT/contexts/work/PROMPT.md" ]
}

@test "context work: SKILLS.md exists" {
  [ -f "$REPO_ROOT/contexts/work/SKILLS.md" ]
}

@test "context work: AGENTS.md is non-empty" {
  [ -s "$REPO_ROOT/contexts/work/AGENTS.md" ]
}

@test "context personal: AGENTS.md exists" {
  [ -f "$REPO_ROOT/contexts/personal/AGENTS.md" ]
}

@test "context personal: PROMPT.md exists" {
  [ -f "$REPO_ROOT/contexts/personal/PROMPT.md" ]
}

@test "context personal: SKILLS.md exists" {
  [ -f "$REPO_ROOT/contexts/personal/SKILLS.md" ]
}

@test "context personal: AGENTS.md is non-empty" {
  [ -s "$REPO_ROOT/contexts/personal/AGENTS.md" ]
}

@test "context projects-personal: AGENTS.md exists" {
  [ -f "$REPO_ROOT/contexts/projects-personal/AGENTS.md" ]
}

@test "context projects-personal: PROMPT.md exists" {
  [ -f "$REPO_ROOT/contexts/projects-personal/PROMPT.md" ]
}

@test "context projects-personal: SKILLS.md exists" {
  [ -f "$REPO_ROOT/contexts/projects-personal/SKILLS.md" ]
}

@test "context projects-personal: AGENTS.md is non-empty" {
  [ -s "$REPO_ROOT/contexts/projects-personal/AGENTS.md" ]
}

@test "context hackathons: AGENTS.md exists" {
  [ -f "$REPO_ROOT/contexts/hackathons/AGENTS.md" ]
}

@test "context hackathons: PROMPT.md exists" {
  [ -f "$REPO_ROOT/contexts/hackathons/PROMPT.md" ]
}

@test "context hackathons: SKILLS.md exists" {
  [ -f "$REPO_ROOT/contexts/hackathons/SKILLS.md" ]
}

@test "context hackathons: AGENTS.md is non-empty" {
  [ -s "$REPO_ROOT/contexts/hackathons/AGENTS.md" ]
}

# ---------------------------------------------------------------------------
# Hackathons content smoke checks (AC-1)
# ---------------------------------------------------------------------------

@test "hackathons AGENTS.md mentions 48h sprint" {
  grep -qi "48" "$REPO_ROOT/contexts/hackathons/AGENTS.md"
}

@test "hackathons AGENTS.md mentions demo" {
  grep -qi "demo" "$REPO_ROOT/contexts/hackathons/AGENTS.md"
}

@test "hackathons AGENTS.md mentions WALTER_CONTEXT" {
  grep -q "WALTER_CONTEXT" "$REPO_ROOT/contexts/hackathons/AGENTS.md"
}

# ---------------------------------------------------------------------------
# PROMPT.md structure smoke checks (AC-2)
# ---------------------------------------------------------------------------

@test "work PROMPT.md contains numbered questions" {
  grep -qE "^[0-9]\." "$REPO_ROOT/contexts/work/PROMPT.md"
}

@test "personal PROMPT.md contains numbered questions" {
  grep -qE "^[0-9]\." "$REPO_ROOT/contexts/personal/PROMPT.md"
}

@test "projects-personal PROMPT.md contains numbered questions" {
  grep -qE "^[0-9]\." "$REPO_ROOT/contexts/projects-personal/PROMPT.md"
}

@test "hackathons PROMPT.md contains numbered questions" {
  grep -qE "^[0-9]\." "$REPO_ROOT/contexts/hackathons/PROMPT.md"
}

# ---------------------------------------------------------------------------
# SKILLS.md structure smoke checks (AC-3)
# ---------------------------------------------------------------------------

@test "work SKILLS.md contains a Markdown table header with Skill column" {
  grep -q "| Skill" "$REPO_ROOT/contexts/work/SKILLS.md"
}

@test "personal SKILLS.md contains a Markdown table header with Skill column" {
  grep -q "| Skill" "$REPO_ROOT/contexts/personal/SKILLS.md"
}

@test "projects-personal SKILLS.md contains a Markdown table header with Skill column" {
  grep -q "| Skill" "$REPO_ROOT/contexts/projects-personal/SKILLS.md"
}

@test "hackathons SKILLS.md contains a Markdown table header with Skill column" {
  grep -q "| Skill" "$REPO_ROOT/contexts/hackathons/SKILLS.md"
}

# ---------------------------------------------------------------------------
# n8n workflows (AC-4)
# ---------------------------------------------------------------------------

@test "n8n/README.md exists" {
  [ -f "$REPO_ROOT/n8n/README.md" ]
}

@test "n8n/workflows/content-publishing/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/content-publishing/README.md" ]
}

@test "n8n/workflows/content-publishing/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/content-publishing/workflow.json.template" ]
}

@test "n8n/workflows/ai-cost-tracking/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/ai-cost-tracking/README.md" ]
}

@test "n8n/workflows/ai-cost-tracking/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/ai-cost-tracking/workflow.json.template" ]
}

@test "n8n/workflows/github-issue-triage/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/github-issue-triage/README.md" ]
}

@test "n8n/workflows/github-issue-triage/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/github-issue-triage/workflow.json.template" ]
}

@test "n8n/workflows/expense-categorization/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/expense-categorization/README.md" ]
}

@test "n8n/workflows/expense-categorization/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/expense-categorization/workflow.json.template" ]
}

@test "n8n/workflows/hackathon-team-formation/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/hackathon-team-formation/README.md" ]
}

@test "n8n/workflows/hackathon-team-formation/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/hackathon-team-formation/workflow.json.template" ]
}

@test "n8n/workflows/daily-standup-summarizer/README.md exists" {
  [ -f "$REPO_ROOT/n8n/workflows/daily-standup-summarizer/README.md" ]
}

@test "n8n/workflows/daily-standup-summarizer/workflow.json.template exists" {
  [ -f "$REPO_ROOT/n8n/workflows/daily-standup-summarizer/workflow.json.template" ]
}

@test "n8n workflow count is at least 6" {
  local count
  count="$(find "$REPO_ROOT/n8n/workflows" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 6 ]
}

# ---------------------------------------------------------------------------
# Operator leak checks (AC-6, AC-7)
# ---------------------------------------------------------------------------

@test "no operator-specific identifiers in contexts/" {
  local count
  count="$(grep -rn "xipherlabs\|nicofernandez\|f0x1777\|Triton One" \
    "$REPO_ROOT/contexts/" \
    --include='*.md' \
    2>/dev/null \
    | grep -v "$REPO_ROOT/contexts/_examples/" \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

@test "no operator-specific identifiers in n8n/" {
  local count
  count="$(grep -rn "xipherlabs\|nicofernandez\|f0x1777\|Triton One" \
    "$REPO_ROOT/n8n/" \
    --include='*.md' \
    --include='*.json' \
    --include='*.template' \
    2>/dev/null \
    | wc -l \
    | tr -d ' ')"
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AGENTS.md global updates (AC-9)
# ---------------------------------------------------------------------------

@test "global AGENTS.md references hackathons context" {
  grep -q "hackathons" "$REPO_ROOT/AGENTS.md"
}

@test "global AGENTS.md references operator-contexts.md" {
  grep -q "operator-contexts.md" "$REPO_ROOT/AGENTS.md"
}

# ---------------------------------------------------------------------------
# setup/personal-overlay-init.sh (AC-10)
# ---------------------------------------------------------------------------

@test "setup/personal-overlay-init.sh exists" {
  [ -f "$REPO_ROOT/setup/personal-overlay-init.sh" ]
}

@test "setup/personal-overlay-init.sh is executable" {
  [ -x "$REPO_ROOT/setup/personal-overlay-init.sh" ]
}

@test "setup/personal-overlay-init.sh mentions hackathons" {
  grep -q "hackathons" "$REPO_ROOT/setup/personal-overlay-init.sh"
}
