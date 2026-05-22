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
  #
  # Reviewer R2 caught that the prior version allowed up to 5 stragglers
  # — but the actual count was 40, so the test passed silently on a
  # tree that violated the constraint. Replaced with an explicit
  # allowlist of the 40 known pre-v1.0 stragglers. NEW skills (or
  # renamed skills) without a trigger section will fail this test. The
  # allowlist must shrink monotonically (no additions); at v1.0 it
  # must be empty.
  local known_stragglers=(
    agent-researcher ai-spend-tripwire alerting-stack brand-creation
    daily-supply-chain-audit data-migration-safety deepsec-integration
    definition-of-done-validator devrel-analyst financial-plan-builder
    forgejo-cli frontend-quality hackathon-spinup hcloud-cli heygen-cli
    hiring-toolkit infisical-agent landing-page-fast medical-data-compliance
    nanobanana personal-assistant-stack postgres-cli pr-review
    project-induction project-pivot quarterly-upgrade-cadence railway-cli
    regulatory-research-argentina regulatory-research-international
    secrets-yubikey-unlock solana-program-review solana-rpc-review
    syncthing-cli telegram-bot-cli telegram-summary terms-policy-generator
    track-pending vercel-agent-skills-bridge vercel-cli web-security-baseline
  )

  local skill skill_name unexpected=0
  while IFS= read -r skill; do
    if ! grep -qiE "^##? (When to use|Use this skill when|When this skill|Trigger)" "$skill"; then
      skill_name="$(basename "$(dirname "$skill")")"
      local in_allowlist=0
      local s
      for s in "${known_stragglers[@]}"; do
        if [[ "$s" == "$skill_name" ]]; then
          in_allowlist=1
          break
        fi
      done
      if [[ "$in_allowlist" -eq 0 ]]; then
        echo "UNEXPECTED straggler (not in allowlist): $skill" >&2
        unexpected=$((unexpected + 1))
      fi
    fi
  done < <(find "$REPO_ROOT/skills" -name "SKILL.md" -type f 2>/dev/null)
  [[ "$unexpected" -eq 0 ]]
}

@test "L2-3: skills directory structure is skills/<name>/SKILL.md (no deeper, no shallower)" {
  # Reject SKILL.md at the wrong depth — that breaks skill discovery.
  # Canonical layout: <repo>/skills/<name>/SKILL.md (exactly 2 levels
  # below the skills/ dir). Anything shallower (skills/SKILL.md) or
  # deeper (skills/foo/bar/SKILL.md) is a layout regression.
  #
  # Reviewer R2 caught that the prior version of this test only
  # checked "find returned at least one match" — vacuous, would pass
  # for any tree containing any SKILL.md anywhere. Now uses find's
  # -mindepth/-maxdepth to scope strictly.
  local at_wrong_depth
  at_wrong_depth="$(find "$REPO_ROOT/skills" -name "SKILL.md" -type f \
    \( -not -path "$REPO_ROOT/skills/*/SKILL.md" -o \
       -path "$REPO_ROOT/skills/*/*/SKILL.md" \) 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$at_wrong_depth" -ne 0 ]]; then
    echo "SKILL.md files at wrong depth:" >&2
    find "$REPO_ROOT/skills" -name "SKILL.md" -type f \
      \( -not -path "$REPO_ROOT/skills/*/SKILL.md" -o \
         -path "$REPO_ROOT/skills/*/*/SKILL.md" \) 2>/dev/null >&2
    return 1
  fi
  # Sanity: at least one SKILL.md at the correct depth exists.
  local at_correct_depth
  at_correct_depth="$(find "$REPO_ROOT/skills" -maxdepth 2 -mindepth 2 \
    -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$at_correct_depth" -ge 1 ]]
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
