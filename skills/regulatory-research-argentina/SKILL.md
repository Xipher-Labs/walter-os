---
name: regulatory-research-argentina
description: "@deprecated — use regulatory-research-international with WALTER_JURISDICTION=Argentina instead. Kept for backward compatibility (operator trade-off T3). Research Argentine national, provincial, and municipal regulations relevant to procurement (Law 13.064, provincial decrees, Compr.Ar/BAC), medical data (Law 26.529, Law 25.326, ANMAT), and general business compliance (IGJ, AFIP/ARCA, small-taxpayer regime, gross-receipts tax). Produces research, NOT legal advice — every output requires counsel review."
---

> **@deprecated** — This skill is retained for backward compatibility (operator trade-off T3).
> For new projects, use `regulatory-research-international` with
> `WALTER_JURISDICTION=Argentina` and `WALTER_REGULATORY_DOMAIN=<domain>`.
> This skill will be moved to the operator's personal overlay in a future cleanup.
> Reference copy also at: `contexts/_examples/skills/regulatory-research-argentina.example.md`

# Regulatory Research Argentina

Research and document Argentine legal/regulatory context for projects.
Argentine regulation is layered: national (law + decree + resolution),
provincial (provincial constitution + provincial laws), and municipal
ordinances. Federal precedence applies but provinces have significant
autonomy in many areas, especially health, procurement, and taxation.

**This skill produces research, not legal advice.** Every output is
reviewed by counsel before being relied on for compliance decisions.

## When to invoke

- New product feature touches a regulated activity
- A specific user-facing claim could be challenged ("compliant with X")
- A partner asks "is this legal in Argentina"
- Cross-border data flow is involved
- Specific industry: health, fintech, procurement, capital markets

## Output format

`docs/regulatory/<topic>-<YYYY-MM-DD>.md`:

```markdown
# Regulatory Research: <Topic>

**Date**: 2026-05-03
**Researcher**: <you>
**Project**: [Project A] / [Project B] / [Company]-AR / etc.
**Status**: Working draft / Reviewed by counsel / Final

## Question

<The specific question you're answering>

## Short answer

<2-3 sentences. The bottom line. With "subject to counsel review" caveat
when there's any ambiguity.>

## Applicable regulations

### National
- **Law X.XXX** (year): <name>. Relevant articles: <art X, Y>.
  Source: infoleg.gob.ar/<id>
- **Decree X/YYYY**: <name>. Relevant articles: <art X>.
- **Resolution X/YYYY (Ministry of Y)**: <name>.

### Provincial (if relevant)
- <Province>: Law X. Source: <link>

### Municipal (if relevant)
- <CABA / specific municipality>: Ordinance X.

## Detailed analysis

<Walk through the question. What does each rule say? What's the
intent? Where do they intersect?>

## Practical implications for <project>

- <what we can do>
- <what we can't do>
- <what requires additional process / authorization>

## Open questions / requires legal counsel

<What we need a lawyer to confirm. Don't pretend to be one.>

## Sources

- infoleg.gob.ar links (primary source for laws)
- Official Gazette for recent decrees
- AAIP / IGJ / ARCA / ANMAT websites for sector-specific
- Legal doctrine if cited (academic / professional commentary)
```

## Key regulatory areas

### Procurement ([Project A])

Primary frameworks:

- **Law 13.064** — Public works (national). Foundational for public
  works contracting. Old (1947) but actively applied. Verify current
  consolidated text.
- **Decree 1023/2001** — National public-administration procurement
  regime. Federal procurement umbrella.
- **Decree 1030/2016** — Regulatory decree, more recent operational rules.
- **ONC** (National Contracting Office) — issuing authority for
  national-level rules. Compr.Ar is their platform.
- **BAC** (Buenos Aires Compras) — CABA-specific platform, separate
  legal regime.
- **Provinces** — each has its own regime. Buenos Aires Province
  uses Law 13.981. Mendoza, Cordoba, and Santa Fe each differ.
- **Tender terms and conditions** — the tender's specific rules,
  which can be more strict than the underlying law.

For [Project A]:
- We don't replace the official platforms (Compr.Ar, BAC, provincial).
  We layer on top with better UX.
- Suppliers' obligations are defined by law plus tender terms. We help them
  comply, not bypass.
- Sealed-bid mechanics in code must match the legal sealing requirement
  (typically: bid hash committed before tender close, revealed after).
- Audit trail must be reviewable by the contracting authority.

### Medical / health ([Project B])

Primary frameworks:

- **Law 26.529** — Patient rights, including:
  - Right to access own medical record
  - Right to confidentiality
  - Informed consent requirements
  - Right to refuse treatment
- **Law 25.326** — Personal data protection. The Argentine GDPR
  predecessor. Reform discussions are ongoing; verify
  current text.
  - "Sensitive data" definition includes health
  - Special protection: needs explicit, written, informed consent
  - AAIP enforcement (Agency for Access to Public Information)
- **Electronic medical record** — Verify current national framework
  for digital health records. Interoperability requirements typically
  include HL7 FHIR compatibility.
