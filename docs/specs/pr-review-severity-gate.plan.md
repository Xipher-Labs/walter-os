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
- `tests/severity-gate/fixtures/blocker-money-path.json`    (referencing `programs/escrow.rs` or `payments/stripe/charge.ts` — spec §4.2 money-flow paths; renamed from -keyword because spec only defines money via PATH, not keyword)
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

Tests (17 total — one fixture per AC1 case + three additional gate tests):
- `@test "AC1: classify blocker-auth-path → BLOCKER"`
- (one per fixture: 14 tests total — see §5 spec for the fixture matrix)
- `@test "AC3: blocker path globs match all AGENTS.md auto-escalation paths"`
- `@test "AC4: each major keyword triggers MAJOR"`
- `@test "AC6: unclassified falls through to LLM fallback with audit log entry"`

**Verify**: 17 FAIL (classifier doesn't exist yet; 14 fixture cases + 3 gate cases = 17).

### A3. Write failing tests for AC7 (gate conditions C1–C8 + issue-create failure slug)

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
- `@test "AC7: opt-out via 'enabled: false' in marker → MERGE_BLOCKED reason=opt-out-kill-switch"`
- `@test "AC7: gh issue create fails → MERGE_BLOCKED reason=follow-up-issue-create-failed"`
  Mock `gh issue create` to return non-zero. Assert the merge is
  aborted (no `gh pr merge` call) + the comment posts the slug.
  Closes Codex R5 #114: the new slug introduced when C8 moved out
  of preconditions in spec R4 had no RED test covering its trigger.
- `@test "AC7: all conditions met → MERGE_APPROVED"`

Mock the GitHub API responses via test fixtures + `curl` stubs.

**Verify**: 11 FAIL (8 gate conditions C1-C8 + 1 opt-out kill-switch
+ 1 issue-create-failure + 1 positive). Note: C8 in spec R4+ is
"all threads resolved" (the former C9); spec/ADR/plan all consistent
on the 8-condition gate.

### A4. Write failing tests for AC8 + AC9 + BLOCKER-handling (action sequence)

**File:** `tests/severity-gate/pr-auto-merge-action.bats`

Tests:
- `@test "AC8: MERGE_APPROVED creates follow-up issue with correct title pattern"`
- `@test "AC8: MERGE_APPROVED auto-resolves MINOR/COSMETIC threads"`
- `@test "AC8: MERGE_APPROVED invokes gh pr merge --squash --delete-branch --admin"`
- `@test "AC9: MERGE_BLOCKED posts a comment with the reason"`
- `@test "G3/§4.4: BLOCKER finding triggers high-priority issue create (not just comment)"`
  Mock: classifier returns one BLOCKER + zero MAJOR. Assert: gate posts
  the diagnostic comment AND invokes `gh issue create` with the
  `[FIX] -SECURITY-` (or `-OPERATIONS-`) title prefix + BLOCKER finding
  body + suggested fix-shape. Closes Codex R3 #114 BLOCKER (plan had
  no task/test for the spec-mandated BLOCKER issue creation).
- `@test "G3/§4.4: BLOCKER finding does NOT auto-close the PR"`
  Mock: classifier returns one BLOCKER. Assert: the PR's state is
  still 'open' after the gate runs + no `gh pr close` call was made.

Mock all GitHub API calls. Validate the calls made, not the GitHub effect.

**Verify**: 6 FAIL.

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
2. **Prefix-token matching** (case-insensitive) for MAJOR triggers —
   matches §4.2's prefix-style semantics so `vulnerabilit` catches
   `vulnerability` + `vulnerabilities`, `expose` catches `exposed` /
   `exposes`, etc. Verb-phrase rules use literal case-insensitive
   substring match.
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
1. Call `infisical secrets get LITELLM_PR_SEVERITY_KEY --env=prod` via the Walter-OS secrets-runtime flow (see `docs/specs/secrets-runtime-architecture.md`). NOTE: AGENTS.md line ~481 still references Vaultwarden as the production secrets store — that's stale prose from the pre-Vaultwarden-retirement era (operator decision 2026-05-05). This plan assumes the live Infisical machine-identity flow; AGENTS.md update is tracked separately + is NOT a prerequisite for this plan.
2. POST to `${LITELLM_BASE_URL}/v1/chat/completions` with a fixed prompt template (in `scripts/walter/lib/pr-severity-prompt.txt`).
3. **Cost extraction**: OpenAI-compatible responses don't ship a cost field by default; LiteLLM proxy injects `usage.response_cost` (or `x-litellm-response-cost` header) when its callback is wired. Read both — header first (cheap parse, always present on a proxy hit), `usage.response_cost` second (fallback if the upstream model passed through). If neither is present, log a WARN + treat the call as if it hit the cap (return MAJOR — fail-safe). If cost > $0.01, log + return MAJOR.
4. Log the call (prompt + response + decision + extracted cost field) to `~/.config/walter-os/state/auto-merge-log.jsonl`.

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

