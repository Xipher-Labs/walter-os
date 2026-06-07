# Semantic gates - spec

**Issue**: #229
**Roadmap item**: AD-4 in `docs/specs/autonomous-delivery-roadmap.md`
**Status**: implemented in first CLI slice

## Problem

Walter-OS has strong syntactic hooks and a Definition of Done checklist, but
the autonomous delivery roadmap needs an executable way to ask whether a spec
is ready for implementation. A PR can include a Markdown spec, ACs, and tests
while still being weak: ACs may be vague, architecture review may be absent, or
tests may not reference the spec they are supposed to prove.

## Non-goals

- Replacing human architecture approval.
- Scoring PR readiness; `walter-os pr-score` owns the broader PR score.
- Relaxing `approval-gate.sh` hard limits or any repo-config human approval
  floor.
- Proving full business correctness from text alone.

## Decisions

| Decision | Rationale |
|---|---|
| Ship a CLI gate before automation wiring. | Operators and CI can adopt the checks incrementally. |
| Use conservative text heuristics. | This catches missing evidence without pretending to understand every domain. |
| Keep the gate independent of `approval-gate.sh`. | Semantic readiness must compose with the hard safety floor, not bypass it. |
| Require test files to reference the spec path. | This makes AC-to-test evidence discoverable during review. |

## Architecture review

`walter-os semantic-gates` is a read-only CLI subcommand. It takes a spec path,
derives the repository root or accepts `--repo`, then evaluates four named
gates:

- `spec-completeness`: required problem/context, non-goals, acceptance
  criteria, and test/verification sections.
- `ac-testability`: checkbox AC bullets must use observable verification
  language such as verify, assert, pass, fail, emit, block, return, record,
  create, update, validate, render, link, or include.
- `architecture-review`: the spec must include architecture, decisions, risks,
  threat model, or explicit review evidence.
- `test-relevance`: at least one test file under `tests/` or `--tests-dir`
  must reference the spec path.

Plain output is human-readable. `--json` emits machine-readable status and gate
evidence for future review automation.

## Acceptance criteria

- [ ] AC-1: `walter-os semantic-gates <spec> --repo <dir>` exits 0 and reports
  all four gates as pass for a complete spec with a referencing test.
- [ ] AC-2: The command exits 1 and reports `spec-completeness: fail` when the
  acceptance criteria section is missing.
- [ ] AC-3: The command exits 1 and reports `ac-testability: fail` when AC
  bullets do not include observable verification language.
- [ ] AC-4: The command exits 1 and reports `test-relevance: fail` when no test
  file references the spec path.
- [ ] AC-5: `--json` emits machine-readable gate results that tests can assert
  with `jq`.

## Test plan

- `bats tests/cli/semantic-gates.bats`
- `bash -n scripts/walter/subcommands/semantic-gates.sh`
- `shellcheck -e SC2155,SC1091,SC1083,SC2317,SC2329 scripts/walter/subcommands/semantic-gates.sh`
- `walter-os semantic-gates docs/specs/semantic-gates.md --repo .`

## Refs

- `docs/specs/autonomous-delivery-roadmap.md` AD-4
- Issue #229