- **ANMAT** — Regulates medical devices and software-as-medical-device.
  If [Project B] makes claims that affect diagnosis/treatment, ANMAT
  jurisdiction kicks in.
- **Provincial health ministries** — Each may
  have additional rules for clinics operating within their jurisdiction.

For [Project B]:
- Patient is the data owner; system enforces this even against
  operators.
- No PHI to external LLMs ever (overlaps with `medical-data-
  compliance` skill).
- Encryption at rest, in transit, key management documented.
- Audit log of every read/write, accessible to the patient.
- Right to deletion: patient request honored within statutory window.
- Cross-border data transfer: Law 25.326 article 12 — destination must
  have "adequate protection level". EU OK (per AAIP determination).
  US case-by-case.
- Argentine law applies for Argentine patients regardless of server
  location.

### Business operations (any project)

- **AFIP / ARCA** — Tax authority. Small-taxpayer regime, registered
  taxpayer status, VAT, income tax. Choose the right regime per revenue level.
- **IGJ** (federal corporate registry) — Corporate registry
  for sociedades. SAS preferred for tech startups (faster, cheaper).
- **Provincial registries** — Outside CABA, IGJ-equivalents per
  province (e.g., DPPJ Buenos Aires).
- **Gross-receipts tax** — Provincial tax. Multilateral agreement applies
  when operating in multiple provinces.
- **Consumer Protection** — Law 24.240. Applies to B2C products
  with specific disclosure / cancellation rules.

### Cross-border / fintech / crypto

- **BCRA** — Central bank. Regulates exchanges, stablecoins, MEP-CCL
  rules.
- **CNV** — National Securities Commission. Token offerings
  may fall under here depending on structure.
- **UIF** — Financial Information Unit. AML/PEP/KYC obligations.
- **ARCA** — Customs/imports.

## Research process

1. **Define the question precisely.** "Can [Project B] store medical
   records on AWS US-East?" beats "Is [Project B] legal?"
2. **Start with infoleg.gob.ar.** Search by topic, by law number, by
   article. Read the actual text — summaries on third-party sites
   are often outdated.
3. **Check for vigencia (in-force status).** Laws can be repealed,
   modified, suspended. Infoleg shows the consolidated text.
4. **Find the implementing decree.** Most laws need a decree for
   operational details. Check the Official Gazette.
5. **Check resolutions.** Sector regulators (ANMAT, AFIP, BCRA) issue
   resolutions constantly that change practical compliance.
6. **Read 2-3 legal doctrine sources.** Argentine legal commentary is rich
   and often clarifies ambiguity. SAIJ (Argentine Legal Information System)
   has free access.
7. **Find precedents if possible.** Courts have interpreted these
   laws — relevant interpretations matter.
8. **Identify the gaps.** What does the law NOT say? What's emergent?
   Crypto, AI, and digital health all have these gaps.
9. **Document open questions for counsel.** Always have these. We're
   not lawyers; we're well-informed engineers/operators.

## Important caveats

- **This skill produces research, not legal advice.** Every output is
  reviewed by counsel before being relied on for compliance decisions.
- **Argentina's regulatory environment changes fast.** Decrees can
  shift rules overnight (especially under DNU regime). Re-research
  before relying on stale analysis.
- **Federalism is real.** A national rule may have provincial
  variation. Always check the specific jurisdiction.
- **"Spirit of the law" matters.** Argentine courts use teleological
  interpretation; the intent often matters more than the literal text.
  Legal doctrine helps capture this.

## Key online resources

- **infoleg.gob.ar** — Primary source for legislation. Always start here.
- **Official Gazette online** (boletinoficial.gob.ar) — Recent norms, before they
  hit infoleg.
- **SAIJ** (saij.gob.ar) — Legal doctrine, case law, free access.
- **AAIP** (argentina.gob.ar/aaip) — Personal data protection.
- **IGJ** (argentina.gob.ar/inspeccion-general-de-justicia)
- **AFIP / ARCA** (afip.gob.ar)
- **ANMAT** (anmat.gob.ar)
- **ONC / Compr.Ar** (comprar.gob.ar)
- **BAC** (buenosairescompras.gob.ar)
- **CSJN** (csjn.gov.ar) — Supreme Court cases.

## Anti-patterns

- **Citing sites that aren't primary sources** — blogs, summaries,
  Wikipedia. Always link to infoleg or BO.
- **Treating legal doctrine as binding** — it is persuasive, not binding.
- **Confusing nacional with CABA** — CABA is a city + autonomous
  jurisdiction. Many "Argentine" rules are actually CABA rules.
- **Assuming gringo equivalents apply** — "GDPR-compliant" doesn't
  mean Law 25.326 compliant. They overlap, but Argentina has its own
  obligations, especially written informed consent.
- **Skipping legal review** — research informs, counsel decides. For
  any compliance-bearing decision, get the lawyer's sign-off.

## Integration

- `medical-data-compliance` consumes [Project B]-relevant findings.
- Skills authoring specs reference applicable regulations in scope.
