# Security Policy

## Supported versions

Walter-OS is currently in early development (v0.2.x). Security fixes are
applied to the current release series only.

| Version | Supported |
|---|---|
| 0.2.x | yes |
| 0.1.x | no (EOL) |

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
