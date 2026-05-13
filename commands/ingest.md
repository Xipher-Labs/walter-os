---
description: Ingest a source (URL, file path, or pasted text) into the operator's LLM-maintained wiki at $WALTER_OS_HOME/wiki/. Reads the source, drafts a sources/<date>-<slug>.md page, identifies referenced entities (people / companies / tools / concepts), creates stub pages with `[[wikilinks]]`, updates topic hubs, and appends to log.md. Apply the wiki-ingest skill.
argument-hint: <url-or-path-or-pasted-text>
---

You are about to ingest a source into the operator's wiki.

**Source**: $ARGUMENTS

Apply the **wiki-ingest** skill (see `$WALTER_OS_HOME/skills/wiki-ingest/SKILL.md`). The contract:

1. Read `$WALTER_OS_HOME/wiki/SCHEMA.md` first — it's binding.
2. Acquire the source (WebFetch URL / Read file / use pasted text).
3. Draft `wiki/sources/$(date +%Y-%m-%d)-<slug>.md` with the prescribed frontmatter.
4. Identify all referenced entities — people, companies, tools, concepts. For each:
   - If a wiki page exists, plan an update.
   - If not, plan a stub page in the right canonical dir (people/, companies/, tools/, concepts/).
5. Identify which topic hub(s) this source contributes to. Plan additions to `topics/<topic>.md`.
6. Plan a `log.md` append entry.

**Show the operator the proposed changes BEFORE writing anything.** They approve, then you write to disk. After approval, run `walter-os wiki commit "ingest: <slug>"` to push to the private mirror.

A single source typically touches **5-15 wiki pages**. If you only touch 1-2, you probably under-ingested — re-scan for entities you missed.
