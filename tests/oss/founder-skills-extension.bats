#!/usr/bin/env bats
# tests/oss/founder-skills-extension.bats
# AC-7, AC-8: Guard for the 8 founder-skills-extension skills (W-14).
# Verifies structure, YAML frontmatter, required sections, description length,
# and no operator-personal identifiers.

setup() {
  SKILLS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/skills"
  BANNED_PATTERN="Triton|BioVault|Licitar|f0x1777|nico\.fran|nico@"
}

# ---------------------------------------------------------------------------
# survey-design
# ---------------------------------------------------------------------------

@test "survey-design directory exists" {
  [[ -d "$SKILLS_DIR/survey-design" ]]
}

@test "survey-design SKILL.md exists" {
  [[ -f "$SKILLS_DIR/survey-design/SKILL.md" ]]
}

@test "survey-design frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/survey-design/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'survey-design', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "survey-design has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/survey-design/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/survey-design/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/survey-design/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/survey-design/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/survey-design/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/survey-design/SKILL.md"
}

@test "survey-design has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/survey-design/SKILL.md"
}

# ---------------------------------------------------------------------------
# marketing-strategist
# ---------------------------------------------------------------------------

@test "marketing-strategist directory exists" {
  [[ -d "$SKILLS_DIR/marketing-strategist" ]]
}

@test "marketing-strategist SKILL.md exists" {
  [[ -f "$SKILLS_DIR/marketing-strategist/SKILL.md" ]]
}

@test "marketing-strategist frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/marketing-strategist/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'marketing-strategist', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "marketing-strategist has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/marketing-strategist/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/marketing-strategist/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/marketing-strategist/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/marketing-strategist/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/marketing-strategist/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/marketing-strategist/SKILL.md"
}

@test "marketing-strategist has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/marketing-strategist/SKILL.md"
}

# ---------------------------------------------------------------------------
# proposal-writer
# ---------------------------------------------------------------------------

@test "proposal-writer directory exists" {
  [[ -d "$SKILLS_DIR/proposal-writer" ]]
}

@test "proposal-writer SKILL.md exists" {
  [[ -f "$SKILLS_DIR/proposal-writer/SKILL.md" ]]
}

@test "proposal-writer frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/proposal-writer/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'proposal-writer', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "proposal-writer has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/proposal-writer/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/proposal-writer/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/proposal-writer/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/proposal-writer/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/proposal-writer/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/proposal-writer/SKILL.md"
}

@test "proposal-writer has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/proposal-writer/SKILL.md"
}

# ---------------------------------------------------------------------------
# saas-metrics-dashboard
# ---------------------------------------------------------------------------

@test "saas-metrics-dashboard directory exists" {
  [[ -d "$SKILLS_DIR/saas-metrics-dashboard" ]]
}

@test "saas-metrics-dashboard SKILL.md exists" {
  [[ -f "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md" ]]
}

@test "saas-metrics-dashboard frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/saas-metrics-dashboard/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'saas-metrics-dashboard', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "saas-metrics-dashboard has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
}

@test "saas-metrics-dashboard has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/saas-metrics-dashboard/SKILL.md"
}

# ---------------------------------------------------------------------------
# compliance-prep-toolkit
# ---------------------------------------------------------------------------

@test "compliance-prep-toolkit directory exists" {
  [[ -d "$SKILLS_DIR/compliance-prep-toolkit" ]]
}

@test "compliance-prep-toolkit SKILL.md exists" {
  [[ -f "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md" ]]
}

@test "compliance-prep-toolkit frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/compliance-prep-toolkit/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'compliance-prep-toolkit', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "compliance-prep-toolkit has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
}

@test "compliance-prep-toolkit has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/compliance-prep-toolkit/SKILL.md"
}

# ---------------------------------------------------------------------------
# decision-journal
# ---------------------------------------------------------------------------

@test "decision-journal directory exists" {
  [[ -d "$SKILLS_DIR/decision-journal" ]]
}

@test "decision-journal SKILL.md exists" {
  [[ -f "$SKILLS_DIR/decision-journal/SKILL.md" ]]
}

@test "decision-journal frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/decision-journal/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'decision-journal', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "decision-journal has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/decision-journal/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/decision-journal/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/decision-journal/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/decision-journal/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/decision-journal/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/decision-journal/SKILL.md"
}

@test "decision-journal has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/decision-journal/SKILL.md"
}

# ---------------------------------------------------------------------------
# long-form-content
# ---------------------------------------------------------------------------

@test "long-form-content directory exists" {
  [[ -d "$SKILLS_DIR/long-form-content" ]]
}

@test "long-form-content SKILL.md exists" {
  [[ -f "$SKILLS_DIR/long-form-content/SKILL.md" ]]
}

@test "long-form-content frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/long-form-content/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'long-form-content', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "long-form-content has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/long-form-content/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/long-form-content/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/long-form-content/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/long-form-content/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/long-form-content/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/long-form-content/SKILL.md"
}

@test "long-form-content has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/long-form-content/SKILL.md"
}

# ---------------------------------------------------------------------------
# knowledge-extraction
# ---------------------------------------------------------------------------

@test "knowledge-extraction directory exists" {
  [[ -d "$SKILLS_DIR/knowledge-extraction" ]]
}

@test "knowledge-extraction SKILL.md exists" {
  [[ -f "$SKILLS_DIR/knowledge-extraction/SKILL.md" ]]
}

@test "knowledge-extraction frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/knowledge-extraction/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'knowledge-extraction', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "knowledge-extraction has required anchored sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
  grep -qE "^## Inputs" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
  grep -qE "^## Sample usage" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
  grep -qE "^## How it composes" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
}

@test "knowledge-extraction has no banned operator-personal patterns" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/knowledge-extraction/SKILL.md"
}
