# Risk-Based Verification Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an executable `walter-os repo-config verification-plan` command for AD-8 / issue #233.

**Architecture:** Extend the existing repo-config library so verification policy stays next to `walter-repo-config.yaml` validation. The command reads the repo policy, applies safe defaults when absent, accepts explicit risk and changed paths, then prints the required verification depth while preserving the hard-limit escalation floor.

**Tech Stack:** Bash CLI, mikefarah/yq through the existing repo-config validator, Bats tests.

---

### Task 1: Add Failing CLI Tests

**Files:**
- Modify: `tests/cli/repo-config.bats`

- [ ] **Step 1: Write failing tests**

Add tests covering default `risk_based`, hard-floor escalation, production mode, invalid risk, and help text.

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/cli/repo-config.bats`

Expected: FAIL because `repo-config verification-plan` is not implemented.

### Task 2: Implement Verification Planner

**Files:**
- Modify: `scripts/walter/lib/repo-config.sh`
- Modify: `scripts/walter/subcommands/repo-config.sh`
- Modify: `bin/walter-os`

- [ ] **Step 1: Add helper functions**

Implement deterministic helpers for risk ranking, UI-path detection, hard-floor path detection, and required-check output.

- [ ] **Step 2: Add command parsing**

Support:

```bash
walter-os repo-config verification-plan [repo-dir|config-file] [--risk low|medium|high] [--path <changed-path>]...
```

- [ ] **Step 3: Run tests**

Run: `bats tests/cli/repo-config.bats`

Expected: PASS.

### Task 3: Document and Verify

**Files:**
- Modify: `docs/operational/repo-config.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Document command behavior**

Explain risk modes, prototype behavior, and hard-floor escalation.

- [ ] **Step 2: Run verification**

Run:

```bash
bats tests/cli/repo-config.bats
bash -n bin/walter-os scripts/walter/lib/repo-config.sh scripts/walter/subcommands/repo-config.sh
shellcheck -e SC1091,SC2155 bin/walter-os scripts/walter/lib/repo-config.sh scripts/walter/subcommands/repo-config.sh
./tests/lint-cross-references.sh
git diff --check
```

Expected: all pass.
