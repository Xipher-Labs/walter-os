---
name: definition-of-done-validator
description: Verify that every acceptance criterion declared in a feature spec has at least one corresponding test, and that business workflow tests exist for personal projects ([Project A], [Project B]). Use this skill before opening a PR, before promoting a branch from dev to staging, when the user asks "is this done", "did I cover all the acceptance criteria", "are the tests sufficient", or as a final gate after the implementation phase. Refuses to approve a PR if any criterion is uncovered.
---

# Definition of Done Validator

The check that prevents the classic "tests pass but the feature is wrong"
trap. Bridges spec to tests. Runs as the final gate before PR creation.

## What "done" means in Walter-OS

A task is done only when:

1. The spec at `docs/specs/<slug>.md` declares acceptance criteria.
2. Every criterion has ≥1 test that demonstrably verifies it.
3. For personal projects in regulated domains ([Project A], [Project B]),
   a business-workflow test exists in `tests/business/<project>/`.
4. All tests pass.

This skill validates 1–3. The test runner validates 4.

## Spec format expected

Specs declare criteria in a parseable section:

```markdown
## Acceptance Criteria

- [AC-1] Logged-in user can submit a tender bid via the dashboard.
- [AC-2] Bids submitted within 60s of deadline are accepted; later bids rejected with code TENDER_CLOSED.
- [AC-3] Each bid generates a Solana transaction containing the bid hash; tx signature stored in `bid.tx_sig`.
- [AC-4] Audit log contains: timestamp, user_id, tender_id, bid_hash, tx_sig.
```

Format rules:
- Each criterion on its own line, prefixed `- [AC-N]`.
- IDs unique within the spec (not globally).
- Stated as observable behavior, not implementation.
- Bad: "use the `submitBid()` function" — that's how, not what.
- Good: "user can submit a bid; system records it" — observable.

## Coverage mapping

Tests declare which AC they cover via marker comments:

```typescript
// tests/tender-submission.test.ts
describe('tender submission [AC-1, AC-2]', () => {
  it('accepts bid before deadline [AC-1]', () => { ... });
  it('rejects bid after deadline with TENDER_CLOSED [AC-2]', () => { ... });
});
```

```rust
/// Covers: AC-3
#[test]
fn bid_generates_solana_tx_with_hash() { ... }
```

```python
# AC: AC-4
def test_audit_log_contains_required_fields(): ...
```

The validator parses these markers and builds a coverage map.

## Validation algorithm

1. Parse spec at `docs/specs/<slug>.md`. If missing, **block** with "spec required".
2. Extract criteria set `S = {AC-1, ..., AC-N}` from `## Acceptance Criteria`.
3. Walk `tests/`, `__tests__/`, `*_test.go`, etc. Extract all marker
   references → coverage map `C: AC → [test files]`.
4. Compute uncovered set `U = S - keys(C)`.
5. If `|U| > 0`, **block** and print uncovered criteria.
6. For each covered AC, sanity-check that the test asserts something
   (not just `expect(true).toBe(true)`).
7. For projects in `personal/{[project-a],[project-b]}/`, additionally require
   `tests/business/<project>/` directory exists and has ≥1 test.

## Output

```
✅ Spec: docs/specs/tender-submission.md (4 criteria)
✅ AC-1 covered by tests/tender-submission.test.ts:5
✅ AC-2 covered by tests/tender-submission.test.ts:11
✅ AC-3 covered by tests/solana-bid-tx.test.ts:3
✅ AC-4 covered by tests/audit-log.test.ts:8
✅ Business workflow tests: tests/business/[project-a]/ (3 tests)

Definition of Done: PASS
```

Or:

```
❌ AC-2 NOT COVERED — no test references this criterion
❌ AC-4 has weak assertion: expect(log).toBeDefined() — strengthen

Definition of Done: BLOCKED
Action: Add tests covering AC-2 and AC-4 (or remove from spec if no longer required)
```

## Edge cases

- **Spec evolved mid-implementation**: criteria added that don't have tests
  yet. Block with the new uncovered list. Either implement the criteria or
  remove them from the spec.
- **Dead criteria**: criteria removed from spec but tests still reference
  them. Warn (not block). Suggest test cleanup.
- **Implicit coverage**: a test asserts something that "kind of" covers an
  AC but doesn't reference it. Block — make the link explicit.

## When to skip this check

Almost never. Specific exceptions:

- **Refactor PRs**: behavior unchanged, no spec needed. Use commit
  prefix `refactor:` and the validator skips. Reviewer must confirm
  no behavior changed.
- **Documentation-only PRs**: `docs:` prefix, validator skips.
- **Hotfix to main**: validator runs but doesn't block. Postmortem
  must add the missing test within 48h.

## Integration

- Invoked by the `pr-review` skill before approving a PR.
- Invoked by the `/pr` slash command before opening a PR.
- The `branch-flow-guard.sh` hook blocks direct pushes to protected
  branches in both modes. Per ADR 0013 it also gates PR base
  branches when `WALTER_BRANCH_FLOW=three-stage` is set; default
  (`single-tier`) accepts `feature/<slug>` → `main` directly.
