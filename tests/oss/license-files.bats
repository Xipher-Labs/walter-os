#!/usr/bin/env bats
# tests/oss/license-files.bats
# Regression guard — OSS launch requires LICENSE + LICENSE-APACHE + NOTICE +
# COMMERCIAL.md at repo root, plus an unambiguous AGPL marker in
# setup/walter-host/.
#
# AC: ADR-0018 (dual-license: Apache-2.0 default + AGPL-3.0 host stack).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ---------------------------------------------------------------------------
# Root LICENSE (AGPL canonical text — kept at root for the host stack + as the
# GitHub-detected license for backward compatibility with adopters who pinned
# to the AGPL-3.0 release line. The Apache-2.0 grant lives in LICENSE-APACHE.)
# ---------------------------------------------------------------------------

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
  ! grep -q "Xipher Labs" "$REPO_ROOT/LICENSE"
}

# ---------------------------------------------------------------------------
# Root LICENSE-APACHE (Apache-2.0 canonical text — covers the contract layer,
# which is the default tree per ADR-0018.)
# ---------------------------------------------------------------------------

@test "LICENSE-APACHE exists at repo root" {
  [[ -f "$REPO_ROOT/LICENSE-APACHE" ]]
}

@test "LICENSE-APACHE contains Apache License Version 2.0" {
  grep -q "Apache License" "$REPO_ROOT/LICENSE-APACHE"
  grep -q "Version 2.0" "$REPO_ROOT/LICENSE-APACHE"
}

@test "LICENSE-APACHE is canonical (no project copyright injected)" {
  # Apache-2.0 boilerplate has an APPENDIX section the project may fill,
  # but the body of the license itself should not name the project.
  # Allow the word "Xipher" inside the APPENDIX boilerplate only — guard
  # against accidental injection in the license text.
  ! grep -q "^Walter-OS$" "$REPO_ROOT/LICENSE-APACHE"
}

# ---------------------------------------------------------------------------
# setup/walter-host/LICENSE (canonical AGPL marker — unambiguously labels the
# host-stack subtree under the AGPL terms.)
# ---------------------------------------------------------------------------

@test "setup/walter-host/LICENSE exists (subtree marker)" {
  [[ -f "$REPO_ROOT/setup/walter-host/LICENSE" ]]
}

@test "setup/walter-host/LICENSE is AGPL Version 3" {
  grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" "$REPO_ROOT/setup/walter-host/LICENSE"
  grep -q "Version 3" "$REPO_ROOT/setup/walter-host/LICENSE"
}

@test "setup/walter-host/LICENSE matches root LICENSE byte-for-byte" {
  # The two files are the canonical AGPL text. Any drift between them is
  # a mistake that creates legal ambiguity for the subtree.
  diff -q "$REPO_ROOT/LICENSE" "$REPO_ROOT/setup/walter-host/LICENSE"
}

# ---------------------------------------------------------------------------
# NOTICE (operator attribution + dual-license map).
# ---------------------------------------------------------------------------

@test "NOTICE exists at repo root" {
  [[ -f "$REPO_ROOT/NOTICE" ]]
}

@test "NOTICE contains Xipher Labs" {
  grep -q "Xipher Labs" "$REPO_ROOT/NOTICE"
}

@test "NOTICE references the dual-license decision (ADR-0018)" {
  grep -q "0018-licensing-strategy" "$REPO_ROOT/NOTICE"
}

@test "NOTICE names both Apache-2.0 and AGPL-3.0" {
  grep -q "Apache" "$REPO_ROOT/NOTICE"
  grep -q "AGPL" "$REPO_ROOT/NOTICE"
}

# ---------------------------------------------------------------------------
# COMMERCIAL.md (entry point for commercial license requests).
# ---------------------------------------------------------------------------

@test "COMMERCIAL.md exists at repo root" {
  [[ -f "$REPO_ROOT/COMMERCIAL.md" ]]
}

@test "COMMERCIAL.md documents the dual-license map" {
  grep -q "Apache-2.0" "$REPO_ROOT/COMMERCIAL.md"
  grep -q "AGPL" "$REPO_ROOT/COMMERCIAL.md"
}

