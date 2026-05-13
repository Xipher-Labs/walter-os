# Implementation Plan: walter-founder-skills-extension

Spec: `docs/specs/walter-founder-skills-extension.md`
Branch: cut from `dev` after PR #64 (W-13) merges.
Commit footer on every commit: `Refs: docs/specs/walter-founder-skills-extension.md`

## Pre-launch decisions (locked defaults, operator may override)

1. `knowledge-extraction` state location: `~/.config/walter-os/state/knowledge/YYYY-MM/<source-slug>.md`
2. `decision-journal` state location: `~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md`
3. `compliance-prep-toolkit` applicability gate: five yes/no questions per framework; if operator answers N to all, that framework's checklist is skipped.
4. `saas-metrics-dashboard` input format: CSV or YAML, both supported; skill asks the operator which format they have.
5. `long-form-content` essay default length: 3,500 words.

---

## Task 1: Bootstrap bats test file (skeleton with failing assertions) [AC-7, AC-8]

- File: `tests/oss/founder-skills-extension.bats` (new)
- Change: Write the skeleton test file with a `@test` block for each of the 8
  skills. Each block asserts:
  1. `[ -d "skills/<name>" ]` — directory exists.
  2. `[ -f "skills/<name>/SKILL.md" ]` — SKILL.md exists.
  3. Frontmatter YAML is valid: `python3 -c "import yaml; ..."`.
  4. Each of the 6 required headings matches `grep -qE "^## When to use"`, etc.
  5. Description is fewer than 500 chars.
  6. No banned patterns (operator personal identifiers; same list as
     `tests/oss/depersonalization.bats` when it exists, otherwise a hardcoded
     list: `example work org`, `example civic app`, `example medical app`, `maintainer-domain`, `operator-name`).
  All 8 blocks will FAIL at this point (RED). Keep them failing until the skill
  files are written.
- Verify: `bats tests/oss/founder-skills-extension.bats` exits non-zero with 8
  failures (all skill directories missing). This is the expected RED state.

---

## Task 2: `survey-design` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/survey-design/SKILL.md` (new)
  - `skills/survey-design/references/survey-frameworks.md` (new)
