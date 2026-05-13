#!/usr/bin/env bats
# tests/oss/founder-skills.bats
# AC-7, AC-8: Regression guard for the 6 founder-skills bundle skills.
# Verifies structure, YAML frontmatter, required sections, and no personal
# operator identifiers.

setup() {
  SKILLS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/skills"
  BANNED_PATTERN="Triton|BioVault|Licitar|f0x1777|nico\.fran|nico@"
}

# ---------------------------------------------------------------------------
# Aggregate test
# ---------------------------------------------------------------------------

@test "all six founder skill directories exist" {
  local skills=(
    customer-interview-synthesizer
    pricing-experiment
    cold-outreach-sequencer
    content-writer
    weekly-review-coach
    competitor-radar
  )
  for skill in "${skills[@]}"; do
    [[ -d "$SKILLS_DIR/$skill" ]]
  done
}

# ---------------------------------------------------------------------------
# customer-interview-synthesizer
# ---------------------------------------------------------------------------

@test "customer-interview-synthesizer directory exists" {
  [[ -d "$SKILLS_DIR/customer-interview-synthesizer" ]]
}

@test "customer-interview-synthesizer SKILL.md exists" {
  [[ -f "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md" ]]
}

@test "customer-interview-synthesizer frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/customer-interview-synthesizer/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'customer-interview-synthesizer', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "customer-interview-synthesizer body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md"
}

@test "customer-interview-synthesizer has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/customer-interview-synthesizer/SKILL.md"
}

# ---------------------------------------------------------------------------
# pricing-experiment
# ---------------------------------------------------------------------------

@test "pricing-experiment directory exists" {
  [[ -d "$SKILLS_DIR/pricing-experiment" ]]
}

@test "pricing-experiment SKILL.md exists" {
  [[ -f "$SKILLS_DIR/pricing-experiment/SKILL.md" ]]
}

@test "pricing-experiment frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/pricing-experiment/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'pricing-experiment', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "pricing-experiment body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/pricing-experiment/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/pricing-experiment/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/pricing-experiment/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/pricing-experiment/SKILL.md"
}

@test "pricing-experiment has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/pricing-experiment/SKILL.md"
}

# ---------------------------------------------------------------------------
# cold-outreach-sequencer
# ---------------------------------------------------------------------------

@test "cold-outreach-sequencer directory exists" {
  [[ -d "$SKILLS_DIR/cold-outreach-sequencer" ]]
}

@test "cold-outreach-sequencer SKILL.md exists" {
  [[ -f "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md" ]]
}

@test "cold-outreach-sequencer frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/cold-outreach-sequencer/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'cold-outreach-sequencer', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "cold-outreach-sequencer body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md"
}

@test "cold-outreach-sequencer has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/cold-outreach-sequencer/SKILL.md"
}

# ---------------------------------------------------------------------------
# content-writer
# ---------------------------------------------------------------------------

@test "content-writer directory exists" {
  [[ -d "$SKILLS_DIR/content-writer" ]]
}

@test "content-writer SKILL.md exists" {
  [[ -f "$SKILLS_DIR/content-writer/SKILL.md" ]]
}

@test "content-writer frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/content-writer/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'content-writer', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "content-writer body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/content-writer/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/content-writer/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/content-writer/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/content-writer/SKILL.md"
}

@test "content-writer has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/content-writer/SKILL.md"
}

# ---------------------------------------------------------------------------
# weekly-review-coach
# ---------------------------------------------------------------------------

@test "weekly-review-coach directory exists" {
  [[ -d "$SKILLS_DIR/weekly-review-coach" ]]
}

@test "weekly-review-coach SKILL.md exists" {
  [[ -f "$SKILLS_DIR/weekly-review-coach/SKILL.md" ]]
}

@test "weekly-review-coach frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/weekly-review-coach/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'weekly-review-coach', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "weekly-review-coach body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/weekly-review-coach/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/weekly-review-coach/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/weekly-review-coach/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/weekly-review-coach/SKILL.md"
}

@test "weekly-review-coach has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/weekly-review-coach/SKILL.md"
}

# ---------------------------------------------------------------------------
# competitor-radar
# ---------------------------------------------------------------------------

@test "competitor-radar directory exists" {
  [[ -d "$SKILLS_DIR/competitor-radar" ]]
}

@test "competitor-radar SKILL.md exists" {
  [[ -f "$SKILLS_DIR/competitor-radar/SKILL.md" ]]
}

@test "competitor-radar frontmatter is valid YAML" {
  run python3 -c "
import yaml, pathlib
doc = pathlib.Path('$SKILLS_DIR/competitor-radar/SKILL.md').read_text()
fm = doc.split('---')[1]
result = yaml.safe_load(fm)
assert result['name'] == 'competitor-radar', 'name mismatch: ' + str(result.get('name'))
assert len(result['description']) < 500, 'description too long: ' + str(len(result.get('description', '')))
print('OK')
"
  [[ "$status" -eq 0 ]]
}

@test "competitor-radar body has required sections" {
  grep -qE "^## When to use" "$SKILLS_DIR/competitor-radar/SKILL.md"
  grep -qE "^## When NOT to use" "$SKILLS_DIR/competitor-radar/SKILL.md"
  grep -qE "^## Outputs" "$SKILLS_DIR/competitor-radar/SKILL.md"
  grep -qE "^## (Sample usage|Example|How it composes)" "$SKILLS_DIR/competitor-radar/SKILL.md"
}

@test "competitor-radar has no operator-personal identifiers" {
  ! grep -iE "$BANNED_PATTERN" "$SKILLS_DIR/competitor-radar/SKILL.md"
}
