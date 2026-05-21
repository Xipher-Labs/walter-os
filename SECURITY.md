# Security Policy

## Supported versions

Walter-OS is in alpha. The `VERSION` file in the repo root is the
**source of truth** for the current release; the table below names which
release lines receive security fixes (not which one is current — read
`VERSION` for that).

Security fixes are applied to the **latest minor** release line. The
previous minor receives security fixes only when the underlying bug is
**CVSS v3.1 score ≥ 7.0** (High or Critical per the standard CVSS
severity bands) AND backporting is straightforward; everything else is
fixed on the latest minor and ships in the next release.

| Version | Supported | Notes |
|---|---|---|
| Latest minor (currently 0.4.x — see `VERSION`) | yes | full security + functional support |
| Previous minor (currently 0.3.x) | partial | CVSS ≥ 7.0 security fixes only |
| Older minors (0.2.x, 0.1.x, and any prior) | no | EOL — upgrade to a supported line |

The "currently" labels are refreshed as part of the release checklist;
if they ever disagree with `VERSION`, `VERSION` wins.

### Pre-1.0 stability note

Walter-OS is pre-1.0 alpha software. Breaking changes between minor
versions are normal. Pin to a specific tag or commit if you depend on
the framework in production. The security policy above tracks the
release-line cadence, NOT API stability.

---

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: `security@xipherlabs.xyz`

Include:
- Description of the vulnerability and its potential impact
- Steps to reproduce (with as much detail as is safe to share)
- Any proof-of-concept code (redact credentials)
- Your preferred contact for follow-up

We aim to acknowledge reports within 48 hours and provide a status update
within 7 days. We request a **90-day responsible disclosure window** before
public disclosure to allow time for a fix and coordinated release.

---

## PGP key

A PGP key for encrypted reports will be published at `keys.openpgp.org`
under `security@xipherlabs.xyz`. Until then, unencrypted email is acceptable.

PGP fingerprint: [PGP key coming in v0.2.1 — for now use email only]

---

## Bug bounty

We do not currently run a bug bounty program. Walter-OS is solo-maintained.
We are grateful for responsible disclosure and will acknowledge contributors
in release notes.

---

## Scope

**In scope**:
- Walter-OS source code (all files in this repository)
- Default configuration shipped in the repo
- CI pipeline and GitHub Actions workflows
- Install scripts (`install.sh`, `setup/`)

**Out of scope**:
- Third-party dependencies — report those to their upstream maintainers
- Infrastructure operated by adopters running their own Walter-OS instances
- The `external/` submodule tree (those carry their own security policies)
- Vulnerabilities requiring physical access to the operator's machine

---

## Cross-reference

For commercial licensing enquiries (separate from security), see [COMMERCIAL.md](COMMERCIAL.md).
