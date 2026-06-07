# Bats CI Suites

Walter-OS keeps the historical required check name `bats hooks tests`, but the
actual Bats workload is split into parallel `bats suite (...)` jobs. The
required job is an aggregator that fails if any split suite fails.

This preserves branch-protection compatibility while avoiding a single opaque
job that serializes every Bats test in the repository.

## Suite Ownership

| Suite | Paths |
| --- | --- |
| `hooks` | `tests/hooks/`, `tests/cloudflare/` |
| `agents-and-skills` | `tests/agents/`, `tests/skills/` |
| `wiki-and-observability` | `tests/wiki/`, `tests/litellm/`, `tests/walter-bridge/` |
| `cli-and-walter` | `tests/cli/`, `tests/walter/` |
| `oss-audit-and-github` | `tests/oss/`, `tests/audit/`, `tests/github-actions/` |
| `compose-and-services` | `tests/compose/`, `tests/walter-host/`, `tests/services/` |
| `install-contracts` | Individual install and script contract `.bats` files |

## Rules For New Tests

- Add new Bats files to the suite that owns the behavior, not to the aggregator.
- Keep the `bats hooks tests` aggregator job name stable unless branch
  protection is updated at the same time.
- Use per-suite timeouts so a hung test fails with a focused job name.
- Prefer adding a new suite over growing an unrelated suite when ownership is
  unclear.
