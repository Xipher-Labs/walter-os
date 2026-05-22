# Walter-OS OSS-Readiness Roadmap

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-21
**Branch**: feature/oss-readiness-roadmap

---

## Audit verification

Before writing anything prescriptive, the architect read the actual files.
This section quotes what is true, calls out where the audit over- or
under-stated the finding, and sets the factual baseline for the workstreams
that follow.

### Audit claim 1: Incomplete depersonalization — PARTIALLY CONFIRMED

The external audit stated that AGENTS.md still carries operator-personal
preferences presented as framework defaults.

Reading `AGENTS.md` confirmed the following verbatim lines exist:

**Tooling preferences section (lines 474-479):**
```
- **OS**: macOS (Apple Silicon), zsh.
- **Package managers**: `pnpm` for Node, `uv` for Python, `cargo` for Rust.
- **Editors**: Cursor primary; Claude Code in terminal for agentic work; Codex CLI
  for second-opinion reviews and GPT-5.5 access.
- **Containers**: OrbStack on Mac (faster than Docker Desktop). On Linux: native
  Docker.
```

**Testing strategy table (lines 373-383):** The table uses three fixed column
headers — "Rust / systems", "Next.js + Supabase", and "React Native + Solana"
— as if these are the only three project archetypes a Walter-OS adopter would
have. Solana and Anchor appear as first-class entries in this table. The
specific lines:
```
| Layer | Rust / systems | Next.js + Supabase | React Native + Solana |
| Integration | solana-test-validator + fixtures | ... | local validator + RN dev mode |
| Solana program | `anchor test` + `solana-program-test` | n/a | `anchor test` |
```

**Auto-escalate list (line 90):**
```
- Any change in `auth/`, `crypto/`, or code that moves money (Solana TX, Stripe).
```

**Skills section (line 72):** Walter-OS native skills include references to
"Solana infrastructure" as a listed domain.

**Calibration note:** The audit said the tone is "this is my setup, consider
it" — this is accurate but partly mitigated. The `## Operator profile` section
now has a prominent HTML comment instructing adopters to replace it with their
own content (lines 9-23), and it includes a call to `setup/personal-overlay-init.sh`.
The issue is that the rest of AGENTS.md below the profile section still presents
the operator's specific toolchain as the global default. An adopter who skips the
overlay init step inherits macOS/Apple Silicon/OrbStack/Solana as their agent's
assumed environment.

**Also confirmed:** `skills/solana-rpc-review/SKILL.md` and
`skills/solana-program-review/SKILL.md` and
`skills/regulatory-research-argentina/SKILL.md` exist in the skills library with
no note that they are operator-specific and not universally applicable.

**Verdict:** Confirmed with nuance. The overlay mechanism exists and is
documented; the operator-profile placeholder comment is in place. But the
body of AGENTS.md below the profile still carries hardcoded stack preferences
(macOS, OrbStack, Cursor-primary, pnpm, Solana/Anchor) that should be in an
overlay example, not the framework contract.

---

### Audit claim 2: Layer coupling — Council requires walter-host — CONFIRMED WITH CONTEXT

The audit stated that the Council requires `COUNCIL_LITELLM_KEY` +
`COUNCIL_PLANE_TOKEN`, which pushes toward deploying LiteLLM + Plane (i.e.,
walter-host).

Confirmed. `README.md` lines 1241-1242 state:
```bash
# In .env.local on the VM:
COUNCIL_LITELLM_KEY=<your-litellm-master-key>
COUNCIL_PLANE_TOKEN=<your-plane-api-token>
```
And line 1684 in the README's known-limitations section confirms:
```
- **Walter Council requires Plane**: the Council agents use Plane as their
  task source. If Plane is not configured, the Council has no work queue.
```

**Calibration note:** The README is honest about this — it says "Council
requires Plane" explicitly. The narrative tension the audit identified is real:
the README presents walter-host as optional ("most adopters never deploy it")
while the most interesting agentic feature (the Council) requires two services
from that stack. This is not a lie, but it is a friction point for potential
adopters who want the Council without the full VM deployment.

**Verdict:** Confirmed. The coupling is documented but not designed away. The
audit correctly identified it as a narrative inconsistency that reduces
credibility.

---

### Audit claim 3: report.log in repo root — CONFIRMED

`report.log` exists at the repository root. `grep -r "report.log"` found no
matches in any `.gitignore`, meaning it is a tracked file (or at minimum
untracked and not ignored). The `.gitignore` file does not list `*.log` or
`report.log`.

This is exactly as described: a log file committed at (or left untracked in)
the repo root on a project that predicates disciplined hygiene.

