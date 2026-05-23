# Antigravity Adapter — Spec

> Closes #190.
>
> Mirrors the Cursor adapter pattern (see
> [`cursor-adapter-completion.md`](./cursor-adapter-completion.md) +
> PR #163) for Google Antigravity.

## Context

Per ADR-0020 (vendor-neutral AGENTS.md cascade), Walter-OS commits to
tool-agnosticism: every adopter should be able to use whatever AI
coding tool they prefer with the same project context. Antigravity
(Google's agentic IDE platform, GA 2025) is the next tool to add to
the supported set alongside Claude Code, Codex CLI, and Cursor.

## Research findings (2026-05-23)

Antigravity v1.20.3+ **reads `AGENTS.md` natively** at the project
root. No derived-file generation is strictly required. The adapter is
therefore **opt-in for operators who want one or more of**:

1. **Isolation from third-party `AGENTS.md` edits** — if a teammate
   edits `AGENTS.md` for non-Walter-OS reasons, the adapter file in
   `.agent/rules/walter-os.md` stays untouched as a stable Walter-OS
   mirror.
2. **Per-tool rule separation** — operators who want Antigravity-
   specific rule isolation distinct from the cascade.
3. **Nested project hierarchies** — `.agent/rules/` supplements
   per-directory `AGENTS.md` without replacing it; useful in
   monorepos where Walter-OS rules apply repo-wide while
   subdirectory-specific `AGENTS.md` files cover local concerns.

### Critical caveat — `GEMINI.md` precedence

If `GEMINI.md` exists at the project root, **Antigravity gives it
precedence over `AGENTS.md`** and silently shadows the cascade. The
adapter does NOT emit a `GEMINI.md` (which would compete with any
operator-managed one), and `walter-os doctor --antigravity` WARNs if a
stray `GEMINI.md` is present so the operator can either remove it or
merge its rules into `AGENTS.md`.

## File conventions

| Path                                       | Role                                                       | Precedence in Antigravity |
| ------------------------------------------ | ---------------------------------------------------------- | ------------------------- |
| `<repo>/GEMINI.md`                         | Antigravity-native rules                                   | **highest**               |
| `<repo>/AGENTS.md`                         | Cross-tool standard (read natively since v1.20.3)          | second                    |
| `<repo>/.agent/rules/walter-os.md`         | Walter-OS adapter (this spec — opt-in mirror of AGENTS.md) | supplements               |
| `<repo>/.agent/rules/*.md` (other)         | Operator-managed split rules                               | supplements               |
| `<repo>/src/.../AGENTS.md`                 | Nested directory-scoped rules                              | scope-local               |
| `~/.gemini/AGENTS.md` / `~/.gemini/GEMINI.md` | User-global rules                                       | apply outside repo        |

## CLI surface

### `./install.sh --antigravity-rules`

Generates `<cwd>/.agent/rules/walter-os.md` from `<cwd>/AGENTS.md`.

- Errors with exit 2 if `<cwd>/AGENTS.md` does not exist (the cascade
  needs to be installed first).
- Warns if `<cwd>/GEMINI.md` exists (would shadow AGENTS.md).
- Dry-run honoured (`--dry-run --antigravity-rules` prints intended
  actions without writing).
- Idempotent — re-running overwrites the adapter from the current
  AGENTS.md.

### `walter-os doctor --antigravity`

Reports the adapter's state. Four possible outputs (all exit 0 —
informational, not gating):

| STATUS          | Meaning                                                         |
| --------------- | --------------------------------------------------------------- |
| `NOT_GENERATED` | Adapter absent. Operator opted out, or Antigravity reads natively. |
| `PASS`          | Adapter present and the recorded SHA matches the current `AGENTS.md`. |
| `STALE`         | Adapter present but the hash is outdated. Re-run `--antigravity-rules`. |
| `WARN`          | Adapter exists but `AGENTS.md` is missing OR `GEMINI.md` shadows it. |

## Acceptance criteria

- [ ] **AC-1**: `./install.sh --antigravity-rules` flag exists + dispatches
      to a generator function. Documented in install.sh header.
- [ ] **AC-2**: Generator writes `<cwd>/.agent/rules/walter-os.md` containing
      a header, the full body of `<cwd>/AGENTS.md`, and a trailing
      `<!-- agents-md-sha256: <hex> -->` comment for staleness detection.
- [ ] **AC-3**: Generator errors with exit 2 + clear message when
      `<cwd>/AGENTS.md` is missing.
- [ ] **AC-4**: Generator warns (but does not fail) when `<cwd>/GEMINI.md`
      exists, naming the shadowing risk.
- [ ] **AC-5**: `--dry-run --antigravity-rules` prints intended
      `mkdir`/`generate` lines without writing.
- [ ] **AC-6**: `walter-os doctor --antigravity` reports each of
      `NOT_GENERATED`, `PASS`, `STALE`, and `WARN` per the table above.
- [ ] **AC-7**: `tests/install/antigravity-adapter.bats` covers the
      generator + dry-run + AGENTS.md-missing error + GEMINI.md warning.
- [ ] **AC-8**: `tests/cli/doctor-antigravity.bats` covers the four
      probe states (NOT_GENERATED, PASS, STALE, WARN-no-agents,
      WARN-gemini-collision).
- [ ] **AC-9**: README has a "Working with Antigravity" subsection
      alongside the existing tool sections (Claude Code, Codex CLI, Cursor).
- [ ] **AC-10**: `docs/specs/agents-md-cascade-spec.md` mentions
      Antigravity as a conforming consumer (since v1.20.3).
- [ ] **AC-11**: Bats covers idempotency — running `--antigravity-rules`
      twice in a row leaves the same file content (modulo timestamps,
      which we intentionally do NOT include in the output).

## Non-goals

- We do NOT emit a `GEMINI.md` — that would create a precedence
  conflict that the operator may not expect. The probe warns about
  stray operator-managed `GEMINI.md` files instead.
- We do NOT generate a `.gemini/GEMINI.md` (global user-level) — too
  invasive for an opt-in adapter; operators handle the global tier
  themselves if they want it.
- We do NOT parse / transform `AGENTS.md` content — it's copied
  verbatim. The cascade stays the single source of truth.

## License posture

This spec is published under Apache-2.0 per ADR-0018 — the contract
layer. The generated adapter file inherits the source `AGENTS.md`'s
license (which for Walter-OS is Apache-2.0).

## Operator usage

```bash
# Inside a Walter-OS-managed repo:
./install.sh --antigravity-rules

# Re-run after editing AGENTS.md:
./install.sh --antigravity-rules

# Verify state at any time:
walter-os doctor --antigravity
```

## References

- ADR-0020: vendor-neutral AGENTS.md cascade
- `docs/specs/cursor-adapter-completion.md` — sister adapter spec (PR #163)
- `docs/specs/agents-md-cascade-spec.md` — the cascade RFC
- Antigravity docs / launch:
  [Build with Antigravity (Google Developers Blog)](https://developers.googleblog.com/build-with-google-antigravity-our-new-agentic-development-platform/),
  [Customize Antigravity (Mete Atamel)](https://atamel.dev/posts/2025/11-25_customize_antigravity_rules_workflows/)
