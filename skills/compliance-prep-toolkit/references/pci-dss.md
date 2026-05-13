# PCI-DSS — Applicability and Checklist

## Five-Question Applicability Check

Answer Yes/No to each question:

1. Do you accept credit card payments directly (cardholder enters card data on
   your site or in your application)?
2. Do you store, process, or transmit cardholder data (card numbers, CVV, expiry)?
3. Do you use a payment gateway but customize the checkout flow with your own code
   (not a fully hosted payment page)?
4. Are you a software provider whose product is used to process payment cards
   by your customers?
5. Do you have access to cardholder data environments at your customers?

**Verdict**: If you answered Yes to ANY of the above, PCI-DSS applies.
If you use a fully hosted payment page (Stripe Checkout, PayPal hosted page)
and store no card data yourself, your scope is minimal (SAQ A).

---

## Scope Summary

PCI-DSS (Payment Card Industry Data Security Standard) v4.0 covers any
organization that stores, processes, or transmits cardholder data. Self-Assessment
Questionnaires (SAQs) reduce the audit burden for lower-risk merchants:

- **SAQ A**: Fully outsourced, no cardholder data stored/processed/transmitted.
- **SAQ A-EP**: E-commerce with redirected payment, JavaScript loaded from your page.
- **SAQ D**: All other merchants and service providers.

Most SaaS companies using Stripe/PayPal hosted checkout qualify for SAQ A or A-EP.

---

## Self-Assessment Checklist (SAQ A / A-EP — most SaaS)

| ID | Control | Evidence required | Status |
|---|---|---|---|
| PCI-1.1 | All cardholder data pages served over HTTPS | SSL certificate; no HTTP pages | [ ] |
| PCI-1.2 | No card data stored in application databases, logs, or caches | Code audit; log review | [ ] |
| PCI-1.3 | Payment service provider is PCI-DSS certified | PSP compliance certificate (e.g., Stripe) | [ ] |
| PCI-1.4 | Signed contract with PSP covering data security responsibilities | PSP agreement | [ ] |
| PCI-2.1 | Third-party scripts on payment pages are from approved sources only | Content Security Policy; script inventory | [ ] |
| PCI-2.2 | Vulnerability scanning of public-facing payment endpoints (quarterly) | ASV scan reports | [ ] |
| PCI-3.1 | Incident response plan covers payment card data breaches | IRP document; PCI section | [ ] |
| PCI-3.2 | User access to payment administration limited to authorized personnel | Access control matrix | [ ] |
| PCI-4.1 | Annual self-assessment questionnaire completed and signed | SAQ document | [ ] |

---

## Common Gaps for Early-Stage Companies

- Logging systems inadvertently capture card numbers or CVVs in request logs.
- JavaScript from third parties loaded on payment pages without CSP controls.
- No documented contract specifying the PSP's compliance responsibilities.
- Developers with access to production have more privileges than needed for scope.
- SAQ never completed (required annually for card brand compliance).

---

## Remediation Priority Order

**P1** (required before accepting live card payments):
- PCI-1.1: HTTPS everywhere
- PCI-1.2: Confirm no card data in logs
- PCI-1.3: Confirm PSP is PCI-certified

**P2** (required for annual self-assessment):
- PCI-2.1: CSP for payment pages
- PCI-2.2: Quarterly ASV scan
- PCI-4.1: Complete SAQ

**P3** (best practice):
- PCI-3.1: IRP with PCI section
- PCI-3.2: Access review for payment admin
