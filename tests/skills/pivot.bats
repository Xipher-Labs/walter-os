#!/usr/bin/env bats
# tests/skills/pivot.bats
#
# Covers: AC-1 through AC-7 for skills/project-pivot/SKILL.md
#
# These tests are deliberately static / grep-based: they do not invoke an
# LLM. They validate the skill definition and fixture outputs that the LLM
# would produce for the four representative combinations.
#
# AC-1: SKILL.md exists and is parseable as a walter-os skill
# AC-2: SKILL.md specifies exactly 4 questions in order
# AC-3: Fixture outputs for 4 representative combos have all 4 required sections
# AC-4: No country-specific law names appear in SKILL.md or fixtures
# AC-5: sensitive-health combo produces PHI routing + medical-data-compliance
# AC-6: financial combo produces web-security-baseline skill
# AC-7: All 4 fixture combos pass section-presence assertions

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SKILL_DIR="${REPO_ROOT}/skills/project-pivot"
SKILL_MD="${SKILL_DIR}/SKILL.md"
FIXTURES_DIR="${SKILL_DIR}/fixtures"

# -----------------------------------------------------------------------
# AC-1: SKILL.md exists and has required frontmatter fields
# -----------------------------------------------------------------------
@test "SKILL.md exists [AC-1]" {
  [[ -f "$SKILL_MD" ]]
}

@test "SKILL.md has name frontmatter field [AC-1]" {
  grep -q '^name: project-pivot' "$SKILL_MD"
}

@test "SKILL.md has description frontmatter field [AC-1]" {
  grep -q '^description:' "$SKILL_MD"
}

@test "SKILL.md is invocable from walter pivot (has pivot trigger documented) [AC-1]" {
  grep -qE 'walter pivot|walter-os pivot' "$SKILL_MD"
}

# -----------------------------------------------------------------------
# AC-2: Exactly 4 questions in order
# -----------------------------------------------------------------------
@test "SKILL.md contains Question 1: domain/industry [AC-2]" {
  grep -qiE 'question 1|Q1.*domain|Q1.*industry|1\..*domain|1\..*industry' "$SKILL_MD"
}

@test "SKILL.md contains Question 2: compliance regime [AC-2]" {
  grep -qiE 'question 2|Q2.*compliance|2\..*compliance' "$SKILL_MD"
}

@test "SKILL.md contains Question 3: data sensitivity [AC-2]" {
  grep -qiE 'question 3|Q3.*data.sensitivity|Q3.*sensitivity|3\..*data.sensitivity|3\..*sensitivity' "$SKILL_MD"
}

@test "SKILL.md contains Question 4: project type [AC-2]" {
  grep -qiE 'question 4|Q4.*project.type|Q4.*type|4\..*project.type|4\..*project type' "$SKILL_MD"
}

@test "SKILL.md compliance options include GDPR HIPAA PCI-DSS SOC2 ISO27001 [AC-2]" {
  grep -q 'GDPR' "$SKILL_MD"
  grep -q 'HIPAA' "$SKILL_MD"
  grep -qE 'PCI.DSS' "$SKILL_MD"
  grep -qE 'SOC.?2' "$SKILL_MD"
  grep -qE 'ISO.?27001' "$SKILL_MD"
}

@test "SKILL.md data sensitivity options include sensitive-health and financial [AC-2]" {
  grep -qE 'sensitive.health|sensitive_health' "$SKILL_MD"
  grep -q 'financial' "$SKILL_MD"
}

@test "SKILL.md project types include personal commercial hackathon oss-contribution [AC-2]" {
  grep -q 'personal' "$SKILL_MD"
  grep -q 'commercial' "$SKILL_MD"
  grep -q 'hackathon' "$SKILL_MD"
  grep -qE 'oss.contribution|open.source.contribution' "$SKILL_MD"
}

# -----------------------------------------------------------------------
# AC-3: Fixture outputs have 4 required sections
# Each fixture is a .example.yml file with the expected LLM output
# -----------------------------------------------------------------------
_assert_fixture_sections() {
  local fixture="$1"
  [[ -f "$fixture" ]] || { echo "Fixture not found: $fixture"; return 1; }
  grep -q 'agents_md_draft:' "$fixture"   || { echo "Missing agents_md_draft in $fixture"; return 1; }
  grep -q 'recommended_hooks:' "$fixture" || { echo "Missing recommended_hooks in $fixture"; return 1; }
  grep -q 'recommended_mcps:' "$fixture"  || { echo "Missing recommended_mcps in $fixture"; return 1; }
  grep -q 'compliance_checklist:' "$fixture" || { echo "Missing compliance_checklist in $fixture"; return 1; }
}

