# Walter-OS tests

Tests use [bats-core](https://bats-core.readthedocs.io/) for shell scripts.

## Run

```bash
brew install bats-core
bats tests/
```

Or run a specific suite:

```bash
bats tests/hooks/
bats tests/install/
```

## Layout

- `tests/hooks/` — pipe JSON in, assert JSON out for each hook
- `tests/install/` — install.sh exercised against a temp HOME via `--target`
- `tests/skills/` — frontmatter validation for SKILL.md files
- `tests/lib/` — shared bats helpers

## CI

CI runs the same suite via `.github/workflows/ci.yml`, plus
`shellcheck` on all shell files and a frontmatter linter on every
`SKILL.md` and subagent definition.
