# HIPAA — Applicability and Light Checklist

## Five-Question Applicability Check

Answer Yes/No to each question:

1. Do you create, receive, maintain, or transmit protected health information (PHI)
   on behalf of a covered entity (hospital, clinic, health plan, healthcare
   clearinghouse)?
2. Are you a Business Associate — a vendor that handles PHI in the course of
   providing services to a covered entity?
3. Does your product collect individually identifiable health information directly
   from patients or plan members?
4. Do you provide services to healthcare providers who share patient data with you
   (even in anonymized or aggregated form)?
5. Do you plan to integrate with EHR systems, insurance payers, or health data
   platforms?

**Verdict**: If you answered Yes to ANY of the above, HIPAA applies.

**Important**: If your product is health-data-intensive, use the
`medical-data-compliance` skill for a more comprehensive assessment. This
reference covers the basics for products with limited HIPAA exposure.

---

## Scope Summary

HIPAA (Health Insurance Portability and Accountability Act, 1996) covers three
rules relevant to technology companies:

- **Privacy Rule**: restricts uses and disclosures of PHI; grants patient rights.
- **Security Rule**: requires administrative, physical, and technical safeguards
  for electronic PHI (ePHI).
- **Breach Notification Rule**: requires notification to patients, HHS, and
  (in some cases) media within 60 days of discovering a breach.

Business Associates (BAs) must sign Business Associate Agreements (BAAs) with
covered entities before receiving PHI. Without a BAA, sharing PHI is a violation.

---

## Self-Assessment Checklist (Business Associate focus)

| ID | Control | Evidence required | Status |
|---|---|---|---|
| HIPAA-1 | Business Associate Agreements (BAAs) signed with all covered entity customers | BAA copies | [ ] |
| HIPAA-2 | PHI is identified and inventoried in your systems | PHI data map | [ ] |
| HIPAA-3 | PHI encrypted at rest (AES-256 or equivalent) | Encryption configuration | [ ] |
| HIPAA-4 | PHI encrypted in transit (TLS 1.2+) | TLS configuration | [ ] |
| HIPAA-5 | Access to PHI limited to minimum necessary (minimum necessary rule) | Access control matrix; audit log | [ ] |
| HIPAA-6 | Audit logs of PHI access maintained for 6 years | Log retention policy; sample logs | [ ] |
| HIPAA-7 | Workforce training on HIPAA completed and documented | Training records | [ ] |
| HIPAA-8 | Breach notification procedure: 60-day notice to covered entity and HHS | Breach notification SOP | [ ] |
| HIPAA-9 | Risk analysis conducted and documented | Risk analysis report | [ ] |
| HIPAA-10 | Subcontractors who handle PHI have signed BAAs (chain of BAAs) | Subcontractor BAA copies | [ ] |

---

## Common Gaps for Early-Stage Companies

- No BAA with covered entity customers (most common violation).
- PHI appears in application logs (URL parameters, error messages).
- Developers have unrestricted access to production PHI.
- No audit logging of PHI access.
- Subcontractors (cloud providers, analytics tools) do not have BAAs in place.

---

## Remediation Priority Order

**P1** (required before handling any PHI):
- HIPAA-1: BAAs with covered entity customers
- HIPAA-3: Encryption at rest
- HIPAA-4: Encryption in transit
- HIPAA-5: Minimum necessary access controls

**P2** (required for operational compliance):
- HIPAA-2: PHI inventory / data map
- HIPAA-6: Audit log retention (6 years)
- HIPAA-8: Breach notification procedure
- HIPAA-10: Subcontractor BAAs (AWS, analytics vendors)

**P3** (sustained compliance):
- HIPAA-7: Workforce training
- HIPAA-9: Annual risk analysis

---

*For comprehensive HIPAA assessment and PHI-intensive products, use the
`medical-data-compliance` skill.*
