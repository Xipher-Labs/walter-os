# Codex Approval Policy Compatibility

## Problem

Walter-OS generates `~/.codex/config.toml` from
`setup/codex-config.toml.example`. The template still uses older approval policy
names, including `untrusted`, which newer Codex releases reject during startup.
That can leave Codex unable to load after `install.sh --upgrade` regenerates the
config.

## Decision

Use `approval_policy = "on-request"` as the Walter-OS default. This matches the
current Codex approval mode that keeps operator review available without relying
on deprecated policy names.

## Acceptance Criteria

- `setup/codex-config.toml.example` uses `approval_policy = "on-request"`.
- The template no longer contains deprecated approval policy names.
- The template parses as valid TOML.
- Existing MCP config generation behavior is unchanged.

## Non-goals

- Do not change the sandbox mode default.
- Do not rewrite existing operator-specific Codex project trust entries.
- Do not alter MCP server generation in this fix.

## Plan

1. Update the Codex config template approval policy comments and value.
2. Add a Bats regression test for deprecated policy names and TOML parsing.
3. Run the new test and existing MCP generator tests.
