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
- **G3.** BLOCKER findings never permit auto-merge regardless of rounds — they spin off into a new high-priority issue and the PR is closed pending the blocker's resolution.
- **G4.** Auto-merge is **per-repo opt-in** via a marker file (`auto-merge-enabled` in repo root). Repos without the marker behave per current `AGENTS.md` (manual operator merge).
- **G5.** The current safety paths (auto-escalation triggers — auth/, crypto/, money, PHI, audit logs, prod migrations, hooks/, AGENTS.md, install.sh, mcp/servers.json) are NEVER eligible for auto-merge, regardless of opt-in or severity.
- **G6.** Severity classification is auditable: a deterministic ruleset produces the verdict, and any LLM-fallback classification is logged with the reasoning that led to it.
- **G7.** Follow-up issues for deferred MINORs are auto-created with the verbatim finding + the source-of-truth file:line reference + a suggested fix shape.

## 3. Non-goals

- **NG1.** Not removing the operator's ability to merge manually. The auto-merge path is additive; manual merge is always available.
- **NG2.** Not reclassifying findings retroactively. Findings landing AFTER this spec ships are classified; older findings stay as-is.
- **NG3.** Not building a UI. CLI + GitHub Actions integration only.
- **NG4.** Not extending to repos beyond walter-os in the first version. Per-org rollout is a follow-up if the walter-os experience is positive.
- **NG5.** Not implementing a "severity override" by the operator on individual findings. The classifier is the source of truth; the operator can adjust the ruleset itself in `~/.config/walter-os/severity-rules.yml` if they disagree.

## 4. Design (decisions locked, see ADR 0015)

### 4.1 Severity taxonomy

