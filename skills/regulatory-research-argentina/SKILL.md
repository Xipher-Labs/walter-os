---
name: regulatory-research-argentina
description: "@deprecated — use regulatory-research-international with WALTER_JURISDICTION=Argentina instead. Kept for backward compatibility (operator trade-off T3). Research Argentine national, provincial, and municipal regulations relevant to procurement (ley 13.064, decretos provinciales, Compr.Ar/BAC), medical data (ley 26.529, ley 25.326, ANMAT), and general business compliance (IGJ, AFIP/ARCA, monotributo, IIBB). Produces research, NOT legal advice — every output requires counsel review."
---

> **@deprecated** — This skill is retained for backward compatibility (operator trade-off T3).
> For new projects, use `regulatory-research-international` with
> `WALTER_JURISDICTION=Argentina` and `WALTER_REGULATORY_DOMAIN=<domain>`.
> This skill will be moved to the operator's personal overlay in a future cleanup.
> Reference copy also at: `contexts/_examples/skills/regulatory-research-argentina.example.md`

# Regulatory Research Argentina

Research and document Argentine legal/regulatory context for projects.
Argentine regulation is layered: national (ley + decreto + resolución),
provincial (constitución provincial + leyes provinciales), and municipal
ordinances. Federal precedence applies but provinces have significant
autonomy in many areas, especially health, procurement, and taxation.

**This skill produces research, not legal advice.** Every output is
reviewed by counsel before being relied on for compliance decisions.

## When to invoke

- New product feature touches a regulated activity
- A specific user-facing claim could be challenged ("compliant with X")
- A partner asks "is this legal in Argentina"
- Cross-border data flow is involved
- Specific industry: salud, fintech, procurement, mercados de capitales

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
- **Ley X.XXX** (year): <name>. Relevant articles: <art X, Y>.
  Source: infoleg.gob.ar/<id>
- **Decreto X/YYYY**: <name>. Relevant articles: <art X>.
- **Resolución X/YYYY (Ministerio de Y)**: <name>.

### Provincial (if relevant)
- <Provincia>: Ley X. Source: <link>

