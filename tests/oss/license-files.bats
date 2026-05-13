#!/usr/bin/env bats
# tests/oss/license-files.bats
# Regression guard — OSS launch requires LICENSE and NOTICE at repo root.
# AC: ADR-0010 (AGPLv3, Xipher Labs)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "LICENSE exists at repo root" {
  [[ -f "$REPO_ROOT/LICENSE" ]]
}

@test "LICENSE contains GNU AGPL Version 3" {
  grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" "$REPO_ROOT/LICENSE"
  grep -q "Version 3" "$REPO_ROOT/LICENSE"
}

@test "LICENSE is canonical AGPL (no project copyright injected)" {
  # Per AGPL §0: "Everyone is permitted to copy and distribute verbatim
  # copies of this license document, but changing it is not allowed."
  # Project-specific copyright lives in NOTICE (next test).
  ! grep -q "Xipher Labs" "$REPO_ROOT/LICENSE"
}

@test "NOTICE exists at repo root" {
  [[ -f "$REPO_ROOT/NOTICE" ]]
}

@test "NOTICE contains Xipher Labs" {
  grep -q "Xipher Labs" "$REPO_ROOT/NOTICE"
}

@test "COMMERCIAL.md exists at repo root" {
  [[ -f "$REPO_ROOT/COMMERCIAL.md" ]]
}

@test "no Apache-2.0 string outside allowlisted files" {
  # Allowlist:
  #   - docs/decisions/0010-oss-license.md          — ADR historical context
  #   - docs/specs/walter-oss-license-switch.*      — this PR's own spec
  #   - docs/specs/walter-oss-ready-docs.*          — sibling PR spec referencing the switch
  #   - tests/oss/license-files.bats                — this test (self-ref)
  #   - skills/*/SKILL.md                           — third-party deps may be Apache-licensed
  local matches
  matches="$(grep -rEn "Apache-2\.0|Apache License, Version 2\.0" "$REPO_ROOT" \
    --exclude-dir=external \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --exclude-dir=.claude \
    2>/dev/null \
    | grep -v "$REPO_ROOT/docs/decisions/0010-oss-license.md" \
    | grep -v "$REPO_ROOT/docs/specs/walter-oss-license-switch" \
    | grep -v "$REPO_ROOT/docs/specs/walter-oss-ready-docs" \
    | grep -v "$REPO_ROOT/tests/oss/license-files.bats" \
    | grep -v "$REPO_ROOT/CHANGELOG.md" \
    | grep -vE "$REPO_ROOT/skills/[^/]+/SKILL\.md" \
    | wc -l \
    | tr -d ' ')"
  [ "$matches" -eq 0 ]
}