| Severity | Definition | Examples |
|---|---|---|
| **BLOCKER** | Touches an auto-escalation path OR introduces a security/safety regression. Never permits auto-merge. | Finding in `auth/`, `crypto/`, money flows, PHI; leaked secret; broken safety hook. |
| **MAJOR** | Real logic bug, broken test, regression in existing functionality, or violation of an `AGENTS.md` hard rule. Blocks auto-merge until resolved. | Failing unit test; logic mismatch between prompt and code (R4 #1-#2 on #111); regression on a previously passing test. |
| **MINOR** | Doc accuracy, prose nit, comment drift, portability quirk, test thoroughness improvement with no current false-negative, dead code. Eligible for auto-merge after gate. | `\s` → `[[:space:]]`; stale comment block; ADR claim doesn't match impl; AC doesn't validate deep nesting. |
| **COSMETIC** | Formatting, indentation, spelling, variable-name preference, ordering of unrelated items. Eligible for auto-merge immediately (skips the round threshold). | Trailing whitespace; renamed `cmd` → `command`; alphabetize unrelated import. |

### 4.2 Classifier — deterministic rules + LLM fallback

`bin/walter-os pr-classify-finding` takes:
- The finding text (review comment body)
- The file path it references
- The PR diff context (file changed by this PR? Y/N)

And returns: `BLOCKER | MAJOR | MINOR | COSMETIC | UNCLASSIFIED`.

Order of evaluation:

1. **Path-based BLOCKER triggers.** If the finding references any file matching:
   ```
   auth/** | crypto/** | programs/** | migrations/** | hooks/**
   AGENTS.md | install.sh | mcp/servers.json
   **/secrets/** | **/.env*
   ```
   → BLOCKER. No further evaluation.

2. **Keyword-based MAJOR triggers** in the finding body:
   - `fail`, `failing test`, `broken`, `regression`, `leak`, `expose`, `vulnerabilit`, `bypass`, `unsafe` (case-insensitive, word boundary)
   - Verb phrases: `would cause`, `breaks`, `will fail`, `currently does not work`
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
| C1 | `auto-merge-enabled` marker file exists at repo root | Per-repo opt-in. Operator's signed declaration that this repo accepts the bounded auto-merge contract. |
| C2 | ≥ N completed review rounds (default N=3, configurable in `auto-merge-enabled` file) | The 3-round Walter-OS review loop has proven its value; we bound the loop, not skip it. |
| C3 | Zero BLOCKER findings on the latest HEAD | Hard rule. |
| C4 | Zero MAJOR findings on the latest HEAD | Hard rule. |
| C5 | All CI checks success on the latest HEAD | Existing rule, just reaffirmed. |
| C6 | PR LOC change ≤ operator-configured cap (default 1500 LOC additions, 500 LOC deletions) | Limits blast radius. Large refactors deserve operator eyeballs. |
| C7 | PR does not touch any auto-escalation path | Even outside the BLOCKER classification, these paths get manual review. |
| C8 | All MINOR + COSMETIC findings have been documented in a single follow-up issue auto-created from the deferred list | Visibility — no lost work, no silent drift. |
| C9 | All review conversation threads marked as resolved (auto-resolved by the gate when their finding is classified as MINOR/COSMETIC and the gate accepts the deferral) | GitHub branch protection requirement (`required_conversation_resolution`). The gate handles this without an operator click. |

### 4.4 Auto-merge action sequence

When C1-C9 hold:

1. The `pr-auto-merge-gate.sh` hook (triggered by GitHub webhook on `pull_request_review` event) executes.
2. The hook calls `walter-os pr-classify-review <pr-num>` which produces a severity-tagged finding list.
3. If gate passes:
   a. Create follow-up issue with the deferred findings (one issue per PR, not per finding).
   b. Comment on the PR with the merge decision + the follow-up issue link.
   c. Auto-resolve the MINOR/COSMETIC review threads on the PR.
   d. Invoke `gh pr merge --squash --delete-branch --admin` (assumes operator's bypass permission is configured per branch-protection).
4. If gate fails on any condition, post a comment on the PR explaining which condition blocked and remain pending.

### 4.5 `auto-merge-enabled` file format

```yaml
# auto-merge-enabled — repo opt-in to the Walter-OS severity-gate auto-merge.
# Operator declaration that this repo accepts the bounded auto-merge contract.
# Empty file = accept all defaults. Below is the full schema with defaults.

enabled: true                              # opt-out kill switch
required_review_rounds: 3                  # rounds before MINOR-only auto-merge
loc_cap:
  additions: 1500
  deletions: 500
classifier_overrides:                      # per-repo additions to the BLOCKER path list
  blocker_paths: []
  major_keywords: []
follow_up_issue:
  labels: [auto-merge-deferred, copilot-review]
  title_prefix: "[CHORE] -OPERATIONS- deferred MINORs from PR #"
audit_log:                                 # where the classifier writes its decisions
  path: ~/.config/walter-os/state/auto-merge-log.jsonl
```

Repos without this file → no auto-merge, manual operator merge as today.

### 4.6 Failure modes & guard rails

- **Misclassified MINOR that's actually MAJOR**: caught by the LLM fallback's audit log + the operator's weekly digest (see G2+ in spec §6). If discovered post-merge, the operator reverts via standard git revert and adjusts the classifier rules.
- **Classifier loops on UNCLASSIFIED → LLM cost runaway**: LLM fallback hard-caps at $0.01 per finding + $1 per PR. Above cap, defaults to MAJOR (fail-safe to "needs human").
- **Operator wants to defer a finding the classifier called MAJOR**: not allowed in the gate. Operator can adjust the keyword list in `auto-merge-enabled` for future PRs, OR manually merge this one.
- **Branch protection enforces non-bypassable rules**: gate respects them. If branch protection requires a human approval that the operator hasn't pre-authorized, gate falls back to posting a "ready for your merge" comment and stops.

## 5. Acceptance criteria

- [ ] **AC1.** `bin/walter-os pr-classify-finding <pr-num> <comment-id>` returns the severity label for a single Copilot inline comment per the §4.2 ruleset.
- [ ] **AC2.** `walter-os pr-classify-review <pr-num>` walks every inline comment on the PR and returns a JSON object `{BLOCKER: [...], MAJOR: [...], MINOR: [...], COSMETIC: [...], UNCLASSIFIED: [...]}`.
- [ ] **AC3.** Path-based BLOCKER trigger fires on every file in the AGENTS.md auto-escalation list; tested with a fixture for each path glob.
- [ ] **AC4.** Keyword-based MAJOR trigger fires on each keyword in the §4.2 list; tested with a fixture file per keyword.
- [ ] **AC5.** Doc-file MINOR vs COSMETIC bias distinguishes correctly for a 10-sample fixture (5 each).
- [ ] **AC6.** UNCLASSIFIED findings trigger the LLM fallback (validated by checking the audit log entry); cost-cap enforces fail-safe to MAJOR above $0.01.
- [ ] **AC7.** `walter-os pr-auto-merge <pr-num>` checks C1-C9 (§4.3) and returns one of `MERGE_APPROVED | MERGE_BLOCKED <reason>`. Tested with one positive fixture and one fixture per blocking condition.
- [ ] **AC8.** When MERGE_APPROVED: hook creates the follow-up issue, auto-resolves the relevant conversation threads, and invokes `gh pr merge --squash --delete-branch --admin`. Tested via mocked GitHub API.
- [ ] **AC9.** When MERGE_BLOCKED: hook posts a comment to the PR with the blocking condition + remediation guidance. Tested via mocked GitHub API.
- [ ] **AC10.** `auto-merge-enabled` file at repo root is the only opt-in mechanism. Repos without it return MERGE_BLOCKED with reason "auto-merge not enabled for this repo".
- [ ] **AC11.** AGENTS.md "Never auto-merge a PR" hard rule is amended to "Never auto-merge a PR UNLESS the bounded conditions in §X.Y are met"; new subsection links to ADR 0015.
- [ ] **AC12.** ADR 0015 documents the design choice + rejected alternatives (always auto-merge / fully manual / per-PR label / time-based auto-merge).
- [ ] **AC13.** End-to-end smoke: a sample PR with one MINOR finding + 3 completed review rounds + `auto-merge-enabled` present produces a follow-up issue, resolves the thread, and squash-merges. Tested via a dedicated `tests/e2e/auto-merge-mock-pr.bats` using a forked test repo.

## 6. Out-of-scope follow-ups (file as separate issues)

- **F1.** Operator weekly digest: "PRs auto-merged this week: N; MINOR findings created from those: M; of which closed: K". Surfaces drift before it becomes systemic.
- **F2.** Severity-gate dashboard in Control Tower with per-classifier-rule pass rate (how often did each BLOCKER trigger fire? UNCLASSIFIED rate trending up = ruleset getting stale).
- **F3.** Cross-repo rollout: `auto-merge-enabled` discoverable across the operator's repos with a `walter-os pr-auto-merge --discover` mode.
- **F4.** Reverse path: detect operator manually overriding the classifier (closing a flagged MAJOR PR without resolving) and prompt to update the ruleset.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Classifier mis-classifies a real bug as MINOR | Med | Med | Triple gate (3 rounds + LOC cap + path exclusion) + weekly digest forces visibility + operator can patch rules |
| Loop becomes ritual sans value, operator disables everything | Low | High | Telemetry shows real value; if turned off, manual merge still works |
| Codex and Copilot disagree on severity | Med | Low | Worst-of: any classifier saying BLOCKER → BLOCKER. Disagreement = upgrade severity. |
| MINOR findings accumulate invisible debt | High | Med | Auto-created follow-up issue is mandatory; >50 open follow-ups trigger an alert in the audit log |
| `auto-merge-enabled` accidentally committed by a fork | Low | Med | The file's presence is operator-intent; fork inheriting it is operator's responsibility. Worst case: the fork auto-merges its own PRs, doesn't affect upstream. |
| LLM fallback hallucinates a severity | Low | Med | Cost-cap fail-safes to MAJOR; audit log + monthly review |
| Branch-protection rule changes silently break the gate | Med | Low | Gate logs the exact GitHub API error; operator notified via the same audit log path |

## 8. Open questions for operator

- **Q1**: should COSMETIC findings skip the 3-round minimum entirely (auto-merge on first round)? Proposed: yes per §4.1, but operator's call.
- **Q2**: per-repo `auto-merge-enabled` override OR per-context (walter-os-personal vs walter-os-work) inheritance? Proposed: per-repo only (G4) — simpler, no inheritance ambiguity. Operator copies the file per repo.
- **Q3**: should the gate be allowed to convert a MAJOR finding to MINOR after the operator resolves the underlying issue (without a new finding from Copilot)? Proposed: no — operator's "resolve" via the GitHub UI is sufficient; the gate doesn't second-guess the operator.

## 9. References

- `AGENTS.md` "Universal disciplines" → "Review loop (standard pattern for every substantive PR)"
- `AGENTS.md` "Things agents must NEVER do" → "Auto-merge a PR" (will be amended per AC11)
- Closed PR #111 (`feature/agent-install-tier-completion`) — the case study that motivated this spec (24 findings across 4 rounds, all non-BLOCKER)
- Follow-up issue #112 — captures the deferred MINORs from #111 R4 + scaffolds this severity-gate work
- ADR 0009 (agent trust tiers) — similar pattern: per-agent tier configuration with override semantics
- ADR 0013 (solo-operator merge policy) — precedent for operator-configurable framework knobs
- ADR 0014 (CLI symlink path) — same review-loop case study