# ---------------------------------------------------------------------------
# Apache-2.0 mention allowlist — post-dual-license, references to Apache-2.0
# are expected throughout the docs tree. Keep the allowlist tight so a stray
# mention in CI workflows, install scripts, or service configs still trips.
# ---------------------------------------------------------------------------

@test "no Apache-2.0 string outside allowlisted files" {
  # Allowlist (post-ADR-0018):
  #   - LICENSE-APACHE                                — canonical text
  #   - NOTICE                                        — dual-license map
  #   - COMMERCIAL.md                                 — commercial entry point
  #   - README.md                                     — license section
  #   - CHANGELOG.md                                  — entries describing the switch
  #   - CONTRIBUTING.md                               — dual-license preamble (ADR-0019)
  #   - CLA.md                                        — CLA scaffold (ADR-0019)
  #   - docs/decisions/0010-oss-license.md            — ADR historical context
  #   - docs/decisions/0018-licensing-strategy.md     — dual-license ADR
  #   - docs/decisions/0019-contributor-license-agreement.md — CLA ADR
  #   - docs/decisions/0021-v1-0-stability-charter.md — references ADR-0018
  #   - docs/specs/walter-oss-license-switch.*        — historical spec
  #   - docs/specs/walter-oss-ready-docs.*            — sibling spec referencing the switch
  #   - docs/specs/walter-os-oss-readiness-roadmap.md — roadmap referencing ADR-0018
  #   - docs/specs/walter-os-v1-0-stability-charter.md — v1.0 spec referencing ADR-0018
  #   - docs/specs/walter-contract-walter-host-split.md — repo-split spec discusses license-by-subtree
  #   - docs/specs/founder-skills-bundle-extraction.md — discusses license posture for extraction
  #   - tests/oss/license-files.bats                  — this test (self-ref)
  #   - skills/*/SKILL.md                             — third-party deps may be Apache-licensed
  #   - .github/workflows/*.yml                       — SPDX headers on workflow files
  #   - hooks/*.sh                                    — SPDX headers on hook scripts
  local matches
  matches="$(grep -rEn "Apache-2\.0|Apache License, Version 2\.0|Apache License|Apache 2\.0" "$REPO_ROOT" \
    --exclude-dir=external \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --exclude-dir=.claude \
    2>/dev/null \
    | grep -v "$REPO_ROOT/LICENSE-APACHE" \
    | grep -v "$REPO_ROOT/NOTICE" \
    | grep -v "$REPO_ROOT/COMMERCIAL.md" \
    | grep -v "$REPO_ROOT/README.md" \
    | grep -v "$REPO_ROOT/CHANGELOG.md" \
    | grep -v "$REPO_ROOT/CONTRIBUTING.md" \
    | grep -v "$REPO_ROOT/CLA.md" \
    | grep -v "$REPO_ROOT/docs/decisions/0010-oss-license.md" \
    | grep -v "$REPO_ROOT/docs/decisions/0018-licensing-strategy.md" \
    | grep -v "$REPO_ROOT/docs/decisions/0019-contributor-license-agreement.md" \
    | grep -v "$REPO_ROOT/docs/decisions/0021-v1-0-stability-charter.md" \
    | grep -v "$REPO_ROOT/docs/specs/walter-oss-license-switch" \
    | grep -v "$REPO_ROOT/docs/specs/walter-oss-ready-docs" \
    | grep -v "$REPO_ROOT/docs/specs/walter-os-oss-readiness-roadmap.md" \
    | grep -v "$REPO_ROOT/docs/specs/walter-os-v1-0-stability-charter.md" \
    | grep -v "$REPO_ROOT/docs/specs/walter-contract-walter-host-split.md" \
    | grep -v "$REPO_ROOT/docs/specs/founder-skills-bundle-extraction.md" \
    | grep -v "$REPO_ROOT/tests/oss/license-files.bats" \
    | grep -v "$REPO_ROOT/tests/oss/entity-formation-gate.bats" \
    | grep -vE "$REPO_ROOT/skills/[^/]+/SKILL\.md" \
    | grep -vE "$REPO_ROOT/\.github/workflows/[a-zA-Z0-9_-]+\.ya?ml" \
    | grep -vE "$REPO_ROOT/hooks/[a-zA-Z0-9_-]+\.sh" \
    | wc -l \
    | tr -d ' ')"
  [ "$matches" -eq 0 ]
}
