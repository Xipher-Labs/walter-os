# GDPR — Applicability and Checklist

## Five-Question Applicability Check

Answer Yes/No to each question:

1. Do you process personal data of individuals in the European Union or EEA?
2. Do you offer goods or services to EU/EEA residents (even if your company is
   not based in the EU)?
3. Do you monitor the behavior of EU/EEA individuals (e.g., website analytics,
   tracking cookies)?
4. Do you process special-category data (health, biometric, ethnic origin,
   political opinion, religious belief, sexual orientation, criminal records)?
5. Do you act as a data processor on behalf of an EU-based controller?

**Verdict**: If you answered Yes to ANY of the above, GDPR applies to you.

---

## Scope Summary

The General Data Protection Regulation (GDPR, EU 2016/679) governs how personal
data of EU/EEA individuals is collected, processed, stored, and deleted. Key
principles: lawfulness, fairness, transparency; purpose limitation; data
minimization; accuracy; storage limitation; integrity and confidentiality.

---

## Self-Assessment Checklist

| ID | Control | Evidence required | Status |
|---|---|---|---|
| GDPR-1 | Privacy policy published at a public URL | URL of privacy policy | [ ] |
| GDPR-2 | Lawful basis documented for each processing activity | Record of Processing Activities (RoPA) | [ ] |
| GDPR-3 | Cookie consent mechanism implemented (if using non-essential cookies) | Screenshot of consent banner; consent management platform config | [ ] |
| GDPR-4 | Data subject rights process: access, deletion, portability, rectification | Written SOP; sample request response | [ ] |
| GDPR-5 | Response time for data subject requests ≤ 30 days | Log of DSARs with response dates | [ ] |
| GDPR-6 | Data Processing Agreements (DPAs) signed with all processors | List of processors + DPA copies | [ ] |
| GDPR-7 | EU Standard Contractual Clauses (SCCs) or adequacy decision for transfers outside EEA | Transfer impact assessment; SCC copies | [ ] |
| GDPR-8 | Data retention policy documented and enforced | Retention schedule; evidence of deletion | [ ] |
| GDPR-9 | Breach notification procedure: report to supervisory authority within 72h | Incident response plan with GDPR section | [ ] |
| GDPR-10 | Data Protection Impact Assessment (DPIA) for high-risk processing | Completed DPIA for applicable activities | [ ] |
| GDPR-11 | Consent records maintained for consent-based processing | Consent logs with timestamp and version | [ ] |
| GDPR-12 | Privacy by design implemented (data minimization in product) | Architecture diagram; product spec references | [ ] |
| GDPR-13 | Employee training on GDPR completed | Training completion records | [ ] |
| GDPR-14 | DPO appointed (if required: >250 employees, or systematic profiling, or special category data at scale) | DPO appointment letter or documented exemption | [ ] |

---

## Common Gaps for Early-Stage Companies

- No Record of Processing Activities (RoPA) — required under Article 30.
- DPAs not signed with third-party processors (CRM, analytics, cloud providers).
- Cookie banners do not obtain consent before loading non-essential scripts.
- No SOP for handling data subject access requests.
- International transfer mechanism missing (most common: no SCCs for US-hosted SaaS).

---

## Remediation Priority Order

**P1** (fix before selling to EU customers):
- GDPR-1: Privacy policy
- GDPR-6: DPAs with processors
- GDPR-7: SCCs or adequacy basis for EEA→US transfer
- GDPR-4: DSAR process

**P2** (fix before formal audit or DPA inspection):
- GDPR-2: RoPA documentation
- GDPR-3: Cookie consent
- GDPR-9: Breach notification procedure
- GDPR-11: Consent records

**P3** (best practice; not audit-blocking at early stage):
- GDPR-10: DPIA for high-risk activities
- GDPR-12: Privacy by design review
- GDPR-13: Employee training
- GDPR-14: DPO assessment
