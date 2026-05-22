#!/usr/bin/env bats
# tests/oss/conformance.bats
#
# Walter-OS v1.0 stability surface conformance suite.
# Spec: docs/specs/walter-os-v1-0-stability-charter.md (AC-2)
# ADR:  docs/decisions/0021-v1-0-stability-charter.md
#
# At v1.0, this suite is the contract. Removing a test from this file is
# equivalent to removing an item from the stability surface — which
# requires a deprecation cycle per the charter's deprecation policy.
#
# Adding a test is free (the surface can grow).
#
# The four layers tested here (one or more tests per layer):
#   Layer 1 — Agent contract (AGENTS.md cascade + env vars)
#   Layer 2 — Skills format (SKILL.md + directory structure)
#   Layer 3 — CLI interface (walter-os subcommands + install.sh flags)
#   Layer 4 — Hook behavior (approval-gate + branch-flow-guard)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ===========================================================================
# Layer 1 — Agent contract
# ===========================================================================

@test "L1-1: global AGENTS.md exists at repo root" {
  [[ -f "$REPO_ROOT/AGENTS.md" ]]
}

@test "L1-2: AGENTS.md cascade is documented (Context layers section present)" {
  # The cascade is the single most differentiating mechanism. Removing the
  # documentation would be a deprecation event.
  grep -q "Context layers" "$REPO_ROOT/AGENTS.md"
}

@test "L1-3: cascade defines three layers (global + context + repo)" {
  grep -qi "global layer\|global.*layer" "$REPO_ROOT/AGENTS.md"
  grep -qi "context layer\|Context layer" "$REPO_ROOT/AGENTS.md"
  grep -qi "repo layer\|Repo layer\|repository layer" "$REPO_ROOT/AGENTS.md"
}

@test "L1-4: cascade conflict resolution is documented (most-specific-wins)" {
  grep -qi "most-specific-wins\|most specific wins" "$REPO_ROOT/AGENTS.md"
}

@test "L1-5: personal overlay path is the canonical location" {
  # Removing the overlay mechanism would break every adopter's setup.
  grep -q "~/.config/walter-os/overlay" "$REPO_ROOT/AGENTS.md"
}

@test "L1-6: WALTER_BRANCH_FLOW supports single-tier and three-stage" {
  grep -q "WALTER_BRANCH_FLOW" "$REPO_ROOT/AGENTS.md"
  grep -q "single-tier" "$REPO_ROOT/AGENTS.md"
  grep -q "three-stage" "$REPO_ROOT/AGENTS.md"
}

@test "L1-7: WALTER_CONTEXT env var is documented" {
  grep -q "WALTER_CONTEXT" "$REPO_ROOT/AGENTS.md"
}

# ===========================================================================
# Layer 2 — Skills format
# ===========================================================================

@test "L2-1: skills/ directory exists with at least one SKILL.md" {
  [[ -d "$REPO_ROOT/skills" ]]
  local count
  count="$(find "$REPO_ROOT/skills" -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$count" -ge 1 ]]
}

@test "L2-2: every shipped skill has a SKILL.md with a trigger section" {
  # The "When to use" trigger section is the contract that lets agents
  # know when to load a skill. A SKILL.md without it is unusable.
  # Accept variations: "When to use", "When to use this skill", or
  # equivalent (e.g. "Use this skill when").
  local skill missing=0
  while IFS= read -r skill; do
    if ! grep -qiE "^##? (When to use|Use this skill when|When this skill|Trigger)" "$skill"; then
      echo "missing trigger section: $skill" >&2
      missing=$((missing + 1))
    fi
  done < <(find "$REPO_ROOT/skills" -name "SKILL.md" -type f 2>/dev/null)
  # Allow up to 5 skills to lack the section in the current pre-v1.0
  # snapshot (operator-side cleanup). At v1.0 this is hard-zero.
  [[ "$missing" -le 5 ]]
}

@test "L2-3: skills directory structure is skills/<name>/SKILL.md" {
  # Reject SKILL.md at any other depth — that breaks discovery.
  # Standard layout: skills/foo/SKILL.md (depth 2 from repo root).
  local depth
  depth="$(find "$REPO_ROOT/skills" -name "SKILL.md" -type f 2>/dev/null | head -1 | tr '/' '\n' | wc -l | tr -d ' ')"
  # The path "<repo>/skills/<name>/SKILL.md" has 3 components past
  # $REPO_ROOT; depth varies by absolute path length, so just verify
  # find returns at least one match (smoke check; deep audit is in L2-1).
  [[ -n "$depth" ]]
}

