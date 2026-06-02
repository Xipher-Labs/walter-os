# SPEC: PR review severity gate + bounded auto-merge

**Status:** Draft (2026-05-21). Awaiting operator approval.
**Triggered by:** Operator observation during PR #111's 4-round Copilot review cycle: 24 findings total, none touching `auth/`, `crypto/`, money flows, or PHI; the substantive logic bugs were closed in R1; R2-R4 were docs accuracy + test thoroughness; the loop continued because there was no mechanism to distinguish blocker findings from cosmetic ones.
**Related:** `AGENTS.md` "Review loop (standard pattern)", `AGENTS.md` "Never auto-merge a PR" hard rule, ADR 0015, follow-up issue #112.
**Rigor classification:** MAJOR (touches `AGENTS.md`, `hooks/`, agent contract, branch-protection-relaxation semantics).

---

## 1. Problem

The current Walter-OS review loop (`AGENTS.md` → "Review loop") prescribes:

- Round 1: Copilot review → address findings.
- Round 2: Codex cross-review → address findings.
- Round 3: Collaborative if anything remains.
- After Round 3: escalate to operator.

In practice, two failure modes show up:

1. **Cosmetic findings extend the loop indefinitely.** A finding like "use `[[:space:]]` instead of `\s` in grep -E" is real but trivial and not blocking. Today it gets the same treatment as a finding like "this commit leaks an API key" — both trigger a fix commit + re-request. PR #111 spent 4 rounds and 10 fix commits closing what was substantively documentation drift (zero security / money / PHI involvement).

2. **The current "Never auto-merge" hard rule has no relief valve.** `AGENTS.md` says the operator clicks merge for every PR. For a 4-round-converged documentation PR, that "click" is essentially a rubber stamp — the operator has no signal that the remaining work is genuinely cosmetic. They either:
   (a) merge by feel, with no documentation of which findings were left unresolved, OR
   (b) keep looping until everything is closed, even the cosmetic items.

Neither matches the operator's actual intent ("merge when only minor stuff remains, defer minor cleanup to follow-up issues").

## 2. Goals

- **G1.** Every Copilot/Codex finding is assigned a severity (BLOCKER, MAJOR, MINOR, COSMETIC) at review-receive time.
- **G2.** After a configurable number of review rounds (default 3), if all remaining findings are MINOR or below AND a set of safety preconditions hold, the PR may be auto-merged. The deferred findings spin off into a single follow-up issue with full context.
- **G3.** BLOCKER findings never permit auto-merge regardless of rounds. The action sequence (§4.4) **(a) creates a new high-priority issue with the BLOCKER finding(s) + a suggested fix-shape, AND (b) posts a PR comment explaining the block and linking the new issue.** PR CLOSE on BLOCKER is an operator decision, not an automatic gate action — the gate posts the diagnostic and waits.
- **G4.** Auto-merge is **per-repo opt-in** via `walter-repo-config.yaml`
  (`auto_merge.enabled: true` plus scoped `auto_merge.allowed_branches`).
  Repos without the config, or with auto-merge disabled, behave per current
  `AGENTS.md` (manual operator merge).
- **G5.** The current safety paths are NEVER eligible for auto-merge, regardless of opt-in or severity. AGENTS.md maintains three related but distinct lists — the task-rigor "auto-escalate to major" triggers (`AGENTS.md:89`), the "Blocked for ALL tiers" hardcoded approval-gate list (`AGENTS.md:322`), and the "Things agents must NEVER do" list (`AGENTS.md:329`). This spec takes the **union** of all three as a conservative super-set: a path landing on any list is BLOCKER. The path-glob list in §4.2 covers auth/, crypto/, money flows including Solana program code (`programs/**` — AGENTS.md explicitly names "money (Solana TX, Stripe)" as an auto-escalation trigger) + Stripe SDK paths, PHI / `personal/health/**`, audit logs (any directory literally named `audit/` or `audit-logs/`), prod migrations, hooks/, AGENTS.md, install.sh, mcp/servers.json. Only ONE path in §4.2 (`**/secrets/**` for any nested secrets dir) is an explicit conservative addition beyond AGENTS.md — labeled as such in §4.2 so future readers don't mis-cite AGENTS.md.
- **G6.** Severity classification is auditable: a deterministic ruleset produces the verdict, and any LLM-fallback classification is logged with the reasoning that led to it.
- **G7.** Follow-up issues for deferred MINORs are auto-created with the verbatim finding + the source-of-truth file:line reference + a suggested fix shape.

