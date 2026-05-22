#!/usr/bin/env bats
# tests/oss/agents-md-cascade-conformance.bats
#
# Conformance suite for the vendor-neutral AGENTS.md cascade spec.
# Spec: docs/specs/agents-md-cascade-spec.md (Section 6, conformance criteria)
#
# This suite verifies that the WALTER-OS REFERENCE IMPLEMENTATION
# satisfies the cascade spec. Other implementations (a fork, a different
# tool) can run this same suite against their tree by setting REPO_ROOT
# to point at their checkout.
#
# Failure modes guarded:
#   C1: three layers exist + are documented (global / context / repo)
#   C2: most-specific-wins is documented
#   C3: concatenation default + override syntax are documented
#   C4: overlay support exists + is operator-private + scaffolded
#   C5: WALTER_BRANCH_FLOW + WALTER_CONTEXT are recognized
#   C6: this suite exists at the documented location
#   C7: cascade is documented in README (discoverable)
#   Sec: security considerations are documented (Section 8)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SPEC="$REPO_ROOT/docs/specs/agents-md-cascade-spec.md"
  AGENTS="$REPO_ROOT/AGENTS.md"
  README="$REPO_ROOT/README.md"
}

# ---------------------------------------------------------------------------
# Spec document presence + structural checks
# ---------------------------------------------------------------------------

@test "spec document exists at the documented path" {
  [[ -f "$SPEC" ]]
}

@test "spec is marked vendor-neutral in its title or abstract" {
  grep -qiE "vendor-neutral|standalone" "$SPEC"
}

@test "spec uses RFC 2119 normative language (MUST / SHOULD / MAY)" {
  grep -q "MUST" "$SPEC"
  grep -q "SHOULD" "$SPEC"
  grep -q "MAY" "$SPEC"
  grep -q "RFC 2119" "$SPEC"
}

# ---------------------------------------------------------------------------
# C1: three layers exist + are documented (spec sections 2.1 / 2.2 / 2.3)
# ---------------------------------------------------------------------------

@test "C1: spec documents Layer 1 (global)" {
  grep -qE "Layer 1.*[Gg]lobal" "$SPEC"
}

@test "C1: spec documents Layer 2 (context)" {
  grep -qE "Layer 2.*[Cc]ontext" "$SPEC"
}

@test "C1: spec documents Layer 3 (repository)" {
  grep -qE "Layer 3.*[Rr]epository" "$SPEC"
}

@test "C1: Walter-OS implementation has all three layers in AGENTS.md" {
  # The reference implementation must itself satisfy the spec. AGENTS.md
  # at the global layer references all three layer names (it IS the global
  # layer, and it documents context + repo layers stacking on top).
  grep -qiE "global layer|\\*\\*global\\*\\*" "$AGENTS"
  grep -qE "[Cc]ontext layer" "$AGENTS"
  grep -qE "[Rr]epo layer|[Rr]epository layer" "$AGENTS"
}

# ---------------------------------------------------------------------------
# C2: most-specific-wins (spec section 3)
# ---------------------------------------------------------------------------

@test "C2: spec documents most-specific-wins" {
  grep -qiE "most-specific-wins|most specific wins" "$SPEC"
}

@test "C2: Walter-OS AGENTS.md documents most-specific-wins" {
  grep -qiE "most-specific-wins|most specific wins" "$AGENTS"
}

# ---------------------------------------------------------------------------
# C3: concatenation default + override syntax (spec section 3)
# ---------------------------------------------------------------------------

@test "C3: spec documents concatenation default" {
  grep -qiE "concatenat" "$SPEC"
}

@test "C3: spec documents explicit override syntax" {
  grep -qiE "override" "$SPEC"
}

# ---------------------------------------------------------------------------
# C4: overlay support (spec section 4)
# ---------------------------------------------------------------------------

@test "C4: spec defines an overlay mechanism" {
  grep -qiE "personal overlay|## .*overlay" "$SPEC"
}

@test "C4: spec mandates overlay is operator-private (not committed)" {
  grep -qiE "out-of-tree|not be committed|never committed|private" "$SPEC"
}

@test "C4: Walter-OS has an overlay scaffolding script" {
  [[ -x "$REPO_ROOT/setup/personal-overlay-init.sh" ]]
}

# ---------------------------------------------------------------------------
# C5: required env vars (spec section 5)
# ---------------------------------------------------------------------------

@test "C5: spec defines WALTER_BRANCH_FLOW with single-tier + three-stage" {
  grep -q "WALTER_BRANCH_FLOW" "$SPEC"
  grep -q "single-tier" "$SPEC"
  grep -q "three-stage" "$SPEC"
}

@test "C5: spec defines WALTER_CONTEXT for explicit context selection" {
  grep -q "WALTER_CONTEXT" "$SPEC"
}

@test "C5: Walter-OS implementation honours WALTER_BRANCH_FLOW + WALTER_CONTEXT" {
  grep -q "WALTER_BRANCH_FLOW" "$AGENTS"
  grep -q "WALTER_CONTEXT" "$AGENTS"
}

# ---------------------------------------------------------------------------
# C7: discoverable from README
# ---------------------------------------------------------------------------

@test "C7: README references the cascade by name" {
  grep -qiE "cascade" "$README"
}

# ---------------------------------------------------------------------------
# Security considerations (spec section 8)
# ---------------------------------------------------------------------------

@test "Sec: spec has a security considerations section" {
  grep -qiE "^## .*[Ss]ecurity considerations" "$SPEC"
}

@test "Sec: spec warns about prompt injection through AGENTS.md content" {
  grep -qiE "prompt injection|prompt-injection" "$SPEC"
}

@test "Sec: spec warns about symlink attacks" {
  grep -qiE "symlink" "$SPEC"
}

# ---------------------------------------------------------------------------
# Non-goals + authorship (spec sections 7 + 9)
# ---------------------------------------------------------------------------

@test "META: spec has a Non-goals section" {
  grep -qE "^## .*[Nn]on-goals" "$SPEC"
}

@test "META: spec attribution names Xipher Labs + Walter-OS reference impl" {
  grep -q "Walter-OS" "$SPEC"
  grep -q "Xipher Labs" "$SPEC"
}

@test "META: spec references at least 3 AI coding tool vendor docs" {
  # External references in §10 should let an implementer cross-check.
  grep -qiE "anthropic|claude" "$SPEC"
  grep -qiE "openai|codex" "$SPEC"
  grep -qiE "cursor" "$SPEC"
}
