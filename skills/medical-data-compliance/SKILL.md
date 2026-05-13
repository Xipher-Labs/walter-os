---
name: medical-data-compliance
description: Enforce strict handling of Protected Health Information (PHI) for [Project B] and any medical-data-touching project. Hard rules on what can/cannot be sent to external LLMs, how data is stored, encrypted, audited, and how patient rights (access, deletion, consent) are operationalized. Use whenever a feature, query, prompt, or workflow could touch patient data — proactively, not after the fact. Also applies in the personal/* context for the operator's own health data.
---

# Medical Data Compliance

Hard rules for any code, content, or workflow that touches PHI in
[Project B], affiliated medical projects, or the operator's own personal
health data. These rules are not suggestions; they are the floor of
legal and ethical operation in Argentina under ley 25.326 + ley 26.529.

## Definitions

**PHI (Protected Health Information)** in this context includes:
- Patient identity (name, DNI, contact)
- Diagnoses, conditions, symptoms
- Treatments, medications, prescriptions
- Lab results, imaging, vitals
- Provider identity tied to a patient
- Appointment dates and locations
- Insurance / coverage details
- Genetic data
- Mental health information (extra protection)
- Anything that could re-identify an individual when combined

**De-identified data** is data where direct and indirect identifiers
have been removed AND the residual re-identification risk has been
formally assessed as acceptable. Removing names is not enough.

## Hard rules (non-negotiable)

### Rule 1: PHI never leaves controlled infrastructure

- No PHI to OpenAI, Anthropic, Google, or any third-party LLM API.
- No PHI to external transcription services.
- No PHI to Google Drive, Dropbox, iCloud sync.
- No PHI in Slack, Telegram, email, SMS.
- No PHI in screenshots committed to GitHub.
- No PHI in error logs sent to Sentry / Datadog / similar.

The only places PHI may live: the [Project B] production infrastructure
(databases with documented controls), the patient's own device, and
the local LLM node (encrypted, no cloud sync) for development —
and only de-identified test data on the local LLM node for non-production
work.

### Rule 2: Use synthetic / de-identified data for development

For any code, prompt, demo, or test:

- Generate synthetic patients with `Faker` or similar libraries.
- Use de-identified, formally-released datasets (MIMIC-IV requires
  agreement; safer alternatives exist).
- Document the synthesis method in the test fixture.

If real PHI is needed for debugging a specific incident, that
debugging happens on the production infrastructure under audit, not
locally and not via external tools.

### Rule 3: Encryption everywhere

- **At rest**: AES-256 minimum. Database-level encryption + application-
  level encryption for sensitive columns.
- **In transit**: TLS 1.3. No exceptions.
- **Backups**: encrypted with separate keys.
- **Keys**: managed in a dedicated key management system, not
  application code, not environment variables in plaintext.
- **Patient-controlled encryption** ([Project B]'s differentiation): the
  patient's key encrypts patient data such that the operator alone
  cannot decrypt without the patient's authorization.

### Rule 4: Auditability is mandatory

Every read of patient data emits an audit event with:
- Reader identity (verified)
- Patient record affected
- Time
- Reason / context (linked to a clinical event or the patient's own
  request)
- Whether consent was checked

The patient can review the audit log for their own record at any time.
This is a feature, not a leak — it's how trust gets built in a
patient-controlled system.

### Rule 5: Consent is granular, revocable, and durable

- Consent for a specific use (e.g., "share with Dr. Pérez for
  consultation") is recorded with timestamp, scope, and method of
  consent (written, video-confirmed, on-platform).
- Consent revocation is immediate and effective. Cached / replicated
  data must be re-evaluated against revoked consent.
- Consent is durable — it survives system migrations, account
  exports, and team changes.

### Rule 6: Patient rights are respected by default, code-enforced

Per ley 26.529 + ley 25.326:

- **Right of access**: patient can export their full record on demand,
  in a portable format.
- **Right of rectification**: patient can request correction of
  erroneous data. Rectification creates a new record entry; never
  destroys history.
- **Right of deletion**: patient can request deletion subject to legal
  retention requirements (specific medical records have minimum
  retention periods under Argentine law). Deletion is hard-deletion
  for non-statutory data; soft-flagging for statutory-retained data
  with no further use.
- **Right to know who accessed**: patient sees the audit log.
- **Right to data portability**: standard format export (HL7 FHIR
  preferred where applicable).

These rights are not buried in settings menus; they're first-class
flows in the product.

### Rule 7: Cross-border data transfer follows ley 25.326 art. 12

- Argentine patient data stored in Argentina by default.
- Transfers to "adequate protection level" countries (per current
  AAIP determination) are permitted with notice.
- Transfers to other jurisdictions require: explicit patient consent,
  contractual safeguards (SCC equivalent), or a specific legal
  exception.
- Document every cross-border data flow in the data-flow registry.

### Rule 8: Vendor / partner data sharing requires DPA

Any third party that processes patient data — even minimally — has a
signed Data Processing Agreement covering:
- Scope and purpose of processing
- Security obligations
- Sub-processor restrictions
- Breach notification timeline
- Termination + data return / destruction
- Patient rights coverage

No data sharing without a DPA. "We just send them logs" is data
sharing.

### Rule 9: Breach response is pre-planned and rehearsed

A documented breach response plan exists, with:
- Who decides what (incident commander, legal lead, comms lead)
- Notification timelines (AAIP within statutory window)
- Patient notification procedures
- Forensic preservation steps
- Post-incident review template

Rehearse the plan annually. Don't discover the gaps during the
incident.

### Rule 10: Threat model documented and reviewed

The PHI threat model is documented in `docs/security/threat-model.md`
and reviewed quarterly:
- Threat actors (insider, external attacker, state actor, partner
  compromise, lost device)
- Attack surfaces (API, web app, mobile app, ops tooling, vendor
  integrations)
- Critical assets (PHI database, encryption keys, consent records,
  audit logs)
- Mitigations and gaps

## Operational checks

For every PR / feature / change:

- [ ] Does this change touch PHI? If yes, this skill applies.
- [ ] No PHI sent to external services (LLM, analytics, telemetry).
- [ ] PHI columns encrypted at rest.
- [ ] Access requires authentication AND authorization.
- [ ] Audit event emitted for every read/write.
- [ ] Consent verified before data use.
- [ ] Test fixtures use synthetic data only.
- [ ] Logs scrubbed of PHI (use structured logging with field-level
      redaction).
- [ ] Error messages don't leak PHI back to the client.
- [ ] Documentation updated if data flow changed.
- [ ] If new vendor involved: DPA in place.
- [ ] If new cross-border flow: documented + lawful basis.

## Specific code patterns

### Logging

```rust
// BAD
tracing::info!("Patient {} accessed record {}", patient_name, record_id);

// GOOD - identifiers as opaque IDs, no PHI in logs
tracing::info!(
    patient_id = patient.id_hash(),
    record_id = record.id,
    accessor_id = actor.id,
    "patient.record.read"
);
```

### Error responses

```rust
// BAD - leaks that the patient exists
return Err(ApiError::Forbidden("Patient X not consented to share with Y"));

// GOOD - minimal information
return Err(ApiError::Forbidden);
```

### Test fixtures

```rust
// In tests/fixtures/synthetic_patients.rs
pub fn synthetic_patient_with_diabetes() -> Patient {
    Patient {
        id: PatientId::new(),
        name: faker_es_AR::name::name(),
        // ... etc, all synthesized
        notes: "[SYNTHETIC] Tipo 2, controlled with metformin",
    }
}
```

Never check real or real-derived PHI into fixtures.

### Prompt construction (if [Project B] ever uses LLMs internally)

Internal use of LLMs is permitted ONLY if:
- LLM is hosted on [Project B] infrastructure (local Ollama, on-prem
  inference, or contractually-isolated tenant)
- Data flow audited
- Patient consent specifically covers this use
- Prompt templates reviewed for PHI leakage

Default position: LLMs do not touch PHI. Build features without LLM
involvement on the PHI path.

## Walter-OS-specific guardrails

When using Claude Code / Codex / any agent on [Project B] repos OR in the
operator's `personal/*` context with their own health data:

- **Never paste real patient data** into prompts. The agent runs in
  Anthropic / OpenAI infrastructure — that's external.
- **Use synthetic fixtures** when asking the agent to debug or build
  features.
- **Pre-commit hook** scans for accidental PHI patterns (DNI, common
  health terms in test data) before commit.
- **The `daily-supply-chain-audit` hook** verifies that the [Project B]
  repo has not had its synthetic-only fixtures replaced with real data.

## Jurisdiction-specific compliance

Medical data compliance is jurisdiction-specific. Use `regulatory-research-international`
with `WALTER_JURISDICTION` and `WALTER_REGULATORY_DOMAIN=health` to research the
applicable framework. Key frameworks by region:

- **HIPAA** (US): minimum necessary standard, covered entity/business associate
  agreements, breach notification within 60 days.
- **GDPR + national health law** (EU): explicit consent, right to erasure, DPO
  required for systematic health data processing.
- **Jurisdiction-specific** (others): invoke `regulatory-research-international`
  to identify the applicable statute.

All frameworks share these core obligations: explicit consent, access logs, encryption,
right of access, right to deletion, breach notification. Implement these universally;
add jurisdiction-specific requirements on top.

Verify specifics with counsel before relying on this skill for compliance decisions.

## Anti-patterns

- **"We'll add encryption later"**: [Project B] never has a "later" for
  this. It's day-1.
- **"It's just test data"**: any test data that's real-derived is
  PHI. Treat it as PHI or don't use it.
- **"The vendor said they're HIPAA-compliant"**: HIPAA is US, doesn't
  apply here. Argentine compliance is what matters; ask the vendor
  about ley 25.326 specifically.
- **"Patient won't notice"**: assume every patient will read the audit
  log of who accessed their record. Build for that audience.
- **"Just for debugging"**: never. Debug in production with audit, or
  with synthetic data.

## Integration

- `regulatory-research-argentina` provides legal grounding.
- `solana-program-review` enforces the on-chain side: no PHI on-chain,
  hashes only.
- `daily-supply-chain-audit` checks repo for PHI exposure patterns.
