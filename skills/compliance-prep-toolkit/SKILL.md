---
name: compliance-prep-toolkit
description: Pre-audit prep checklists for GDPR compliance, SOC2 prep, PCI-DSS checklist, ISO 27001, and HIPAA. Five-question applicability gate per framework. Outputs self-assessment checklist with evidence templates, gap analysis, and remediation priorities. Not legal advice.
---

# compliance-prep-toolkit

Pre-audit compliance preparation for early-stage companies. Covers five
frameworks: GDPR, SOC 2, PCI-DSS, ISO 27001, and HIPAA (light). Each framework
starts with a five-question applicability check — if a framework does not apply,
its checklist is skipped. Produces self-assessment checklists with evidence
templates, a gap analysis, and a remediation priority order (P1/P2/P3).

This skill generates preparation materials. It is NOT a substitute for legal
counsel or a formal audit. Engage a qualified auditor before making compliance
claims to customers.

## When to use this skill

- You are preparing for a customer security questionnaire and want to know your
  compliance posture.
- You are approaching a formal SOC 2 or ISO 27001 audit and want to identify
  gaps before the auditor does.
- You handle EU personal data and want to assess GDPR readiness.
- You process payment cards and want to understand PCI-DSS obligations.
- You work with health data and want to understand HIPAA scope.

## When NOT to use this skill

- You need formal certification or a signed audit opinion (engage an auditor).
- You need legal advice on regulatory interpretation (engage a lawyer).
- You are assessing HIPAA in depth — `medical-data-compliance` covers HIPAA
  more thoroughly for health-data-centric products.
- You need a real-time compliance monitoring system (that is a platform feature).

## Inputs

- **Frameworks to assess**: GDPR, SOC 2, PCI-DSS, ISO 27001, HIPAA, or "all".
- **Company description**: type of product, data you handle, customer types.
- **Current security controls**: brief description of what you already have
  (or "none").
- **Audit timeline** (optional): when you need to be ready.

## Outputs

For each applicable framework (those that pass the five-question gate):

1. **Applicability verdict**: Yes / Partial / No, with one-sentence rationale.
2. **Self-assessment checklist**: controls with evidence template column. Each
   control has a unique ID (e.g., GDPR-1, SOC2-CC6.1).
3. **Gap analysis**: controls where evidence is missing or insufficient.
4. **Remediation priority order**:
   - P1: Fix before any customer conversation (critical gaps that block sales).
   - P2: Fix before formal audit (will generate findings if left open).
   - P3: Best practices (improve over time; not audit-blocking).

## Sample usage

```
Skill: compliance-prep-toolkit

Frameworks: SOC 2 + GDPR

Company: B2B SaaS. We process personal data of EU employees on behalf of HR
  departments. We store names, emails, salary data, and performance reviews.
  We are US-based but have EU customers.

Current controls: We use AWS (SOC 2 certified), have MFA on all admin accounts,
  and have a basic privacy policy on our website.

Audit timeline: SOC 2 Type I in 6 months.
```

Expected output: GDPR applicability = Yes (EU personal data, HR category).
SOC 2 applicability = Yes (SaaS, customer data). GDPR checklist with 35
controls, 18 of which have gaps. SOC 2 checklist with 60 controls, 22 gaps.
Remediation order: P1 = data processing agreements with EU customers (blocks
sales), P2 = incident response plan, P3 = annual penetration testing.

## How it composes with other Walter-OS skills

- `medical-data-compliance` — HIPAA is covered more thoroughly in
  medical-data-compliance for health-data products. This skill's HIPAA light
  reference (`references/hipaa-light.md`) covers the basics; defer to
  medical-data-compliance for PHI-intensive products.
- `web-security-baseline` — the technical controls in web-security-baseline
  map directly to many SOC 2 and ISO 27001 control requirements. Run
  web-security-baseline first to get your baseline posture.
- `decision-journal` — log the compliance decisions (which frameworks to pursue,
  which gaps to defer) in the decision journal for accountability.

## Prompt for your AI

```
I need to assess my compliance readiness. Here is my context:

Frameworks: [GDPR | SOC 2 | PCI-DSS | ISO 27001 | HIPAA | all]
Company: [type of product, data you handle, customer types]
Current controls: [brief description or "none"]
Audit timeline: [date or "none"]

For each framework, please:
1. Run the five-question applicability check and give a verdict (Yes/Partial/No)
2. If applicable, produce a self-assessment checklist with evidence template column
3. Identify gaps (controls where evidence is missing)
4. Produce a remediation priority order (P1/P2/P3)
```
