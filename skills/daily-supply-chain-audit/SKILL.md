---
name: daily-supply-chain-audit
description: Run a comprehensive daily security audit of all installed MCP servers, Claude Code skills, agent configs, and AI CLI tooling. Detects supply chain attacks, tool-name shadowing, malicious skills, configuration drift, missing CVE patches, and untrusted package versions. Use this skill EVERY MORNING before starting work, on demand when installing a new MCP/skill, or after pulling Walter-OS updates. ALSO trigger when the user asks "is my agent setup safe", "audit my MCPs", "check for vulnerabilities", "any new CVEs", or mentions concerns about supply chain, tool poisoning, prompt injection, or malicious skills.
---

# Daily Supply Chain Audit

Audits the agentic toolchain end-to-end and refuses to let work continue if
critical vulnerabilities are found. Designed for paranoia, calibrated for
2026's threat landscape (1,184 malicious skills found in ClawHavoc,
CVE-2025-59536 hooks injection RCE, three vulns in Anthropic's own Git MCP,
mcp-remote CVSS 9.6 RCE — supply chain attacks on AI tooling are real and
ongoing).

## What it checks

1. **Tool versions** — `claude --version` ≥ 2.0.65, `codex --version` current,
   `gh`, `node`, `pnpm` not on known-vulnerable releases.
2. **Config drift** — `~/.claude/settings.json`, `~/.codex/config.toml`, and
   any `.mcp.json` in active repos diffed against signed baselines stored in
   `~/.config/walter-os/baselines/`. Unauthorized additions = block.
3. **Hooks integrity** — every hook in `~/.claude/settings.json` matches a
   sha256 in `~/.config/walter-os/hook-checksums.json`. New hooks require
   explicit operator approval (the script prompts).
4. **Installed MCP servers** — runs `mcp-scan` (Snyk) and `mcp-scanner` (Cisco)
   if available; queries `agentaudit.dev` and `mcpskills.io` for trust scores.
5. **Skills audit** — every skill in `~/.claude/skills/` and `~/.codex/skills/`
   gets static analysis: scripts shouldn't `curl | bash`, shouldn't write to
   `~/.ssh`, shouldn't egress to non-allowlisted domains.
6. **Tool definition drift** — stdio, HTTP, and SSE MCP servers loaded from
   `~/.claude/settings.json` are probed via `tools/list` and compared against
   the operator-approved baseline in
   `~/.config/walter-os/mcp-tool-snapshots.json`. Mutation = potential
   tool-name shadowing attack = block. The probe only executes default-profile
   MCPs whose approved registry entry is enabled and whose stdio
   `command`/`args`/`env` or remote `type`/`url`/`headers` match the approved
   server-registry baseline. Remote header placeholders are materialized only
   after that registry match and are not persisted to the tool baseline.
7. **Pinned versions** — every MCP package reference in runtime config
   (`~/.claude/settings.json` → `.mcpServers`) must be pinned. The audit
   enforces these exact forms:
   - npm / npx: `package@x.y.z` (or `@scope/package@x.y.z`)
   - uvx: `package==x.y.z` (or `uvx --from package==x.y.z <entry-point>`)
   - git: `package#<commit-sha>` (7+ hex chars)
   Dist-tags/ranges are rejected (`@latest`, `@beta`, `^1.2.3`, `>=1.0`,
   `~=1.5`, etc.). If you change `mcp/servers.json`, re-run `install.sh
   --upgrade` so `~/.claude/settings.json` is refreshed before auditing.
8. **Vendored skill pins** — every third-party skill vendored under `skills/`
   must be listed in `assets/pinned-refs.toml` with a full 40-char upstream
   commit SHA and a deterministic local content hash. Drift or missing
   manifest entries emit a high-severity audit finding.
9. **CVE feed** — checks NVD for new CVEs published in the last 24h affecting
   any installed package. Match-by-name and match-by-CPE.
10. **Secrets exposure** — greps `~/.claude/settings.json`, `~/.codex/config.toml`,
   and any `.mcp.json` for plaintext keys (API tokens, JWT, AWS creds).
   Should be zero — all secrets via env vars.
11. **Minimum release age** — queries npm and PyPI to verify that each installed
    package version meets the active protection level's `minReleaseAge` threshold.
    Uses `check-release-age.py` with a 24h TTL cache and justify-log integration.
    Network failures produce `info`-severity findings (not blocks) so the audit
    continues in offline/degraded mode. See "Protection levels" section below.

## Protection levels

Walter-OS supports four protection levels, defined in
`skills/daily-supply-chain-audit/protection-levels.toml`. Each level bundles a
`minReleaseAge`, pin strategy, audit gate severity, and review requirement.

| Level | `minReleaseAge` | Pin strategy | Audit gate | Review |
|---|---|---|---|---|
| `experimental` | 0 d | any | info only | self |
| `sandbox` | 7 d | minor-locked | warn (no block) | self |
| `staging` | 14 d | exact | block CVSS >= 7 | reviewer subagent |
| `production` | 21 d | exact | block CVSS >= 7 + drift | reviewer + security-auditor |

**Auto-assignment by path** (when no `walter-os.toml` manifest is found):

