# Recon + vuln-scanning profile — spec

**Status**: ready for `/write-plan` after operator approval
**Issue**: #27 (`[FEAT] -SECURITY- add recon and vuln-scanning profile`)
**Target release**: v0.5.0 (alongside multi-model wizard #24 and walter-debt tracker #2)
**Depends on**: nothing new in main — uses the existing MCP-profile pattern.

## Problem

Walter-OS gives the operator a strong defensive posture (daily supply-chain audit, approval-gate, hook integrity scan, env-allowlist parser) but ZERO offensive tooling. Two legitimate operator scenarios are unsupported today:

1. **Self-scan before deploy.** "I'm about to ship project X to walter.example. Is there an obvious open port / weak TLS / unpinned dep I missed?"
2. **Authorized pentesting.** Bug-bounty work, or a security audit on a friend's product with written permission. The operator needs nuclei / httpx / subfinder ready to go.

Adding these tools to the default profile would be a foot-gun: an agent with `tier=medium` running `nuclei` against a third-party target is an unauthorized scan = potentially criminal. So the question isn't "should Walter-OS have offensive tooling" — it's "how do we ship it with the discipline that matches its risk."

Pattern reference: the existing repo already splits Claude Code's settings into `default` (read-mostly, low-blast-radius, loaded automatically) and `high-risk` (destructive, money-spending, lateral-movement-risk, manually swapped via `walter-os profile high-risk` per AGENTS.md). `mcp/servers.json` flags servers with a `"profile": "manual"` field — these are loaded only when the high-risk settings file is active. The recon tooling lives in the same risk class as the high-risk profile and uses the same swap pattern.

## Non-goals

- Building a managed pentest service. Walter-OS provides the CLIs; operator drives the engagement.
- Bundling Greenbone/OpenVAS in `default`. Heavy footprint, slow update cadence, separate concern.
- Authorization workflow automation (TOSAS / disclosure templates). Skill-level future work.
- Auto-running nuclei after every `walter-os deploy`. Operator chooses targets; we don't auto-scan.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **New settings profile: `pentest`** alongside `default` and `high-risk`. Lives in `~/.claude/settings.pentest.json` and `~/.codex/config.pentest.toml`. Activated via `walter-os profile pentest` — extends the existing `walter-os profile {default,high-risk}` swap pattern to a third profile name. Requires the same code-path additions in `cmd_profile` for the new profile name. | Same swap pattern, third tier. |
| D-2 | **CLI-skills, NOT MCPs.** Walter-OS vendors `skills/nuclei-cli/`, `skills/httpx-cli/`, `skills/subfinder-cli/`, `skills/trivy-cli/`, `skills/grype-cli/`. No third-party MCP supply chain. | Same rationale as `heygen-cli`, `hcloud-cli` etc. CLI is the official surface for all these tools; MCPs would just be uncontrolled wrappers. |
| D-3 | **Authorization gate ALWAYS required for any function that hits a third-party target.** This applies to recon tools whether the call is read-only (subfinder, httpx, theHarvester, nuclei probes) or arguably state-changing — the risk is unauthorized scanning, not state mutation. The gate refuses to run against a target unless the operator explicitly types the target hostname AND a one-line authorization note ("operator owns walter.example", "bug bounty program at hackerone.com/foo", etc.). | Legal cover. Recon tools are PRIMARILY read-only but the risk class is "unauthorized probing" — characterizing them as "state-changing" would mis-frame the threat. The note gets logged. |
| D-4 | **Greenbone/OpenVAS deferred to a `heavy-pentest` profile.** Documented as opt-in, RAM/storage expectations called out. Not part of v0.5.0. | Greenbone is a separate concern; folding it in delays the lightweight CLI ship. |
| D-5 | **Default profile gains `trivy` + `grype` as `info`-only.** These are container/dep CVE scanners on the operator's OWN artifacts (Docker images they built, repos they own) — no third-party target involved. Safe to run in default. | Catches CVEs in operator's own supply chain without flipping to pentest profile. |
| D-6 | **`pentest` profile, when active, makes approval-gate stricter, not looser.** Every nuclei/httpx invocation is classified by `_classify_command` (new patterns: `nuclei-scan`, `httpx-probe`, `subfinder-enum`, `amass-enum`, `theharvester-enum`) and the corresponding `CATEGORY_MIN_TIER` entries set the tier minimum to `high`. CATEGORY_MIN_TIER is a TIER-MINIMUM matrix (low/medium/high) — recon tools require an agent at tier `high` (currently only `reviewer` per `~/.config/walter-os/trust-tiers.yml`) before the gate's classification path even runs. The classifier additions are part of this spec. | The profile UNLOCKS the tooling but does NOT loosen the gate; reflexive guardrails remain. Both halves are required — adding entries to `CATEGORY_MIN_TIER` without matching `_classify_command` patterns is a no-op (the tier check only applies to categories the classifier emits). |
| D-7 | **Daily-supply-chain-audit checks the recon tools too.** When the `pentest` profile is active, the audit cycles through trivy/grype/nuclei version pinning + CVE checks. | Consistency: every tool in any profile is pinned + scanned. |

## Tool evaluation matrix

| Tool | What it does | Profile | Status |
|---|---|---|---|
| **trivy** | Container + filesystem + git repo CVE scanner | **default** (operator-own artifacts only) | Mature, Aqua Security, weekly DB updates, free. |
| **grype** | Filesystem + container CVE scanner (similar to trivy, second opinion) | **default** | Mature, Anchore, daily DB. |
| **nuclei** | Template-based vuln scanner (web / SSL / DNS / API). Read-only HTTP probes. | **pentest** | Mature, ProjectDiscovery, very high template-quality. THIS IS THE PRIMARY TOOL. |
| **httpx** | Fast HTTP probe — title, status, tech detection. | **pentest** | Same maintainer as nuclei. Pairs naturally. |
| **subfinder** | Subdomain enumeration via passive sources (Censys, Shodan, ChaosDB, etc.). | **pentest** | Same maintainer. Passive sources = no direct scan of target. |
| **amass** | Subdomain enum + active brute-force + ASN mapping. | **pentest** (deeper option) | More features than subfinder but slower; ship both, operator picks. |
| **theHarvester** | OSINT email + subdomain harvester from search engines. | **pentest** | Passive sources only; classic recon. |
| **Greenbone/OpenVAS** | Full vulnerability management platform — heavy agent, daily NVT feed (1GB+), Postgres backend. | **`heavy-pentest`** (deferred) | Heavyweight; v0.5.0 spec defers it. |

Selection for v0.5.0:
- **Default profile**: add `trivy`, `grype` skills.
- **`pentest` profile**: `nuclei`, `httpx`, `subfinder`, `amass`, `theHarvester`.
- **Deferred**: Greenbone/OpenVAS to a future `heavy-pentest` profile.

## Acceptance criteria

### AC-1 — Default-profile CVE scanners (trivy + grype)
- [ ] `skills/trivy-cli/SKILL.md` + `trivy.sh` — function library wrapping `trivy image`, `trivy fs`, `trivy repo`. Read-only; no scanning of third-party assets.
- [ ] `skills/grype-cli/SKILL.md` + `grype.sh` — same shape; second-opinion CVE scanner.
- [ ] `setup/Brewfile` adds `trivy` + `grype` to the install list.
- [ ] `daily-supply-chain-audit` extended `check_versions()` includes trivy + grype version pinning if installed.

### AC-2 — `pentest` MCP profile
- [ ] `~/.claude/settings.pentest.json` template generated by `install.sh --profile-pentest`.
- [ ] `~/.codex/config.pentest.toml` same.
- [ ] `walter-os profile pentest` switches both. `walter-os profile default` switches back.
- [ ] Profile contents: same MCP set as `default` PLUS the recon skill autoloads (`nuclei-cli`, `httpx-cli`, `subfinder-cli`, `amass-cli`, `theHarvester-cli`).

### AC-3 — Recon CLI skills (5 skills)
Each skill follows the heygen-cli / hcloud-cli template:

- [ ] `skills/nuclei-cli/SKILL.md` + `nuclei.sh`. Functions: `nuclei_scan <target>` (requires `--auth "reason"` flag), `nuclei_template_list`, `nuclei_template_update`. Authorization gate: any function that hits the network refuses without `--auth "<one-line reason>"` and logs the auth note to `~/.config/walter-os/pentest-log.jsonl`.
- [ ] `skills/httpx-cli/SKILL.md` + `httpx.sh`. Same gate.
- [ ] `skills/subfinder-cli/SKILL.md` + `subfinder.sh`. Same gate.
- [ ] `skills/amass-cli/SKILL.md` + `amass.sh`. Same gate. Comment on the active-brute-force mode explicitly (it's louder than subfinder; operator must opt in with `--active`).
- [ ] `skills/theHarvester-cli/SKILL.md` + `theharvester.sh`. Same gate. Passive sources only.

### AC-4 — Approval-gate hardening for pentest mode
- [ ] `hooks/approval-gate.sh` `CATEGORY_MIN_TIER` adds:
  - `nuclei-scan=high`
  - `subfinder-scan=high`
  - `amass-scan=high`
  - `httpx-probe=high`
  - `theharvester-probe=high`
- [ ] When `WALTER_PROFILE=pentest` is detected, the gate ALSO requires `WALTER_PENTEST_AUTH=<reason>` to be set in the same env. Without it, the hook blocks with `pentest profile active but WALTER_PENTEST_AUTH not set`.
- [ ] bats coverage in `tests/hooks/approval-gate.bats` for: `WALTER_PROFILE=pentest` without auth → block; with auth → allow + log.

### AC-5 — Pentest audit log
- [ ] Every authorized scan appends a JSONL record to `~/.config/walter-os/pentest-log.jsonl`:
  ```json
  {"ts":"2026-...","tool":"nuclei","target":"walter.example","auth":"operator owns walter.example","operator":"ops-bot"}
  ```
- [ ] `walter-os pentest log` subcommand prints the log filtered by tool / target / date range.
- [ ] Auditable trail for incident-response or bug-bounty disclosure submission.

### AC-6 — Legal + operator-facing docs
- [ ] `docs/operational/pentest-profile.md` (new):
  - Authorization-only-targets policy.
  - How to verify target ownership before scanning.
  - Bug-bounty program checklist (in-scope assets list, rate-limit awareness, disclosure timeline).
  - Greenbone/OpenVAS deferred — heavy-pentest profile placeholder.
- [ ] CHANGELOG entry under `[Unreleased] → Added`.

### AC-7 — Heavy-pentest profile placeholder
- [ ] `docs/operational/heavy-pentest-profile.md` (stub) documents the deferred Greenbone/OpenVAS path with:
  - Resource expectations (4GB RAM, 5GB storage, daily NVT feed)
  - Why deferred (operational overhead beyond v0.5.0 scope)
  - When to revisit (operator running > 10 self-hosted services + wanting deep auth scans)
- [ ] No code shipped for AC-7 in v0.5.0.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Operator chooses profile                                        │
│  $ walter-os profile pentest                                     │
│  ↓                                                               │
│  ~/.claude/settings.json ← settings.pentest.json (swap)         │
│  ~/.codex/config.toml    ← config.pentest.toml    (swap)        │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ Profile is now ACTIVE.
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Operator must set WALTER_PENTEST_AUTH before any scan           │
│  $ export WALTER_PENTEST_AUTH="bug bounty: hackerone.com/foo"    │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Skill invocation                                                │
│  $ source skills/nuclei-cli/nuclei.sh                            │
│  $ nuclei_scan https://walter.example                            │
│     ├─► approval-gate.sh: WALTER_PROFILE=pentest +               │
│     │                     WALTER_PENTEST_AUTH set + category    │
│     │                     `nuclei-scan` requires tier `high`     │
│     ├─► reflexive guardrail: operator MUST type "go" in chat     │
│     ├─► append to pentest-log.jsonl                              │
│     └─► exec nuclei -u $TARGET -t /path/to/templates             │
└──────────────────────────────────────────────────────────────────┘
```

## Threat model

- **Operator scans a third-party target without permission.** The `--auth "<reason>"` flag + `WALTER_PENTEST_AUTH` env + reflexive guardrail force the operator to type a justification three times before any HTTP probe leaves the machine. If they still do it, that's an operator decision; the audit trail is in `pentest-log.jsonl`.
- **Agent triggers a scan via prompt injection.** `nuclei-scan` is `tier=high` in approval-gate; agents at `medium` or lower cannot trigger it. Lateral movement via MCP is blocked by the standing-approvals lockdown (P1-06 fix).
- **Template repo poisoning (nuclei loads templates from a community repo).** `nuclei_template_update` pins to a specific commit SHA of `projectdiscovery/nuclei-templates`. Same pattern as P0-05 submodule pinning.

## Out of scope

- **Greenbone/OpenVAS.** Deferred to `heavy-pentest` profile, future release.
- **Burp Suite / OWASP ZAP integration.** Both are GUI-heavy; CLI integration is awkward; not v0.5.0.
- **Auto-generated bug-bounty submission reports.** Skill follow-up, not in v0.5.0.
- **Phishing simulation tooling.** Different threat model + much higher operator-error blast radius. Separate epic.

## Recommended PR ordering

1. AC-1 — trivy + grype skills (default profile, no new MCP profile yet)
2. AC-3a — nuclei-cli skill + authorization gate
3. AC-3b — httpx-cli, subfinder-cli (compose with nuclei)
4. AC-3c — amass-cli, theHarvester-cli
5. AC-2 — `pentest` MCP profile + `walter-os profile pentest` subcommand
6. AC-4 — approval-gate `CATEGORY_MIN_TIER` extensions + `WALTER_PENTEST_AUTH` gate
7. AC-5 — pentest-log + `walter-os pentest log` subcommand
8. AC-6 + AC-7 — docs + CHANGELOG + heavy-pentest placeholder

Each PR is small (≤250 LOC), runs the 3-round review, and references this spec.

## Open questions for the operator

1. **Should `trivy` + `grype` BOTH ship in default, or just one?** Proposal: both. They catch different CVE feeds; second-opinion has value. Operator can disable one in personal.env.
2. **Should `WALTER_PENTEST_AUTH` be a one-time-per-shell decision (operator sets it once and it covers all scans in that shell) or per-invocation (every `nuclei_scan` call requires re-typing)?** Proposal: one-time-per-shell, with a 4-hour TTL written to a tmp file so a forgotten shell doesn't auto-authorize next week's scan.
3. **Should `walter-os pentest log` be its own subcommand or part of `walter-os audit`?** Proposal: its own subcommand; the pentest log is operator-owned audit trail, conceptually different from supply-chain audit findings.

## Refs

- Issue #27
- `mcp/servers.json` `default` / `manual` profile pattern
- `hooks/approval-gate.sh` `CATEGORY_MIN_TIER` table
- `docs/decisions/0009-agent-trust-tiers.md` (tier semantics)
- `skills/hcloud-cli/`, `skills/heygen-cli/` (CLI-skill template)
