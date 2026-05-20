---
name: pr-review
description: Run a rigorous, multi-dimensional review checklist on any pull request before opening, merging, or after receiving review comments. Use this skill ALWAYS before opening a PR, when asked to "review this PR/branch/diff", "check my changes", "is this ready to merge", or before promoting a branch from dev to staging or staging to main. Goes beyond style — checks security, performance, testing rigor, supply chain, and Definition of Done coverage.
---

# Pull Request Review

This is the rubric. Apply it to every PR before opening and again before
merging. The reviewer subagent uses this checklist with read-only tools
(`Read`, `Grep`, `Glob`).

## Required before opening a PR

- [ ] **PR title validated**: run `./hooks/pr-title-validator.sh "$TITLE"` before
      calling `gh pr create`. If exit != 0, fix the title — do not proceed.
      Format: `[TYPE] -CATEGORY- title` (see CONTRIBUTING.md -> "Title convention").
- [ ] Spec exists at `docs/specs/<slug>.md` and is current
- [ ] Plan exists at `docs/specs/<slug>.plan.md` and matches the diff
- [ ] All acceptance criteria in spec map to ≥1 test
- [ ] Tests pass locally on the latest commit: unit, integration, e2e
- [ ] Lint passes: language formatter + linter
- [ ] Typecheck passes (TS strict, mypy strict, cargo check, etc.)
- [ ] No `.only`, `.skip`, `xit`, `xdescribe`, `#[ignore]` left
- [ ] No `console.log`, `println!()`, `print()`, `dbg!()` debugging artifacts
- [ ] No secrets in diff (grep for typical key prefixes)
- [ ] No commented-out code blocks (delete or commit-message it)
- [ ] Branch flow respected: feature/* → main (single-tier per ADR 0013)
- [ ] Commit messages follow conventional commits
- [ ] PR description references spec and ticket (`Refs: docs/specs/...`,
      `Closes TRI-NNN`)

## Code review dimensions

For every changed file, check each dimension. Score 0 (clean), 1 (minor),
2 (blocking).

### 1. Correctness

- Edge cases: empty, null, single element, max size, unicode, negative,
  zero, NaN, very large, concurrent access.
- Off-by-one in loops and slicing.
- Time and timezone: anywhere `now()`, `Date`, `chrono`, ensure UTC at
  storage boundary, render in user TZ.
- Number precision: `f64` for money is wrong; use integer cents or BigInt.
  For Solana lamports, always integer.
- Async correctness: every `await`/`?` checked, no swallowed errors,
  cancellation handled.

### 2. Security

- Input validation at trust boundaries (HTTP, RPC, file, IPC).
- Output encoding: HTML-escape, JSON-encode, SQL-parameterize. No string
  concat into queries.
- AuthN before AuthZ. AuthZ before any data return.
- No secrets in logs, even at debug level. No PII either (especially for
  [Project B]).
- Crypto: use library primitives; never roll your own. Constant-time
  comparison for sensitive checks.
- For Solana code: signer checks on every account that should be signed,
  owner checks on every PDA, account discriminator validation.
- Dependencies: any new `npm`/`cargo`/`pip` dep in this PR? Check it via
  `daily-supply-chain-audit` script: `walter-os audit-pkg <name@version>`.

### 3. Performance

- Anything in a hot path (request handler, message loop, gRPC stream)
  must avoid: allocations per call, unbounded loops, blocking I/O on
  the async runtime, unbounded channels.
- Database: every query has an explained index path. N+1 queries get
  flagged. Migrations pre-checked on staging dataset size.
- For Yellowstone/Geyser code: profile before merging anything in the
  per-message critical path. Submit a flamegraph in the PR if changes
  the path.

### 4. Testing rigor

- Tests aren't just present — they actually fail when mutated.
- Assertions are specific (`toBe(42)`, not `toBeTruthy()`).
- Each test asserts one thing (or one tightly grouped behavior).
- Test names describe behavior, not implementation.
- Slow tests (>100ms unit, >1s integration) flagged.

### 5. Readability

- Function name says what it does, not how.
- Function length: >50 lines is suspect, >100 is blocking.
- Cyclomatic complexity: >10 is suspect, >15 blocking.
- Comments explain *why*, not *what*. Code that needs a "what" comment
  should be refactored into a well-named function.
- Public APIs documented with examples.

### 6. Backward compatibility

- API change? Versioned or deprecated, not removed.
- DB migration? Reversible. Tested on staging before main.
- Config schema change? Old values still read with sensible defaults
  for one release cycle.

### 7. Operational

- New env var? Documented in `.env.example` and `docs/operations.md`.
- New external dependency (DB, queue, API)? Failure mode considered.
  Circuit breaker or retry-with-backoff if appropriate.
- New scheduled job? Idempotent. Logged with structured fields.
- Observability: any new code path that fails silently is a bug. Add
  metrics or logs.

## Blocking findings template

When you find a blocking issue, write a comment in this format:

```
**[BLOCKING] <one-line summary>**

Where: `path/to/file.ts:42-58`
What: <specific problem, one paragraph>
Why blocking: <which dimension above + impact>
Fix: <suggested concrete change, code if short>
```

## Approval criteria

PR approved when:

- All blocking findings resolved (not just acknowledged — actually fixed).
- All non-blocking findings either fixed or explicitly acked in PR
  comment with reasoning.
- The reviewer's confidence: "I would deploy this myself, on a Friday."
  If not, keep iterating.

## Iteration limits

- Minimum: 2 review rounds (the reviewer subagent + Copilot).
- Maximum: 5 rounds. After 5, escalate to operator. Either the spec is
  unclear, the implementer has wrong context, or the change is too big
  for one PR (split it).

## What this skill does NOT do

- Replace architectural review. Big design decisions require operator
  input via the `architect` subagent before any code is written.
- Replace human review on [Company] work. The work context disables
  auto-PR for that reason.
- Catch subtle business-logic bugs in domains the reviewer doesn't
  understand. For [Project A] (procurement law) and [Project B] (medical
  compliance), invoke domain-specific subagents.
