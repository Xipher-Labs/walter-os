---
name: project-pivot
description: >
  Conduct a short 4-question guided interview with the operator to derive a
  project-specific AGENTS.md draft, recommended hooks, recommended MCPs, and a
  compliance checklist. Invoke via `walter pivot` or `walter-os pivot`. Use when
  starting a new project or adapting an existing one to a new domain or compliance
  context. Replaces fixed industry templates with runtime-derived configuration
  tailored to the operator's actual setup.
trigger:
  - walter pivot
  - walter-os pivot
  - walter new project --interactive
---

# Skill: project-pivot

**Purpose**: Drive a 4-question interview to produce a runtime-derived, tailored
project configuration. No static template matches every setup; this skill derives
the right defaults from four orthogonal axes: domain, compliance, data handling,
and project nature.

**Constraint (hard, non-negotiable)**: Never output country-specific law names
(e.g., Ley NNNN, CCPA, PIPEDA, LGPD, PDPA, DPA 2018, APPI, POPIA, NDPR).
If the operator's answers imply a jurisdiction, output:
> "Consult the `regulatory-research-<jurisdiction>` skill family and insert the
> applicable statute name here as a placeholder."

This constraint exists because country-specific law names require expert
interpretation, update over time, and are handled better by dedicated
regulatory-research skills than by a generic pivot skill.

---

## Interview Protocol

Conduct the questions in strict order. Do not proceed to the next question until
the operator has provided a valid answer to the current one. For each question,
show the available options and accept a free-text override when noted.

---

### Question 1: Domain / Industry

**Ask**: "What is the primary domain or industry of this project?"

**Options** (single-select; free-text override allowed):

| Key | Domain |
|---|---|
| `procurement` | Public/private procurement, RFP/tender management |
| `healthcare` | Clinical software, patient data, medical devices |
| `fintech` | Payments, lending, trading, digital banking |
| `devtools` | Developer tooling, SDKs, CLIs, infrastructure software |
| `content` | Media, publishing, content platforms, social |
| `e-commerce` | Online retail, marketplaces, checkout flows |
| `education` | EdTech, learning platforms, academic software |
| `gaming` | Games, in-app purchases, virtual goods |
| `iot` | IoT devices, embedded firmware, sensor data |
| `research` | Scientific computing, data science, ML research |
| `generic` | General-purpose software, no specific vertical |

If the operator provides a domain not in this list, accept it and note it as
`custom:<operator-supplied-text>`.

---

### Question 2: Compliance Regime

**Ask**: "Which compliance regimes apply? Select all that apply."

**Options** (multi-select; free-text `other` allowed):

| Key | Regime | When it applies |
|---|---|---|
| `gdpr` | GDPR | Processing personal data of EU residents |
| `hipaa` | HIPAA | US healthcare data (PHI); also used as a general health-data security benchmark |
| `pci-dss` | PCI-DSS | Storing/processing/transmitting payment card data |
| `soc2` | SOC 2 | SaaS/cloud services needing trust-service criteria audit |
| `iso27001` | ISO 27001 | Information security management systems |
| `best-practices` | Best practices only | No formal compliance requirement; apply sensible defaults |
| `other` | Other | Free-text; produces a note to consult the relevant regulatory-research skill |

**If the operator selects `other` or types a jurisdiction-specific regime**:
Do not output the law name. Output:
> "Open question: consult `regulatory-research-<domain>` skill and insert the
> applicable framework name here: [COMPLIANCE_FRAMEWORK_PLACEHOLDER]."

**Union rule**: when multiple regimes are selected, produce the union of all
their required controls. The most restrictive control wins.

---

### Question 3: Data Sensitivity

**Ask**: "What is the most sensitive category of data this project handles?"

**Options** (single-select; choose the highest applicable level):

| Key | Category | Routing decision |
|---|---|---|
| `none` | No user data / fully public | Cloud APIs allowed |
| `internal` | Internal/business data, no PII | Cloud APIs allowed with TLS |
| `personal` | Personal data (name, email, address, account info) | Cloud APIs allowed; GDPR-class personal-data controls required |
| `financial` | Payment card data, bank account numbers, transaction records | Cloud APIs with strict controls; PCI-DSS scope if cards |
| `sensitive-health` | Health records, diagnoses, prescriptions, biometrics, PHI | Local-only LLM routing; no PHI to external APIs |
| `mixed` | Multiple categories above | Apply union of all controls for each category present |

**When `sensitive-health` or `mixed` (containing health data)**:
- AGENTS.md draft MUST include: `NEVER send data tagged PHI to external APIs. Route all PHI processing to local Ollama only.`
- `medical-data-compliance` MUST appear in `## Skill loading`.
- Compliance checklist MUST include item: `[ ] Local LLM routing verified for all PHI data paths`.

**When `financial`**:
- AGENTS.md draft MUST include `web-security-baseline` in `## Skill loading`.
- If `pci-dss` was selected in Q2: add `pci-dss-checklist` to `## Skill loading`.
- If `pci-dss` was NOT selected: add `security-audit` to `## Skill loading`.

---

### Question 4: Project Type

**Ask**: "What type of project is this?"

**Options** (single-select):

| Key | Type | Effect on output |
|---|---|---|
| `personal` | Personal/hobby project | Relaxed branch-flow strictness; reviewer subagent optional |
| `commercial` | Commercial product or service | Full branch-flow enforcement; reviewer subagent mandatory |
| `hackathon` | Hackathon / time-boxed prototype | Cut non-critical gates; ship fast; tests are still mandatory |
| `oss-contribution` | Contributing to an existing OSS project | Follow the upstream project's conventions; add Walter-OS discipline on top |

