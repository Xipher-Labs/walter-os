# Walter-OS Wiki — Schema

> **Read this first** when ingesting, querying, or linting the wiki.
> This file is the contract between the operator and the LLM.

---

## What this wiki is (and isn't)

**This wiki is a persistent, LLM-maintained knowledge base.** Every
useful thing the operator learns or decides should compound here, so
that future sessions don't re-derive it from scratch.

Architecture (per [Karpathy 2026](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)):

| Layer | Owned by | Mutable by LLM? |
|---|---|---|
| **Raw sources** — PDFs, articles, Slack/Telegram messages, meeting transcripts | Operator (Obsidian vault, Drive, Plane comments, ...) | ❌ Read-only. LLM never edits these. |
| **The wiki** (this directory) | LLM, supervised by operator | ✅ LLM creates/updates pages on every Ingest, Query (sometimes), and Lint. |
| **The schema** (this file) | Operator | ❌ LLM reads it but doesn't change it. |

**This wiki is NOT** a chat-log dump, a to-do list (use Plane), a
journal (use Obsidian vault), or a code repository. It's a structured
knowledge graph.

---

## Page types (canonical)

Every page lives under exactly **one** of these directories:

### `people/<slug>.md`
Proper noun (a real person). Slug is `firstname-lastname` lowercase.

```markdown
---
type: person
slug: jane-doe
created: 2026-05-05
last_updated: 2026-05-05
contexts: [work, projects-personal]   # which agent contexts care about this person
---

# Jane Doe

**Role**: <what they do>
**Status**: <active client | former teammate | competitor | journalist | ...>
**Where**: <city, company>
**Communication**: <preferred channel + cadence>

## Facts

- ...

## Conversations

- [[sources/2026-05-05-call-jane-quarterly-review]]

## Related

- [[companies/[company]]]
- [[topics/devrel]]
```

### `companies/<slug>.md`
Org / company / institution. Slug = `kebab-case-name`.

### `concepts/<slug>.md`
An abstract idea, definition, theorem, technique. Slug describes the
concept (`geyser-plugin`, `eip-7702`, `local-tax-regime`).

### `decisions/<slug>.md` (ADR)
A decision the operator made (or made jointly with the agent), with
context and consequences. Slug = `YYYY-MM-DD-short-decision`.

```markdown
---
type: decision
slug: 2026-05-05-yubikey-hard-required
date: 2026-05-05
status: accepted   # proposed | accepted | superseded | deprecated
contexts: [walter-os, security]
---

# Yubikey hard-required for walter-os secrets

## Context
<why this came up>

## Decision
<what was decided>

## Consequences
<positive + negative>

## Related
- [[decisions/...]]   ← supersedes / superseded-by
- [[concepts/secrets-runtime]]
```

### `tools/<slug>.md`
A piece of software / service the operator uses. Slug = `kebab-tool-name`.

```markdown
---
type: tool
slug: claude-code-router
vendor: musistudio
tier: free
alternatives: [openrouter, litellm]
last_evaluated: 2026-05-05
---

# Claude Code Router (CCR)

**What**: ...
**Why we use it**: ...
**Costs**: ...
**Caveats**: ...

## Operational notes

- Deployed at: [[concepts/walter-vm]] under `setup/walter-host/services/llm-proxies/`
- API key rotation: [[decisions/2026-05-05-ccr-apikey-rotation]]
```

### `topics/<slug>.md`
Hub page that links many other pages on a theme. Slug = broad area
(`solana`, `regulatory-ar`, `agentic-llm-coding`, `branding`).

A topic page is mostly an index — its body is `## Pages` with bullet
lists of `[[wikilinks]]` plus a one-line summary each.

### `sources/YYYY-MM-DD-<slug>.md`
**One per ingested source.** Slug = short kebab-case name of the
source (article title, paper title, meeting type).

```markdown
---
type: source
slug: 2026-05-05-karpathy-llm-wiki-gist
date_ingested: 2026-05-05
source_url: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
source_type: gist
contexts: [walter-os, agentic-llm]
---

# Source — Karpathy "LLM Wiki" gist

## TL;DR
<2-3 sentences>

## Key points
- ...

## Quotes
> "Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase."

## Filed into
- [[concepts/llm-wiki-pattern]] (new page)
- [[topics/agentic-llm-coding]] (linked from)
- [[decisions/2026-05-05-walter-os-wiki-compliance]] (this triggered)
```

---

## Cross-link rules (HARD requirements)

