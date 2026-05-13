---
name: regulatory-research-international
description: Research legal and regulatory requirements for any jurisdiction and domain. Parameterized via WALTER_JURISDICTION (e.g., "Argentina", "EU", "US-California", "Brazil") and WALTER_REGULATORY_DOMAIN (e.g., "data-protection", "procurement", "health", "financial", "employment"). Use when starting work on a feature in a regulated domain, when validating compliance, or when a user asks about legal requirements for a specific market. Produces research, NOT legal advice — every output requires counsel review before reliance.
---

# Regulatory Research (International)

Research and document legal/regulatory requirements for any jurisdiction and domain.
This skill is parameterized — it adapts to your specific context rather than
hardcoding any country's laws.

**This skill produces research, not legal advice.** Every output must be reviewed
by qualified counsel before being relied upon for compliance decisions.

## Parameters

Invoke with:
- `WALTER_JURISDICTION` — the jurisdiction(s) to research. Examples:
  - Country: `"Argentina"`, `"Germany"`, `"Japan"`, `"Brazil"`
  - Region: `"EU"`, `"LATAM"`, `"APAC"`
  - Sub-national: `"US-California"`, `"US-HIPAA-Covered"`, `"Canada-Quebec"`
- `WALTER_REGULATORY_DOMAIN` — the regulatory area. Examples:
  - `"data-protection"` — privacy, GDPR, CCPA, LGPD
  - `"health"` — medical data, patient rights, clinical software
  - `"procurement"` — public contracting, government purchasing
  - `"financial"` — fintech, banking, AML/KYC, securities
  - `"employment"` — labor law, contractor classification
  - `"consumer"` — consumer protection, e-commerce
  - `"ai-liability"` — AI Act (EU), emerging AI regulation

## When to invoke

- New product feature touches a regulated activity in a specific market
- A user-facing claim could be challenged ("compliant with X")
- A partner asks "is this legal in [jurisdiction]"
- Cross-border data flow is involved
- Starting a new project targeting a specific market

## Output format

`docs/regulatory/<topic>-<jurisdiction>-<YYYY-MM-DD>.md`:

```markdown
# Regulatory Research: <Topic> — <Jurisdiction>

**Date**: <ISO date>
**Jurisdiction**: <filled from WALTER_JURISDICTION>
**Domain**: <filled from WALTER_REGULATORY_DOMAIN>
**Status**: Working draft / Reviewed by counsel / Final

## Question

<The specific compliance question being answered>

## Short answer

<2-3 sentences. The bottom line. Include "subject to counsel review" caveat
when there's any ambiguity.>

## Applicable regulations

### Primary framework
- **<Law/Regulation Name>** (<year>): <name and scope>. Relevant articles: <X, Y>.
  Source: <official source URL>

### Secondary frameworks
- <Other applicable rules, standards, or guidance>

### International overlaps
- <If EU/GDPR applies, note it. If HIPAA applies, note it. Cross-border rules.>

## Detailed analysis

<Walk through the question. What does each rule say? What's the intent?
Where do they intersect? Cite specific articles.>

## Practical implications

- <What the product can do>
- <What the product cannot do>
- <What requires additional process / authorization / consent>
- <Reporting/disclosure obligations>

## Open questions / requires legal counsel

<What a lawyer must confirm. Don't pretend to be one.>

## Sources

- <Primary legislation link — government or official body>
- <Regulatory authority guidance>
- <Official interpretations or decisions>
```

## Key frameworks by domain

### Data protection / privacy

| Jurisdiction | Framework | Regulator |
|---|---|---|
| EU + EEA | GDPR (General Data Protection Regulation) | National DPAs + EDPB |
| UK | UK GDPR + Data Protection Act 2018 | ICO |
| US (no federal law) | CCPA/CPRA (California), VCDPA (Virginia), CPA (Colorado), others | State AGs |
| US healthcare | HIPAA (Health Insurance Portability and Accountability Act) | HHS OCR |
| Brazil | LGPD (Lei Geral de Proteção de Dados) | ANPD |
| Canada | PIPEDA + provincial laws (Quebec Law 25) | OPC + provincial |
| Japan | APPI (Act on Protection of Personal Information) | PPC |
| Australia | Privacy Act 1988 (with 2024 amendments pending) | OAIC |

Core principles across frameworks: lawful basis, data minimization, purpose limitation,
accuracy, storage limitation, integrity/confidentiality, accountability.

### Health data

Health data receives heightened protection in virtually all jurisdictions:
- **US**: HIPAA defines PHI; covered entities + business associates have strict rules.
- **EU**: GDPR Art. 9 "special category" — explicit consent or narrow exceptions.
- **UK**: UK GDPR + NHS Data Security and Protection Toolkit for NHS-touching apps.
- **Brazil**: LGPD Art. 11 "sensitive personal data" — heightened protection.
- **Australia**: Privacy Act Health Records provisions.

