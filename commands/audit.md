---
description: Run the daily supply-chain audit on demand (also runs automatically every morning).
---

Invoke the `daily-supply-chain-audit` skill via the `walter-os` CLI:

```bash
walter-os audit
```

This resolves to `${WALTER_OS_HOME}/skills/daily-supply-chain-audit/scripts/audit.sh`,
where `WALTER_OS_HOME` is set in `~/.config/walter-os/env` by `install.sh`.

Capture exit code:
- 0: clean — print summary, continue
- 1: info — print findings, continue
- 2: high — print findings, ask operator: "High-severity findings.
  Acknowledge with `walter-os ack <id>` or fix before continuing.
  Proceed anyway?"
- 3: critical — print findings, REFUSE further agentic work in this
  session. Operator must triage manually.

Then summarize the report at `~/.config/walter-os/audit-YYYY-MM-DD.md`
in 3–5 bullets, highlighting actionable items only.