- `~/work/*` or remote matches `github.com:${WALTER_WORK_GITHUB_ORG}/*` → `production`
- `~/Projects-Personal/*` → `staging`
- Repo name contains `hackathon` → `sandbox`
- Everything else → `staging` (safe default)

### Manifest (`walter-os.toml`)

Place at the repo root to declare the protection level explicitly:

```toml
[walter]
protection = "production"   # one of: experimental | sandbox | staging | production
context    = "work"         # mirrors Walter-OS context system

[walter.overrides]
# Any bundle key can be overridden here.
# minReleaseAge = "7d"   # e.g. relax for a specific repo
```

The `[walter.overrides]` section is additive: only specified keys override the
bundle; unspecified keys inherit from the named level. Missing or malformed
files fall back to `staging` with a warning (never crash).

### Package-manager enforcement

`install.sh` writes the `minimumReleaseAge` value to two PM-layer configs so
the PM itself refuses to install packages younger than the threshold:

- **Bun** (`~/.bunfig.toml`): `[install] minimumReleaseAge = "<seconds>s"`
- **pnpm** (`~/.config/pnpm/rc`): `minimum-release-age=<minutes>`

Verify with `walter-os doctor` (looks for these keys) and view the active
level with `walter-os protection [--json]`.

**Known gaps**: npm, cargo, and uvx do not have native `minimumReleaseAge`
support. Release-age enforcement for those ecosystems is via `audit.sh` only.

### `--justify` flow

When a package must be installed before it has aged sufficiently, use:

```bash
walter-os justify <pkg>@<version> --reason="<text>"
```

This appends one tamper-evident JSON object to
`~/.config/walter-os/justify-log.jsonl` (append-only). The justified
package+version is exempt from the age check for 90 days from the timestamp.

To see active (non-expired) justify entries:

```bash
walter-os justify list
```

For early revocation, edit `~/.config/walter-os/justify-log.jsonl` directly
and set `"expires"` to a past timestamp. There is no `justify revoke`
subcommand in v0.1 — the 90-day TTL handles natural expiry.

### Offline / degraded mode

If the network is unavailable during `check_min_release_age()`:

- If the package has a cached release date (< 24 h old): uses cached value.
- If a stale cache entry exists (> 24 h old): uses it as-is with `stale_cache: true`.
- If no cache entry exists: emits `info`-severity finding (`network_error: true`),
  does NOT fail the package, and continues.

The audit script exits with severity ≤ 2 in offline mode (never blocks on
release-age network failures alone).

## Severity gates

The script exits with these codes (consumed by `daily-audit-gate.sh` hook):

- `0` — clean, work may proceed.
- `1` — informational findings (out-of-date but not vulnerable). Warn only.
- `2` — high severity (CVSS 7.0–8.9). Block until acknowledged with
  `walter-os ack <finding-id>`.
- `3` — critical (CVSS ≥ 9.0 or active exploit reported). Hard block. Operator
  must triage manually before any agent work.

## Output

Every run writes a markdown report to `~/.config/walter-os/audit-YYYY-MM-DD.md`
and a one-line summary to stderr. On findings ≥ severity 2, it also:

- Sends a Telegram alert (if `WALTER_TELEGRAM_*` env vars set)
- Posts to a Slack webhook (if `WALTER_SLACK_WEBHOOK` set)
- Writes a status file at `~/.config/walter-os/audit-status.json` consumed by
  the launchd daily job

## How to use

Manually:

```bash
${WALTER_OS_HOME:-/path/to/walter-os}/skills/daily-supply-chain-audit/scripts/audit.sh
```

Or via slash command:

```
/audit
```

Or automatically every morning at 08:30 (set up by `install.sh` as a launchd
LaunchAgent on macOS).

## When findings appear

The report contains a triage section per finding with:

- CVE / advisory ID + link
- Affected package and current installed version
- Patched version (if available)
- Suggested action: upgrade, pin, remove, or `ack` (acknowledge as accepted risk)

To acknowledge a non-critical finding without acting:

```bash
walter-os ack <finding-id> --reason "tracked in TRI-456, scheduled fix"
```

Acknowledgments expire after 7 days unless renewed. Critical findings cannot
be acked — they must be resolved.

## Checks I cannot do (manual operator review)

- Whether a skill is *semantically* malicious (the agent reads pattern-match,
  not intent). For new skills, manually inspect SKILL.md and any scripts/
  before installing.
- Whether an MCP server is doing something subtle in production traffic. For
  high-trust MCPs, sandbox first (run inside a container with read-only
  filesystem).
- Phishing or social-engineering attacks delivered via MCP tool descriptions.
  These are increasingly common — read tool descriptions before approving.

## References

- OWASP Top 10 for Agentic Applications 2026
- CVE-2025-59536 (Claude Code hooks injection RCE)
- CVE-2026-21852 (Claude Code MCP consent bypass)
- ClawHavoc malicious skills disclosure (April 2026)
- Snyk mcp-scan: <https://github.com/snyk/mcp-scan>
- Cisco mcp-scanner: <https://github.com/cisco/mcp-scanner>
- AgentAudit: <https://agentaudit.dev>
- mcpskills.io: <https://mcpskills.io>