Common requirements across jurisdictions:
- Explicit consent (written or equivalent) before processing health data
- Access controls: who can see what, with audit log
- Encryption at rest and in transit, operator-controlled keys preferred
- Patient right to access their own data
- Patient right to deletion (with certain exceptions for retention obligations)
- Breach notification (varies: 72 hours GDPR, 60 days HIPAA, etc.)

### Procurement / government contracting

Government procurement is regulated at the national level and often sub-nationally.
Research the specific jurisdiction. Common frameworks:
- **EU**: Public Procurement Directives (2014/24/EU for public contracts,
  2014/25/EU for utilities, 2014/23/EU for concessions)
- **US Federal**: FAR (Federal Acquisition Regulation), DFARS (defense)
- **US State/Local**: varies significantly by state
- **UK**: Procurement Act 2023 (post-Brexit replacement for EU directives)
- **Canada**: CFTA, CETA procurement chapters
- **Latin America**: varies widely by country — research the specific country

Key questions: publication thresholds, eligibility requirements, sealed-bid
mechanics, appeal processes, audit trail requirements.

### Financial / fintech

- **EU**: PSD2 (open banking), MiCA (crypto assets), AML/CFT Directives
- **US**: Bank Secrecy Act, FinCEN rules, state money transmitter licenses
- **UK**: FCA authorization, Payment Services Regulations 2017
- **GLOBAL**: FATF recommendations for AML/KYC

### AI-specific regulation (emerging)

- **EU AI Act** (2024+): risk-based categorization; prohibited AI, high-risk AI
  (requires conformity assessment), limited/minimal risk. Medical devices and
  employment fall under high-risk.
- **US**: sector-specific guidance (FTC, FDA for medical AI, CFPB for credit)
- **UK**: sector-based approach through existing regulators (FCA, ICO, etc.)

## Research process

1. **Define the question precisely.** "Can we store health records on AWS US-East
   for EU patients?" beats "Is this GDPR compliant?"
2. **Identify the jurisdiction(s).** Where are users? Where is data processed?
   Where is the company incorporated? All three may create obligations.
3. **Find the primary legislation.** Use official government or regulatory body
   websites, not third-party summaries.
4. **Check for guidance documents.** Regulators issue interpretive guidance,
   FAQs, and decisions that clarify ambiguous law.
5. **Check for recent changes.** Laws evolve. Verify the version in force.
6. **Identify the regulator.** Who enforces? What are the enforcement priorities?
   What sanctions have been issued?
7. **Find precedents.** Fines, decisions, and enforcement actions reveal how
   rules are applied in practice.
8. **Identify gaps and open questions.** Emerging tech (AI, blockchain, decentralized
   storage) often outpaces legislation. Document the uncertainty.
9. **Flag everything for counsel.** Research informs; lawyers decide.

## Key research sources

### International / multi-jurisdiction
- **EUR-Lex** (eur-lex.europa.eu) — EU law and regulations
- **OECD iLibrary** (oecd-ilibrary.org) — privacy guidelines and policy research
- **FATF** (fatf-gafi.org) — AML/CFT standards
- **IAPP** (iapp.org) — privacy professional resources, jurisdiction summaries
- **Fieldfisher Global Privacy Directory** — quick-reference by country

### US
- **law.cornell.edu** — US federal law (Cornell LII)
- **regulations.gov** — federal regulations and rulemaking
- **ftc.gov** — FTC enforcement actions and guidance
- **hhs.gov/hipaa** — HIPAA rules and enforcement
- **oag.ca.gov** — California AG CCPA guidance

### EU
- **EUR-Lex** (eur-lex.europa.eu) — primary source
- **edpb.europa.eu** — EDPB opinions and guidelines
- **gdprhub.eu** — GDPR case law database

### UK
- **legislation.gov.uk** — primary source
- **ico.org.uk** — ICO guidance and enforcement

## Important caveats

- **This skill produces research, not legal advice.** Require counsel review
  before any compliance-bearing decision.
- **Jurisdictions change fast.** Privacy law especially is evolving rapidly.
  Re-research before relying on stale analysis.
- **Multi-jurisdiction complexity is real.** A product serving EU and US users
  may face GDPR, CCPA, and HIPAA simultaneously.
- **Enforcement patterns matter as much as the text.** What regulators actually
  fine for may differ from what the law says.
- **Ask the specific question.** Broad questions produce broad (less useful)
  answers. Narrow the research to the specific compliance question.

## Integration

- `medical-data-compliance` consumes health-related findings for implementation
  guidance.
- `regulatory-research-argentina` (in `contexts/_examples/skills/`) is a concrete
  example of a jurisdiction-specific implementation of this pattern.
- Skills authoring specs reference applicable regulations in scope.
