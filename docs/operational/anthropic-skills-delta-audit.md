# Anthropic Skills Delta Audit

Issue: #222
Upstream: `anthropics/skills`
Audited upstream commit: `da20c92503b2e8ff1cf28ca81a0df4673debdbf7`

## Decision

No skills are vendored in this pass.

Prefer the plugin mechanism for Anthropic first-party skills because it keeps
the supply-chain boundary smaller, avoids duplicate local skills, and lets the
operator receive plugin updates without Walter-OS carrying a second copy of the
same source. Vendoring should only happen when Walter-OS needs local
customization, a pinned fork, or behavior that the plugin cannot expose.

## Current Plugin Coverage

The issue records the currently exposed `anthropic-skills:` plugin surface as:

- `algorithmic-art`
- `brand-guidelines`
- `canvas-design`
- `consolidate-memory`
- `docx`
- `internal-comms`
- `pdf`
- `pptx`
- `setup-cowork`
- `skill-creator`
- `theme-factory`
- `xlsx`

Walter-OS also references the plugin directly in the design stack for static
design output and slide decks. That means the operator intent behind most
document, slide, spreadsheet, PDF, theme, brand, and skill-authoring workflows is
already covered without vendoring upstream files.

Two skills from the issue's plugin list were not present in the audited upstream
snapshot:

- `consolidate-memory`
- `setup-cowork`

Treat those as stale issue data unless they are found in a local installed
plugin cache for a specific operator environment.

## Upstream Snapshot

The audited upstream commit exposes these skills:

| Upstream skill | Plugin-covered today | Decision |
| --- | --- | --- |
| `algorithmic-art` | Yes | Use plugin |
| `brand-guidelines` | Yes | Use plugin |
| `canvas-design` | Yes | Use plugin |
| `claude-api` | No | Skip for now; Walter-OS already has OpenAI and model-router guidance, and Anthropic API-specific behavior should stay plugin-provided unless a Walter-native bridge is needed |
| `doc-coauthoring` | No | Skip for now; overlaps with `readme-craft`, `proposal-writer`, `content-writer`, specs/ADR workflows, and the superpowers planning flow |
| `docx` | Yes | Use plugin |
| `frontend-design` | No | Skip for now; overlaps with `frontend-quality`, `landing-page-fast`, `ui-ux-pro-max`, and external Vercel/frontend skills |
| `internal-comms` | Yes | Use plugin |
| `mcp-builder` | No | Track as a future candidate; could help when Walter-OS starts authoring MCP servers, but vendoring now adds supply-chain surface before a concrete need |
| `pdf` | Yes | Use plugin |
| `pptx` | Yes | Use plugin |
| `skill-creator` | Yes | Use plugin |
| `slack-gif-creator` | No | Skip; narrow communications asset workflow and no current Walter-OS stack dependency |
| `theme-factory` | Yes | Use plugin |
| `web-artifacts-builder` | No | Skip for now; overlaps with frontend/web app skills and does not need Walter-specific customization yet |
| `webapp-testing` | No | Track as a future candidate; useful, but Walter-OS already has Playwright/browser testing guidance and no immediate delta requires vendoring |
| `xlsx` | Yes | Use plugin |

## Net-New Upstream Skills

These upstream skills are not in the plugin-exposed list captured by #222:

- `claude-api`
- `doc-coauthoring`
- `frontend-design`
- `mcp-builder`
- `slack-gif-creator`
- `web-artifacts-builder`
- `webapp-testing`

Recommended handling:

- Import none in this pass.
- Monitor `mcp-builder` and `webapp-testing` as the strongest future candidates.
- Prefer requesting or waiting for plugin exposure over local vendoring.
- If vendoring becomes necessary, pin the upstream commit, record source URL and
  local checksum in the daily supply-chain audit baseline, and update
  `skills/INDEX.md`.

## Plugin Tracking Note

The upstream repository includes marketplace metadata that maps plugin sets to
`./skills/...`, so new upstream skills can flow through the official plugin when
the marketplace/plugin package updates. Local installed plugin state can still be
pinned or cached by the operator's environment. Walter-OS should therefore say
"install or update the official Anthropic skills plugin" rather than assuming
every operator already has the newest upstream skill set live.

## Follow-Up Triggers

Open a new import PR only when one of these is true:

- a Walter-OS feature requires local customization of a net-new Anthropic skill
- the plugin does not expose a needed upstream skill after a reasonable wait
- a supply-chain review explicitly prefers vendoring over plugin delivery
- a net-new skill has no overlap with existing Walter-native or external skills

Until then, this issue can close as a documented no-vendor decision.