---

## Compliance Framework Mapping

The LLM uses this mapping table to derive outputs. The table is declarative —
not exhaustive. When in doubt, be more cautious, not less.

### Domain defaults

| Domain | Likely compliance | Likely data sensitivity | Default MCPs |
|---|---|---|---|
| `procurement` | `best-practices` or `soc2` | `internal` | `github`, `linear`, `postgres` |
| `healthcare` | `hipaa` + `soc2` | `sensitive-health` | `github`, `postgres` |
| `fintech` | `pci-dss` + `soc2` | `financial` | `github`, `stripe`, `postgres` |
| `devtools` | `best-practices` or `soc2` | `internal` | `github`, `linear` |
| `content` | `gdpr` | `personal` | `github`, `supabase` |
| `e-commerce` | `pci-dss` + `gdpr` | `financial` | `github`, `stripe`, `supabase` |
| `education` | `gdpr` + `soc2` | `personal` | `github`, `supabase` |
| `gaming` | `best-practices` | `personal` | `github`, `supabase` |
| `iot` | `iso27001` | `internal` | `github`, `postgres` |
| `research` | `best-practices` | `internal` | `github`, `postgres` |
| `generic` | `best-practices` | `internal` | `github` |

These are starting-point defaults. The operator's Q2/Q3 answers override them.

### Compliance regime → required controls

| Regime | Required hooks | Required skills | Checklist items (minimum) |
|---|---|---|---|
| `gdpr` | `pre-commit-phi-scan.sh` | `web-security-baseline` | Data subject rights flow; retention policy; breach notification plan |
| `hipaa` | `pre-commit-phi-scan.sh`, `medical-data-compliance.sh` | `medical-data-compliance`, `web-security-baseline` | PHI access log; encryption at rest/transit; BAA with vendors |
| `pci-dss` | `pre-commit-secrets-scan.sh` | `web-security-baseline`, `pci-dss-checklist` | Cardholder data scoping; no card storage unless tokenized; SAQ documented |
| `soc2` | `pre-commit-secrets-scan.sh` | `web-security-baseline` | Change management log; access control review; incident response plan |
| `iso27001` | `pre-commit-secrets-scan.sh` | `web-security-baseline` | ISMS scope defined; risk register maintained; management review scheduled |
| `best-practices` | `pre-commit-secrets-scan.sh` | `web-security-baseline` | No hardcoded secrets; TLS everywhere; least-privilege access |

### Data sensitivity → routing rules

| Sensitivity | AGENTS.md hard rule | Skills to add | Checklist item |
|---|---|---|---|
| `none` | — | — | — |
| `internal` | No internal data in public repos | — | `[ ] No internal data leaked to public logs or repos` |
| `personal` | Minimize PII collection; document retention | `web-security-baseline` | `[ ] PII inventory documented; retention schedule defined` |
| `financial` | No raw card data in logs or repos; route to secure vault | `web-security-baseline` + `pci-dss-checklist` or `security-audit` | `[ ] Cardholder data never logged; tokenization verified` |
| `sensitive-health` | NEVER send PHI to external APIs; local Ollama only | `medical-data-compliance` | `[ ] Local LLM routing verified for all PHI data paths` |
| `mixed` | Union of all applicable rules | Union of all applicable skills | Union of all applicable checklist items |

---

## Output Format

Produce all four sections. Each is clearly delimited. The operator pastes the
AGENTS.md draft into their project root and edits as needed. The compliance
checklist goes into `docs/compliance-checklist.md` in the target project.

```
## Project Pivot Output

### AGENTS.md Draft

---
# AGENTS.md — <Project Name>
# Generated by project-pivot skill. Review and edit before committing.

## Context

<1-2 sentences describing the project, domain, and compliance context>

## Hard rules

- <Rule 1 derived from compliance + sensitivity answers>
- <Rule 2>
- ...

## Skill loading

- <skill-1>
- <skill-2>
- ...

## Branch flow

<strictness derived from project type>

## Never do

- <item derived from compliance + sensitivity>
- ...
---

### Recommended Hooks

- `hooks/<hook-name>.sh` — <reason>
- ...

### Recommended MCPs

- `<mcp-name>` — <reason>
- ...

### Compliance Checklist

Place this in `docs/compliance-checklist.md` in the target project.

- [ ] <Item 1>
- [ ] <Item 2>
- [ ] <Item 3>
...
```

---

## Edge cases

- **Multiple compliance regimes**: produce union of controls; note conflicts explicitly.
- **`mixed` data sensitivity**: apply union of all sensitivity-level rules.
- **`other` compliance regime**: output placeholder and recommend `regulatory-research-<domain>` skill.
- **Project type `hackathon`**: note which gates are relaxed and which remain mandatory (tests always stay mandatory).
- **Country-specific laws implied by operator's answers**: never output the law name; output a placeholder with a note.

---

## Integration

- Invoked by `bin/walter-os pivot` (see `docs/specs/phase-w-2-cli-ai.md` for CLI integration).
- `medical-data-compliance` skill is auto-added when `sensitive-health` selected.
- `regulatory-research-*` skill family handles jurisdiction-specific legal grounding.
- Output AGENTS.md draft feeds into `project-induction` if both skills are used together.
- W-5 depersonalization removes operator-specific contexts; this skill is how new adopters configure theirs.
