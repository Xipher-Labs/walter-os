# SPEC: Walter-OS compliance with Karpathy's "LLM Wiki" pattern

**Status:** Approved (2026-05-05). Decisions locked, implementation in progress.
**Triggered by:** Operator request to ensure the Walter-OS spec complies with the referenced article.
**Source:** https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f — *"LLM Wiki"* (April 2026).

## Operator decisions (locked 2026-05-05)

| Question | Decision |
|---|---|
| Public or private wiki? | **Private.** Wiki content carries example work org confidential / example civic app legal / example medical app medical references. Public `walter-os` repo carries only the SCHEMA + skills; wiki content lives in a private Forgejo mirror. |
| One global vs per-context? | **One global** (per Karpathy's recommendation). Cross-context links are the compounding value. Privacy at git-repo level. |
| Location | `walter-os/wiki/` (gitignored from public repo) symlinked from `~/sync/agent-memory/wiki/` so Syncthing replicates cross-device. Committed to private Forgejo at `git.${WALTER_DOMAIN}/operator/walter-wiki` (e.g. `git.example.com/operator/walter-wiki`). |
| Obsidian vault relationship | Vault = raw sources (operator-owned, free-form journaling). Wiki = LLM-maintained derived knowledge. Disjoint. |
| MCP indexing | v1: `memory` MCP. Revisit at 200+ pages (Karpathy recommends `qmd` for BM25+vector at scale). |

---

## 1. What Karpathy proposes (in 3 sentences)

The LLM should **incrementally build and maintain a persistent wiki** — a directory of markdown files cross-referenced via `[[wikilinks]]` — instead of re-deriving knowledge from raw sources via RAG on every query. Three layers: **raw sources** (immutable), **the wiki** (LLM-owned), **the schema** (a `CLAUDE.md`/`AGENTS.md` document that tells the LLM *how* to maintain the wiki). Three operations: **Ingest** (read source → file pages → cross-link), **Query** (read wiki + maybe file the answer back), **Lint** (find contradictions, stale claims, orphans, missing cross-refs).

Slogan: *"Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase."*

---

## 2. Walter-OS today vs. the pattern

| Karpathy element | Walter-OS today | Status |
|---|---|---|
| Schema document (`AGENTS.md`/`CLAUDE.md`) | `AGENTS.md` (global) + `CLAUDE.md` + 3 context overlays | ✅ Strong. Better than Karpathy's example — layered. |
| Git repo of markdown | `walter-os/` is a git repo of markdown | ✅ |
| Skills as mini-knowledge units | `skills/*/SKILL.md` (50+) | ✅ But these are **methodology**, not the operator's substantive notes. |
| Obsidian as IDE | Obsidian vault syncs via Forgejo + Syncthing (`agent-memory` folder) | ✅ Wiring present, vault content not yet structured per Karpathy. |
| Operator's persistent knowledge wiki | **Missing.** No dedicated `wiki/` directory. Notes scattered in Obsidian vault (semi-structured) and `~/.claude/agent-memory/` (unstructured). | ❌ |
| `index.md` (catalog of all pages) | Missing | ❌ |
| `log.md` (chronological append-only log) | Partial — `~/.claude/agent-memory/projects/<id>/MEMORY.md` files exist but no central log | ⚠️ |
| Ingest workflow | Implicit — operator pastes content, agent summarizes ad-hoc | ❌ No formal ingest path. |
| Query workflow | Always derive on demand from project docs / web | ❌ No "check wiki first" pattern. |
| Lint workflow | Daily supply-chain audit (security only) — no wiki lint | ❌ |
| Raw-sources / wiki separation | Skills/agents bundle everything together | ⚠️ Conceptually adjacent but not enforced. |

**Verdict**: Walter-OS has **the schema and infrastructure**, but **is missing the wiki itself + the maintenance loops**.

---

## 3. The plan — make Walter-OS compliant

### Phase WK1 — Wiki bootstrap (1 weekend)

Create the missing layer: a single canonical knowledge base, structured per Karpathy.

```
walter-os/
└── wiki/                           # NEW. The operator's compounding KB.
    ├── index.md                    # auto-maintained catalog (LLM rebuilds)
    ├── log.md                      # append-only chronological log
    ├── people/                     # entity pages: Person → role + links
    ├── companies/
    ├── concepts/                   # ideas, theorems, definitions
    ├── decisions/                  # ADRs across all projects (example work org, example civic app, example medical app)
    ├── tools/                      # tools/services the operator uses
    ├── topics/                     # broad topical hubs (e.g. solana, postgres, regulatory-AR)
    └── sources/                    # one summary page per ingested source
```

**Key design decisions:**

1. **Wiki location**: inside `walter-os/wiki/`, **not** in Obsidian vault. Reason: Walter-OS is the cross-tool source-of-truth; Obsidian vault stays for daily journaling + raw notes (the "raw sources" layer per Karpathy).
2. **Sync**: `wiki/` syncs through the existing `agent-memory` Syncthing folder (already cross-device). Add `wiki/` symlink target there.
3. **Privacy**: `wiki/` is gitignored from the public `walter-os` repo (it contains operator-specific notes), but committed to a **private** Forgejo mirror at `git.${WALTER_DOMAIN}/operator/walter-wiki` (e.g. `git.example.com/operator/walter-wiki`). Walter-OS itself stays public.
4. **Obsidian compatibility**: use `[[wikilinks]]` syntax; Obsidian opens `wiki/` as a vault directly when needed.

### Phase WK2 — Wiki schema (the contract)

New file: `wiki/SCHEMA.md` — operator-facing description of how the wiki is structured. Loaded by the agent like a context overlay when operator is in `wiki/` cwd.

Skeleton:

```markdown
# Walter-OS Wiki — Schema

Read this first when ingesting, querying, or linting the wiki.

## Page types

- people/<slug>.md       — proper noun (the operator, ColabFold authors, example work org clients).
                           Header: name, role, contexts, current_status.
                           Body: facts, conversations, links.
- companies/<slug>.md    — orgs (example work org, Anthropic, Hetzner, AFIP).
- concepts/<slug>.md     — abstract idea (eMVO, Geyser plugin, EIP-7702).
- decisions/<slug>.md    — ADR. Header: date, context, decision, consequences.
- tools/<slug>.md        — software/services. Header: vendor, tier, alternatives.
- topics/<slug>.md       — hub page (linking many other pages on a theme).
- sources/<YYYY-MM-DD>-<slug>.md — one per ingested source.

## Cross-link rules

- Every page MUST link from at least one topic/<topic>.md hub.
- Every entity (people, companies) referenced in a source MUST have a stub
  page (or an existing one updated) — no orphan references.
- Decisions MUST link to the topics they affect.

## index.md format

Auto-rebuilt by `walter-os wiki lint`:
- # categories
- alphabetical list of pages with one-line summaries
- last-modified date

## log.md format

Append-only:
  ## [2026-MM-DD] <op> | <slug>

where <op> ∈ {ingest, query, lint, decision, refactor}.
```

### Phase WK3 — Operations (the loops)

#### Ingest

New skill: `skills/wiki-ingest/SKILL.md`. New slash command: `/ingest <url-or-path>`.

Flow:
1. Operator: `/ingest https://example.com/article` OR `/ingest ~/Downloads/whitepaper.pdf`.
2. Agent reads source.
3. Agent proposes a summary page (`sources/YYYY-MM-DD-<slug>.md`) for operator review.
4. Operator approves or refines.
5. Agent identifies entities, concepts, decisions in the source → updates / creates corresponding pages.
6. Agent updates `index.md` with new entries.
7. Agent appends to `log.md`: `## [2026-05-05] ingest | <slug>`.
8. Operator commits.

#### Query

New skill: `skills/wiki-query/SKILL.md`.

Flow:
1. Agent receives operator question.
2. Before web/RAG: `cat wiki/index.md | grep <relevant-terms>` → load matching pages.
3. If wiki has the answer → cite.
4. If wiki doesn't → web/MCP search → answer → **propose new wiki page**.
5. Operator approves → agent files the answer.

#### Lint

New skill: `skills/wiki-lint/SKILL.md`. New subcommand: `walter-os wiki lint`.

Checks:
- Orphan pages (no inbound links).
- Broken `[[wikilinks]]`.
- Stale claims (pages with `last_verified:` older than N days for time-sensitive content).
- Contradictions across pages (LLM scan).
- Missing entities (people/companies referenced but no page exists).
- `index.md` consistent with directory contents.

Run in CI on the private wiki repo + monthly via cron.

### Phase WK4 — Walter-OS integration

1. New CLI subcommand: `walter-os wiki {ingest|query|lint|status}`.
2. New context overlay: `contexts/wiki/AGENTS.md` (loads when cwd is `walter-os/wiki/`).
3. New hook: `wiki-validity-gate.sh` — if `wiki/log.md` hasn't grown in N days and the operator opens a session in `walter-os/wiki/`, prompt to lint.
4. Index the wiki in MCP `memory` server so all sessions can query it without explicit ingestion.

---

## 4. What this gives the operator (concretely)

**Before** (today):
- Operator reads a paper → notes go into Obsidian vault → never re-discovered → eventually forgotten.
- Agent answers a question → reasoning evaporates → next session re-derives from scratch.
- Decisions across example work org / example civic app / example medical app made in PR descriptions → not findable later.

**After** (Phase WK1-4 done):
- Operator reads a paper → `/ingest` → 5-10 wiki pages updated/created with cross-links → next time agent is asked anything related, it pulls from those pages first.
- Decisions accumulate at `wiki/decisions/` — searchable across projects.
- Operator's accumulated knowledge **compounds** instead of evaporating.
- Agent on a new device pulls wiki via Syncthing → starts with full context.

---

## 5. Cost / complexity

| Phase | Effort | Value |
|---|---|---|
| WK1 (bootstrap dirs + SCHEMA.md) | 2-3h | Foundation only; no value yet. |
| WK2 (skills: ingest, query, lint) | 1-2 days | Real value starts here. |
| WK3 (loops + slash command + CLI) | 1 day | Workflow lands. |
| WK4 (integration + hooks + MCP indexing) | 1 day | Polish; compounding kicks in. |

Total: ~4-5 days of work.

**Should you do this?** Yes if you want compound learning across the projects you run. **Skip** if your knowledge management is fine as-is (Obsidian + memory only).

Operator's hint: Walter-OS should help across both work and personal contexts. The wiki is **exactly** the cross-context compounding layer that delivers on this. Recommend proceeding.

---

## 6. Open questions for operator

1. **Public or private wiki?** I assumed private (Forgejo mirror) given operator's notes will mix example work org confidential, example civic app legal, example medical app medical references. Confirm.
2. **Obsidian vault relationship.** Karpathy's pattern says LLM owns the wiki. Operator's Obsidian vault has personal journaling + raw notes that LLM should NOT rewrite. Decision: vault = "raw sources", wiki = "LLM-maintained derived knowledge". Move existing semi-structured notes into wiki/ over time, manually.
3. **MCP indexing**: index `wiki/` via the `memory` MCP, OR via a local BM25/vector store like `qmd` (Karpathy's recommendation)? `memory` is simpler; `qmd` is more powerful at scale (1000s of pages). v1 = `memory`; revisit at 200+ pages.
4. **Multi-context wiki**: one global `wiki/` shared across work/personal-projects/personal? Or three separate wikis per context? Recommend ONE — cross-context links are the value (e.g., "this Solana technique I learned at example work org applies to example medical app's on-chain attestation"). Privacy enforced at git-repo level (private Forgejo), not per-page.

---

## 7. Acceptance criteria

- [ ] `walter-os/wiki/` directory exists with `SCHEMA.md`, `index.md`, `log.md`.
- [ ] Three skills (`wiki-ingest`, `wiki-query`, `wiki-lint`) implemented + symlinked.
- [ ] `walter-os wiki {ingest|query|lint|status}` subcommands work.
- [ ] `/ingest` slash command produces a stub source page + entity updates.
- [ ] Lint catches an injected orphan page during testing.
- [ ] Wiki syncs to second device via Syncthing.
- [ ] Wiki excluded from public `walter-os` repo (gitignore) but committed to private mirror.

Implementation = follow-up phase WK1-4. This spec is the contract.
