> **EXAMPLE FILE — Regulatory Research (Any Jurisdiction)**
> This file shows how to configure the `regulatory-research-international`
> skill for a specific jurisdiction and regulatory domain. All org and project
> names are fictional. Replace every `[BRACKETED]` or placeholder value with
> your actual situation before using this as a reference when invoking the
> skill. This is not a context overlay — it is a skill configuration reference.

# Regulatory Research Skill Configuration — Generic Template

## What this skill does

The `regulatory-research-international` skill helps research legal and
regulatory requirements in any jurisdiction. It covers frameworks like:

- **Data protection**: GDPR (EU/EEA), UK GDPR, LGPD (Brazil), PIPEDA (Canada),
  CCPA (California), PDPA (Thailand/Singapore), APPI (Japan), and others.
- **Healthcare**: HIPAA (US), MDR (EU medical devices), TGA (Australia).
- **Financial**: PCI-DSS (global), SOX (US public companies), MiFID II (EU),
  Open Banking / PSD2 (EU), Basel III (banking).
- **Procurement**: public procurement rules vary by jurisdiction — EU Directives,
  FAR/DFARS (US federal), and national equivalents.
- **AI regulation**: EU AI Act, US EO on Safe and Trustworthy AI, and emerging
  national frameworks.

## How to configure for your situation

Set these environment variables before invoking the skill:

```bash
export WALTER_JURISDICTION="<your-jurisdiction>"
# Examples: "EU", "US", "UK", "Brazil", "Canada", "Australia", "Japan", "Singapore"

export WALTER_REGULATORY_DOMAIN="<your-domain>"
# Values: "data-protection" | "healthcare" | "financial" | "procurement" | "ai" | "labor"
```

Then invoke the skill:
```
/regulatory-research jurisdiction=<your-jurisdiction> domain=<your-domain>
```

## Example: data protection for a SaaS with EU customers

```bash
export WALTER_JURISDICTION="EU"
export WALTER_REGULATORY_DOMAIN="data-protection"
```

Key statutes: GDPR (Regulation 2016/679). Primary regulator: your local DPA
(e.g., CNIL in France, ICO in the UK, BfDI in Germany). Key compliance tasks:
privacy policy, DPA agreements, DSAR response process, breach notification
within 72 hours.

## Example: healthcare app in the United States

```bash
export WALTER_JURISDICTION="US"
export WALTER_REGULATORY_DOMAIN="healthcare"
```

Key statute: HIPAA. Primary regulator: HHS Office for Civil Rights. Key tasks:
Business Associate Agreements (BAAs), HIPAA Security Rule technical safeguards,
audit logs, PHI encryption at rest and in transit.

## Counsel relationship

Document your legal counsel relationship here so the agent knows escalation
boundaries:

```
Legal counsel: [firm name or "none — self-research only"]
Counsel jurisdiction: [jurisdiction]
Last regulatory review date: [YYYY-MM-DD]
Next scheduled review: [YYYY-MM-DD]
```

The agent performs research and drafts; counsel reviews and validates.
The agent is never a substitute for licensed legal advice.

## Prompt for your AI

Copy the following into your preferred AI assistant (ChatGPT, Claude, Gemini, etc.)
and replace the `[BRACKETED]` fields with your actual situation:

> I'm setting up Walter-OS's `regulatory-research-international` skill for
> my specific regulatory context. My situation:
>
> - Jurisdiction(s) I operate in: [list countries/regions]
> - Regulatory domain: [data protection / healthcare / financial / procurement / AI / labor]
> - Primary regulatory framework I need to comply with: [GDPR / HIPAA / PCI-DSS / other]
> - Primary regulator: [regulator name]
> - Key statutes I already know: [list any you are already aware of]
> - Product / service description: [one sentence]
> - Customer type: [B2B / B2C / government / internal]
> - Do I have in-house or external legal counsel? [yes — firm name / no]
> - Last compliance review date: [YYYY-MM-DD or "never"]
>
> Based on this, generate a customized configuration block for the
> `regulatory-research-international` skill that I can place in my
> Walter-OS personal overlay or reference when invoking the skill.
> Include the env vars, key statutes, and top 3 compliance gaps I should
> investigate first.
