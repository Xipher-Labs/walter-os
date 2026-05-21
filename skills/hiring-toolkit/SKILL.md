---
name: hiring-toolkit
description: Produce a job description, an interview rubric, and an offer letter for a single role, all from a project-level role spec. Use when opening a new role at the company, when refining a problematic JD, when preparing for an interview loop, or when extending an offer. Outputs to `hiring/<role>/`. Generates drafts; the operator and (for offer letters) a lawyer review and finalize before sending.
---

# Hiring toolkit

Three artifacts that every role needs and that every founder
spends too long drafting from scratch: the job description, the
interview rubric, and the offer letter. This skill produces
opinionated drafts from a role spec.

## Disclaimer

- **The JD is a draft**. You will edit it to match the actual job
  before posting. The skill produces the structural template + the
  paragraphs that are the same across every role at the company.
- **The interview rubric is a default**. Adapt it to the specific
  bar you set for the role (a staff engineer rubric is not a
  senior engineer rubric).
- **The offer letter is NOT legal advice**. Compensation,
  equity, jurisdiction-specific clauses (at-will, non-compete,
  arbitration), and immigration status are all areas where you
  must run the draft past a lawyer in your jurisdiction before
  signing. The skill emits `[REVIEW]` markers and a header
  reminder.

## Inputs — `hiring/<role>/spec.yml`

```yaml
role:
  title: Senior Backend Engineer
  level: senior                        # junior / mid / senior / staff / principal
  team: platform
  reports_to: CTO
  location: remote-friendly            # remote-only / remote-friendly / on-site
  time_zone_band: UTC-8 to UTC+2       # required for remote roles
  employment_type: full-time           # full-time / part-time / contractor
  jurisdiction: US                     # for offer-letter law selection

compensation:
  salary_band_low_usd: 130000
  salary_band_high_usd: 170000
  equity_band_pct_low: 0.10            # founders' equity grant in percent
  equity_band_pct_high: 0.30
  vesting: 4-years-with-1-year-cliff
  signing_bonus_usd: 0
  benefits:
    - health-insurance
    - dental-vision
    - 401k-no-match
    - 20-days-pto
    - 10-days-sick
    - home-office-stipend-1500

requirements:
  must_have:
    - 5+ years building production backend services
    - Strong async / concurrency experience (Rust, Go, or async Python)
    - Has shipped a service to production with > 100k requests/day
    - Has been on-call for production
  nice_to_have:
    - Solana / blockchain experience
    - Open source contributions
    - Experience with Postgres at scale
  hard_requirements:
    - Authorized to work in the US without sponsorship
    - Can work UTC-8 to UTC+2 overlap

responsibilities:
  - Own the data pipeline service end to end
  - Be on-call rotation (one week in 4)
  - Mentor junior engineers
  - Contribute to architecture decisions

interview_loop:
  stages:
    - name: recruiter-screen
      duration_min: 30
      who: founder
      goal: confirm interest + basic fit + comp expectations
    - name: technical-screen
      duration_min: 60
      who: senior-engineer
      goal: filter on technical bar
    - name: take-home
      duration_hr: 4-6
      who: candidate
      goal: see code quality + design judgment
    - name: take-home-debrief
      duration_min: 60
      who: senior-engineer + founder
      goal: walk through the take-home + extension questions
    - name: founders-chat
      duration_min: 45
      who: founder
      goal: values fit, motivation, mutual interest
    - name: references
      duration_min: 60                  # combined across 2-3 calls
      who: founder
      goal: validate "could you describe a project where X struggled?"

bar:
  must_pass: [technical-screen, take-home, founders-chat]
  optional_pass: [references-confirm-narrative]
```

## Outputs

Writes to `hiring/<role>/`:

```
hiring/<role>/
├── spec.yml                    (input, kept for traceability)
├── job-description.md          (post on job boards + the company site)
├── interview-rubric.md         (used by every interviewer in the loop)
├── offer-letter-template.md    (template; the actual offer is generated
│                                from this + the candidate's filled-in fields)
└── DISCLAIMER.md               (operator-facing reminder)
```