## 3. Non-goals

- **NG1.** Not removing the operator's ability to merge manually. The auto-merge path is additive; manual merge is always available.
- **NG2.** Not reclassifying findings retroactively. Findings landing AFTER this spec ships are classified; older findings stay as-is.
- **NG3.** Not building a UI. CLI + GitHub Actions integration + the existing hook/n8n event surface only — no operator dashboard, no web app, no new UX.
- **NG4.** Not extending to repos beyond walter-os in the first version. Per-org rollout is a follow-up if the walter-os experience is positive.
- **NG5.** Not implementing a "severity override" by the operator on
  individual findings. The classifier is the source of truth; future
  classifier override policy belongs in `walter-repo-config.yaml` or a
  referenced repo-policy extension, not in a separate marker file.

## 4. Design (decisions locked, see ADR 0015)

### 4.1 Severity taxonomy

| Severity | Definition | Examples |
|---|---|---|
| **BLOCKER** | Touches an auto-escalation path OR introduces a security/safety regression. Never permits auto-merge. | Finding in `auth/`, `crypto/`, money flows, PHI; leaked secret; broken safety hook. |
| **MAJOR** | Real logic bug, broken test, regression in existing functionality, or violation of an `AGENTS.md` hard rule. Blocks auto-merge until resolved. | Failing unit test; logic mismatch between prompt and code (R4 #1-#2 on #111); regression on a previously passing test. |
| **MINOR** | Doc accuracy, prose nit, comment drift, portability quirk, test thoroughness improvement with no current false-negative, dead code. Eligible for auto-merge after gate. | `\s` → `[[:space:]]`; stale comment block; ADR claim doesn't match impl; AC doesn't validate deep nesting. |
| **COSMETIC** | Formatting, indentation, spelling, variable-name preference, ordering of unrelated items. Eligible for auto-merge once ALL gate conditions (C1-C9) are met — COSMETIC respects the same round threshold as MINOR (C2 ≥ N rounds). Both MINOR and COSMETIC items are bundled into the single follow-up issue created by C8 — neither severity bypasses the visibility requirement. | Trailing whitespace; renamed `cmd` → `command`; alphabetize unrelated import. |

### 4.2 Classifier — deterministic rules + LLM fallback

`bin/walter-os pr-classify-finding <pr-num> <comment-id>` takes the
PR number + the GitHub review-comment ID (from `GET /repos/.../pulls/{n}/comments`)
and itself fetches the three inputs the classifier needs:

- The finding text (review comment body)
- The file path the comment is anchored on
- Whether that file is in the PR diff (Y/N) — determined by querying
  `GET /repos/.../pulls/{n}/files` and matching `path`.

The CLI design takes IDs (not raw text + path) so the classifier can be
re-invoked deterministically from a hook/audit without the caller having
to re-fetch + reassemble the same comment fields. Returns a single-line JSON
object on stdout (matches plan B1):
```json
{"severity":"BLOCKER","rule":"auth-path-trigger","rule_detail":"auth/oauth.ts matched auth/**"}
```
Where `severity ∈ {BLOCKER, MAJOR, MINOR, COSMETIC, UNCLASSIFIED}`. Callers
that only want the label can pipe through `jq -r .severity`.

Order of evaluation:

1. **Path-based BLOCKER triggers.** If the finding references any file matching:
   ```
   # From AGENTS.md auto-escalation-to-major + "Blocked for ALL tiers":
   auth/** | crypto/** | hooks/**
   migrations/** | **/migrations/**     # any DB migration path (prod-DB risk)
   audit/** | **/audit/** | audit-logs/** | **/audit-logs/**   # audit-trail paths (top-level + nested)
   AGENTS.md | install.sh | mcp/servers.json
   personal/health/** | **/medical/** | **/phi/** | **/.env*
   # Money-flow paths — AGENTS.md "money (Solana TX, Stripe)" trigger
   # expanded to concrete file globs so the classifier can match:
   programs/**                          # Solana on-chain code (anchor)
   **/stripe/** | **/billing/**         # Stripe SDK + billing logic
   # Conservative additions beyond AGENTS.md (this spec, §2 G5):
   **/secrets/**                        # any nested 'secrets' dir
   ```
   → BLOCKER. No further evaluation. The first two blocks are concrete
   expansions of AGENTS.md triggers (the second block names the paths
   that AGENTS.md's abstract "money" trigger covers — Solana TX +
   Stripe). Only `**/secrets/**` is a spec-level conservative
   addition (AGENTS.md mentions `.env*` files + "never commit secrets"
   but no `secrets/` directory glob).

2. **Keyword-based MAJOR triggers** in the finding body. Each token in
   the list below is matched as a **prefix** against words in the finding
   (case-insensitive); the prefix style is intentional so word-stem
   variants (`vulnerability` / `vulnerabilities`; `expose` / `exposed` /
   `exposes`) all hit the same rule without enumerating every form.
   - Prefix tokens: `fail`, `broken`, `regression`, `leak`, `expose`,
     `vulnerabilit`, `bypass`, `unsafe`, `crash`
   - Verb phrases (literal substring, case-insensitive): `would cause`,
     `will fail`, `currently does not work`, `breaks the`, `failing test`
   → MAJOR.

3. **Path-based COSMETIC bias** for findings only touching docs:
   - File path matches `**/*.md` AND finding body contains: `typo`, `spelling`, `whitespace`, `formatting`, `indent`, `alphabetize`, `naming`, `rename`
   → COSMETIC.

4. **Path-based MINOR bias** for documentation files with substantive feedback:
   - File path matches `**/*.md`, `docs/**`, `README*`, `CHANGELOG*`
   - Finding body does NOT match COSMETIC keywords above
   → MINOR.

5. **Test file MINOR bias** for test-thoroughness improvements:
   - File path matches `tests/**`
   - Finding body contains: `tighten`, `also validate`, `does not cover`, `false negative`, `could miss`, `thoroughness`
   → MINOR.

6. **Anything not matched above** → UNCLASSIFIED. The LLM fallback classifier (a small dedicated prompt to a low-cost model via LiteLLM, capped at $0.01 per call) makes the call. The decision is logged with the prompt + response for audit.

A skill named `pr-review-severity` documents the ruleset, the keyword lists, and the LLM fallback prompt.

### 4.3 Auto-merge conditions (ALL must hold)

| # | Condition | Why |
|---|---|---|
| C1 | `walter-repo-config.yaml` exists on the default branch before the PR and has `auto_merge.enabled: true`; the PR source branch matches `auto_merge.allowed_branches` and does not match `auto_merge.forbidden_branches`. | Per-repo opt-in + kill-switch for eligible source branches. Absence returns `MERGE_BLOCKED:no-opt-in`; disabled auto-merge returns `MERGE_BLOCKED:opt-out-kill-switch`. Reading the default-branch version prevents a PR from authorizing itself. |
| C2 | ≥ N completed review rounds (default N=3; future repo-config extension may lower/raise this without relaxing the hard floor) | The 3-round Walter-OS review loop has proven its value; we bound the loop, not skip it. |
| C3 | Zero BLOCKER findings on the latest HEAD | Hard rule. |
| C4 | Zero MAJOR findings on the latest HEAD | Hard rule. |
| C5 | All CI checks success on the latest HEAD | Existing rule, just reaffirmed. |
| C6 | PR LOC change ≤ operator-configured cap (default 1500 LOC additions, 500 LOC deletions) | Limits blast radius. Large refactors deserve operator eyeballs. |
| C7 | PR does not touch any auto-escalation path | Even outside the BLOCKER classification, these paths get manual review. |
| C8 | All review conversation threads marked as resolved (auto-resolved by the gate when their finding is classified as MINOR/COSMETIC and the gate accepts the deferral) | GitHub branch protection requirement (`required_conversation_resolution`). The gate handles this without an operator click. |

Codex R4 #114: the previous version of this table listed a C8
"follow-up issue auto-created" as a precondition. That conflated
gate-check with gate-action — the issue can only be created AFTER
the gate decides to pass, so it could never be a pre-decision check.
Issue creation is now part of §4.4 step 3a (action sequence) with
explicit failure behavior: if `gh issue create` fails (rate-limit,
auth, etc.), the merge is aborted and a MERGE_BLOCKED comment is
posted with reason `follow-up-issue-create-failed` (added to the
AC7 slug enum). Conversation thread resolution (formerly C9) is now
C8 (renumbered).

### 4.4 Auto-merge action sequence

When C1-C8 hold (gate passes):

1. The `pr-auto-merge-gate.sh` hook (triggered by GitHub webhook on `pull_request_review` event) executes.
2. The hook calls `walter-os pr-classify-review <pr-num>` which produces a severity-tagged finding list.
3. Gate-pass action sequence:
   a. Create follow-up issue with the deferred MINOR/COSMETIC findings (one issue per PR, not per finding). If `gh issue create` returns non-zero → abort, emit `MERGE_BLOCKED:follow-up-issue-create-failed`, post a PR comment with the slug + retry guidance, exit the action sequence here.
   b. Comment on the PR with the merge decision + the follow-up issue link.
   c. Auto-resolve the MINOR/COSMETIC review threads on the PR.
   d. Invoke `gh pr merge --squash --delete-branch --admin` (assumes operator's bypass permission is configured per branch-protection).

When the gate fails on any condition (C1-C8):

1. Post a PR comment naming the failing condition + `MERGE_BLOCKED:<reason-slug>` + remediation guidance. PR remains open.

When a BLOCKER finding is detected (independent of gate pass/fail — this path supersedes step 3's gate-pass action when ANY BLOCKER is present, since C3 would already be failing):

1. Create a high-priority follow-up issue capturing the BLOCKER finding(s) verbatim + the source file:line + a suggested fix-shape (per G3). The issue title prefix is `[FIX] -SECURITY-` for security paths, `[FIX] -OPERATIONS-` otherwise.
2. Post a PR comment naming the BLOCKER(s), linking the issue from step 1, and explicitly stating the gate did NOT auto-close the PR — operator decides (G3, Decision 4).
3. The PR stays open. No further action.

### 4.5 `walter-repo-config.yaml` auto-merge policy

```yaml
# walter-repo-config.yaml — single per-repo autonomy policy surface.
autonomy_mode: guided
profile: balanced
capability_tier_ceiling: 1
auto_merge:
  enabled: true
  allowed_branches: ["feature/*", "codex/*"]
  forbidden_branches:
    - main
    - master
    - staging
    - production
    - "release/*"
  require_green_ci: true
  min_walter_score: 90
  max_risk: low
verification: risk_based
preview_deploy: false
human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
```

The old standalone auto-merge marker file is superseded by ADR-0026 and the
`auto_merge` block above. Classifier overrides, follow-up issue labels, audit
log path, and LLM fallback caps remain future extensions; if added, they should
extend this policy surface or reference a repo-policy extension from it.

Repos without `walter-repo-config.yaml`, or with `auto_merge.enabled: false`,
fall back to manual operator merge as today.

### 4.6 Failure modes & guard rails

- **Misclassified MINOR that's actually MAJOR**: caught by the LLM fallback's audit log + the operator's weekly digest (out-of-scope follow-up F1 in §6). If discovered post-merge, the operator reverts via standard git revert and adjusts the classifier rules.
- **Classifier loops on UNCLASSIFIED → LLM cost runaway**: LLM fallback hard-caps at $0.01 per finding + $1 per PR. Above cap, defaults to MAJOR (fail-safe to "needs human").
- **Operator wants to defer a finding the classifier called MAJOR**: not
  allowed in the gate. Operator can manually merge this one, or later adjust
  classifier policy through the repo-config extension surface if implemented.
- **Branch protection enforces non-bypassable rules**: gate respects them. If branch protection requires a human approval that the operator hasn't pre-authorized, gate falls back to posting a "ready for your merge" comment and stops.

## 5. Acceptance criteria

- [ ] **AC1.** `bin/walter-os pr-classify-finding <pr-num> <comment-id>` returns the severity label for a single Copilot inline comment per the §4.2 ruleset.
- [ ] **AC2.** `walter-os pr-classify-review <pr-num>` walks every inline comment on the PR and returns a JSON object `{BLOCKER: [...], MAJOR: [...], MINOR: [...], COSMETIC: [...], UNCLASSIFIED: [...]}`.
- [ ] **AC3.** Path-based BLOCKER trigger fires on every file in the AGENTS.md auto-escalation list; tested with a fixture for each path glob.
- [ ] **AC4.** Keyword-based MAJOR trigger fires on each keyword in the §4.2 list; tested with a fixture file per keyword.
- [ ] **AC5.** Doc-file MINOR vs COSMETIC bias distinguishes correctly for a 10-sample fixture (5 each).
- [ ] **AC6.** UNCLASSIFIED findings trigger the LLM fallback (validated by checking the audit log entry); cost-cap enforces fail-safe to MAJOR above $0.01.
- [ ] **AC7.** `walter-os pr-auto-merge <pr-num>` checks C1-C8 (§4.3) and returns one of `MERGE_APPROVED` (exit 0) or `MERGE_BLOCKED:<reason-slug>` (exit 1, reason-slug is one of: `no-opt-in`, `insufficient-rounds`, `blocker-present`, `major-present`, `ci-not-clean`, `loc-cap-exceeded`, `safe-path-touched`, `unresolved-threads`, `opt-out-kill-switch`, `follow-up-issue-create-failed`). Tested with one positive fixture (MERGE_APPROVED) + one fixture per blocking slug (10 total = 11 fixtures, matching plan A3's 11 FAIL). The last slug fires when §4.4 step 3a's `gh issue create` returns non-zero — visibility-of-deferred-work is a hard requirement, so the gate aborts the merge if it can't be enforced.
- [ ] **AC8.** When MERGE_APPROVED: hook creates the follow-up issue, auto-resolves the relevant conversation threads, and invokes `gh pr merge --squash --delete-branch --admin`. Tested via mocked GitHub API.
- [ ] **AC9.** When MERGE_BLOCKED: hook posts a comment to the PR with the blocking condition + remediation guidance. Tested via mocked GitHub API.
- [ ] **AC10.** `walter-repo-config.yaml` with `auto_merge.enabled: true` is
  the only opt-in mechanism. Repos without it return
  `MERGE_BLOCKED:no-opt-in` (slug consistent with AC7's slug enumeration).
  The policy must be read from the default branch state that existed before
  the PR, so a PR that adds or loosens the file cannot self-authorize.
- [ ] **AC11.** AGENTS.md has TWO blocks that mention auto-merging — the
  implementation must amend both:
  - Line ~336 (`## Universal disciplines` → `Things agents must NEVER do` → "Auto-merge a PR. Operator clicks merge.") → amended to "Auto-merge a PR UNLESS the bounded conditions in §4.3 (gate) + §4.4 (action sequence) of `docs/specs/pr-review-severity-gate.md` are met".
  - Line ~322 (`## Trust tiers (Council agents — Phase T+)` → "Blocked for ALL tiers" hardcoded list including "merge PRs") → annotated with the same conditional, so the approval-gate.sh hook respects bounded auto-merge when `walter-repo-config.yaml` has `auto_merge.enabled: true` and all gate conditions hold.
  Both edits link ADR 0015 for the severity-gate rationale and ADR-0026
  for the repo-config opt-in surface. The implementation PR (not this spec
  PR) also updates `hooks/approval-gate.sh` to read
  `walter-repo-config.yaml` from the default branch + invoke the gate before
  refusing the merge action.
- [ ] **AC12.** ADR 0015 documents the severity-gate design choice + rejected
  alternatives (always auto-merge / fully manual / per-PR label / time-based
  auto-merge), while ADR-0026 documents `walter-repo-config.yaml` as the
  repo-config opt-in surface.
- [ ] **AC13.** End-to-end smoke: a sample PR with one MINOR finding + 3
  completed review rounds + `walter-repo-config.yaml` auto-merge enabled on
  the default branch produces a follow-up issue, resolves the thread, and
  squash-merges. Tested via a dedicated `tests/e2e/auto-merge-mock-pr.bats`
  using a forked test repo.

## 6. Out-of-scope follow-ups (file as separate issues)

- **F1.** Operator weekly digest: "PRs auto-merged this week: N; MINOR findings created from those: M; of which closed: K". Surfaces drift before it becomes systemic.
- **F2.** Severity-gate dashboard in Control Tower with per-classifier-rule pass rate (how often did each BLOCKER trigger fire? UNCLASSIFIED rate trending up = ruleset getting stale).
- **F3.** Cross-repo rollout: `walter-repo-config.yaml` discoverable across the operator's repos with a `walter-os pr-auto-merge --discover` mode.
- **F4.** Reverse path: detect operator manually overriding the classifier (closing a flagged MAJOR PR without resolving) and prompt to update the ruleset.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Classifier mis-classifies a real bug as MINOR | Med | Med | Triple gate (3 rounds + LOC cap + path exclusion) + weekly digest forces visibility + operator can patch rules |
| Loop becomes ritual sans value, operator disables everything | Low | High | Telemetry shows real value; if turned off, manual merge still works |
| Codex and Copilot disagree on severity | Med | Low | Worst-of: any classifier saying BLOCKER → BLOCKER. Disagreement = upgrade severity. |
| MINOR findings accumulate invisible debt | High | Med | Auto-created follow-up issue is mandatory; an open-follow-up backlog alert is tracked as an out-of-scope follow-up (F1 weekly digest covers near-term visibility; F2 dashboard formalizes the count-and-threshold mechanic). |
| `walter-repo-config.yaml` with `auto_merge.enabled: true` accidentally committed by a fork | Low | Med | The policy's presence is operator intent; fork inheriting it is operator responsibility. Worst case: the fork auto-merges its own eligible PRs, but protected branch and hard-floor rules still apply. |
| LLM fallback hallucinates a severity | Low | Med | Cost-cap fail-safes to MAJOR; audit log + monthly review |
| Branch-protection rule changes silently break the gate | Med | Low | Gate logs the exact GitHub API error; operator notified via the same audit log path |

## 8. Open questions for operator

- **Q1**: should COSMETIC findings skip the 3-round minimum entirely (auto-merge on first round)? **Currently locked: NO** — §4.1 and C2 treat COSMETIC the same as MINOR for the round threshold. This question is preserved as an open lever the operator may choose to unlock later (it would require relaxing C2's "unconditional N rounds" semantics in the ADR + amending §4.1).
- **Q2**: per-repo `walter-repo-config.yaml` override OR per-context
  (walter-os-personal vs walter-os-work) inheritance? Locked by ADR-0026:
  per-repo policy only. Context can suggest defaults, but committed repo
  policy is the source of truth.
- **Q3**: should the gate be allowed to convert a MAJOR finding to MINOR after the operator resolves the underlying issue (without a new finding from Copilot)? Proposed: no — operator's "resolve" via the GitHub UI is sufficient; the gate doesn't second-guess the operator.

## 9. References

- `AGENTS.md` "Universal disciplines" → "Review loop (standard pattern for every substantive PR)"
- `AGENTS.md` "Things agents must NEVER do" → "Auto-merge a PR" (will be amended per AC11)
- Closed PR #111 (`feature/agent-install-tier-completion`) — the case study that motivated this spec (24 findings across 4 rounds, all non-BLOCKER)
- Follow-up issue #112 — captures the deferred MINORs from #111 R4 + scaffolds this severity-gate work
- ADR 0009 (agent trust tiers) — similar pattern: per-agent tier configuration with override semantics
- ADR 0013 (solo-operator merge policy) — precedent for operator-configurable framework knobs
- ADR 0014 (CLI symlink path) — same review-loop case study