**Verdict:** Confirmed.

---

## Problem

Walter-OS at v0.4.5-alpha has solid architectural foundations — a layered
AGENTS.md cascade, an overlay system, hooks, a skills library, a Council of
agents, and a 4-tier install path. However, it cannot yet claim "ready for
serious OSS adoption" for three interconnected reasons.

First, the depersonalization work done through v0.3.0 and v0.4.0 was
structural (overlay system, examples directory, context templates) but did not
complete the final pass on the global `AGENTS.md` itself. The framework's
canonical contract still encodes one operator's preferred OS (macOS Apple
Silicon), package manager (pnpm), editor setup (Cursor-primary), container
runtime (OrbStack), and domain-specific tools (Solana/Anchor/Stripe) as if
they are universal defaults. A new adopter who clones the repo and reads
`AGENTS.md` inherits these as their agent's working assumptions unless they
already know to configure an overlay.

Second, the entry story is too complex. Tier I through Tier IV is well-designed,
but the README buries Tier I — the $0, 5-minute path that delivers real value
with no VM and no Docker — under a long narrative. Tier I should be the hero.
The repo also lacks a sub-tier "Lite" experience: a single file an adopter can
drop into any Claude Code or Codex CLI session to get Walter-OS disciplines
without installing anything.

Third, the Cursor adapter remains backlog. Cursor is the majority-market
AI-enabled editor. "Wire Cursor rules manually" is documented in three places
as backlog work, and it has been since at least v0.2.0. As long as it stays
there, Cursor users are second-class citizens.

Two adjacent strategic concerns (licensing for the IdeaOS future, and whether
to split the repo) require architectural decisions captured in ADRs but do not
require immediate implementation work.

---

## Workstreams

### Classification

| Workstream | Rigor | Sprint | Blocks |
|---|---|---|---|
| WS-1 Depersonalization deep cleanup | major | 1 | WS-5, WS-7 |
| WS-2 Walter-OS Lite entry tier | major | 1 | — |
| WS-3 Cursor adapter completion | major | 2 | — |
| WS-4 report.log removal + .gitignore | tiny | 1 (do first) | — |
| WS-5 Cascade spec as public standard | major | 3 | WS-1 |
| WS-6 Review loop as GitHub Action | major | 2 | — |
| WS-7 MCP money-spending guardrails RFC | major | 3 | WS-1 |
| WS-8 Founder-skills bundle extraction | major | 3 | — |
| WS-9 walter-contract / walter-host split | major | 3 | WS-1, ADR-0020 |
| WS-10 v1.0 stability charter | major | 4 | WS-1, WS-3, WS-5 |
| ADR-0018 Licensing strategy | — | 1 | ADR-0019 |
| ADR-0019 CLA vs DCO | — | 1 | — |
| ADR-0020 Repo split decision | — | 2 | ADR-0018 |
| ADR-0021 v1.0 stability charter | — | 4 | WS-10 |
| ADR-0022 Xipher Labs legal entity | — | 1 | ADR-0018 |

### Dependency graph

```
WS-4 (tiny, do immediately)
ADR-0018 → ADR-0019 → WS-1 → WS-5 → WS-7
                             → WS-9 (via ADR-0020)
                             → WS-10 (via ADR-0021)
WS-2 (independent, Sprint 1)
WS-3 (Sprint 2, independent of WS-1)
WS-6 (Sprint 2, independent)
WS-8 (Sprint 3, independent)
```

---

## Workstream details

### WS-1: Depersonalization deep cleanup

**Rigor**: major
**Spec**: `docs/specs/depersonalization-deep-cleanup.md`
**Plan**: `docs/specs/depersonalization-deep-cleanup.plan.md`

Remove all operator-specific technology preferences from the global
`AGENTS.md`. Move the testing strategy table to an overlay example.
Relocate Solana/Stripe/Anchor references to `skills/` SKILL.md files where
they belong as domain-specific capabilities. Move macOS/OrbStack/pnpm
preferences to an `_examples/operator-preferences.example.md` file. Add or
strengthen the depersonalization test suite to catch regressions.

### WS-2: Walter-OS Lite entry tier

**Rigor**: major
**Spec**: `docs/specs/walter-os-lite-entry-tier.md`
**Plan**: `docs/specs/walter-os-lite-entry-tier.plan.md`

Define and ship a "Lite" bundle: a single Markdown file (or a small set) that
drops into a Claude Code session or Codex CLI conversation and installs the
minimum Walter-OS contract in under 60 seconds, with no Docker, no VM, and no
personal overlay required. This becomes the top entry in the README install
section, above Tier I through IV. It is not a replacement for Tier I; it is a
zero-friction evaluation path.

