---
name: wiki-lint
description: Health-check the operator's LLM-maintained wiki at $WALTER_OS_HOME/wiki/. Find broken `[[wikilinks]]`, orphan pages (no inbound links), missing entity stubs (referenced by name but no page), stale claims (`last_verified:` > 90d on time-sensitive pages), index.md / directory drift, and contradictions across pages (LLM scan, expensive, weekly only). Critical findings block further `/ingest`. Run on demand via `walter-os wiki lint` (Phase WK3) or invoked when the operator asks "is the wiki healthy?" / "any orphans?" / "lint the wiki".
---

# Wiki lint

## When this skill applies

- `walter-os wiki lint` is invoked.
- Operator asks "is the wiki healthy?" / "any orphans?" / "broken links?"
- Periodically (weekly cron, when set up in Phase WK4) — operator
  approves before the lint runs autonomously.

## Severity ladder

| Severity | What | Action |
|---|---|---|
| 🚨 critical | Broken `[[wikilink]]` (file referenced doesn't exist) | Block further `/ingest` until resolved. Force re-checked answers. |
| 🚨 critical | Front-matter malformed / missing required field per SCHEMA.md | Block. Page is invalid. |
| ⚠️ high | Orphan page (no inbound links from any `topics/` or other page) | Warn. Either link from a topic, delete, or mark with `orphan: justified` in front-matter. |
| ⚠️ high | Missing entity (a name appears in 3+ pages but has no own page) | Propose stub creation. |
| ℹ️ info | Stale claim (`last_verified:` > 90 days on a `time_sensitive: true` page) | Suggest refresh-pass. |
| ℹ️ info | `index.md` out of sync with directory contents | Auto-rebuild `index.md`. |
| ℹ️ info | Contradictions across pages (LLM scan) | Surface to operator for resolution. Expensive — run weekly only. |

## Workflow

### 1. Inventory

```
find wiki -name '*.md' -not -path 'wiki/index.md' -not -path 'wiki/log.md' \
    -not -path 'wiki/SCHEMA.md' -not -path 'wiki/README.md'
```

Each file gets parsed: front-matter (yaml), `[[wikilinks]]` extracted
from body, named entities heuristically detected (capitalized
multi-word noun phrases not already matching a wiki page).

### 2. Build the link graph

For each page, list:
- Outbound `[[wikilinks]]`.
- Inbound links (computed by scanning every other page's outbound).

### 3. Run checks

#### Broken links (🚨)
For each outbound `[[link]]`, check the target file exists. List
broken links + the page that contains them.

#### Front-matter validity (🚨)
Per SCHEMA.md, each page type has required fields. Check:
- `type` matches the directory (people/ ↔ type:person, etc.).
- `slug`, `created`, `last_updated` present.
- For decisions: `status` ∈ {proposed, accepted, superseded, deprecated}.
- For sources: `source_url`, `source_type`, `date_ingested`.

#### Orphans (⚠️)
A page is an orphan if no other page links to it. Allowed exceptions:
- `topics/*` are roots (don't need inbound).
- Pages with `orphan: justified` front-matter.

For each orphan, propose: which topic page should link to this, or
should this be deleted?

#### Missing entities (⚠️)
Heuristic: scan body of all pages for capitalized multi-word noun
phrases (`Jane Doe`, `[Company]`, `Yellowstone gRPC`). If a phrase
appears in ≥3 pages without a corresponding `people/` /
`companies/` / `tools/` / `concepts/` page, suggest a stub.

This is heuristic — false positives expected. Operator confirms
before any stub is created.

#### Stale claims (ℹ️)
Pages with `time_sensitive: true` AND `last_verified:` more than 90
days ago get flagged for refresh. Examples: tool versions, pricing,
external service URLs.

#### Index drift (ℹ️)
Compare `wiki/index.md` against the directory contents. If a page
exists in `concepts/` but not in `index.md`, or vice versa, regenerate
`index.md`.

#### Contradictions (ℹ️ — weekly only)
LLM scan. For each topic, load its hub + linked pages, ask the model:
"Are there factual contradictions between these pages? Be specific."
Surface findings to operator.

This is **expensive** — only run weekly. Skip if the last contradiction
scan was within 7 days.

### 4. Report

```
=== Wiki lint — 2026-05-12 18:00 ===

🚨 Critical (1)
  ─ wiki/concepts/eip-7702.md → broken link [[concepts/eip-3074]] (file missing)

⚠️  High (3)
  ─ wiki/people/jane-doe.md is orphan (no inbound links)
    Suggest: link from [[topics/[company]-customers]]
  ─ "ColabFold" referenced in 4 pages but no concept page exists
    Suggest: create wiki/concepts/colabfold.md as stub
  ─ wiki/tools/headscale.md is orphan
    Suggest: link from [[topics/walter-vm]]

ℹ️  Info (2)
  ─ wiki/tools/claude-code-router.md last_verified=2026-02-04 (97d ago)
  ─ index.md missing 2 pages: concepts/eip-7702, decisions/2026-05-05-secrets-runtime

Recommendation:
  - Resolve critical 🚨 BEFORE next /ingest (will block).
  - Run `walter-os wiki lint --rebuild-index` to fix the info 🟦.
  - Triage orphans + missing entities at next session.
```

### 5. Auto-fixes (if operator approves)

`walter-os wiki lint --apply` applies these fixes only:

- Rebuild `index.md` from current directory contents.
- Append a `log.md` entry.
- Nothing else — entities, orphan triage, stale refresh stay manual.

### 6. Output to log.md

```markdown
## [<YYYY-MM-DD HH:MM>] lint | full
Critical: <N>. High: <N>. Info: <N>.
Auto-fixed: <list, if --apply>. Pending operator triage: <list>.
```

## Implementation notes (for Phase WK3 wiring)

`scripts/wiki-lint.sh` will:

1. Walk `wiki/` excluding the special files.
2. Parse front-matter (use `yq` or python).
3. Extract `[[wikilinks]]` via regex `\[\[([^\]]+)\]\]`.
4. For LLM-driven contradiction scan, only invoke when
   `--full` flag is passed AND last contradiction scan > 7 days old.
   Spend caps via `ai-spend-tripwire` skill.

## Related

- `skills/wiki-ingest/SKILL.md` — write direction
- `skills/wiki-query/SKILL.md` — read direction
- `wiki/SCHEMA.md` — the contract
