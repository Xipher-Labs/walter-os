# Implementation Plan: walter-os-lite-entry-tier

Executes against `docs/specs/walter-os-lite-entry-tier.md`.

---

## Task 1: Write lite-format bats tests (RED phase) [AC-7]

- File: `tests/oss/lite-format.bats` (new)
- Change: Three `@test` blocks:
  - `"lite.md contains exactly one fenced block"` — counts ` ``` ` delimiters
  - `"lite.md fenced block is under 600 lines"` — wc -l on extracted block
  - `"lite.md fenced block contains no tool-requiring shell commands"` — grep
    for patterns like `brew install`, `apt-get`, `pip install`, `npm install`,
    `curl`, `wget` inside the block
- Verify: `bats tests/oss/lite-format.bats` fails (RED — `setup/agent-install/lite.md`
  does not exist yet).

---

## Task 2: Write `setup/agent-install/lite.md` [AC-1, AC-2, AC-3]

- File: `setup/agent-install/lite.md` (new)
- Change: Create the file. The fenced block must contain:
  1. A short preamble (≤3 sentences) telling the agent what disciplines to
     activate for this session.
  2. The rigor-classification rule (tiny/small/major criteria, abbreviated).
  3. The conventional commit format rule.
  4. The branch-flow rule (feature/<slug> → main; no push to main).
  5. The TDD gate rule (RED → GREEN → REFACTOR; skipping RED is a violation).
  6. The single-round self-review checklist (≤5 items).
  7. The upgrade callout: "To make these disciplines permanent, use Tier I:
     paste `setup/agent-install/tier-1.md` into this session."
  The block must be self-contained with no shell commands, no external URLs
  required to fetch, no file reads.
- Verify: `bats tests/oss/lite-format.bats` passes all three tests (GREEN).

---

## Task 3: Write `setup/agent-install/lite-persist.md` [AC-4]

- File: `setup/agent-install/lite-persist.md` (new)
- Change: Create the file. Its fenced block does two things when pasted:
  1. Writes `.walter-os-lite/AGENTS.md` into the current directory with the
     same discipline content as `lite.md`.
  2. Adds `.walter-os-lite/` to `.gitignore` in the current repo (or notes
     that the operator should do so if .gitignore is not writable by the agent).
  The fenced block makes clear: "This is a session-persistent Lite install.
  For a permanent, repo-wide install, use Tier I."
- Verify: Reading `setup/agent-install/lite-persist.md` — the fenced block
  contains the gitignore step and creates the `.walter-os-lite/AGENTS.md`
  path.

---

## Task 4: Add `doctor --lite` subcommand [AC-6]

- File: `bin/walter-os` (modify)
- Change: In the `cmd_doctor()` function, handle a `--lite` flag. When
  `--lite` is passed:
  - Check if `.walter-os-lite/AGENTS.md` exists in the current directory.
  - If yes: print PASS + list the disciplines found (parse the headings).
  - If no: print NONE + print the one-liner: "Run `setup/agent-install/lite.md`
    to install the Lite contract in this session."
- Verify: `bin/walter-os doctor --lite` returns exit 0 when
  `.walter-os-lite/AGENTS.md` exists, exit 1 when it does not.

---

## Task 5: Restructure README install section [AC-5]

- File: `README.md` (modify — "Install via agent (Tier I → IV)" section)
- Change: Add a new `### Walter-OS Lite — start here` subsection BEFORE the
  Tier I-IV table. The subsection contains:
  - One-line pitch: "Start here. No install. 30 seconds."
  - One-paragraph description: paste the fenced block from
    `setup/agent-install/lite.md` into Claude Code or Codex CLI, and you get
    Walter-OS disciplines for this session.
  - A prominent link: "Ready to make it permanent? Use Tier I:"
  - Then the existing Tier I-IV table follows.
- Verify: Reading the README — the Lite section appears above the tier table.
  The tier table remains intact.

---

## Task 6: REFACTOR — tighten Lite prompt content [AC-2]

- File: `setup/agent-install/lite.md` (modify)
- Change: Count tokens in the fenced block using a rough estimate (characters
  / 4). If over 500 tokens, trim: shorten the rigor criteria examples, reduce
  self-review checklist to 4 items. Preserve all six discipline categories.
- Verify: Rough token estimate ≤ 500. `bats tests/oss/lite-format.bats` still
  passes.

---

## Completion check

All tasks done when:
- `bats tests/oss/lite-format.bats` passes (3/3 tests)
- `setup/agent-install/lite.md` exists with single fenced block
- `setup/agent-install/lite-persist.md` exists
- `bin/walter-os doctor --lite` works
- README has Lite section above Tier table
- DoD validator passes
