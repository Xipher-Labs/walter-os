# Walter Founder Skills Extension (W-13b)

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-12
**Linear/Plane**: (assign before implementation starts)

## Problem

PR #64 (W-13) shipped six founder skills — `customer-interview-synthesizer`,
`pricing-experiment`, `cold-outreach-sequencer`, `content-writer`,
`weekly-review-coach`, and `competitor-radar` — raising average toolkit maturity
from 3.3 to 4.2 across ten founder-relevant areas. That is a meaningful
improvement, but it leaves several high-value domains underserved: quantitative
customer research, marketing strategy, long-form content, B2B sales documentation,
SaaS financial health, compliance readiness, personal decision tracking, and
structured learning.

A solo founder or small team relying on Walter-OS today can conduct qualitative
interviews and write short-form content, but has no skill for converting interview
findings into a validated survey, no strategy layer above content production, no
tooling for writing proposals or tracking SaaS metrics, and no way to systematically
extract and retain knowledge from books or papers. These gaps force the operator
out of the agent workflow for routine founder tasks that are well within the scope
of what a structured skill can accelerate.

Adding eight targeted skills closes the remaining gaps in a single bundle PR,
pushing average maturity from 4.2 to 4.7, and completing the founder toolkit to a
point where no area scores below 4.0.

## Proposed Solution

Deliver eight new skill directories under `skills/` following the same pattern
established by W-13: YAML frontmatter with auto-trigger keywords, six required
sections (When to use / When NOT to use / Inputs / Outputs / Sample usage / How it
composes), a `## Prompt for your AI` section where the skill emits paste-able
prompts, and at least one reference file per skill.

Each skill explicitly composes with existing W-13 and pre-W-13 skills rather than
duplicating their logic. The bats test suite gains a new test file
`tests/oss/founder-skills-extension.bats` covering all eight skills. The
`skills/INDEX.md` file is updated with the eight new entries grouped by domain.
All content is English-only, operator-neutral, and passes the existing
depersonalization test.

## Dependency

