---
name: wiki-query
description: Answer operator questions by reading the LLM-maintained wiki at $WALTER_OS_HOME/wiki/ before falling back to web search or model knowledge. Read $WALTER_OS_HOME/wiki/index.md first, grep for relevant terms, load matching pages, answer with `[[wikilink]]` citations. If the wiki doesn't have the answer, derive it via web/MCP search and propose a new wiki page (concepts/ or decisions/) so future queries don't re-derive. Triggered any time the operator asks a substantive question — the agent should self-decide to apply this skill, not wait for an explicit "/query".
---

# Wiki query

## When this skill applies

Whenever the operator asks a question that's:

- About a person, company, tool, concept, or decision relevant to the
  operator's contexts (work / projects-personal / personal).
- Likely answered already (operator is asking for the second time, or
  the area's been discussed before).
- Substantive — not a passing chat-style question (don't query the
  wiki for "what's 2+2?").

The agent should **proactively** check the wiki before answering, then
optionally **file the answer back** if it's a novel synthesis.

## Workflow

### 1. Identify wiki-relevant terms in the operator's question

Extract proper nouns, tool names, technical concepts, project names.
Skip stop-words and generic verbs.

### 2. Read `wiki/index.md` first

`index.md` is the catalog. Grep it for the relevant terms.

```
grep -iE "<term1>|<term2>|<term3>" wiki/index.md
```

If hits, load those pages.

### 3. If `index.md` has nothing — broaden

```
ls wiki/people/ wiki/companies/ wiki/tools/ wiki/concepts/ \
    wiki/decisions/ wiki/topics/
```

then `grep -ril "<term>" wiki/{people,companies,tools,concepts,decisions,topics}`.

### 4. Load candidates + answer

Read the matching pages. **Cite with `[[wikilinks]]`** in the answer
so the operator sees what the agent based its claim on.

If the wiki gives a confident answer, return it. Mention which pages
were consulted.

### 5. Wiki-miss flow

If the wiki doesn't have the answer:

1. Note this to the operator: "Wiki doesn't have this — going to derive."
2. Use web/MCP search / model knowledge / current-codebase reading.
3. Answer.
4. **Propose a new wiki page** if the answer is reusable. Pattern:

   > "I derived this from <sources>. Worth filing as
   > `concepts/<slug>.md`? It would link from `topics/<topic>` and
   > capture: <2-line summary of the keep-able knowledge>."

5. If operator says yes → invoke the `wiki-ingest` skill flow to file
   the answer.

### 6. Don't refile what's already filed

If the wiki page already exists and you just confirmed the same fact,
don't duplicate. If the page is **stale** (`last_verified:` > 90d for
time-sensitive content), update it AND log: "refreshed [[page]] —
verified <claim> as of <date>".

## Citation format

In the answer:

> The operator's CCR deployment uses `@musistudio/claude-code-router@2.0.0`,
> bound to `claude-code-router:3456` inside `litellm_net`. Per
> [[tools/claude-code-router]] (last verified 2026-05-05).

Don't paraphrase wiki content as if you knew it. Make the source
explicit so the operator can audit.

## Failure modes to avoid

- **Hallucinating wiki content**: never invent `[[wikilink]]` paths.
  If you cite `[[tools/foo]]`, that file must exist. If it doesn't,
  you propose it via the `wiki-ingest` flow.
- **Skipping the wiki**: even when the answer "feels obvious", a quick
  grep is cheap. The wiki is the operator's accumulated context — use it.
- **Over-filing**: not every conversation produces a wiki-worthy fact.
  Only file when the answer is **reusable** (will help a future
  session) AND **specific** (not generic LLM knowledge).

## Performance

`wiki/index.md` is the cache. Greps against it are O(file size).
Loading 3-5 candidate pages is cheap. Don't grep the whole tree on
every question — the index exists for a reason.

If the wiki grows past 200 pages, the spec migrates to `qmd`
(BM25+vector). Until then, plain grep is fine.

## Related

- `skills/wiki-ingest/SKILL.md` — write direction
- `skills/wiki-lint/SKILL.md` — health checks (catches answers that
  weren't filed back)
- `wiki/SCHEMA.md` — the contract
