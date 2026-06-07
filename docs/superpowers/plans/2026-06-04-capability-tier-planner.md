# Capability Tier Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an executable `walter-os repo-config capability-plan` command for AD-7 / issue #232.

**Architecture:** Extend the existing repo-config policy library with read-only capability-tier planning. The command validates `walter-repo-config.yaml`, reads `capability_tier_ceiling`, computes an evidence tier from explicit objective signals, caps it by repo ceiling and risk/hard-floor constraints, and prints the resulting capability contract.

**Tech Stack:** Bash CLI, existing repo-config validator and protected-path policy, Bats tests.

---

### Task 1: Add Failing Capability-Plan Tests

**Files:**
- Modify: `tests/cli/repo-config.bats`

- [ ] **Step 1: Write failing tests**

Add tests for absent config defaults, assisted tier with CI/tests evidence,
repo ceiling capping rich evidence, bounded autonomy with ceiling 3 and all
signals, hard-floor downgrade, and invalid evidence input.

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/cli/repo-config.bats`

Expected: FAIL because `repo-config capability-plan` is not implemented.

### Task 2: Implement Capability Planner

**Files:**
- Modify: `scripts/walter/lib/repo-config.sh`
- Modify: `scripts/walter/subcommands/repo-config.sh`
- Modify: `bin/walter-os`

- [ ] **Step 1: Add tier helpers**

Add helpers that map tier numbers to names, normalize evidence names, and
compute evidence tier from objective signals.

- [ ] **Step 2: Add command parsing**

Support:

```bash
walter-os repo-config capability-plan [repo-dir|config-file] \
  --risk low|medium|high \
  --evidence ci --evidence tests --evidence sandbox \
  --path <changed-path>
```

- [ ] **Step 3: Run tests**

Run: `bats tests/cli/repo-config.bats`

Expected: PASS.

### Task 3: Document and Verify

**Files:**
- Modify: `docs/operational/repo-config.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Document command behavior**

Explain evidence signals, repo ceiling, risk caps, and hard-floor downgrade.

- [ ] **Step 2: Run verification**

Run:

```bash
bats tests/cli/repo-config.bats
bash -n bin/walter-os scripts/walter/lib/repo-config.sh scripts/walter/subcommands/repo-config.sh tests/cli/repo-config.bats
shellcheck -e SC1091,SC2155 bin/walter-os scripts/walter/lib/repo-config.sh scripts/walter/subcommands/repo-config.sh
./tests/lint-cross-references.sh
git diff --check
```

Expected: all pass.