### Municipal (if relevant)
- <CABA / specific municipality>: Ordenanza X.

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
- BO (Boletín Oficial) for recent decretos
- AAIP / IGJ / ARCA / ANMAT websites for sector-specific
- Doctrina if cited (academic / professional commentary)
```

## Key regulatory areas

### Procurement ([Project A])

Primary frameworks:

- **Ley 13.064** — Obras públicas (national). Foundational for public
  works contracting. Old (1947) but actively applied. Verify current
  consolidated text.
- **Decreto 1023/2001** — Régimen de contrataciones de la administración
  nacional. Federal procurement umbrella.
- **Decreto 1030/2016** — Reglamentación, more recent operational rules.
- **ONC** (Oficina Nacional de Contrataciones) — issuing authority for
  national-level rules. Compr.Ar is their platform.
- **BAC** (Buenos Aires Compras) — CABA-specific platform, separate
  legal regime.
- **Provincias** — each has its own regime. Buenos Aires (provincia)
  uses ley 13.981. Mendoza, Córdoba, Santa Fe each different.
- **Pliego de bases y condiciones** — the tender's specific rules,
  which can be more strict than the underlying law.

For [Project A]:
- We don't replace the official platforms (Compr.Ar, BAC, provincial).
  We layer on top with better UX.
- Suppliers' obligations are defined by law + pliego. We help them
  comply, not bypass.
- Sealed-bid mechanics in code must match the legal sealing requirement
  (typically: bid hash committed before tender close, revealed after).
- Audit trail must be reviewable by the contracting authority.

### Medical / health ([Project B])

Primary frameworks:

- **Ley 26.529** — Derechos del paciente. Patient rights, including:
  - Right to access own medical record
  - Right to confidentiality
  - Informed consent requirements
  - Right to refuse treatment
- **Ley 25.326** — Protección de datos personales. The Argentine GDPR
  predecessor. Updated discussions for ley reform ongoing — verify
  current text.
  - "Datos sensibles" definition includes salud
  - Special protection: needs explicit, written, informed consent
  - AAIP enforcement (Agencia de Acceso a la Información Pública)
- **Historia Clínica Electrónica** — Verify current national framework
  for digital health records. Interoperability requirements typically
  include HL7 FHIR compatibility.
- **ANMAT** — Regulates medical devices and software-as-medical-device.
  If [Project B] makes claims that affect diagnosis/treatment, ANMAT
  jurisdiction kicks in.
- **MINSAL provincial** — Ministerios de Salud provinciales. Each may
  have additional rules for clinics operating within their jurisdiction.

For [Project B]:
- Patient is the data owner; system enforces this even against
  operators.
- No PHI to external LLMs ever (overlaps with `medical-data-
  compliance` skill).
- Encryption at rest, in transit, key management documented.
- Audit log of every read/write, accessible to the patient.
- Right to deletion: patient request honored within statutory window.
- Cross-border data transfer: ley 25.326 art. 12 — destination must
  have "adequate protection level". EU OK (per AAIP determination).
  US case-by-case.
- Argentine law applies for Argentine patients regardless of server
  location.

### Business operations (any project)

- **AFIP / ARCA** — Tax authority. Monotributo, Responsable Inscripto,
  IVA, ganancias. Choose right regime per revenue level.
- **IGJ** (Inspección General de Justicia, federal) — Corporate registry
  for sociedades. SAS preferred for tech startups (faster, cheaper).
- **Provincial registries** — Outside CABA, IGJ-equivalents per
  province (e.g., DPPJ Buenos Aires).
- **IIBB** (Ingresos Brutos) — Provincial tax. Multilateral if
  operating in multiple provincias.
- **Defensa del Consumidor** — Ley 24.240. Applies to B2C products
  with specific disclosure / cancellation rules.

### Cross-border / fintech / crypto

- **BCRA** — Central bank. Regulates exchanges, stablecoins, MEP-CCL
  rules.
- **CNV** — Comisión Nacional de Valores. Securities. Token offerings
  may fall under here depending on structure.
- **UIF** — Unidad de Información Financiera. AML/PEP/KYC obligations.
- **ARCA** — Customs/imports.

## Research process

1. **Define the question precisely.** "Can [Project B] store medical
   records on AWS US-East?" beats "Is [Project B] legal?"
2. **Start with infoleg.gob.ar.** Search by topic, by ley number, by
   article. Read the actual text — summaries on third-party sites
   are often outdated.
3. **Check for vigencia (in-force status).** Laws can be repealed,
   modified, suspended. Infoleg shows the consolidated text.
4. **Find the implementing decreto.** Most leyes need a decreto for
   operational details. Check BO (Boletín Oficial).
5. **Check resoluciones.** Sector regulators (ANMAT, AFIP, BCRA) issue
   resoluciones constantly that change practical compliance.
6. **Read 2-3 doctrina sources.** Argentine legal commentary is rich
   and often clarifies ambiguity. SAIJ (Sistema Argentino de
   Información Jurídica) has free access.
7. **Find precedents if possible.** Courts have interpreted these
   laws — relevant interpretations matter.
8. **Identify the gaps.** What does the law NOT say? What's emergent?
   Crypto, AI, and digital health all have these gaps.
9. **Document open questions for counsel.** Always have these. We're
   not lawyers; we're well-informed engineers/operators.

## Important caveats

- **This skill produces research, not legal advice.** Every output is
  reviewed by counsel before being relied on for compliance decisions.
- **Argentina's regulatory environment changes fast.** Decretos can
  shift rules overnight (especially under DNU regime). Re-research
  before relying on stale analysis.
- **Federalism is real.** A national rule may have provincial
  variation. Always check the specific jurisdiction.
- **"Spirit of the law" matters.** Argentine courts use teleological
  interpretation; the intent often matters more than the literal text.
  Doctrina helps capture this.

## Key online resources

- **infoleg.gob.ar** — Primary source for legislation. Always start here.
- **BO online** (boletinoficial.gob.ar) — Recent norms, before they
  hit infoleg.
- **SAIJ** (saij.gob.ar) — Doctrina, fallos, free access.
- **AAIP** (argentina.gob.ar/aaip) — Personal data protection.
- **IGJ** (argentina.gob.ar/inspeccion-general-de-justicia)
- **AFIP / ARCA** (afip.gob.ar)
- **ANMAT** (anmat.gob.ar)
- **ONC / Compr.Ar** (comprar.gob.ar)
- **BAC** (buenosairescompras.gob.ar)
- **CSJN** (csjn.gov.ar) — Supreme Court fallos.

## Anti-patterns

- **Citing sites that aren't primary sources** — blogs, summaries,
  Wikipedia. Always link to infoleg or BO.
- **Treating doctrina as binding** — it's persuasive, not binding.
- **Confusing nacional with CABA** — CABA is a city + autonomous
  jurisdiction. Many "Argentine" rules are actually CABA rules.
- **Assuming gringo equivalents apply** — "GDPR-compliant" doesn't
  mean ley 25.326 compliant. They overlap, but Argentina has its own
  obligations (especially "consentimiento informado por escrito").
- **Skipping legal review** — research informs, counsel decides. For
  any compliance-bearing decision, get the lawyer's sign-off.

## Integration

- `medical-data-compliance` consumes [Project B]-relevant findings.
- Skills authoring specs reference applicable regulations in scope.