### `job-description.md` structure

```markdown
# Senior Backend Engineer @ <company>

**Team**: Platform
**Reports to**: CTO
**Location**: Remote-friendly (UTC-8 to UTC+2)
**Employment**: Full-time
**Compensation**: $130,000 – $170,000 + equity (0.10% – 0.30%)

## About <company>

<2-paragraph blurb the operator fills in once, reused for every JD.>

## What you'll do

- Own the data pipeline service end to end.
- Be on-call rotation (one week in 4).
- Mentor junior engineers.
- Contribute to architecture decisions.

## Requirements

**Must have**:
- 5+ years building production backend services.
- Strong async / concurrency experience (Rust, Go, or async Python).
- Has shipped a service to production with > 100k requests/day.
- Has been on-call for production.

**Nice to have**:
- Solana / blockchain experience.
- Open source contributions.
- Experience with Postgres at scale.

**Required for legal / logistical reasons**:
- Authorized to work in the US without sponsorship.
- Can work UTC-8 to UTC+2 overlap.

## Interview process

We use a structured 5-stage loop. Each stage has a clear goal so
you know what to expect:

1. **Recruiter screen** (30 min, with founder): confirm interest +
   basic fit + comp expectations.
2. **Technical screen** (60 min): live coding/debugging on a small
   problem from our actual code.
3. **Take-home** (4-6 hours of your time, due in a week): a
   self-contained design + implementation problem.
4. **Take-home debrief** (60 min): walk through your solution +
   extension questions.
5. **Founders chat** (45 min): values fit + mutual questions.

We close decisions within 7 business days of the founders chat.

## How to apply

Email <hiring@<domain>> with your CV + a paragraph on why this
role. We read every application. Cover letters are optional but
read.

We are committed to a fair process. We do not require unpaid trial
weeks. We pay for the take-home time if you ask.

---
*Generated by walter-os hiring-toolkit on <date>. Operator edits
before posting.*
```

### `interview-rubric.md` structure

```markdown
# Interview rubric: Senior Backend Engineer

The same rubric every interviewer uses, every loop. Eliminates
"I just got a good vibe" hiring. Scores 1-5 per criterion;
final yes/no comes from a calibrated discussion, not a sum.

| # | Criterion | Stage(s) | Score 1 | Score 3 | Score 5 |
|---|---|---|---|---|---|
| 1 | Production debugging instinct | technical-screen, take-home-debrief | Adds `print()` randomly | Knows the right log levels, traces by hand | Pattern-matches to a known failure class, validates with a targeted experiment, fixes in one pass |
| 2 | Design judgment | take-home, take-home-debrief | Picks the first thing they thought of | Considers 2 alternatives, picks one with stated tradeoff | Considers ≥ 3 alternatives, articulates the tradeoff for the operator's actual constraints |
| 3 | Async / concurrency rigor | technical-screen | Confuses parallelism + concurrency | Understands the model, occasionally misuses primitives | Picks primitives correctly first time + explains the failure mode of the wrong choice |
| 4 | Communication under uncertainty | every stage | Goes silent / handwaves | Asks clarifying questions; commits to a path | Names the uncertainty explicitly; picks the next experiment to reduce it |
| 5 | Operability mindset | take-home-debrief, founders-chat | Code works on happy path | Considers errors + retries | Asks how this is monitored, what the on-call experience looks like, what the rollback story is |
| 6 | Mentorship & feedback | founders-chat | "I don't really mentor" | Has mentored once, can describe specifics | Has built a feedback loop with multiple people, can name what they changed in their own behavior in response |
| 7 | Values fit | founders-chat + references | Defensive on hard questions | Engages honestly with hard questions | Brings up something they got wrong before; specific lesson learned |

## Calibration meeting (must happen, every loop)

- All interviewers meet within 24h of the founders chat.
- Each interviewer reads their notes aloud BEFORE seeing scores.
- Then scores compared.
- Decision: hire / no-hire / hold (gather more signal).
- A `hold` is not "no with extra steps". A hold either resolves to
  hire within 14 days or it converts to no-hire.

## Anti-patterns

1. **Sum-the-scores hiring.** A 4-5-5-5-4-3-5 is not better than
   a 4-5-5-5-3-4-5. Discuss the criteria.
2. **Strong opinions from the recruiter screen.** That stage is a
   filter, not a signal. Decisions come from the technical loop.
3. **Letting one interviewer drive the decision.** Default to a
   conservative bar; the loop is for calibration, not deference.

---
*Generated by walter-os hiring-toolkit. Operator adapts to the
specific role bar before the first interview.*
```