### WS-3: Cursor adapter completion

**Rigor**: major
**Spec**: `docs/specs/cursor-adapter-completion.md`
**Plan**: `docs/specs/cursor-adapter-completion.plan.md`

Define what "first-class Cursor support" means, then implement it: a
generated `.cursor/rules` file (or `.cursorrules`) produced by `install.sh`
that mirrors the global AGENTS.md contract. Include MCP server bridging
documentation for Cursor's MCP configuration. Ship a verification step
(`walter-os doctor --cursor`) that confirms the Cursor adapter is current
with the installed AGENTS.md.

### WS-4: report.log removal and .gitignore hardening

**Rigor**: tiny
**No spec required** — single commit with commit body explaining the change.

Remove `report.log` from the repository (delete the file, add `*.log` or
`report.log` to `.gitignore`). Verify no other log artifacts are tracked or
unignored at the repo root.

### WS-5: AGENTS.md cascade as a public standard document

**Rigor**: major
**Spec**: `docs/specs/agents-md-cascade-as-standard.md`
**No plan** (strategic positioning spec, not an implementation task)

Extract the cascade specification from the README into a standalone
`docs/specs/agents-md-cascade-spec.md` that describes the cascade mechanism
in vendor-neutral terms. This is the precursor to any future RFC submission.
This workstream does NOT include actually submitting to Anthropic/OpenAI — it
produces the document that would be submitted. Engagement with those
organizations is operator-territory.

### WS-6: Review loop as a GitHub Action

**Rigor**: major
**Spec**: `docs/specs/review-loop-as-action.md`

Extract the 3-round Copilot → Codex → collaborative review loop into a
reusable GitHub Action with defined inputs (PR number, base branch,
severity-gate config) and defined outputs (JSON findings, per-finding
severity). This is a standalone marketable artifact.

### WS-7: MCP money-spending guardrails RFC

**Rigor**: major
**Spec**: `docs/specs/mcp-money-spending-guardrails-rfc.md`

Formalize the 6 guardrails already documented in AGENTS.md and the `"money":
true` tag in `mcp/servers.json` into a vendor-neutral RFC document targeting
the MCP ecosystem. This workstream produces the document; outreach to the MCP
community is operator-territory.

### WS-8: Founder-skills bundle extraction decision

**Rigor**: major
**Spec**: `docs/specs/founder-skills-bundle-extraction.md`

Evaluate whether the founder-skills bundle (`track-pending`,
`terms-policy-generator`, `legal-doc-review`, `financial-plan-builder`,
`hiring-toolkit`) should be extracted to its own repository with its own
marketing surface, or remain in-tree with better discoverability. Produce a
recommendation with decision criteria.

### WS-9: walter-contract / walter-host split

**Rigor**: major
**Spec**: `docs/specs/walter-contract-walter-host-split.md`
**ADR**: `docs/decisions/0020-repo-split-walter-contract-walter-host.md`

Evaluate and decide on the monorepo vs split-repo question. The operator's
strategic plan advocates separating the agent contract layer from the Docker
stack. This workstream documents the trade-offs, makes a recommendation, and
if the split is recommended, defines the migration path.

### WS-10: v1.0 stability charter

**Rigor**: major
**Spec**: `docs/specs/walter-os-v1-0-stability-charter.md`
**ADR**: `docs/decisions/0021-v1-0-stability-charter.md`

Define what v1.0 means for Walter-OS: which APIs are frozen, what the
deprecation policy is, what the conformance suite must cover, and what the
release cadence is post-v1.0.

---

## "Fix now in walter-os" vs "IdeaOS future"

The following items are OSS-readiness work that lands in this repo:

- WS-1 through WS-10 above
- ADR-0018 through ADR-0022

The following items are IdeaOS-territory and explicitly out of scope for this
repo and this roadmap:

- Managed hosting, multi-tenancy, billing, UI abstraction
- Customer-interview research and vertical selection
- IdeaOS MVP implementation
- Pricing and unit-economics calculation

The licensing work (ADR-0018) and legal entity work (ADR-0022) are shared
infrastructure that enables IdeaOS but live in walter-os as governance
decisions.

---

## v1.0-stable bar

v1.0 is shippable when ALL of the following are true:

1. `AGENTS.md` global layer contains no operator-personal tool preferences
   or domain-specific references (passes `tests/oss/depersonalization.bats`
   extended suite).
2. The AGENTS.md cascade is documented in a standalone spec document
   (`docs/specs/agents-md-cascade-spec.md`) with vendor-neutral language.
