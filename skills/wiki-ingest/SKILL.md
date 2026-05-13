---
name: wiki-ingest
description: Ingest a source (URL / file / paste) into the operator's LLM-maintained wiki at $WALTER_OS_HOME/wiki/. Creates a sources/<date>-<slug>.md page summarizing the source, identifies referenced entities (people/companies/tools/concepts), creates or updates their pages with `[[wikilinks]]`, updates relevant topic hubs, appends to log.md. Triggered by the slash command `/ingest <url-or-path>` or by the operator saying "ingest this" / "file this in the wiki" / "agregalo al wiki". Read $WALTER_OS_HOME/wiki/SCHEMA.md before doing anything — it's the contract.
---

# Wiki ingest

## When this skill applies

- Operator pastes a URL, file path, or text block + says "ingest" /
  "file this" / "save this in the wiki" / "agregalo al wiki".
- `/ingest <arg>` slash command is invoked.
- Operator asks a question whose answer is novel + reusable —
  consider proposing ingest after answering (Query→Ingest pattern).

**Don't auto-ingest** without explicit operator request. Spamming the
wiki with low-signal sources is the failure mode Karpathy specifically
warns against.

## The contract

`$WALTER_OS_HOME/wiki/SCHEMA.md` is binding. **Read it first.** Key
invariants:

1. Source goes to `wiki/sources/YYYY-MM-DD-<slug>.md` with the
   prescribed frontmatter (`type`, `slug`, `date_ingested`, `source_url`,
   `source_type`, `contexts`).
2. Every referenced entity (named person / company / tool) gets a stub
   page in the right directory (`people/`, `companies/`, `tools/`).
   No broken `[[wikilinks]]`.
3. Every concept worth keeping gets `concepts/<slug>.md`.
4. The relevant topic hub (`topics/<topic>.md`) gets a new bullet.
5. `wiki/log.md` gets an appended entry.
6. **One source typically touches 5-15 wiki pages.** If you only touch
   1, you probably under-ingested.

## Workflow

### 1. Acquire the source

| Source kind | How |
|---|---|
| URL | `WebFetch` |
| Local file | `Read` |
| Pasted text | use as-is |
| YouTube transcript | URL → `WebFetch` (often returns transcript) |
| Email / Slack thread | Operator pastes |
| PDF | `Read` (Claude handles PDFs natively) |

If `WebFetch` returns paywalled / login-walled, ask operator for the
content rather than guessing.

### 2. Choose the slug

`slug = YYYY-MM-DD-<3-to-6-words-kebab>`. Keep it descriptive but
short. Examples:

- `2026-05-05-karpathy-llm-wiki-gist`
- `2026-04-15-anthropic-claude-code-2.0-blog`
- `2026-04-22-call-jane-quarterly-review`

### 3. Draft the source page

Template (fill all frontmatter fields; truncate body sensibly):

```markdown
---
type: source
slug: <slug>
date_ingested: <YYYY-MM-DD>
source_url: <url or path or "(pasted)">
source_type: <article|gist|paper|talk|email|chat|pdf|video|book|tweet|other>
contexts: [<context-tags>]
---

# Source — <one-line title>

## TL;DR
<2-3 sentences. The "what would I want to know in 30 seconds?".>

## Key points
- <bullet>
- <bullet>

## Quotes (max 3)
> "<short quote>" — author, location

## Filed into
- [[<page-1>]] (created | updated)
- [[<page-2>]] (created | updated)
- ...

## Open questions
<things the source raises but doesn't answer; useful for future ingests>
```

### 4. Identify entities and concepts

Scan the source for:

| Mention | Action |
|---|---|
| Proper noun (person) | Create or update `people/<slug>.md` |
| Org / company / institution | Create or update `companies/<slug>.md` |
| Software / service / tool | Create or update `tools/<slug>.md` |
| Important idea / technique / definition | Create `concepts/<slug>.md` if novel; update existing if refined |
| Theme / area | Update `topics/<topic>.md` to add bullet linking the new pages |

For brand-new entities, create **stubs** with at minimum:

```markdown
---
type: <person|company|tool|concept>
slug: <slug>
created: <date>
last_updated: <date>
contexts: [<contexts>]
---

# <Title>

<one-line description>

## Mentioned in
- [[sources/<the source page just created>]]
```

The stub bar is intentionally low — better to have a stub than a
broken `[[wikilink]]`. The next ingest mentioning the same entity
will deepen the page.

### 5. Update topic hubs

Identify which topics this source contributes to. If a fitting topic
doesn't exist, create one:

```markdown
---
type: topic
slug: <slug>
last_updated: <date>
---

# <Topic title>

<1-paragraph description of the area>

## Pages

- [[concepts/<page>]] — <one-line summary>
- [[tools/<page>]] — <one-line summary>
- [[decisions/<page>]] — <one-line summary>
```

### 6. Append to log.md

```markdown
## [<YYYY-MM-DD HH:MM>] ingest | <source-slug>
Triggered: N new + M updated. Touched: <comma list of slugs>.
```

### 7. Show the operator

Before the agent commits or claims completion, show the operator:

- The full text of the source page.
- The list of entity / concept / topic pages created or updated, with
  diff/preview if changed.
- The log.md entry.

Operator approves → agent writes to disk + commits. Operator rejects
or refines → iterate.

### 8. Commit (when wiki CLI is wired in WK3)

`walter-os wiki commit -m "ingest: <slug>"` will commit to the
**private** Forgejo mirror. Don't push to the public walter-os repo.

## Failure modes to avoid

- **Skimming**: don't lose nuance. If the source has a non-obvious
  twist, capture it in `## Key points`, not just the TL;DR.
- **Under-cross-linking**: if a source mentions [Company] + Solana but
  you only file under topics/agentic-llm-coding, the cross-context
  value is lost. Be generous.
- **Stub abandonment**: creating 10 stubs and never deepening them
  is worse than not creating them. Run `walter-os wiki lint` weekly
  to catch this.
- **Updating without sourcing**: if you change a fact on an entity
  page, link to the source that justified the change. Otherwise
  future-you can't audit the wiki.

## Examples (when implemented in WK3+)

```
/ingest https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
/ingest ~/Downloads/whitepaper-anthropic-prompt-caching.pdf
/ingest "<paste the whole jane call transcript>"
```

For each, expect the agent to propose 5-15 page changes for review.

## Related

- `skills/wiki-query/SKILL.md` — read direction
- `skills/wiki-lint/SKILL.md` — health checks
- `wiki/SCHEMA.md` — the contract this skill obeys
