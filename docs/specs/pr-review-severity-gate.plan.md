# PLAN: PR review severity gate + bounded auto-merge

**Spec:** `docs/specs/pr-review-severity-gate.md`
**ADR:** `docs/decisions/0015-pr-review-severity-gate.md`
**Branch:** `feature/pr-review-severity-gate`
**Total tasks:** 20 (17 implementation + 3 verification).
**Estimated effort:** 8–12 hours assuming Bats + bash + GitHub API familiarity.

Each task follows RED-GREEN-REFACTOR. Skip RED is a violation of
`test-driven-development` (superpowers).

---

## Phase A — Test scaffolding (RED state)

### A1. Create fixture directory + sample finding payloads

**Files:**
- `tests/severity-gate/fixtures/blocker-auth-path.json`     (Copilot comment referencing `auth/oauth.ts`)
- `tests/severity-gate/fixtures/blocker-crypto-path.json`   (referencing `crypto/sign.rs`)
- `tests/severity-gate/fixtures/blocker-money-keyword.json` (text mentions Stripe charge)
- `tests/severity-gate/fixtures/blocker-phi-path.json`      (referencing `personal/health/`)
- `tests/severity-gate/fixtures/blocker-hooks-path.json`    (referencing `hooks/approval-gate.sh`)
- `tests/severity-gate/fixtures/major-failing-test.json`    (body: "this test will fail when X")
- `tests/severity-gate/fixtures/major-regression.json`      (body: "regression on existing functionality")
- `tests/severity-gate/fixtures/major-leak.json`            (body: "exposes API key")
- `tests/severity-gate/fixtures/minor-doc-accuracy.json`    (file: README.md, body: "comment drift")
- `tests/severity-gate/fixtures/minor-test-thoroughness.json` (file: tests/, body: "could miss")
- `tests/severity-gate/fixtures/minor-portability.json`     (body: "\s isn't POSIX")
- `tests/severity-gate/fixtures/cosmetic-typo.json`         (body: "typo: 'recieve' → 'receive'")
- `tests/severity-gate/fixtures/cosmetic-formatting.json`   (body: "extra blank line")
- `tests/severity-gate/fixtures/unclassified-vague.json`    (body: "this seems off")

**Verify**: `ls tests/severity-gate/fixtures/ | wc -l` → 14.

### A2. Write failing tests for AC1–AC6 (classifier)

**File:** `tests/severity-gate/pr-classify-finding.bats`

Tests:
- `@test "AC1: classify blocker-auth-path → BLOCKER"`
- (one per fixture: 14 tests total)
- `@test "AC3: blocker path globs match all AGENTS.md auto-escalation paths"`
- `@test "AC4: each major keyword triggers MAJOR"`
- `@test "AC6: unclassified falls through to LLM fallback with audit log entry"`