### `offer-letter-template.md`

The template is jurisdiction-aware: US default is at-will employment;
EU emits notice-period language; UK emits probation period. The
template uses `<<CANDIDATE_NAME>>` / `<<START_DATE>>` /
`<<SALARY_USD>>` etc. placeholders for the operator to fill in per
offer.

Mandatory sections:

1. Role + start date.
2. Compensation (salary + equity + vesting + bonus if any).
3. Benefits enumeration.
4. Employment terms (at-will for US, notice for EU, probation for
   UK).
5. Confidentiality + IP assignment.
6. Background check / reference contingency.
7. Acceptance window (default 7 days).
8. Signature blocks.

Every offer letter includes:

```
> [GENERATED] This is a draft. Counsel must review jurisdiction-
> specific clauses (at-will language, equity grant mechanics, non-
> compete enforceability, arbitration, immigration sponsorship)
> before this letter is sent to a candidate.
```

## What this skill does NOT generate

- **The candidate's offer letter itself** (the template is the
  generic shape; the actual letter is generated from the template
  + the candidate's filled-in details, ideally via a different tool
  or hand).
- **A take-home problem**. The operator picks one that reflects
  the actual work.
- **Reference questions**. These are role-specific; out of scope.
- **An ATS workflow** (Applicant Tracking System). Use Lever /
  Greenhouse / Notion-as-ATS — this skill doesn't manage state.
- **Salary benchmarking research**. The operator supplies the
  salary band from their own research (Levels.fyi, Pave, etc.).
  The skill propagates the band, it doesn't pick it.

## Anti-patterns

1. **Posting a JD before the rubric is written.** You'll evaluate
   against criteria you make up under pressure. Write the rubric
   first.
2. **One-loop hires.** Even for "obvious yes" candidates, the full
   loop is the discipline. The cost of a wrong hire is 6 months
   of dragged-down velocity.
3. **Skipping the calibration meeting.** Async slack threads are
   not calibration. People hedge in writing; you need the
   face-to-face.
4. **Hiring against the equity band without modeling.** Run the
   role's compensation through the `financial-plan-builder` skill
   before signing the offer. Adding $150k/yr + 1% equity is a
   material change to the cash plan.

## Hard rules

- **Always emit the generated-by header on every output.**
- **Always emit the counsel-required disclaimer on the offer
  letter template.**
- **Always reference the calibration meeting in the rubric.** A
  rubric without calibration is theater.
- **The salary band in the JD matches the band in the rubric and
  the offer template exactly.** Mismatch = the candidate notices.

## Integration with other Walter-OS skills

- **`financial-plan-builder`** — model the cost of the hire before
  posting the JD. The hire's start month + monthly_total_usd are
  inputs to that skill.
- **`legal-doc-review`** — review the offer letter template once
  per jurisdiction (not per offer) before first use.
- **`terms-policy-generator`** — handles the customer-facing
  legal documents. Hiring is internal, but the patterns are
  similar (counsel-reviewed template, [REVIEW] markers).
- **`track-pending`** — file a TP entry for any role-specific
  customization that should make it back into the template (e.g.,
  "the take-home problem worked, codify it").

## References

- Walter-OS execution plan Phase 4.1.5.
- `skills/financial-plan-builder/SKILL.md` — cost modeling.
- `skills/legal-doc-review/SKILL.md` — offer letter counsel review.
- Levels.fyi / Pave — for salary benchmarking (operator supplies
  bands, this skill doesn't pick them).
