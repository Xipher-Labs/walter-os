# Walter-OS — Detailed README

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-12
**Linear/Plane**: (to be filed)

## Problem

The current README (~650 lines as of post-PR-#49) is well-structured for a reader
who wants a quick orientation and then goes digging through `docs/operational/`.
However, the operator has confirmed the intent is a **comprehensive adopter-facing
guide** — detailed enough that a competent engineer can stand up Walter-OS without
reading every doc in `docs/operational/`. The current README does not satisfy that
requirement.

Specifically, the gaps are: the services table omits RAM budgets, profile
assignment, and per-service cross-links; the installation flow is referenced but
not enumerated step-by-step; the secrets architecture is described but not
diagrammed; the multi-device strategy presents only one approach (Syncthing) when
three exist; the resource budget is a single-line "Hetzner CX53" without tiers;
the troubleshooting section is absent entirely; and the Walter-Bridge / CLI-client
setup is treated as a footnote.

A new adopter who forks the repo today must read the README, three operational
docs, and several SUGGESTIONS.md files to get their first service online. The
new README should collapse that surface into one canonical onboarding document,
with operational docs acting as "deeper reading" supplements rather than required
pre-reading.

## Proposed solution

Replace the existing `README.md` with a comprehensive, opinionated, adopter-facing
guide that covers every part of the stack in one document. The structure follows the
order a new adopter naturally encounters: understanding what the project is and
whether it fits (personas), surveying the services (stack at a glance), understanding
the network and secrets model (networking + secrets flow), deciding on resource
sizing (resource budget), following a numbered installation (step-by-step install),
customizing to their situation (customization patterns), and troubleshooting the
known failure modes (troubleshooting).

The README explicitly avoids marketing tone. It should be honest about what
Walter-OS is not (a zero-config starter, a stable API, a generic framework). It
must not reference any operator-specific values — all examples use placeholder
conventions (`yourdomain.com`, `you@example.com`, the Xipher Labs attribution
only as a model for forkers).

## Acceptance Criteria

- [AC-1] `README.md` exists at repo root and replaces the current ~650-line version.
- [AC-2] All sections specified in this document are present in the order listed
  (see "Required sections" below).
- [AC-3] The README is 1500–2500 lines. "MUY detallado" is the requirement; 1500 is
  the floor, 2500 is the cap to prevent runaway length.
- [AC-4] No operator-specific values appear: strings `operator-handle`,
  `operator.email`, `operator@`, and `private.example` must not appear anywhere
  in the file. The maintainer entity name `Xipher Labs` is allowed where
  required for public attribution. The string `xipherlabs.xyz` may appear only
  in the license/brand attribution section as a model email placeholder
  (e.g., `licensing@xipherlabs.xyz`).
- [AC-5] All cross-links to other docs use relative paths (e.g.,
  `docs/operational/hosting-providers-comparison.md`) and resolve to files that
  exist in the repo (verified by the bats test suite).
- [AC-6] The stack-at-a-glance table covers every service listed in the
  `setup/vm/services/` directory plus Control Tower; no service is undocumented.
- [AC-7] The resource budget table includes Hetzner CX53 as the explicitly
  labelled "Recommended" SKU.
- [AC-8] The multi-device strategy table covers all three approaches: Syncthing,
  private git overlay, and Ansible/dotfiles reference.
- [AC-9] The troubleshooting section has at least 15 entries, each with a one-line
  cause and a one-line fix.
- [AC-10] The license/brand section credits Xipher Labs and references COMMERCIAL.md.
- [AC-11] `tests/oss/readme-detailed.bats` exists and asserts: section headings
  present, line count in range, absence of operator-specific strings, all relative
  cross-links resolve to real files.
- [AC-12] Running `markdownlint README.md` (or noting the check is deferred if the
  tool is not installed) produces zero errors on the heading hierarchy and link
  syntax.

## Required sections (in order)

1. Logo placeholder + tagline
2. Badges row
3. One-paragraph value prop (honest — IS / IS NOT)
4. Quick demo (ASCII `tree` or Mermaid showing homepage tiles)
5. TL;DR install (3 commands)
6. Table of contents (auto or manual)
7. Personas (Builder / Founder / Operator / Hackathon participant)
8. Stack at a glance (full services table with RAM, profile, hostname, cross-link)
9. Networking and access (Mermaid or ASCII: CF Tunnel → Caddy → services;
   Tailscale overlay for Control Tower)
10. Secrets flow (diagram + Infisical / .env.local / overlay layers explanation)
11. Multi-device strategy (3-approach table)
12. Resource budget + minimum specs (4-tier table; CX53 = Recommended)
13. Step-by-step installation (numbered, ≥10 steps)
14. Customization patterns (per-service, profiles, per-skill, per-context)
15. Walter-Bridge and CLI clients (gateway rationale, model aliases, CLI setup)
16. Operator contexts at a glance (4 contexts, cascade, PROMPT.md / SKILLS.md)
17. n8n workflows (6 curated suggestions + import flow)
18. Updating (pull + rebuild; major bumps; submodule pins)
19. Troubleshooting (≥15 entries)
20. Contribution (link to CONTRIBUTING.md)
21. Security (link to SECURITY.md)
22. License + brand (AGPLv3, Xipher Labs, COMMERCIAL.md reference)

## Non-goals

- NOT a tutorial with explanatory prose at every step. Target reader is a
  competent engineer who can run a command.
- NOT marketing copy. Value prop is honest about limitations and alpha status.
- NOT replacing CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, or CHANGELOG.md.
  These files stay as-is; the README links to them.
- NOT a single-page visual demo. Visual demos belong in `docs/operational/`.
- NOT spec-compliant until the operator approves; the current file is the reference.

## Open questions

- Q1: The spec assumes `setup/vm/services/<svc>/SUGGESTIONS.md` files exist for
  each service (per the operator's stated repo state). If those files do not yet
  exist on main, the implementer should link to `setup/vm/services/<svc>/` instead
  and add a TODO comment in the README so the link can be tightened later.
- Q2: Hetzner CX53 cost (~€25/mo) is a placeholder. The implementer should verify
  the current price in the Hetzner console during Task 1 or leave a `<!-- TODO:
  verify price -->` comment.
- Q3: The Walter-Bridge section references 37 model aliases across 17 providers.
  The implementer should verify the alias count against the actual LiteLLM config
  before writing the section, or use "30+" as a conservative floor.

## References

- `docs/operational/hosting-providers-comparison.md` (hosting tiers)
- `docs/operational/universal-vs-personal-config.md` (overlay model)
- `docs/operational/multi-device-sync.md` (sync approaches)
- `docs/operational/marketing-core-stack.md` (PostHog / ClickHouse config)
- `docs/operational/operator-contexts.md` (context cascade)
- `docs/operational/ads-via-n8n.md` (n8n workflow examples)
- `docs/operational/onboarding-checklist.md` (current onboarding state)
- `docs/specs/walter-council-v2.md` (Council architecture)
- `docs/decisions/0008-control-tower-stack.md` (Control Tower tech choice)
- `docs/decisions/0009-agent-trust-tiers.md` (trust tier design)
- Current `README.md` (content to carry forward: CLI reference, Council section,
  disciplines, MCP catalog, architecture diagram)