When ingesting or editing pages, the LLM **must**:

1. Every page MUST be linked from at least one `topics/<topic>.md` hub.
   Orphans get caught by `walter-os wiki lint`.

2. Every entity (person, company, tool) **referenced by name** in a
   source page MUST have a corresponding page under
   `people/`/`companies/`/`tools/`. If a stub doesn't exist yet, create
   one with at least the front-matter and a 1-line description. No
   broken `[[wikilinks]]`.

3. Every decision MUST link to:
   - The topics it affects.
   - Any prior decision it supersedes (mark prior as `status: superseded` and add `superseded-by:` link).

4. Every source MUST list which pages it triggered creation/updates of
   (the `## Filed into` section).

5. Use `[[wikilinks]]` syntax (Obsidian-compatible). Never raw paths.

---

## Special files

### `wiki/index.md` (rebuilt by `walter-os wiki lint`)

Auto-generated catalog. The LLM reads `index.md` first when answering
queries, to find candidate pages without grepping the whole tree.

Format:

```markdown
# Index — last rebuilt 2026-05-05 18:42

## people (12)
- [[people/jane-doe]] — VP Eng at Acme; quarterly check-ins
- ...

## companies (8)
- [[companies/[company]]] — Solana RPC infra; operator's day job
- ...

## concepts (...)
- ...
```

### `wiki/log.md` (append-only)

Every wiki operation appends a line. Operator-readable, grep-friendly.
LLM appends; never rewrites.

Format:

```markdown
## [2026-05-05 18:00] ingest | karpathy-llm-wiki-gist
Triggered: 1 new concept (llm-wiki-pattern), 1 new topic (agentic-llm-coding),
1 new decision (walter-os-wiki-compliance), 0 stub-creations.

## [2026-05-05 18:42] lint | full
Rebuilt index.md. Findings: 0 orphans, 0 broken links, 1 stale claim
(tools/headscale-admin "purple bug" — page should be marked resolved).

## [2026-05-06 09:15] query | "what's status of openclaw?"
Read pages: [[tools/openclaw]], [[decisions/2026-05-05-openclaw-gateway-fix]].
Filed answer back to: [[tools/openclaw]] (added "current state" section).
```

---

## Operations (the loops)

The LLM doesn't do these autonomously — operator triggers each. Each
operation is implemented as a skill in `skills/wiki-{ingest,query,lint}/`.

### Ingest — `/ingest <url-or-path>`

1. LLM fetches/reads the source.
2. Creates `sources/<date>-<slug>.md` with the structure above.
3. Identifies entities + concepts referenced; creates/updates pages.
4. Updates `topics/` hubs that should link to the new pages.
5. Appends `log.md`.
6. Commits to private wiki repo.

Ratio: a single source typically touches **5-15 wiki pages**.

### Query — operator asks a question

1. LLM reads `index.md` + grep for relevant terms.
2. Loads candidate pages.
3. Answers from the wiki if possible.
4. If the wiki doesn't have it: web/MCP search → answer → propose new
   wiki page (operator approves).
5. If a particularly interesting answer was derived, file it back into
   the wiki as a new `concepts/` or `decisions/` page.

### Lint — `walter-os wiki lint`

Health check. Findings categorized:

| Severity | Check |
|---|---|
| 🚨 critical | Broken `[[wikilink]]` (target file doesn't exist) |
| ⚠️ high | Orphan page (no inbound links from `topics/`) |
| ℹ️ info | Stale claim (page with `last_verified:` > 90 days for time-sensitive content) |
| ℹ️ info | Missing entity (referenced by name but no page) |
| ℹ️ info | `index.md` out of sync with directory contents |
| ℹ️ info | Contradictions across pages (LLM scan; expensive, weekly only) |

Critical findings block any further `/ingest` until resolved.

---

## Privacy

This wiki is **private**. Walter-OS the public repo carries only this
schema + the wiki skills. The wiki **content** lives in a separate
private Forgejo repo `git.${WALTER_DOMAIN}/operator/walter-wiki`,
auto-mirrored from `walter-os/wiki/` on commit. The `wiki/` directory
is gitignored from the public `walter-os` repo (except `SCHEMA.md` and
this README, which are operator-readable contract).

Cross-device sync via Syncthing folder `agent-memory` (see
`walter-os agent-memory setup`).

---

## Versioning

This schema is at **v1** (2026-05-05). Major changes require a new
decision page: `decisions/<date>-wiki-schema-v2.md`. Backward-compatible
additions are fine without ceremony.