_assert_fixture_hard_rules() {
  local fixture="$1"
  grep -qE 'hard.rules|Hard Rules|## Hard rules' "$fixture" || { echo "Missing Hard rules section in $fixture"; return 1; }
}

_assert_fixture_skill_loading() {
  local fixture="$1"
  grep -qE 'skill.loading|Skill loading|## Skill loading' "$fixture" || { echo "Missing Skill loading section in $fixture"; return 1; }
}

_assert_checklist_min_items() {
  local fixture="$1"
  # Count lines starting with "  - " under compliance_checklist — need at least 3.
  # Use an explicit in_section flag; exit on the first non-indented line after
  # the section starts (any line not beginning with a space), not on NR>1 which
  # fires on the global line number rather than the section-local one.
  local count
  count=$(awk '
    /^compliance_checklist:/ { in_section=1; next }
    in_section && /^[^ ]/   { exit }
    in_section && /^  -/    { count++ }
    END                     { print count+0 }
  ' "$fixture")
  [[ "$count" -ge 3 ]] || { echo "compliance_checklist has fewer than 3 items ($count) in $fixture"; return 1; }
}

@test "fixture fintech-pci-dss-financial-commercial.example.yml exists [AC-3]" {
  [[ -f "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml" ]]
}

@test "fixture healthcare-hipaa-sensitive-health-commercial.example.yml exists [AC-3]" {
  [[ -f "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml" ]]
}

@test "fixture devtools-best-practices-internal-oss.example.yml exists [AC-3]" {
  [[ -f "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml" ]]
}

@test "fixture generic-gdpr-personal-personal.example.yml exists [AC-3]" {
  [[ -f "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml" ]]
}

@test "fintech fixture has all 4 output sections [AC-3]" {
  _assert_fixture_sections "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
}

@test "fintech fixture agents_md_draft has Hard rules section [AC-3]" {
  _assert_fixture_hard_rules "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
}

@test "fintech fixture agents_md_draft has Skill loading section [AC-3]" {
  _assert_fixture_skill_loading "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
}

@test "fintech fixture compliance_checklist has at least 3 items [AC-3]" {
  _assert_checklist_min_items "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
}

@test "healthcare fixture has all 4 output sections [AC-3]" {
  _assert_fixture_sections "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
}

@test "healthcare fixture agents_md_draft has Hard rules section [AC-3]" {
  _assert_fixture_hard_rules "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
}

@test "healthcare fixture agents_md_draft has Skill loading section [AC-3]" {
  _assert_fixture_skill_loading "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
}

@test "healthcare fixture compliance_checklist has at least 3 items [AC-3]" {
  _assert_checklist_min_items "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
}

@test "devtools fixture has all 4 output sections [AC-3]" {
  _assert_fixture_sections "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml"
}

@test "devtools fixture agents_md_draft has Hard rules section [AC-3]" {
  _assert_fixture_hard_rules "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml"
}

@test "devtools fixture agents_md_draft has Skill loading section [AC-3]" {
  _assert_fixture_skill_loading "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml"
}

@test "devtools fixture compliance_checklist has at least 3 items [AC-3]" {
  _assert_checklist_min_items "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml"
}

@test "generic fixture has all 4 output sections [AC-3]" {
  _assert_fixture_sections "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml"
}

@test "generic fixture agents_md_draft has Hard rules section [AC-3]" {
  _assert_fixture_hard_rules "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml"
}

@test "generic fixture agents_md_draft has Skill loading section [AC-3]" {
  _assert_fixture_skill_loading "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml"
}

@test "generic fixture compliance_checklist has at least 3 items [AC-3]" {
  _assert_checklist_min_items "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml"
}

# -----------------------------------------------------------------------
# AC-4: No country-specific law names in SKILL.md or fixtures
# -----------------------------------------------------------------------
_assert_no_country_laws() {
  local file="$1"
  # Pattern: Ley NNNN, CCPA, PIPEDA, LGPD, PDPA, DPA 2018, etc.
  # Skip lines that are part of the skill's own constraint definition (the "never do this"
  # list) — those legitimately name forbidden patterns for documentation purposes.
  # Only flag occurrences that appear as positive recommendations in output sections.
  local violations
  violations=$(grep -nE 'Ley [0-9]+|CCPA|PIPEDA|LGPD|PDPA|DPA 2018|APPI|POPIA|NDPR' "$file" \
    | grep -vE 'e\.g\.,|never output' \
    || true)
  if [[ -n "$violations" ]]; then
    echo "Unrestricted country-specific law name found in $file:"
    echo "$violations"
    return 1
  fi
}

@test "SKILL.md contains no country-specific law names outside constraint definition [AC-4]" {
  _assert_no_country_laws "$SKILL_MD"
}

@test "fintech fixture contains no country-specific law names [AC-4]" {
  _assert_no_country_laws "${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
}

@test "healthcare fixture contains no country-specific law names [AC-4]" {
  _assert_no_country_laws "${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
}

@test "devtools fixture contains no country-specific law names [AC-4]" {
  _assert_no_country_laws "${FIXTURES_DIR}/devtools-best-practices-internal-oss.example.yml"
}

@test "generic fixture contains no country-specific law names [AC-4]" {
  _assert_no_country_laws "${FIXTURES_DIR}/generic-gdpr-personal-personal.example.yml"
}

# -----------------------------------------------------------------------
# AC-2 (extended): mixed sensitivity option exists; health component triggers PHI routing
# -----------------------------------------------------------------------
@test "AC-2: mixed sensitivity option listed in SKILL.md data sensitivity table" {
  grep -qE '^\| `mixed`' "$SKILL_MD" \
    || { echo "mixed sensitivity row not found in SKILL.md"; return 1; }
}

@test "AC-2: mixed sensitivity with health triggers PHI local-only routing" {
  # SKILL.md must state that mixed containing health data requires local-only PHI routing
  grep -qE 'mixed.*health.*local|mixed.*local.*health|mixed.*containing health' "$SKILL_MD" \
    || { echo "SKILL.md does not specify that mixed+health requires local-only routing"; return 1; }
}

# -----------------------------------------------------------------------
# AC-5: sensitive-health → PHI local routing + medical-data-compliance
# -----------------------------------------------------------------------
@test "healthcare fixture AGENTS.md draft contains PHI local-only routing rule [AC-5]" {
  local fixture="${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
  grep -qE 'PHI|local.only|local Ollama|never.*external.*API|NEVER.*PHI' "$fixture" \
    || { echo "Missing PHI local-only routing in $fixture"; return 1; }
}

@test "healthcare fixture includes medical-data-compliance in skill loading [AC-5]" {
  local fixture="${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
  grep -q 'medical-data-compliance' "$fixture" \
    || { echo "Missing medical-data-compliance in $fixture"; return 1; }
}

@test "healthcare fixture compliance checklist requires local LLM routing for PHI [AC-5]" {
  local fixture="${FIXTURES_DIR}/healthcare-hipaa-sensitive-health-commercial.example.yml"
  grep -qiE 'local LLM|local.only.*PHI|PHI.*local|Ollama.*PHI|PHI.*Ollama' "$fixture" \
    || { echo "Missing local-LLM-for-PHI checklist item in $fixture"; return 1; }
}

# -----------------------------------------------------------------------
# AC-6: financial → web-security-baseline + pci-dss or security-audit skill
# -----------------------------------------------------------------------
@test "fintech fixture includes web-security-baseline in skill loading [AC-6]" {
  local fixture="${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
  grep -q 'web-security-baseline' "$fixture" \
    || { echo "Missing web-security-baseline in $fixture"; return 1; }
}

@test "fintech fixture includes pci-dss-checklist or security-audit skill [AC-6]" {
  local fixture="${FIXTURES_DIR}/fintech-pci-dss-financial-commercial.example.yml"
  grep -qE 'pci.dss.checklist|security.audit' "$fixture" \
    || { echo "Missing pci-dss-checklist or security-audit in $fixture"; return 1; }
}
