# Operator Preferences — Example

> **How to use this file**: copy it into your personal overlay at
> `~/.config/walter-os/overlay/preferences.md` and edit. Walter-OS does NOT
> prescribe any of the values below in its global contract — they belong in
> your overlay because they vary by operator.
>
> The values shown are illustrative, drawn from one operator's macOS-on-Apple-
> Silicon setup. Replace with your own. Linux/Windows operators delete the
> macOS-specific entries entirely.

## OS + shell

- **OS**: macOS (Apple Silicon). Common alternatives: Ubuntu 24.04 LTS,
  Debian 12, Fedora Workstation, NixOS.
- **Shell**: zsh. Alternatives: bash, fish.

## Package managers

- **Node**: `pnpm` (preferred for monorepo workspaces + disk efficiency).
  Alternatives: `npm` (default everywhere), `yarn` (classic), `bun` (newer).
- **Python**: `uv` (fast, modern). Alternatives: `pip` + `venv`, `poetry`,
  `pdm`, `pipx`.
- **Rust**: `cargo` (universal).

## Editor stack

- **Primary IDE**: Cursor (AI-native fork of VS Code). Alternatives:
  VS Code with Continue, JetBrains with the Codeium plugin, Zed.
- **Terminal agent**: Claude Code (CLI). Use for plan-driven work and any
  task that benefits from deep tool use across the repo.
- **Second-opinion agent**: Codex CLI (GPT-5.5). Use for security review and
  cross-model second opinions, per the AGENTS.md "Review loop" section.

## Container runtime

- **macOS**: OrbStack (faster + lighter than Docker Desktop, with native
  Kubernetes). Free for personal use; commercial license required for
  business. Alternative: Docker Desktop, colima, Podman Desktop.
- **Linux**: native Docker via the distro's package manager. Alternative:
  Podman.

## Secrets management

- **Dev**: `.env.local` for local-only secrets (gitignored). Never commit.
- **Production**: a self-hosted Vaultwarden instance reachable over
  Tailscale from the operator's homelab. Alternatives: HashiCorp Vault,
  1Password (via 1Password CLI), Bitwarden (cloud), AWS Secrets Manager,
  GCP Secret Manager.
- Never hardcode. The pre-commit gitleaks hook (see CONTRIBUTING.md) blocks
  accidental commits.

## Testing defaults

- **JavaScript / TypeScript**: Vitest or Jest. Vitest for new projects.
- **Python**: pytest.
- **Rust**: `cargo test` (built-in).
- **End-to-end (web)**: Playwright. Has an MCP server, integrates with
  Claude Code.
- **End-to-end (mobile)**: Maestro. Also has an MCP server.
- **Property-based**: `fast-check` (JS), `proptest` (Rust).
- **Mutation**: `stryker` (JS), `cargo-mutants` (Rust).

See `contexts/_examples/testing-strategy.example.md` for a worked
project-type matrix.

## How Walter-OS uses this file

When the operator runs `setup/personal-overlay-init.sh`, the script
copies this file (or its content) into
`~/.config/walter-os/overlay/preferences.md` as a starting point. The
operator edits, removes irrelevant sections, and adds their own.

Agents (Claude Code, Codex CLI) do NOT read `preferences.md` directly.
The global `AGENTS.md` is silent on these preferences by design. Operators
who want their agents to follow these defaults reference them in their
context-specific `AGENTS.md` (under `contexts/work/`,
`contexts/projects-personal/`, etc.) which IS loaded by the cascade.
