# Testing Strategy — Example

> **How to use this file**: this is a *worked example* of the testing matrix
> Walter-OS recommends, drawn from one operator's three primary project
> archetypes. Walter-OS does NOT prescribe these archetypes in its global
> contract — replace with your own stack in your overlay or context-specific
> `AGENTS.md`.
>
> What the global contract DOES enforce: TDD discipline (RED → GREEN →
> REFACTOR via the `test-driven-development` skill from `obra/superpowers`).
> The table below is one operator's mapping of that discipline onto concrete
> tools. Yours will differ.

## Three-archetype example matrix

Applicable test layers by project type:

| Layer | Rust / systems | Next.js + Supabase | React Native + Solana |
|---|---|---|---|
| Unit | `cargo test` | `vitest` | `vitest` + `cargo test` (programs) |
| Integration | solana-test-validator + fixtures | Supabase staging + Drizzle | local validator + RN dev mode |
| E2E web | n/a | **Playwright** (MCP) | n/a |
| E2E mobile | n/a | n/a | **Maestro** (MCP) |
| Visual regression | n/a | Chromatic / Percy / Playwright snapshots | same |
| Property-based | `proptest` | `fast-check` | both |
| Mutation | `cargo-mutants` | `stryker` | both |
| Load / perf | criterion + custom harness | k6 | n/a |
| Solana program | `anchor test` + `solana-program-test` | n/a | `anchor test` |

**Maestro vs Playwright**: they do not replace each other. Maestro is excellent
for mobile (YAML flows, realistic gestures, easy maintenance). Playwright is
better for web (granular DOM control, network interception, visual diffs).
Projects with both a React Native app and a web portal need both.

## When to write tests (universal — applies regardless of stack)

The `test-driven-development` skill (from `obra/superpowers`) enforces
RED → GREEN → REFACTOR for every code change. That is the default discipline
across all project types and is part of the Walter-OS contract.

Non-unit layers (E2E, visual regression, mutation) typically run separately
in CI rather than pre-commit because they are slow. The split is a per-
project decision documented in the project's own `README.md` or
`CONTRIBUTING.md`, not in the global `AGENTS.md`.

## How to adapt this for your stack

1. Copy this file's table into your overlay or your project's `CONTRIBUTING.md`.
2. Replace the three archetype columns with the project types you actually
   maintain (e.g., "Django + Postgres", "Go microservices", "Elixir Phoenix").
3. Drop the rows that don't apply.
4. Add layers you care about that aren't listed (security scanning, fuzzing,
   contract testing, accessibility, internationalization).
5. Reference the result from your context-specific `AGENTS.md`:
   `See contexts/work/testing.md for the project-type matrix.`

The global `AGENTS.md` stays archetype-agnostic and points operators to
this file (or their own copy of it) as an example.