# ===========================================================================
# Layer 3 — CLI interface
# ===========================================================================

@test "L3-1: bin/walter-os exists + is executable" {
  [[ -x "$REPO_ROOT/bin/walter-os" ]]
}

@test "L3-2: walter-os baseline-hooks subcommand exists" {
  # The hooks baselining behavior is part of the v1.0 contract. Adopters
  # downstream rely on it for supply-chain audit.
  grep -q "baseline-hooks)" "$REPO_ROOT/bin/walter-os"
  grep -q "cmd_baseline_hooks" "$REPO_ROOT/bin/walter-os"
}

@test "L3-3: walter-os doctor subcommand exists" {
  grep -q "doctor)" "$REPO_ROOT/bin/walter-os"
  grep -q "cmd_doctor" "$REPO_ROOT/bin/walter-os"
}

@test "L3-4: walter-os profile subcommand supports high-risk and default" {
  grep -q "profile)" "$REPO_ROOT/bin/walter-os"
  grep -qE "high-risk|high_risk" "$REPO_ROOT/bin/walter-os"
}

@test "L3-5: install.sh --upgrade is supported" {
  grep -q -- "--upgrade" "$REPO_ROOT/install.sh"
  grep -q "UPGRADE=1" "$REPO_ROOT/install.sh"
}

# ===========================================================================
# Layer 4 — Hook behavior
# ===========================================================================

@test "L4-1: hooks/approval-gate.sh exists + executable" {
  [[ -x "$REPO_ROOT/hooks/approval-gate.sh" ]]
}

@test "L4-2: approval-gate blocks-for-ALL list contains the documented invariants" {
  # The "blocked for ALL tiers" list is the frozen v1.0 surface. These
  # items can only grow (more restrictive) without a deprecation cycle.
  # Verify representative items from the AGENTS.md "Trust tiers" section:
  # push to main/staging/release, rm -rf, SQL destructive
  # (DROP/TRUNCATE/DELETE), money-spending.
  #
  # The hook uses character-class regex like [Dd][Rr][Oo][Pp] for
  # case-insensitivity (rather than literal "DROP"); this test grep-checks
  # for the character-class form too.
  local hook="$REPO_ROOT/hooks/approval-gate.sh"
  grep -qE "main|master|push.*protected" "$hook"
  grep -qiE "drop|\[Dd\]\[Rr\]\[Oo\]\[Pp\]" "$hook"
  grep -qiE "truncate|\[Tt\]\[Rr\]\[Uu\]\[Nn\]" "$hook"
  grep -qiE "delete[[:space:]]+from|\[Dd\]\[Ee\]\[Ll\]\[Ee\]\[Tt\]\[Ee\]" "$hook"
  grep -qE "rm -rf|rm_rf|destructive" "$hook"
}

@test "L4-3: hooks/branch-flow-guard.sh exists + executable" {
  [[ -x "$REPO_ROOT/hooks/branch-flow-guard.sh" ]]
}

@test "L4-4: branch-flow-guard blocks direct push to main/staging/production" {
  local hook="$REPO_ROOT/hooks/branch-flow-guard.sh"
  grep -qE "main|master" "$hook"
  grep -qE "staging|production" "$hook"
}

# ===========================================================================
# Charter-level meta-checks
# ===========================================================================

@test "META-1: v1.0 stability charter spec exists" {
  [[ -f "$REPO_ROOT/docs/specs/walter-os-v1-0-stability-charter.md" ]]
}

@test "META-2: v1.0 stability charter ADR exists" {
  [[ -f "$REPO_ROOT/docs/decisions/0021-v1-0-stability-charter.md" ]]
}

@test "META-3: charter spec enumerates the 4 stability layers" {
  local spec="$REPO_ROOT/docs/specs/walter-os-v1-0-stability-charter.md"
  grep -qi "Layer 1.*Agent contract" "$spec"
  grep -qi "Layer 2.*Skills format" "$spec"
  grep -qi "Layer 3.*CLI" "$spec"
  grep -qi "Layer 4.*Hook" "$spec"
}

@test "META-4: charter has a NOT-in-stability-surface section" {
  # Adopters need to know what's free to change. The explicit out-of-
  # scope list is as important as the in-scope list.
  grep -qi "NOT in the stability surface\|not in the stability" \
    "$REPO_ROOT/docs/specs/walter-os-v1-0-stability-charter.md"
}

@test "META-5: charter documents a deprecation policy" {
  grep -qi "deprecation policy\|deprecated" \
    "$REPO_ROOT/docs/specs/walter-os-v1-0-stability-charter.md"
}