Checks C1-C8 in order. Returns `MERGE_APPROVED` or `MERGE_BLOCKED:<reason-slug>` (one of the 10 slugs in AC7, including `follow-up-issue-create-failed` emitted from the §4.4 step 3a action if gh issue create returns non-zero).

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

When any condition fails, post a PR comment with the failing condition + the remediation: "To unblock, address the BLOCKER findings in [list], then re-trigger via `walter-os pr-auto-merge <pr-num>`." (The PR number is substituted at hook-call time; never hard-code a specific PR in the template.)

### D5. BLOCKER-finding action sequence (Codex R4 #114)

Implements §4.4 steps 6/7/8 — the BLOCKER-specific path. Distinct
from D1-D3 (which only run when the gate PASSES) and D4 (which posts
a generic blocked-condition comment). Called whenever the classifier
emits at least one BLOCKER finding, independently of the other gate
conditions' status.

**Files:**
- `scripts/walter/subcommands/pr-auto-merge.sh` (extend)
- `scripts/walter/lib/blocker-issue.sh` (new — title/body builder)

Behavior:
1. For each BLOCKER finding, append to the issue body: verbatim
   finding text, file:line anchor, classifier `rule` + `rule_detail`,
   suggested fix-shape (deterministic mapping from rule → shape;
   `auth-path-trigger` → "audit the auth/ change for secret/PII
   leak", etc.).
2. Title: `[FIX] -SECURITY- <PR-title-body> — BLOCKER from PR #<N>`
   when ANY BLOCKER's path matches a SECURITY glob (auth/, crypto/,
   secrets/, .env*, PHI). Otherwise `[FIX] -OPERATIONS- ... — BLOCKER`.
3. `gh issue create --label severity-blocker,from-auto-merge --title "..." --body "..."`
4. Post PR comment naming each BLOCKER + linking the new issue.
5. EXPLICITLY do NOT call `gh pr close`. The PR stays open; closure
   is operator-only.

**Verify**: the two A4 BLOCKER tests PASS (issue-create + no-close).

**Verify**: AC9 PASS.

---

## Phase E — Hook + AGENTS.md update

### E1. Implement `pr-auto-merge-gate.sh` hook

**File:** `hooks/pr-auto-merge-gate.sh`

Triggered by n8n webhook on GitHub `pull_request_review` event. Calls `walter-os pr-auto-merge $PR_NUM`. Logs the outcome to `~/.config/walter-os/state/auto-merge-log.jsonl`.

This is the actual unattended-mode trigger. Without n8n wiring, the gate is invoked manually via the CLI.

### E2. AGENTS.md amendment (TWO blocks — Codex R3 #114 BLOCKER)

AGENTS.md has TWO sites that hard-block auto-merge — both must be
amended in this task. Closes Codex R3 #114: the previous version of
this task only patched site #1, missing AGENTS.md:322-327 which
hardcodes the approval-gate's refusal independent of the rule list.

**Site 1** — `## Universal disciplines` → `Things agents must NEVER do`
(AGENTS.md:329-336). Replace:

```
- Never auto-merge a PR. The operator clicks merge.
```

with:

```
- Never auto-merge a PR EXCEPT through the bounded conditions in
  `docs/specs/pr-review-severity-gate.md` §4.3 (operator opt-in via
  `auto-merge-enabled` marker file in repo root, zero
  BLOCKER/MAJOR remaining after ≥3 review rounds, LOC cap,
  auto-escalation path exclusion, follow-up issue auto-created for
  every deferred MINOR/COSMETIC). See ADR 0015.
```

**Site 2** — `## Trust tiers` → `Blocked for ALL tiers` hardcoded list
(AGENTS.md:322-327). The current list reads:

```
push to main/staging/release, merge PRs, force-push any branch, ...
[no override possible]
```

Amend the "merge PRs" entry with the same conditional:

```
push to main/staging/release, merge PRs (EXCEPT when the bounded
conditions in `docs/specs/pr-review-severity-gate.md` §4.3 + §4.4
hold and `auto-merge-enabled` is present at repo root — see ADR
0015), force-push any branch, ...
```

This task ALSO patches `hooks/approval-gate.sh` to read the
`auto-merge-enabled` marker + call `walter-os pr-auto-merge` before
emitting the BLOCKED-by-hardcoded-rule response. Without that patch,
the rule-list amendment alone wouldn't actually unlock auto-merge —
the hook still hard-refuses based on its internal action-category
allowlist.

**Verify**: AC11 PASS (both AGENTS.md sites diffed + approval-gate.sh
test covers the marker-file-present path).

### E3. ADR 0015 final

`docs/decisions/0015-pr-review-severity-gate.md` — already drafted in the upfront ADR commit, refined as the design surfaces edge cases during implementation. Final form documents the locked design + 5 rejected alternatives (always auto-merge, fully manual, per-PR label, time-based auto-merge, single-bit classifier without severity tiers).

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

One commit per task (~20 commits — matches the 20-task total in the
header). Conventional commit messages.

PR title: `[FEAT] -OPERATIONS- severity-gate + bounded auto-merge spec`
(matches `hooks/pr-title-validator.sh` convention — body ≤ 60 chars).
