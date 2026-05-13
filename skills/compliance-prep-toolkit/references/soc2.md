# SOC 2 — Applicability and Checklist

## Five-Question Applicability Check

Answer Yes/No to each question:

1. Do you provide a SaaS product or managed service to business customers?
2. Do your customers store or process their data on your infrastructure?
3. Have customers or prospects asked for a SOC 2 report or security questionnaire?
4. Do you handle sensitive customer data (PII, financial records, health
   information, intellectual property)?
5. Are you planning to sell to enterprise customers in the next 12 months?

**Verdict**: If you answered Yes to ANY of the above, SOC 2 is worth pursuing.

---

## Scope Summary

SOC 2 (Service Organization Control 2) is an auditing standard from the AICPA.
It evaluates controls relevant to the Trust Services Criteria (TSC): Security
(CC), Availability (A), Processing Integrity (PI), Confidentiality (C), and
Privacy (P). Security is the mandatory criteria; others are optional.

SOC 2 Type I: point-in-time assessment (design of controls).
SOC 2 Type II: 6-12 month operating effectiveness period (most customers require Type II).

---

## Self-Assessment Checklist (Security TSC — required)

| ID | Control | Evidence required | Status |
|---|---|---|---|
| SOC2-CC1.1 | Organizational policies documented and approved | Policy documents with approval records | [ ] |
| SOC2-CC2.1 | Information security policy covers all major risk areas | Policy document; last review date | [ ] |
| SOC2-CC3.1 | Risk assessment conducted annually | Risk register; assessment report | [ ] |
| SOC2-CC4.1 | Vendor risk assessments for critical third parties | Vendor questionnaires; assessment records | [ ] |
| SOC2-CC5.1 | Logical access controls: unique user accounts, no shared credentials | User directory; access review records | [ ] |
| SOC2-CC5.2 | MFA enforced on all administrative and privileged access | MFA configuration screenshots | [ ] |
| SOC2-CC5.3 | Role-based access control (RBAC) documented and enforced | Access control matrix | [ ] |
| SOC2-CC6.1 | Encryption at rest for sensitive data | Encryption configuration; key management policy | [ ] |
| SOC2-CC6.2 | Encryption in transit (TLS 1.2+) for all data transfers | TLS configuration; certificate records | [ ] |
| SOC2-CC6.3 | Access to production systems requires approval and audit log | Change management SOP; audit log samples | [ ] |
| SOC2-CC7.1 | Vulnerability scanning conducted quarterly | Scan reports; remediation tickets | [ ] |
| SOC2-CC7.2 | Penetration testing conducted annually | Pen test report; remediation records | [ ] |
| SOC2-CC8.1 | Change management process documented (code reviews, staging) | Change management SOP; PR records | [ ] |
| SOC2-CC9.1 | Incident response plan documented | IRP document; last test date | [ ] |
| SOC2-CC9.2 | Security incidents tracked and resolved | Incident log with resolution evidence | [ ] |
| SOC2-A1.1 | System availability SLA defined and monitored | SLA document; uptime monitoring records | [ ] |

---

## Common Gaps for Early-Stage Companies

- No formal risk register or risk assessment process.
- No access review process (SOC 2 Type II auditors will request quarterly reviews).
- Shared credentials in production.
- No incident response plan beyond "someone calls the founder".
- Vulnerability scans never run (or run but not acted on).
- No formal offboarding process (revoke access on employee departure).

---

## Remediation Priority Order

**P1** (required before audit kickoff):
- SOC2-CC5.1: Unique accounts, no shared credentials
- SOC2-CC5.2: MFA on all admin access
- SOC2-CC6.1: Encryption at rest
- SOC2-CC6.2: Encryption in transit (TLS 1.2+)
- SOC2-CC9.1: Incident response plan

**P2** (required for Type I; must be operating for Type II):
- SOC2-CC3.1: Risk assessment
- SOC2-CC7.1: Vulnerability scanning
- SOC2-CC8.1: Change management process
- SOC2-A1.1: Availability monitoring

**P3** (improve operating effectiveness for Type II):
- SOC2-CC4.1: Vendor risk management
- SOC2-CC7.2: Annual pen test
- SOC2-CC9.2: Incident log discipline
