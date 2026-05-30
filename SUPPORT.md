# Support

Walter-OS is an open-source alpha project maintained by Xipher Labs +
the community. We do not offer paid support. Use the channels below in
the order listed.

## 1. Check the docs first

- **[README.md](README.md)** — top-level overview, three install modes,
  uninstall flow, security floor.
- **[docs/operational/](docs/operational/)** — runbooks for the
  optional self-hosted stack:
  - [`operator-setup-runbook.md`](docs/operational/operator-setup-runbook.md) — full step-by-step VM install
  - [`requirements.md`](docs/operational/requirements.md) — hardware + DNS + SSH prereqs
  - [`resource-budget.md`](docs/operational/resource-budget.md) — VM sizing per profile combo
  - [`stack-overview.md`](docs/operational/stack-overview.md) — service catalogue
  - [`walter-bridge.md`](docs/operational/walter-bridge.md) — LiteLLM gateway + CLI clients
  - [`network-egress.md`](docs/operational/network-egress.md) — egress allowlist operator guide
  - [`customization-patterns.md`](docs/operational/customization-patterns.md) — four customization layers
  - [`troubleshooting.md`](docs/operational/troubleshooting.md) — 20+ symptom-cause-fix rows
  - [`personas.md`](docs/operational/personas.md) — who Walter-OS is for, in detail
  - [`operator-contexts.md`](docs/operational/operator-contexts.md) — context cascade + overlay paths
  - [`known-issues.md`](docs/operational/known-issues.md) — tracked issues without quick fixes
- **[docs/specs/](docs/specs/)** — feature specs + implementation plans
- **[docs/decisions/](docs/decisions/)** — Architecture Decision Records

## 2. Run the diagnostic

```bash
walter-os doctor       # check install state
walter-os audit        # run the daily supply-chain audit
walter-os doctor --tier 4   # per-tier readiness (1 = agent contract, 4 = Council)
```

Both commands print exact remediation hints for anything they catch.

## 3. Search existing issues

[Open + closed GitHub issues](https://github.com/Xipher-Labs/walter-os/issues?q=is%3Aissue).
Use the same wording the error message uses; the maintainer tends to
copy error strings verbatim into issue titles.

## 4. File a new issue

If nothing above resolves it, open a [new issue](https://github.com/Xipher-Labs/walter-os/issues/new)
with the following template:

```
**Symptom**: (one-line summary)

**Command that triggered it**: `...`

**Expected**: (what should have happened)

**Actual**: (what happened — paste error verbatim)

**Environment**:
- Walter-OS version: `cat VERSION`
- Platform: (macOS ARM / Ubuntu 24.04 / etc.)
- Docker version: `docker --version`
- Mode installed: (1 Lite / 2 Client / 3 Self-hosted)

**Diagnostic output** (redacted of secrets):
```
walter-os doctor
walter-os audit
```
```

PR title convention: `[FIX] -CATEGORY- short description`. CI rejects
malformed titles; [CONTRIBUTING.md](CONTRIBUTING.md) has the full table
of TYPE + CATEGORY values.

## 5. Security findings — do NOT use issues

Security vulnerabilities go through [SECURITY.md](SECURITY.md)'s
private disclosure process. Do not file public issues for
vulnerabilities — the project will work with you to coordinate the
fix and disclosure timeline.

## Response expectations

Walter-OS is alpha. We try to respond to issues within ~5 business
days, but make no commitments. Severity-impacting bugs (security,
data loss, install regressions on a reference platform) get priority.
Feature requests go on the [OSS Trust roadmap](docs/specs/oss-trust-roadmap.md)
backlog and are considered at quarterly review.

Walter-OS does not currently offer guaranteed response times or paid
hands-on support. [COMMERCIAL.md](COMMERCIAL.md) covers commercial
licensing only.
