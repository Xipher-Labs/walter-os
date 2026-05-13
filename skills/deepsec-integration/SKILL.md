---
name: deepsec-integration
description: Run Vercel's DeepSec security scanner against any Walter-OS-tracked repo ([Project A], [Project B], [Company], hackathons). DeepSec uses thinking-level models to surface hard-to-find vulns that pattern matchers miss. SPENDS MONEY ($100s-$thousands per scan). Operator-invoked only, with explicit budget cap and confirmation. Triggered by user requests like "run deepsec on [project-a]", "scan [company] for vulnerabilities", "deep security audit of <repo>".
---

# DeepSec — agent-powered deep security audit

[deepsec](https://github.com/vercel-labs/deepsec) by Vercel Labs (Apache-2.0,
~700 stars). Wraps coding agents at maximum thinking levels to find:
- subtle auth-bypass paths
- TOCTOU race conditions
- crypto misuse (custom IV, key reuse)
- SSRF in user-controllable URL handlers
- prototype pollution, ReDoS in dynamic regex
- vulnerable dep transitive paths static SAST misses

Distinct from `daily-supply-chain-audit` (which is dep-tree CVE scanning).
DeepSec reads YOUR code semantically.

## When to invoke

| Trigger | Example |
|---|---|
| Pre-launch deep audit | "Run deepsec on [project-a] before going to mainnet" |
| Post-incident root cause | "Scan [company]-rpc for the auth-bypass class we just patched" |
| Periodic deep dive | "Quarterly deepsec on [project-b]" |
| Specific concern | "Deepsec the new Solana program in anchor-vault" |

DO NOT run automatically. DO NOT run on every PR (cost). DO confirm
budget before kicking off.

## Cost reality

Per the project's own README: scans can cost **thousands of dollars** for
large repos because they fan out parallel workers at maximum reasoning
depth.

**Walter-OS budget guardrail**:
- Confirm $ before any scan
- Use scoped repos (small components, not monorepos)
- Default model tier: Opus or GPT-5.5-pro (cheaper than maximum)
- Cap fan-out workers at 2 unless operator overrides

## Setup (per repo, one-time)

```bash
cd ~/Projects-Personal/<repo>     # or ~/work/<repo>
npx deepsec init                  # creates .deepsec/ scaffold
cd .deepsec
pnpm install                      # pulls deepsec from npm
```

The `init` command creates `.deepsec/data/<id>/SETUP.md` and an empty
`INFO.md`. Walter-OS convention: bootstrap INFO.md via Claude Code:

```
Read .deepsec/node_modules/deepsec/SKILL.md to understand the tool.
Then read .deepsec/data/<id>/SETUP.md and follow it. Keep INFO.md
under 100 lines, project-specific only (skip generic CWE cats —
built-in matchers cover those). Name auth helpers, middleware,
external boundaries. No line numbers, no exhaustive enumeration —
3-5 representative examples per section.
```

## Running a scan

```bash
cd <repo>/.deepsec
pnpm deepsec scan                 # the actual scan, MOST EXPENSIVE STEP
pnpm deepsec process              # consolidate findings
pnpm deepsec revalidate           # optional FP reduction
pnpm deepsec export --format md-dir --out ./findings
```

Operator pre-flight:
```
1. budget = $___    (confirm with operator BEFORE scan)
2. scope =  <repo>  (sub-package or full?)
3. matchers = default OR custom
```

After scan: review findings in `./findings/`. Each finding is a markdown
file describing vuln + reproduction + suggested fix.

## Walter-OS integration

### Hook to `walter audit` subcommand

`walter audit deep <repo>` (planned addition) wraps deepsec invocation:

```bash
walter audit deep [project-a]-web          # scopes to one repo
walter audit deep --budget 50 [company]   # cap LLM spend at $50
walter audit deep --quick [project-b]     # use quick matchers (cheap, less coverage)
```

Implementation: see `scripts/walter/subcommands/audit-deep.sh` (TODO).

### Include in quarterly cadence

Per `quarterly-upgrade-cadence` skill:
- Q1, Q3: light deep-scan on all production repos ([Project A], [Project B] prod, [Company])
- Q2, Q4: full deep-scan on highest-stakes repo only

### Output handling

- Findings → `~/Projects-Personal/<repo>/.deepsec/findings/<date>/`
- Critical findings (CVSS ≥ 8) → auto-create Plane issue with label `security`
- Trivial / FP findings → archive in `findings/dismissed/` with operator note

## Hard rules

- **NEVER run deepsec on a third-party repo without permission.** This is
  semantic code analysis with strong agents; it's effectively reverse-engineering.
- **NEVER let deepsec exfiltrate secrets.** Scope `.gitignore`-d files
  excluded by default; verify `.deepsec/.gitignore` includes `.env*`.
- **Budget before scope.** Always cap LLM spend per scan.
- **Findings are not fixes.** Operator reviews, decides which to act on.
  Some findings are theoretical or out-of-scope.

## What this skill does NOT do

- Replace daily-supply-chain-audit (CVE/license scan)
- Run continuously / in CI (too expensive, too slow)
- Fix findings — that's a human + standard reviewer subagent loop
- Cover infrastructure (Walter-VM hardening) — that's separate

## References

- https://github.com/vercel-labs/deepsec
- https://vercel.com/blog/introducing-deepsec-find-and-fix-vulnerabilities-in-your-code-base
- skills/daily-supply-chain-audit/ — complementary, dep-tree scanning
- skills/security-auditor/ (planned) — specific OWASP / web-security-baseline