3. Cursor support is first-class: `install.sh` generates a valid
   `.cursor/rules` file and `walter-os doctor --cursor` passes.
4. The Tier I / Lite install path installs and verifies in under 60 seconds
   on a clean macOS and clean Ubuntu 24.04 machine.
5. All existing depersonalization tests pass. No new operator-personal
   references introduced.
6. The Walter Council's dependency on walter-host is documented as an
   explicit architectural choice with migration guidance for Council-without-
   full-host configurations (e.g., using hosted Plane SaaS + hosted LiteLLM
   proxy).
7. The repo has a CLA or DCO enforcement mechanism in place before external
   PRs are accepted.
8. The licensing strategy is formalized in an ADR and COMMERCIAL.md reflects it.
9. `report.log` and any other runtime artifact are removed from the repository
   and added to `.gitignore`.
10. The OSS Trust roadmap items through Layer B are implemented (runtime
    sandboxing + audit chain basics — as defined in `docs/specs/oss-trust-roadmap.md`).

---

## Issues to file

The following issues should be filed via `gh issue create` after this PR
opens. Titles follow the `[TYPE] -CATEGORY- title` convention. Body summaries
reference the spec or ADR where applicable.

| # | Title | Severity | Spec / ADR reference |
|---|---|---|---|
| I-01 | `[FIX] -TECHNICAL- remove report.log and add to .gitignore` | COSMETIC | WS-4 (no spec) |
| I-02 | `[FIX] -TECHNICAL- depersonalization deep cleanup in global AGENTS.md` | MAJOR | `docs/specs/depersonalization-deep-cleanup.md` |
| I-03 | `[FEAT] -TECHNICAL- Walter-OS Lite zero-friction entry tier` | MAJOR | `docs/specs/walter-os-lite-entry-tier.md` |
| I-04 | `[FEAT] -TECHNICAL- Cursor adapter first-class support` | MAJOR | `docs/specs/cursor-adapter-completion.md` |
| I-05 | `[DOCS] -TECHNICAL- AGENTS.md cascade as vendor-neutral standalone spec` | MINOR | `docs/specs/agents-md-cascade-as-standard.md` |
| I-06 | `[FEAT] -TECHNICAL- review loop as reusable GitHub Action` | MAJOR | `docs/specs/review-loop-as-action.md` |
| I-07 | `[DOCS] -TECHNICAL- MCP money-spending guardrails RFC document` | MINOR | `docs/specs/mcp-money-spending-guardrails-rfc.md` |
| I-08 | `[DOCS] -BUSINESS- founder-skills bundle extraction decision` | MINOR | `docs/specs/founder-skills-bundle-extraction.md` |
| I-09 | `[CHORE] -BUSINESS- walter-contract vs walter-host split decision` | MAJOR | `docs/specs/walter-contract-walter-host-split.md`, ADR-0020 |
| I-10 | `[DOCS] -TECHNICAL- v1.0 stability charter and deprecation policy` | MAJOR | `docs/specs/walter-os-v1-0-stability-charter.md`, ADR-0021 |
| I-11 | `[CHORE] -COMPLIANCE- define licensing strategy (ADR-0018)` | BLOCKER | `docs/decisions/0018-licensing-strategy.md` |
| I-12 | `[CHORE] -COMPLIANCE- add CLA or DCO contributor gate (ADR-0019)` | BLOCKER | `docs/decisions/0019-contributor-license-agreement.md` |
| I-13 | `[CHORE] -COMPLIANCE- Xipher Labs legal entity registration (ADR-0022)` | BLOCKER | `docs/decisions/0022-xipher-labs-legal-entity.md` |
| I-14 | `[DOCS] -TECHNICAL- document Council without walter-host (hosted Plane/LiteLLM)` | MINOR | README known-limitations section |
| I-15 | `[FIX] -TECHNICAL- add report.log pattern to .gitignore before removal` | COSMETIC | WS-4 |

Note: I-01 and I-15 overlap; file as one issue (I-01 covers both the removal
and the .gitignore fix).

---

## References

- `docs/decisions/0010-oss-license.md` — current AGPL-3.0 decision (superseded by ADR-0018)
- `docs/decisions/0011-depersonalization-strategy.md` — overlay architecture decision
- `docs/specs/phase-w-5-depersonalization.md` — prior depersonalization pass
- `docs/specs/oss-trust-roadmap.md` — parallel security workstream (v0.5.0+)
- `docs/specs/walter-host-extraction.md` — service-level depersonalization
- `docs/specs/walter-council-v2.md` — Council v2 full spec
- External audit 2026-05-21 (operator-provided findings, quoted verbatim in problem statement)