**Verify**: 16 FAIL (classifier doesn't exist yet).

### A3. Write failing tests for AC7 (gate conditions C1–C9)

**File:** `tests/severity-gate/pr-auto-merge-gate.bats`

Tests:
- `@test "AC7: missing auto-merge-enabled file → MERGE_BLOCKED reason=no-opt-in"`
- `@test "AC7: <3 review rounds → MERGE_BLOCKED reason=insufficient-rounds"`
- `@test "AC7: any BLOCKER finding → MERGE_BLOCKED reason=blocker-present"`
- `@test "AC7: any MAJOR finding → MERGE_BLOCKED reason=major-present"`
- `@test "AC7: CI not all green → MERGE_BLOCKED reason=ci-not-clean"`
- `@test "AC7: LOC over cap → MERGE_BLOCKED reason=loc-cap-exceeded"`
- `@test "AC7: auto-escalation path touched → MERGE_BLOCKED reason=safe-path-touched"`
- `@test "AC7: unresolved conversations → MERGE_BLOCKED reason=unresolved-threads"`
- `@test "AC7: all conditions met → MERGE_APPROVED"`

Mock the GitHub API responses via test fixtures + `curl` stubs.

**Verify**: 9 FAIL.

### A4. Write failing tests for AC8 + AC9 (action sequence)

**File:** `tests/severity-gate/pr-auto-merge-action.bats`

Tests:
- `@test "AC8: MERGE_APPROVED creates follow-up issue with correct title pattern"`
- `@test "AC8: MERGE_APPROVED auto-resolves MINOR/COSMETIC threads"`
- `@test "AC8: MERGE_APPROVED invokes gh pr merge --squash --delete-branch --admin"`
- `@test "AC9: MERGE_BLOCKED posts a comment with the reason"`

Mock all GitHub API calls. Validate the calls made, not the GitHub effect.

**Verify**: 4 FAIL.

### A5. Write failing tests for AC10 (opt-in marker file)

**File:** `tests/severity-gate/auto-merge-marker.bats`

Tests:
- `@test "AC10: presence of auto-merge-enabled at repo root enables gate"`
- `@test "AC10: empty auto-merge-enabled = accept all defaults"`
- `@test "AC10: explicit enabled: false in marker = MERGE_BLOCKED reason=opt-out-kill-switch"`
- `@test "AC10: marker not at repo root (subdir) = no opt-in"`

**Verify**: 4 FAIL.

---

## Phase B — Severity classifier

### B1. Implement `walter-os pr-classify-finding`

**File:** `scripts/walter/subcommands/pr-classify-finding.sh`

Implements §4.2 ruleset:
1. Path glob matching for BLOCKER triggers.
2. Keyword (case-insensitive, word-boundary) matching for MAJOR triggers.
3. Doc-file COSMETIC and MINOR bias.
4. Test-file MINOR bias.
5. UNCLASSIFIED → LLM fallback via existing LiteLLM virtual key (use the `pr-review-severity` virtual key, $0.01 per call cap).

Inputs: PR number + comment ID.
Output: JSON `{"severity": "BLOCKER", "rule": "auth-path-trigger", "rule_detail": "auth/oauth.ts matched auth/**"}`.

**File:** `bin/walter-os` (extend dispatch):
- New case: `pr-classify-finding) exec scripts/walter/subcommands/pr-classify-finding.sh "$@"`

**Verify**: AC1-AC5 PASS.

### B2. Wire LLM fallback for UNCLASSIFIED

**File:** `scripts/walter/subcommands/pr-classify-finding.sh` (extend).

When no rule matches:
1. Call `infisical secrets get LITELLM_PR_SEVERITY_KEY --env=prod` (key per AGENTS.md secrets flow).
2. POST to `${LITELLM_BASE_URL}/v1/chat/completions` with a fixed prompt template (in `scripts/walter/lib/pr-severity-prompt.txt`).
3. Cost-cap: read response's `usage.cost_usd`; if > 0.01, log + return MAJOR.
4. Log the call (prompt + response + decision) to `~/.config/walter-os/state/auto-merge-log.jsonl`.

**Verify**: AC6 PASS.

### B3. Implement `walter-os pr-classify-review` (PR-level walker)

**File:** `scripts/walter/subcommands/pr-classify-review.sh`

Walks every inline comment on the PR, calls pr-classify-finding for each, returns:
```json
{
  "BLOCKER": [...],
  "MAJOR": [...],
  "MINOR": [...],
  "COSMETIC": [...],
  "UNCLASSIFIED": [...]
}
```

**Verify**: AC2 PASS.

---

## Phase C — Gate conditions

### C1. Implement `walter-os pr-auto-merge` condition checker

**File:** `scripts/walter/subcommands/pr-auto-merge.sh`

Checks C1-C9 in order. Returns `MERGE_APPROVED` or `MERGE_BLOCKED:<reason-slug>`.

Helpers needed:
- `_auto_merge_marker_path()` — find `auto-merge-enabled` at repo root
- `_count_review_rounds()` — count distinct Copilot reviews on PR
- `_ci_all_green()` — query latest commit's check-runs
- `_pr_loc_change()` — query `additions` + `deletions` from PR API
- `_pr_touches_safe_path()` — diff list intersected with safe-path globs
- `_unresolved_threads()` — GraphQL count of `reviewThreads.nodes[].isResolved == false`

**Verify**: AC7 PASS (9/9 conditions tested).

### C2. Implement opt-in marker parsing

**File:** `scripts/walter/lib/auto-merge-config.sh`

Sourced by the gate. Parses `auto-merge-enabled` YAML, exports its values as shell vars with sane defaults from the schema in spec §4.5.

**Verify**: AC10 PASS.

---

## Phase D — Action sequence

### D1. Implement follow-up issue creation

**File:** `scripts/walter/subcommands/pr-auto-merge.sh` (extend).

When gate passes:
1. Build issue body from the MINOR + COSMETIC finding list (verbatim text + file:line + suggested fix shape from rule_detail).
2. Title pattern: `[CHORE] -OPERATIONS- deferred MINORs from PR #<N>` (configurable per spec §4.5).
3. `gh issue create --label auto-merge-deferred,copilot-review --title "..." --body "..."`

**Verify**: AC8 (issue-creation portion) PASS via mock.

### D2. Auto-resolve MINOR/COSMETIC threads

**File:** `scripts/walter/lib/resolve-threads.sh`

GraphQL mutation `resolveReviewThread` for each thread classified MINOR or COSMETIC. Preserves BLOCKER/MAJOR threads as-is (since gate fails before reaching this step if any are present).

**Verify**: AC8 (resolve portion) PASS.

### D3. Invoke merge

`gh pr merge <N> --squash --delete-branch --admin` (the `--admin` flag relies on operator being in `bypass_pull_request_allowances` per branch protection).

If the gh call returns non-2xx, log + fail (do not retry).

**Verify**: AC8 (merge portion) PASS.

### D4. MERGE_BLOCKED comment

When any condition fails, post a PR comment with the failing condition + the remediation: "To unblock, address the BLOCKER findings in [list], then re-trigger via `walter-os pr-auto-merge 111`."

**Verify**: AC9 PASS.

---

## Phase E — Hook + AGENTS.md update

### E1. Implement `pr-auto-merge-gate.sh` hook

**File:** `hooks/pr-auto-merge-gate.sh`

Triggered by n8n webhook on GitHub `pull_request_review` event. Calls `walter-os pr-auto-merge $PR_NUM`. Logs the outcome to `~/.config/walter-os/state/auto-merge-log.jsonl`.

This is the actual unattended-mode trigger. Without n8n wiring, the gate is invoked manually via the CLI.

### E2. AGENTS.md amendment

Replace the current absolute hard rule:

```
- Never auto-merge a PR. The operator clicks merge.
```

with the bounded version:

```
- Never auto-merge a PR EXCEPT through the bounded conditions in
  `docs/specs/pr-review-severity-gate.md` §4.3 (operator opt-in via
  `auto-merge-enabled` marker file in repo root, zero
  BLOCKER/MAJOR remaining after ≥3 review rounds, LOC cap,
  auto-escalation path exclusion, follow-up issue auto-created for
  every deferred MINOR/COSMETIC). See ADR 0015.
```

**Verify**: AC11 PASS (doc only; reviewer confirms diff).

### E3. ADR 0015 final

`docs/decisions/0015-pr-review-severity-gate.md` — already drafted in the upfront ADR commit, refined as the design surfaces edge cases during implementation. Final form documents the locked design + 4 rejected alternatives (always auto-merge, fully manual, per-PR label, time-based auto-merge).

**Verify**: AC12 PASS.

---

## Phase F — Verification

### F1. Full bats suite

```bash
bats tests/severity-gate/
```

Expected: AC1-AC11 PASS.

### F2. E2E smoke test

```bash
bats tests/e2e/auto-merge-mock-pr.bats
```

Uses a forked test repo (e.g. `Xipher-Labs/walter-os-auto-merge-test`) seeded with a fixture PR. Tests the full sequence end-to-end.

**Verify**: AC13 PASS.

### F3. DoD validation + PR creation

- Run `definition-of-done-validator` against the spec.
- Open PR titled `[FEAT] -OPERATIONS- pr-review-severity-gate + bounded auto-merge (supersedes #112 scaffolding)`.
- Request Copilot review.
- Cycle review rounds per AGENTS.md.
- **Meta**: this PR cannot use its own auto-merge feature on first land (the marker file doesn't exist yet on main). Operator merges manually. After merge + repo `auto-merge-enabled` file commit, subsequent PRs use the new gate.

---

## Out-of-plan items (file separately)

- F1: weekly digest dashboard
- F2: Control Tower severity-gate panel
- F3: cross-repo discovery
- F4: operator-override drift detection

---

## Commit strategy

One commit per task (~18 commits). Conventional commit messages.

PR title: `[FEAT] -OPERATIONS- pr-review-severity-gate + bounded auto-merge`
(matches `hooks/pr-title-validator.sh` convention).
