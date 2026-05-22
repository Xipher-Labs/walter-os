# Implementation Plan: depersonalization-deep-cleanup

Executes against `docs/specs/depersonalization-deep-cleanup.md`.
Each task is 2-5 min for implementation + verification. All tasks follow
RED → GREEN → REFACTOR discipline.

---

## Task 1: Add depersonalization regression tests (RED phase) [AC-6]

- File: `tests/oss/depersonalization.bats` (modify)
- Change: Add four new `@test` blocks:
  - `"global AGENTS.md contains no Solana reference"` — `grep -c "Solana" AGENTS.md` returns 0
  - `"global AGENTS.md contains no OrbStack reference"` — `grep -c "OrbStack" AGENTS.md` returns 0
  - `"global AGENTS.md contains no Apple Silicon reference"` — `grep -c "Apple Silicon" AGENTS.md` returns 0
  - `"global AGENTS.md does not prescribe pnpm as global default"` — the phrase "pnpm for Node" does not appear in AGENTS.md
- Verify: `bats tests/oss/depersonalization.bats` fails on the four new tests
  (RED — AGENTS.md has not been changed yet). Existing tests still pass.

---

## Task 2: Create operator-preferences overlay example [AC-5]

- File: `contexts/_examples/operator-preferences.example.md` (new)
- Change: New file containing the toolchain preference content that will be
  removed from AGENTS.md. Include: OS and shell, package managers, editor
  setup, container runtime, secrets strategy. Use macOS/pnpm/OrbStack/Cursor
  as the concrete example values — they are useful as examples, they just must
  not live in the global contract. Include header comment directing readers to
  copy to `~/.config/walter-os/overlay/personal.env`.
- Verify: File exists. `grep -c "OrbStack" contexts/_examples/operator-preferences.example.md`
  returns > 0 (the example content is there).

---

## Task 3: Create testing strategy overlay example [AC-2]

- File: `contexts/_examples/testing-strategy.example.md` (new)
- Change: Move the full three-column testing table (Rust / systems, Next.js +
  Supabase, React Native + Solana) from AGENTS.md into this file. Add header
  explaining: "This is an example testing strategy for three project types.
  Replace with your own stack in your overlay." Keep all current rows
  including the Solana-specific rows — they are useful examples.
- Verify: File exists and contains the Solana program row. The testing strategy
  table exists in the example file with all rows intact.

---

## Task 4: Strip tooling preferences from global AGENTS.md [AC-1]

- File: `AGENTS.md` (modify)
- Change: Replace the `## Tooling preferences` section body (the six bullet
  points from "OS: macOS..." to "Testing: Vitest/Jest...") with a two-line
  callout:
  ```
  Configure your preferred OS, shell, package managers, editor, and container
  runtime in your personal overlay. See
  `contexts/_examples/operator-preferences.example.md` for a complete example.
  ```
  Keep the section header `## Tooling preferences` so the document structure
  is preserved.
- Verify: `grep -c "OrbStack\|Apple Silicon\|pnpm for Node\|Cursor primary" AGENTS.md`
  returns 0.

---

## Task 5: Strip testing strategy table from global AGENTS.md [AC-2]

- File: `AGENTS.md` (modify)
- Change: Replace the `### Testing strategy (layered)` section body (the full
  table plus the Maestro/Playwright paragraph) with a brief callout:
  ```
  Define your project-type testing matrix in your overlay. See
  `contexts/_examples/testing-strategy.example.md` for a fully worked example
  covering three project archetypes.

  **When to write tests**: superpowers' `test-driven-development` skill enforces
  RED→GREEN→REFACTOR. That is the default discipline across all project types.
  Non-unit layers (E2E, visual, mutation) run separately in CI, not in
  pre-commit (too slow).
  ```
- Verify: `grep -c "Solana\|Anchor\|solana-test-validator" AGENTS.md` returns 0.

---

## Task 6: Neutralize the auto-escalation list [AC-3]

- File: `AGENTS.md` (modify)
- Change: Replace the line:
  ```
  - Any change in `auth/`, `crypto/`, or code that moves money (Solana TX, Stripe).
  ```
  with:
  ```
  - Any change in `auth/`, `crypto/`, or code that moves money (payment
    processing, token transfers, financial APIs).
  ```
- Verify: `grep -c "Solana TX\|Stripe" AGENTS.md` returns 0.

---

## Task 7: Remove domain references from the Plugins section [AC-4]

- File: `AGENTS.md` (modify)
- Change: In the `## Plugins (required)` section, the current text says
  "Solana infrastructure, security auditing" among Walter-OS native skill
  domains. Replace this list with a generic: "domain-specific skills for
  areas such as branding, hackathons, DevRel, regulatory research, security
  auditing, and others listed in `skills/INDEX.md`."
- Verify: `grep -c "Solana infrastructure" AGENTS.md` returns 0.

---

## Task 8: Run full test suite (GREEN phase) [AC-6, AC-7]

- File: no file changes — verification step
- Change: None.
- Verify:
  - `bats tests/oss/depersonalization.bats` — all tests pass including the
    four new ones from Task 1.
  - `grep -rn "Apple Silicon\|OrbStack\|pnpm for Node\|Solana TX\|Solana infrastructure" AGENTS.md`
    returns no matches.
  - `cat AGENTS.md | grep -i "tooling preferences" -A5` shows the callout,
    not the old bullet list.

---

## Task 9: Update install.sh overlay-init callout [AC-7]

- File: `setup/personal-overlay-init.sh` (modify)
- Change: Add a line in the scaffold output that copies
  `contexts/_examples/operator-preferences.example.md` to
  `~/.config/walter-os/overlay/preferences.md.example` with a note that the
  operator should rename it and fill it in. This ensures new adopters see the
  example during their first `overlay-init` run.
- Verify: `./setup/personal-overlay-init.sh --dry-run` (if supported) shows
  the new example file in the output. Manual review of the script shows the
  copy step.

---

## Task 10: REFACTOR — review and tighten test descriptions [AC-6]

- File: `tests/oss/depersonalization.bats` (modify)
- Change: Review the four new test descriptions for clarity. Ensure each test
  has a clear failure message that tells the contributor exactly what to fix
  and where to put the content instead.
- Verify: Run `bats tests/oss/depersonalization.bats --tap` and confirm all
  test descriptions are legible in the TAP output.

---

## Completion check

All tasks done when:
- `bats tests/oss/` passes (all tests including four new ones)
- `grep -rn "Apple Silicon\|OrbStack\|Solana TX\|pnpm for Node\|Cursor primary\|Solana infrastructure" AGENTS.md` returns empty
- `contexts/_examples/operator-preferences.example.md` exists
- `contexts/_examples/testing-strategy.example.md` exists
- PR description references `Refs: docs/specs/depersonalization-deep-cleanup.md`
- DoD validator passes