This PR depends on W-13 (PR #64) landing first. The skills `customer-interview-synthesizer`,
`pricing-experiment`, `content-writer`, `weekly-review-coach`, and `competitor-radar`
are referenced in compose sections and must exist in `skills/` before the CI
frontmatter lint can validate cross-references. Branch this off `dev` after PR #64
merges, not off `feature/oss-license-agplv3`.

## The Eight Skills

### 1. `survey-design` (Customer Research +0.5)

Helps founders design quantitative surveys (NPS, CSAT, CES, PMF fit) to
complement qualitative interviews. Outputs a validated question battery, sample
size guidance, distribution channel suggestions, and response-rate-boost
techniques. Composes with `customer-interview-synthesizer` for the
qualitative-to-quantitative pipeline. Reference file covers Sean Ellis PMF
framework, NPS, CSAT, and CES scoring rubrics.

### 2. `marketing-strategist` (Marketing +1.0)

Strategy-level marketing: SEO audit (keyword gap analysis, technical SEO
checklist), 12-week rolling content calendar, platform-specific social strategy
with cadence and KPIs, and a distribution playbook covering HN, Reddit, LinkedIn,
X, and niche communities. Explicitly NOT content production — that is
`content-writer`'s domain. Composes with `competitor-radar` (signal feed),
`content-writer` (downstream execution), and `landing-page-fast` (page strategy).
Three reference files: SEO checklist, content calendar template, distribution
channels guide.

### 3. `proposal-writer` (Sales +0.5)

Generates B2B proposals for consulting, SaaS, or agency engagements. Outputs an
executive summary, statement of work with deliverables and milestones, pricing
breakdown (fixed / T&M / retainer), terms summary (IP, payment, exit), and an
appendix with case study placeholders. Two reference files: SOW template and
pricing models.

### 4. `saas-metrics-dashboard` (Sales / Finance +0.5)

Calculates and interprets SaaS metrics: MRR, ARR, churn, LTV, CAC, Quick Ratio,
Magic Number, and Rule of 40. Accepts CSV or YAML input. Benchmarks computed values
against per-stage norms (pre-PMF / $0-1M / $1-10M / $10M+) and produces a
diagnosis identifying where to focus. Optionally composes with `postgres-cli` when
the operator's analytics DB is queryable. Reference file: per-stage benchmark
table.

### 5. `compliance-prep-toolkit` (Security / Risk +0.5)

Pre-audit checklists for GDPR, SOC 2, PCI-DSS, ISO 27001, and HIPAA. Each
framework starts with a five-question applicability check that tells the operator
whether the framework applies before they read further. Outputs a self-assessment
checklist with evidence templates, a gap analysis, and a remediation priority
order. Explicitly not a substitute for legal counsel. Composes with
`medical-data-compliance` (HIPAA is covered there; this skill adds the remaining
four frameworks). Five reference files, one per framework.

### 6. `decision-journal` (Personal Effectiveness +0.5)

Captures significant decisions in a structured format — context, alternatives
considered, selected option with rationale, expected outcome and success criteria,
confidence level, and a revisit date. Stores entries at
`~/.config/walter-os/state/decisions/YYYY-MM-DD-<slug>.md` (out-of-repo,
operator-private). The revisit prompt surfaces past-due entries and walks the
operator through a retrospective assessment. Composes with `weekly-review-coach`
(surfaces upcoming revisit dates) and any `learn-by-mistake` skill if present.
Reference file: decision template.

### 7. `long-form-content` (Content +0.5)

Long-form writing in three modes: essays (3,000-8,000 words with thesis, pillar
arguments, counter-position, and synthesis), podcast preparation (episode outline
with 8-12 question blocks, talking points, transitions, sound bites, and show
notes), and conference talks (hook, three-act structure, slide deck outline,
speaker notes, Q&A prep, and CFP abstract). Default essay length: 3,500 words.
Composes with `content-writer` (short-form sibling) and `brand-creation` (voice
loading). Three reference files: essay structure, podcast prep template, talk
outline framework.

### 8. `knowledge-extraction` (Learning +1.0)

Extracts structured knowledge from books, papers, articles, or any Markdown source
in two phases. Phase A produces key claims with citations, named frameworks and
mental models, actionable takeaways, open questions, and suggested follow-up reads.
Phase B converts extracted claims into Anki/Mochi-compatible cards (Q/A format)
with target review intervals. Cards stored at
`~/.config/walter-os/state/knowledge/YYYY-MM/<source-slug>.md` (out-of-repo).
No actual Anki/Mochi sync — operator imports the file. Composes with
`weekly-review-coach` (surfaces due reviews). Two reference files: Anki card
format guide and extraction template.

## Acceptance Criteria

- [AC-1] 8 new skill directories exist under `skills/<name>/` each with a
  `SKILL.md` and at least one reference file under `skills/<name>/references/`.
- [AC-2] Each `SKILL.md` has valid YAML frontmatter with `name` and `description`
  fields parseable by `python3 -c "import yaml; yaml.safe_load(open(...).read())"`.
- [AC-3] Each description field includes the auto-trigger keywords listed in the
  skill definitions above and is verifiable by a keyword regex check in the bats
  test.
- [AC-4] Each `SKILL.md` contains all six required sections as anchored headings:
  `## When to use`, `## When NOT to use`, `## Inputs`, `## Outputs`,
  `## Sample usage`, `## How it composes`.
- [AC-5] All prose content is English. No operator-personal identifiers (names,
  project names, company names specific to the operator) appear in any new file.
  The existing `tests/oss/depersonalization.bats` passes without modification.
- [AC-6] `skills/INDEX.md` is updated with 8 new entries, each categorized under
  its matching group: Customer Research, Marketing, Sales, Security/Risk, Personal,
  Content, Learning.
- [AC-7] `tests/oss/founder-skills-extension.bats` exists and, for each of the 8
  skills, asserts: directory exists, `SKILL.md` exists, frontmatter parses as
  valid YAML, each required section heading is present as an anchored regex match,
  and no banned patterns appear.
- [AC-8] The CI workflow that currently covers `skills/**` via frontmatter lint
  (`tests/lint-frontmatter.sh`) runs on the new skills without modification. A new
  step invoking `bats tests/oss/founder-skills-extension.bats` is added to the
  appropriate CI job (or a new `oss-skills` job if no `tests/oss/` step exists).
- [AC-9] Each skill description is fewer than 500 characters (enforced by the
  bats test via `wc -c` on the extracted description value).
- [AC-10] Each skill's `## How it composes` section names at least one existing
  Walter-OS skill by its directory name in backtick format.

## Non-Goals

- No integration with external CRMs, survey tools, or spreadsheet APIs. Skills
  produce prompts and templates for operator use, not live data pipelines.
- No translation to Spanish. Content is English-only per the request.
- No replacement or modification of any W-13 skill. This bundle extends, not
  changes.
- No actual Anki or Mochi sync implementation. `knowledge-extraction` writes card
  files; the operator imports them manually.
- No SaaS metrics dashboard UI. That belongs to Control Tower. This skill
  computes metrics from operator-provided data and reports them as structured text.
- No legal advice in `compliance-prep-toolkit`. The skill generates checklists
  and gap analyses as preparation for engaging real auditors, not as a substitute.

## Open Questions

- None blocking. The five pre-launch decisions in the Implementation Plan section
  are resolved with documented defaults; operator can override at implementation
  time.

## References

- W-13 spec: `docs/specs/walter-marketing-core.md` (PR #64)
- Skill pattern reference: `skills/brand-creation/SKILL.md`,
  `skills/landing-page-fast/SKILL.md`
- Frontmatter lint: `tests/lint-frontmatter.sh`
- Depersonalization bats (when merged from W-13 branch):
  `tests/oss/depersonalization.bats`
