# W-3: Project Pivot Skill

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-11
**Parent**: `docs/specs/phase-w-overview.md`

## Problem

Walter-OS ships with context overlays for example work org (Solana RPC), example civic app
(Argentine procurement), and example medical app (medical records). These are operator-specific
and will be moved out of the OSS core in W-5. But even after W-5, a new adopter
needs to answer the question: "how do I configure Walter-OS for my specific domain
and compliance regime?"

The original plan was to ship a set of fixed industry templates (fintech template,
healthcare template, e-commerce template, etc.). Fixed templates have two problems.
First, they require maintenance — every time AGENTS.md evolves or new capabilities
land in Walter-OS, all templates need updating. Second, they force the operator into
one of N predefined buckets. The real space of domains, compliance regimes, team
contexts, and project types is too large for a template library to cover usefully.

A skill that conducts a short guided interview and derives the configuration at
runtime is more maintainable, more flexible, and actually produces a configuration
tailored to the operator rather than a generic approximation.

## Proposed solution

A single skill `project-pivot` at `skills/project-pivot/SKILL.md` that the LLM
invokes when an operator runs `walter pivot` or `walter new project --interactive`.
The skill drives a 4-question interview (domain, compliance regime, data sensitivity,
project type) and uses the answers to construct four outputs: a scoped AGENTS.md
draft, a recommended hook list, a recommended MCP list, and a compliance checklist.

Crucially, the skill uses only general international frameworks for compliance
(GDPR, HIPAA, PCI-DSS, SOC2, ISO 27001, best-practices). No country-specific law
references are hardcoded. If an operator answers "I need Argentine procurement law
compliance", the skill's response is to recommend the `regulatory-research-*` skill
family (parameterized) and flag it as an open question to resolve in the spec — it
does not pretend to know Argentine law.

## Acceptance Criteria

- [AC-1] `skills/project-pivot/SKILL.md` exists and the LLM correctly parses it
  as a skill invocable from `walter pivot`.
- [AC-2] The skill asks exactly four questions in order: (1) domain/industry,
  (2) compliance regime (multi-select from: GDPR / HIPAA / PCI-DSS / SOC2 /
  ISO 27001 / best-practices / other — with free-text for "other"),
  (3) data sensitivity (none / internal / personal / sensitive-health / financial /
  mixed — where `mixed` means multiple categories apply and requires the union of
  all applicable controls; `mixed` containing health data triggers the same
  PHI local-routing requirement as `sensitive-health`),
  (4) project type (personal / commercial / hackathon / oss-contribution).
- [AC-3] For at least four representative combinations (see test matrix below),
  the skill produces: (a) an AGENTS.md draft with non-empty `## Hard rules` and
  `## Skill loading` sections, (b) a non-empty recommended hooks list, (c) a
  non-empty MCP recommendations section, (d) a compliance checklist with at
  least 3 items.
- [AC-4] The skill never outputs any country-specific law name (e.g., "Ley 26.529",
  "CCPA", "PIPEDA"). If an operator's answer implies a specific jurisdiction,
  the skill outputs a recommendation to consult the `regulatory-research-*` skill
  family and leaves the specific legal text as a placeholder.
- [AC-5] Data sensitivity answer of "sensitive-health" always produces: local-only
  data tag in AGENTS.md, `medical-data-compliance` skill in loading list, and
  a compliance checklist item requiring local LLM routing for PHI.
- [AC-6] Data sensitivity answer of "financial" always produces: `web-security-baseline`
  and either `pci-dss-checklist` (if PCI-DSS selected) or `security-audit` skill
  in loading list.
- [AC-7] Bats tests in `tests/skills/pivot.bats` mock the LLM responses for 4
  representative combinations and assert each output section is present and
  non-empty. Test combinations:
  - fintech + PCI-DSS + financial + commercial
  - healthcare + HIPAA + sensitive-health + commercial
  - devtools + best-practices + internal + oss-contribution
  - generic + GDPR + personal + personal

## Non-goals

- Generating complete, production-ready AGENTS.md files: the output is a draft
  the operator is expected to review and edit. The skill makes no claim that
  the output is legally sufficient.
- Multi-turn editing: the pivot interview is a single forward pass. Editing
  the output is the operator's job in their editor.
- Industry templates as static files: this spec explicitly replaces that approach.

## Open questions

- Should the compliance checklist be inline in the AGENTS.md draft or a
  separate output section? Spec says separate section labeled `## Compliance
  Checklist` so it can be stripped before committing AGENTS.md to the repo.
- The four questions may not be enough for complex setups (e.g., a platform
  that handles both financial and health data). The skill should note when
  multiple sensitivity levels apply and produce the union of their requirements.
  This is a skill behavior specification, not a question — flagged for the
  implementer to handle.

## Implementation plan

### Task 1: Write `skills/project-pivot/SKILL.md` [AC-1, AC-2]
- File: `skills/project-pivot/SKILL.md` (new)
- Change: Skill definition. Interview protocol: 4 questions in order with
  defined answer options. Output format spec: AGENTS.md draft section,
  recommended hooks section, MCP recommendations section, compliance
  checklist section. Constraint section: no country-specific law names.
- Verify: File exists. `walter explain project-pivot` returns non-empty output.

### Task 2: Implement compliance framework mapping [AC-3, AC-5, AC-6]
- File: `skills/project-pivot/SKILL.md` (modify)
- Change: Embed a mapping table in the skill that the LLM uses to derive
  outputs. Format: domain × compliance × data-sensitivity → hooks, MCPs,
  AGENTS.md sections. This is skill-level declarative logic, not code.
- Verify: Running skill with mocked responses produces all four output sections.

### Task 3: Implement local-only routing rule [AC-5]
- File: `skills/project-pivot/SKILL.md` (modify)
- Change: When data-sensitivity=sensitive-health, the skill adds to AGENTS.md
  draft: `NEVER send data tagged PHI to external APIs. Route to local Ollama
  only.` and adds `medical-data-compliance` to `## Skill loading`.
- Verify: Mock test with sensitive-health asserts these strings appear in output.

### Task 4: Write `tests/skills/pivot.bats` [AC-7]
- File: `tests/skills/pivot.bats` (new)
- Change: 4 bats test cases, one per combination in the test matrix. Each
  case invokes `walter pivot` with `WALTER_LLM_MOCK_FILE` pointing to a
  fixture that simulates the 4 interview answers and the skill output. Asserts
  presence of required output sections.
- Verify: `bats tests/skills/pivot.bats` passes with no LLM credentials.

### Task 5: Verify no country-specific law names in skill output [AC-4]
- File: `tests/skills/pivot.bats` (modify)
- Change: Add assertion that fixtures and skill SKILL.md do not contain
  country-specific law name patterns (regex: `Ley \d+|CCPA|PIPEDA|LGPD` etc.).
  This is a static grep test, not an LLM test.
- Verify: Test passes on the committed SKILL.md.

## References

- `skills/regulatory-research-argentina/SKILL.md` — example of country-specific
  skill (to be parameterized in W-5)
- `skills/medical-data-compliance/SKILL.md` — compliance skill triggered by
  sensitive-health data type
- `docs/specs/phase-w-2-cli-ai.md` — CLI integration that invokes this skill
- `docs/specs/phase-w-5-depersonalization.md` — context that removes the
  fixed templates this skill replaces