- Change:
  - `SKILL.md`: YAML frontmatter with `name: survey-design` and description
    containing trigger keywords: `survey design`, `NPS survey`, `PMF survey`,
    `satisfaction survey`, `Likert scale`. Description under 500 chars.
    Six required sections. `## Prompt for your AI` section with a paste-able
    prompt template for generating a question battery. `## How it composes`
    names `customer-interview-synthesizer`.
  - `references/survey-frameworks.md`: Sean Ellis PMF framework (40% "very
    disappointed" threshold), NPS (-100 to +100, Promoters/Passives/Detractors),
    CSAT (1-5 scale, target >80%), CES (Customer Effort Score, 1-7), sample size
    formula for 95% confidence with margin of error table.
- Verify: `bats tests/oss/founder-skills-extension.bats` — the `survey-design`
  block passes. 7 remaining blocks still fail.

---

## Task 3: `marketing-strategist` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/marketing-strategist/SKILL.md` (new)
  - `skills/marketing-strategist/references/seo-checklist.md` (new)
  - `skills/marketing-strategist/references/content-calendar-template.md` (new)
  - `skills/marketing-strategist/references/distribution-channels.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `marketing strategy`,
    `SEO audit`, `content calendar`, `social strategy`, `distribution playbook`,
    `go-to-market plan`. Six required sections covering four phases (SEO audit,
    content calendar, social strategy, distribution). `## Prompt for your AI`
    section. `## How it composes` names `competitor-radar`, `content-writer`,
    `landing-page-fast`.
  - `references/seo-checklist.md`: technical SEO checklist (sitemap.xml,
    robots.txt, schema.org markup, Core Web Vitals targets, canonical URLs,
    hreflang, 301 redirect hygiene, crawl budget, keyword research process).
  - `references/content-calendar-template.md`: 12-week rolling table with columns
    Week / Theme / Content type / Target keyword / Distribution channels / Owner /
    Status.
  - `references/distribution-channels.md`: tiered channel list (Tier 1: HN Show
    HN, Reddit r/startups, LinkedIn; Tier 2: Product Hunt, X/Twitter, niche
    subreddits; Tier 3: newsletters, podcasts, communities) with posting cadence
    and format notes per channel.
- Verify: `bats tests/oss/founder-skills-extension.bats` — `marketing-strategist`
  block passes. 6 remaining blocks still fail.

---

## Task 4: `proposal-writer` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/proposal-writer/SKILL.md` (new)
  - `skills/proposal-writer/references/sow-template.md` (new)
  - `skills/proposal-writer/references/pricing-models.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `proposal writer`,
    `RFP response`, `statement of work`, `SOW`, `B2B proposal`. Six required
    sections covering five output sections (executive summary, SOW, pricing,
    terms, appendix). `## Prompt for your AI` section. `## How it composes`
    names `cold-outreach-sequencer` (upstream lead context) and
    `pricing-experiment` (pricing rationale).
  - `references/sow-template.md`: structured SOW template with sections:
    Project overview, Scope of work (in-scope / out-of-scope), Deliverables
    (table: deliverable / format / due date / acceptance criteria), Timeline
    (phases + milestones), Assumptions and dependencies, Change management
    process.
  - `references/pricing-models.md`: comparison of fixed-price, T&M, retainer,
    value-based, and milestone-based models with when to use each, risk profile,
    and example rate card structures.
- Verify: `bats tests/oss/founder-skills-extension.bats` — `proposal-writer`
  block passes. 5 remaining blocks still fail.

---

## Task 5: `saas-metrics-dashboard` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/saas-metrics-dashboard/SKILL.md` (new)
  - `skills/saas-metrics-dashboard/references/saas-benchmarks.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `MRR calculation`, `ARR`,
    `churn rate`, `LTV CAC`, `Quick Ratio`, `SaaS metrics`, `unit economics`.
    Six required sections. Inputs section describes CSV format
    (columns: month, new_mrr, expansion_mrr, churned_mrr, new_customers,
    churned_customers, cac_spend) and YAML equivalent. Outputs section lists
    computed metrics with formulas. `## Prompt for your AI` section with a
    metrics computation prompt. `## How it composes` names `postgres-cli`
    (optional, when analytics DB is queryable).
  - `references/saas-benchmarks.md`: per-ARR-stage benchmark table covering
    MRR growth rate, net revenue retention, gross revenue churn, LTV:CAC ratio,
    Quick Ratio, Magic Number, and Rule of 40 for stages: pre-PMF / $0-1M /
    $1-10M / $10-50M / $50M+. Sources: Bessemer, OpenView, SaaStr benchmarks.
- Verify: `bats tests/oss/founder-skills-extension.bats` — `saas-metrics-dashboard`
  block passes. 4 remaining blocks still fail.

---

## Task 6: `compliance-prep-toolkit` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/compliance-prep-toolkit/SKILL.md` (new)
  - `skills/compliance-prep-toolkit/references/gdpr.md` (new)
  - `skills/compliance-prep-toolkit/references/soc2.md` (new)
  - `skills/compliance-prep-toolkit/references/pci-dss.md` (new)
  - `skills/compliance-prep-toolkit/references/iso27001.md` (new)
  - `skills/compliance-prep-toolkit/references/hipaa-light.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `GDPR compliance`,
    `SOC2 prep`, `PCI-DSS checklist`, `ISO 27001`, `compliance audit prep`.
    Six required sections. When to use covers all five frameworks. When NOT to
    use includes "when you need actual legal sign-off or formal certification
    — engage an auditor". `## Prompt for your AI` section. `## How it composes`
    names `medical-data-compliance` (HIPAA overlap) and `web-security-baseline`.
  - Each reference file follows the same structure: (a) 5-question applicability
    check, (b) scope summary (3-4 sentences), (c) self-assessment checklist with
    control IDs and evidence template column, (d) common gaps for early-stage
    companies, (e) remediation priority order (P1/P2/P3).
- Verify: `bats tests/oss/founder-skills-extension.bats` — `compliance-prep-toolkit`
  block passes. 3 remaining blocks still fail.

---

## Task 7: `decision-journal` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/decision-journal/SKILL.md` (new)
  - `skills/decision-journal/references/decision-template.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `decision journal`,
    `log this decision`, `important decision`, `decision review`. Six required
    sections. Inputs section specifies the seven fields (context, options
    considered, selected option, rationale, expected outcome, confidence 1-10,
    revisit date). Outputs section describes the stored Markdown file at
    `~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md` and the revisit
    prompt behavior. `## Prompt for your AI` section with a structured prompt
    that walks through each field. `## How it composes` names
    `weekly-review-coach`.
  - `references/decision-template.md`: the Markdown template that gets written
    per decision, with placeholder comments for each field and an example
    decision filled in.
- Verify: `bats tests/oss/founder-skills-extension.bats` — `decision-journal`
  block passes. 2 remaining blocks still fail.

---

## Task 8: `long-form-content` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/long-form-content/SKILL.md` (new)
  - `skills/long-form-content/references/essay-structure.md` (new)
  - `skills/long-form-content/references/podcast-prep-template.md` (new)
  - `skills/long-form-content/references/talk-outline-framework.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `essay`, `long-form`,
    `podcast prep`, `conference talk`, `talk outline`, `CFP abstract`,
    `speaker notes`. Six required sections. Three modes documented in Outputs
    (essay / podcast prep / conference talk). Default essay length: 3,500 words.
    `## Prompt for your AI` section with mode-specific prompt templates.
    `## How it composes` names `content-writer` and `brand-creation`.
  - `references/essay-structure.md`: thesis-driven essay structure (hook,
    context, thesis, 3-5 pillar arguments each with evidence + counter-position,
    synthesis, call-to-action). Citation discipline notes.
  - `references/podcast-prep-template.md`: episode outline template (title,
    guest bio one-liner, 3-sentence premise, 8-12 question blocks each with
    primary question + follow-up probes + transition, sound bite targets, outro,
    show notes structure).
  - `references/talk-outline-framework.md`: three-act structure for conference
    talks (act 1: hook + problem frame, act 2: solution + evidence + stories,
    act 3: synthesis + call-to-action). Slide count guidance per duration
    (15min / 30min / 45min). CFP abstract template. Q&A prep checklist.
- Verify: `bats tests/oss/founder-skills-extension.bats` — `long-form-content`
  block passes. 1 remaining block still fails.

---

## Task 9: `knowledge-extraction` skill [AC-1, AC-2, AC-3, AC-4, AC-5, AC-9, AC-10]

- Files:
  - `skills/knowledge-extraction/SKILL.md` (new)
  - `skills/knowledge-extraction/references/anki-format.md` (new)
  - `skills/knowledge-extraction/references/extraction-template.md` (new)
- Change:
  - `SKILL.md`: frontmatter with trigger keywords: `extract knowledge`,
    `summarize paper`, `book notes`, `Anki cards`, `spaced repetition`,
    `learning from`. Six required sections. Two-phase structure documented:
    Phase A (extract) and Phase B (spaced repetition). State location for card
    files: `~/.config/walter-os/state/knowledge/YYYY-MM/<source-slug>.md`.
    `## Prompt for your AI` section with phase-specific prompts. `## How it
    composes` names `weekly-review-coach`.
  - `references/anki-format.md`: Anki card format (front / back / tags /
    interval hint), Mochi equivalent, guidance on card granularity (one fact
    per card, minimum information principle), example cards from a fictional
    source.
  - `references/extraction-template.md`: the Markdown template written per
    source, with sections: source metadata, key claims (table: claim / citation /
    confidence H/M/L), frameworks and mental models, actionable takeaways,
    open questions, follow-up reads, cards (Phase B output).
- Verify: `bats tests/oss/founder-skills-extension.bats` — all 8 blocks now pass
  (full GREEN). `bats tests/oss/founder-skills-extension.bats` exits 0.

---

## Task 10: `skills/INDEX.md` update + CI wiring [AC-6, AC-8]

- Files:
  - `skills/INDEX.md` (modify — create if it does not exist yet)
  - `.github/workflows/ci.yml` (modify)
- Change:
  - `skills/INDEX.md`: add a section header for each of the relevant groups
    (Customer Research, Marketing, Sales, Security/Risk, Personal, Content,
    Learning) if not already present. Add one entry per new skill with its
    trigger keywords and a one-line summary. Preserve all existing entries.
  - `.github/workflows/ci.yml`: identify the job that runs bats tests
    (currently the `bats` job running `tests/hooks/`, `tests/agents/`,
    `tests/wiki/`). Add `tests/oss/` to the bats invocation, or add a separate
    `oss-skills` job that runs:
    ```
    bats tests/oss/
    ```
    Confirm `python3-yaml` is already installed in that job (it is — see the
    `bats` job's `Install bats + jq + flock + sqlite3 + python3-yaml` step).
    If the `tests/oss/` directory is new, the directory is created implicitly
    by Task 1.
- Verify:
  1. `grep -c "survey-design\|marketing-strategist\|proposal-writer\|saas-metrics-dashboard\|compliance-prep-toolkit\|decision-journal\|long-form-content\|knowledge-extraction" skills/INDEX.md` returns 8.
  2. `grep -E "tests/oss" .github/workflows/ci.yml` matches at least one line.
  3. Full test run: `bats tests/oss/founder-skills-extension.bats` exits 0.
  4. `./tests/lint-frontmatter.sh` exits 0 (all 8 new SKILL.md files pass
     frontmatter lint).

---

## Commit sequence (one commit per task)

```
feat(skills): add survey-design skill — quantitative survey design for founders
feat(skills): add marketing-strategist skill — SEO, content calendar, distribution
feat(skills): add proposal-writer skill — B2B proposals and SOW generation
feat(skills): add saas-metrics-dashboard skill — MRR/ARR/churn/LTV computation
feat(skills): add compliance-prep-toolkit skill — GDPR/SOC2/PCI/ISO/HIPAA checklists
feat(skills): add decision-journal skill — structured decision capture and review
feat(skills): add long-form-content skill — essays, podcast prep, conference talks
feat(skills): add knowledge-extraction skill — extract and retain structured knowledge
feat(skills): add founder-skills-extension bats tests [AC-7]
feat(skills): update INDEX.md + wire tests/oss to CI [AC-6, AC-8]
```

Task 1 (bats skeleton) commits first; tasks 2-9 each commit skill + turn their
bats block green; task 10 commits last. This keeps the commit history meaningful
and each intermediate commit buildable (CI runs only the tests that are green,
bats exits non-zero until task 9 completes — accept this in draft PR, gate merge
on final green).

Alternative sequencing for CI cleanliness: write the bats file as a final task
(after all 8 skills exist) in a single commit. Either ordering satisfies the ACs.
Operator chooses at implementation time.

## Definition of Done checklist

- [ ] All 8 skill directories exist with SKILL.md + reference files
- [ ] `bats tests/oss/founder-skills-extension.bats` exits 0
- [ ] `./tests/lint-frontmatter.sh` exits 0
- [ ] `skills/INDEX.md` has 8 new entries
- [ ] CI workflow runs `tests/oss/` (new job or extended bats job)
- [ ] Reviewer subagent has approved
- [ ] Copilot review requested via REST API after `gh pr create`
- [ ] No operator-personal identifiers in any new file
