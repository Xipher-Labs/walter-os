# Business Consulting Pack — Integration Evaluation

**Status**: Draft
**Owner**: architect
**Created**: 2026-05-11
**Source pack**: `<operator-home>/Downloads/walter_os_business_consulting_pack/`

---

## Per-file categorization

---

### File: `README.md`

**Category**: REFERENCE

**Rationale**: High-level framing and the mermaid DAG. Useful as orientation
doc but contains no executable skill logic. The principle statement ("Walter-OS
should improve the founder's judgment, not help build anything") is worth
absorbing into `AGENTS.md` contexts/projects-personal, not a standalone file.

**Walter-OS integration path**:
- Target: Surface the 4-mode taxonomy (Triage / Deep Validation / Market /
  Brand+GTM) in the `contexts/projects-personal/AGENTS.md` introduction so
  the agent loads it for every personal project.
- Estimated effort: 0.5h (prose addition to existing AGENTS.md)
- Dependencies: none
- Trigger conditions: always loaded in projects-personal context

**Conflicts with existing**: None.

---

### File: `00_WALTER_OS_BUSINESS_CONSULTING_BRIEF.md`

**Category**: MERGE into `hackathon-spinup` Phase -1 + new `idea-triage` trigger

**Rationale**: This is the richest conceptual file. The "3 errors" framing
(solution without problem / late entry without wedge / product without
business) and the 5 operating modes (A–E) are exactly what Phase -1 of
`hackathon-spinup` attempts to do conversationally. However Phase -1 is
hackathon-scoped and optimistic; the brief's framing is adversarial and
general. The `Idea Brief` input template (section 6) and `Founder Decision
Memo` output template (section 7) are immediately reusable. The Build / Pivot /
Park / Kill decision framework with explicit criteria (section 8) is the
highest-value fragment.

**Walter-OS integration path**:
- Merge the B/P/P/K decision rules and the 5 operating modes into
  `hackathon-spinup` Phase -1 as a decision gate.
- Extract the `Idea Brief` input template and `Founder Decision Memo` output
  template into `templates/business/idea-brief.md` and
  `templates/business/founder-decision-memo.md`.
- Estimated effort: 1h
- Dependencies: none
- Trigger conditions: any time Phase -1 of hackathon-spinup runs; also
  standalone when user says "evaluate this idea", "should I build X"

**Conflicts with existing**:
- `hackathon-spinup` Phase -1 already does a 2-pass thinking-model
  interrogation. The 5 operating modes from this brief map roughly to the
  two passes, but are broader. Merge direction: Phase -1 stays as the
  execution protocol; this brief provides the decision taxonomy that
  Phase -1 currently lacks.

---

### File: `01_AGENT_ORCHESTRATOR.md`

**Category**: DIRECT FIT — new skill `idea-triage` (orchestrator role)

**Rationale**: This is the coordinator that decides which specialist agents to
invoke based on idea maturity. Walter-OS currently has no equivalent. The
`architect` agent handles spec production for known ideas, but there is no
agent whose job is to question whether an idea is worth speccing at all. This
fills that gap. The routing table (Situation → Required Agents) and the
Force Decision Clarity rule ("no 'depende' as a final answer") are directly
usable. The output format maps cleanly to a Walter-OS skill output.

**Walter-OS integration path**:
- Skill name: `idea-triage`
- Target directory: `skills/idea-triage/SKILL.md`
- The skill becomes the entry point that dispatches sub-skills
  (`business-validation`, `market-competition`, `differentiation-positioning`,
  etc.) based on the routing table.
- Add trigger: "should I build X", "evaluate this idea", "is X worth building",
  "new project idea"
- Estimated effort: 1.5h (write SKILL.md, wire trigger keywords)
- Dependencies: sub-skills listed below

**Conflicts with existing**:
- `hackathon-spinup` Phase -1 overlaps partially. Resolution: `idea-triage`
  is the general-purpose pre-build gate; `hackathon-spinup` Phase -1 becomes
  a consumer of it when the idea is hackathon-bound.
- `architect` agent: no conflict — architect runs after triage approves Build.

---

### File: `02_AGENT_BUSINESS_VALIDATION.md`

**Category**: DIRECT FIT — new skill `business-validation`

**Rationale**: Contains a self-contained validation framework: 5 scored
dimensions (problem clarity, customer specificity, urgency, WTP,
founder-market fit), a 10-question customer interview plan, and 4 fast
validation experiments with measurable success signals. None of this exists
in Walter-OS today. The red flags list is particularly useful as a blocker
checklist before entering the build path. The output template is clean and
structured.

**Walter-OS integration path**:
- Skill name: `business-validation`
- Target directory: `skills/business-validation/SKILL.md`
- Trigger: invoked by `idea-triage`; also directly when user says "validate
  this idea", "is there demand for X"
- Estimated effort: 1h (adapt to SKILL.md format, keep content intact)
- Dependencies: none (standalone; outputs feed into `differentiation-positioning`)

**Conflicts with existing**: None material. `hackathon-spinup` Phase -1 has
thinking-model interrogation but no scoring rubric.

---

### File: `03_AGENT_MARKET_COMPETITION.md`

**Category**: DIRECT FIT — new skill `market-competition`

**Rationale**: Structured competitor taxonomy (Direct / Indirect / Substitute
workflows / Internal / Non-consumption) plus saturation scoring and a market
gaps framework. The web_search tool suggestion in `10_MCP_SKILL_MANIFEST_EXAMPLE.md`
is already present in Walter-OS (brave_search MCP loaded by default). This
skill slots in naturally. The `market attractiveness` scorecard (10 dimensions)
is a valuable complement to the technical-oriented scorecards already in
Walter-OS.

**Walter-OS integration path**:
- Skill name: `market-competition`
- Target directory: `skills/market-competition/SKILL.md`
- Add explicit dependency on `brave_search` MCP for live data enrichment.
- Trigger: invoked by `idea-triage`; also "research the market for X",
  "who are the competitors in X"
- Estimated effort: 1h
- Dependencies: `brave_search` MCP (already loaded in default profile)

**Conflicts with existing**: None.

---

### File: `04_AGENT_DIFFERENTIATION_POSITIONING.md`

**Category**: DIRECT FIT — new skill `differentiation-positioning`

**Rationale**: The wedge framework (specific / painful / accessible /
monetizable / defensible / expandable) and the positioning statement template
(`For [ICP] who suffer from [problem]...`) are immediately actionable. The
differentiator taxonomy (strong vs weak) directly addresses the
"more AI-powered" anti-pattern that Walter-OS's philosophy already flags.
The positioning stress test (10 questions) acts as a DoD validator for
positioning work. This is the most "upstream" impact skill — bad positioning
kills everything downstream.

**Walter-OS integration path**:
- Skill name: `differentiation-positioning`
- Target directory: `skills/differentiation-positioning/SKILL.md`
- Trigger: invoked by `idea-triage`; also "help me position X",
  "what's my wedge", "write a positioning statement"
- Estimated effort: 1h
- Dependencies: outputs from `business-validation` and `market-competition`
  are useful but not required

**Conflicts with existing**:
- `brand-creation` covers voice/tone but not strategic positioning. These are
  complementary: positioning-first, brand-creation-second. No conflict; the
  SKILL.md should note this sequence.

---

### File: `05_AGENT_BUSINESS_MODEL_GTM.md`

**Category**: DIRECT FIT — new skill `business-model-gtm`

**Rationale**: The GTM motion taxonomy (Founder-led / Content-led / Community /
PLG / Partner / Outbound / Paid / Enterprise) with "when to use" criteria is
the most operationally useful piece. The 30/60/90 plan structure and MVP
scoping discipline (Must / Should / Not Now) maps cleanly to the existing
Walter-OS spec format. The GTM validation experiments table (20 cold messages /
landing + waitlist / concierge MVP / etc.) with success signals is the kind of
concrete guidance hackathon-spinup lacks for the business track.

**Walter-OS integration path**:
- Skill name: `business-model-gtm`
- Target directory: `skills/business-model-gtm/SKILL.md`
- Trigger: invoked by `idea-triage`; also "create a GTM plan for X",
  "how do I monetize X", "pricing model for X"
- Estimated effort: 1h
- Dependencies: `differentiation-positioning` output (ICP, wedge)

**Conflicts with existing**:
- `hackathon-spinup` Phase 0 (idea lock) has a cut list and pitch; no
  business model section. `business-model-gtm` can be explicitly referenced
  from `hackathon-spinup` for the non-hackathon path.

---

### File: `06_AGENT_BRAND_COMMUNICATIONS_SOCIAL.md`

**Category**: MERGE into `brand-creation`

**Rationale**: `brand-creation` already covers moodboard, logo, palette,
typography, and voice-tone. The pack's agent adds: naming evaluation rubric
(clarity / memorability / domain / pronunciation / expansibility /
differentiation / legal risk), verbal identity kit (one-liner / tagline /
elevator pitch / homepage hero / social bio / founder pitch / email intro /
sales DM), and a social launch sequence template. These are distinct from what
`brand-creation` currently produces and fill a real gap — `brand-creation`
stops at the brand kit; this agent starts at "now how do you communicate it".

**Walter-OS integration path**:
- Merge the naming rubric, verbal identity kit, and social launch sequence
  into `skills/brand-creation/SKILL.md` as a new Phase 8 ("Communication Kit").
- The visual direction section is already covered (moodboard + palette +
  typography in existing phases). Skip duplication.
- Estimated effort: 1.5h (extend existing SKILL.md, keep existing phases intact)
- Dependencies: `differentiation-positioning` output (ICP, positioning statement)

**Conflicts with existing**:
- `brand-creation` Phase 6 (voice and tone) partially overlaps with this
  agent's verbal identity. Merge carefully — pack content is more granular
  (has homepage hero, sales DM, social bio as separate items).

---

### File: `07_AGENT_FINANCE_RISK_LEGAL_OPS.md`

**Category**: DIRECT FIT — new skill `finance-risk-ops`

**Rationale**: Unit economics framework (Price / Margin / CAC / LTV / Churn /
Payback) with Argentine-relevant considerations (taxes, payment fees, refunds,
export-of-services). The operational complexity score and legal/compliance flag
table are exactly what Walter-OS lacks before greenlighting a project. The
70% gross margin quick-check is a specific, verifiable gate. This is distinct
from `regulatory-research-argentina` (which is about specific statute lookups)
and distinct from `medical-data-compliance` (PHI-specific). Finance-risk-ops
is the general business viability gate.

**Walter-OS integration path**:
- Skill name: `finance-risk-ops`
- Target directory: `skills/finance-risk-ops/SKILL.md`
- Add note: for Argentine regulatory specifics → invoke
  `regulatory-research-argentina`; for medical data → invoke
  `medical-data-compliance`. This skill is the general wrapper.
- Trigger: invoked by `idea-triage`; also "unit economics for X",
  "is X profitable", "what are the legal risks of X"
- Estimated effort: 1h
- Dependencies: `regulatory-research-argentina` (optional, for AR-specific
  compliance items)

**Conflicts with existing**:
- `regulatory-research-argentina`: no conflict, complementary.
- `medical-data-compliance`: no conflict, complementary.

---

### File: `08_SCORECARDS.md`

**Category**: REFERENCE — `templates/business/scorecards.md`

**Rationale**: 8 scoring matrices (Founder Decision, Idea Triage, Market
Saturation, GTM Feasibility, Differentiation Strength, Brand Readiness, Risk
Severity, Build/Pivot/Park/Kill rules). These are shared resources referenced
by all specialist skills. They should not live inside any single skill — they
belong in a shared templates directory. The `definition-of-done-validator`
skill already uses a similar pattern. The Build/Pivot/Park/Kill thresholds
(avg score 8.0 = Build, 6.5-7.9 = Build after validation, etc.) are the
numeric backbone of the entire system and need a canonical location.

**Walter-OS integration path**:
- Target: `templates/business/scorecards.md` (new file)
- All business-related skills reference this file for scoring logic.
- Estimated effort: 0.25h (copy, minor formatting to match Walter-OS style)
- Dependencies: none

**Conflicts with existing**: None.

---

### File: `09_OUTPUT_TEMPLATES.md`

**Category**: REFERENCE — `templates/business/`

**Rationale**: 10 output templates (Idea Brief, Founder Decision Memo, Market
Research, Business Plan Lite, GTM Plan, Brand Platform, Landing Page Structure,
Social Launch Sequence, Customer Interview Script, Kill/Pivot Memo). These are
directly usable and high-value. The Landing Page Structure template overlaps
slightly with `landing-page-fast` section structure, but is more concise and
useful as a standalone template. The Customer Interview Script is missing
entirely from Walter-OS today.

**Walter-OS integration path**:
- Target directory: `templates/business/` (new)
- Extract each template to its own file:
  - `templates/business/idea-brief.md`
  - `templates/business/founder-decision-memo.md`
  - `templates/business/market-research.md`
  - `templates/business/business-plan-lite.md`
  - `templates/business/gtm-plan.md`
  - `templates/business/brand-platform.md`
  - `templates/business/landing-page-structure.md`
  - `templates/business/social-launch-sequence.md`
  - `templates/business/customer-interview-script.md`
  - `templates/business/kill-pivot-memo.md`
- Estimated effort: 0.5h
- Dependencies: none

**Conflicts with existing**:
- `landing-page-fast` has its own section structure. The template in `09`
  is simpler (doc-based, not code-based). Keep both: template for planning,
  skill for execution.

---

### File: `10_MCP_SKILL_MANIFEST_EXAMPLE.md`

**Category**: EXAMPLE

**Rationale**: A YAML manifest showing how the 7 agents could be wired into
an MCP server or cross-LLM registry. The model routing aliases
(`reasoning_best`, `research_best`, `creative_best`, `cheap_draft`) are a
useful pattern for Walter-OS Phase 2 when LiteLLM routing is fully operational.
The workflow definitions (`idea_triage`, `full_consulting_review`,
`brand_and_gtm_only`) map to the AGENTS.md `Loaded skills` section. The
scoring thresholds in YAML are a future machine-readable spec for the
`definition-of-done-validator`.

**Walter-OS integration path**:
- Keep as `docs/examples/business-consulting-manifest.yaml` for reference
  when wiring the LiteLLM gateway routing (Phase 2).
- The model routing aliases should inform the LiteLLM route config when that
  work happens — note this in the LiteLLM runbook.
- Estimated effort: 0.25h (copy, add header noting it is a future reference)
- Dependencies: LiteLLM gateway (Phase 2, separate spec)

**Conflicts with existing**: None.

---

## Overall analysis

### Coherence with Walter-OS philosophy

The pack is highly coherent. OSS-first: all content is plain markdown,
no vendor lock. Multi-agent: the orchestrator + 6 specialists pattern
mirrors exactly the Walter Council pattern (triage + researcher + coder +
reviewer + janitor + liaison). The adversarial tone ("not a compliant
assistant", "Build/Pivot/Park/Kill, never 'depends'") matches the
AGENTS.md operator preference for accuracy over agreement.

### Duplication audit

| Pack capability | Existing Walter-OS | Assessment |
|---|---|---|
| Idea validation | hackathon-spinup Phase -1 (partial) | Complementary — pack is general, spinup is hackathon-scoped |
| Brand identity | brand-creation (phases 1-7) | Partial overlap — pack adds naming rubric + verbal identity |
| GTM planning | hackathon-spinup Phase 0 (shallow) | Pack is significantly deeper |
| Market research | None | Gap filled by pack |
| Differentiation | None | Gap filled by pack |
| Unit economics | None | Gap filled by pack |
| Risk assessment | None | Gap filled by pack |
| Output templates | None (no `templates/business/`) | Gap filled by pack |
| Scorecards | None | Gap filled by pack |

### "Walter Business Council" pattern

Yes, this creates a parallel Council: Orchestrator + 6 specialists running
sequentially or selectively based on idea maturity. This is distinct from
the Walter Council (Phase R) which is a general-purpose code/research
council. The Business Council is domain-specific (idea → business validation
→ market → positioning → GTM → brand → finance). Both can coexist without
conflict — one triggers from engineering tasks, the other from founder-mode
business evaluation.

### Overlap with `founder-mode` skill

There is no `founder-mode` skill in the current skills directory — the
`hackathon-spinup` SKILL.md is the closest thing. The pack would be the
primary implementation of what a `founder-mode` might eventually be.

### Overlap with `architect` skill

No conflict. Architect produces specs for known ideas. Business Council
validates whether ideas are worth speccing. Sequence is:
`idea-triage` → `business-validation` → `market-competition` →
`differentiation-positioning` → (decision gate) → `architect` → plan.

---

## Recommendation

**Integrate as a new `idea-triage` orchestrator skill + 5 specialist
sub-skills, with 2 merges into existing skills and content into a new
`templates/business/` directory.**

Specifically:
1. Create `skills/idea-triage/SKILL.md` (orchestrator, from file 01)
2. Create `skills/business-validation/SKILL.md` (from file 02)
3. Create `skills/market-competition/SKILL.md` (from file 03)
4. Create `skills/differentiation-positioning/SKILL.md` (from file 04)
5. Create `skills/business-model-gtm/SKILL.md` (from file 05)
6. Create `skills/finance-risk-ops/SKILL.md` (from file 07)
7. Merge file 06 into `skills/brand-creation/SKILL.md` as Phase 8
8. Create `templates/business/` with 10 templates from file 09
9. Create `templates/business/scorecards.md` from file 08
10. Add `docs/examples/business-consulting-manifest.yaml` from file 10
11. Enrich `contexts/projects-personal/AGENTS.md` with the framing from README + file 00

**Do NOT create a single `business-consulting` monolith.** Individual skills
follow the existing Walter-OS pattern, compose naturally, and stay
independently testable.

**Do NOT merge content into `founder-mode`** — that skill does not exist and
the framing would be cleaner as an `idea-triage` entry point.

**Cherry-pick or all?** All 7 agents have distinct value. The gap analysis
shows 5 of them fill completely absent capabilities. The other 2 (orchestrator,
brand) either fill an absent role or enrich an existing skill meaningfully.
No SKIP items.

---

## Effort estimate

| Item | Effort |
|---|---|
| 6 new SKILL.md files (01-05, 07) | 6.5h |
| Merge 06 into brand-creation | 1.5h |
| templates/business/ directory (10 files) | 0.5h |
| scorecards.md | 0.25h |
| AGENTS.md enrichment (projects-personal) | 0.5h |
| docs/examples/manifest | 0.25h |
| **Total** | **9.5h** |

Breakable into 2 sessions. Session A (5h): 6 new skills.
Session B (4.5h): merges, templates, docs, AGENTS.md.

---

## Critical decisions for operator approval

1. **New `templates/business/` directory** — does this belong at repo root or
   under `docs/templates/`? Convention in this repo is `docs/` for all
   non-code, but `templates/` is a common alternative. Recommend `docs/templates/business/`.

2. **`idea-triage` as gating step before `architect`** — operator must
   explicitly confirm this is the intended flow. If the architect should
   remain the first stop for all non-trivial requests, `idea-triage` should
   be additive (invoked on request) not upstream.

3. **`brand-creation` merge scope** — the verbal identity kit (Phase 8 addition)
   significantly expands that skill's scope. Operator should confirm whether
   to merge in-place or create a new `brand-communication` skill and have
   `brand-creation` reference it.

4. **Language policy for skill content** — current skills are English.
   Source pack content is mixed-language. Recommend translating SKILL.md content
   to English for consistency with existing skills, while preserving the
   response-style guidance as English commentary.
   Operator approval needed.

5. **Trigger for `idea-triage`** — should it fire automatically when a new
   project is started via `walter new project`, or only on explicit invocation?
   If automatic, it changes the `walter new project` UX significantly.
