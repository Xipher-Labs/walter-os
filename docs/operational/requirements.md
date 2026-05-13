# Walter-OS Requirements

Walter-OS has two install surfaces:

- **Client-only**: local agent contract, skills, hooks, CLI, and personal overlay.
- **walter-host**: optional self-hosted service stack with Docker Compose.

Run this first from a clean clone:

```bash
./install.sh --check
```

## Minimum Local Tools

| Tool | Required for | Install hint |
|---|---|---|
| `git` | Clone/update Walter-OS | `brew install git` or `sudo apt-get install -y git` |
| `curl` | Installer downloads and health checks | `brew install curl` or `sudo apt-get install -y curl` |
| `jq` | Installer, hooks, MCP config generation | `brew install jq` or `sudo apt-get install -y jq` |
| `docker` | Full walter-host stack | OrbStack/Docker Desktop on macOS, Docker Engine on Linux |

## Secrets Bootstrap Tools

Walter-OS stores the Infisical Machine Identity in the local OS credential
store. Hardware security keys are optional hardening; they are not required by
the default bootstrap path.

| Platform | Required backend | Install hint |
|---|---|---|
| macOS | Keychain via `security` | Built in |
| Linux | Secret Service via `secret-tool` | `sudo apt-get install -y libsecret-tools gnome-keyring` |
| Linux fallback | `pass` + `gpg` | `sudo apt-get install -y pass gnupg` |

Canonical setup command:

```bash
walter-os secrets-identity-init
```

## Recommended Local Tools

| Tool | Why |
|---|---|
| `gh` | GitHub PR, issue, and release workflows |
| `infisical` | Runtime secret fetch from the configured Infisical server |
| `rg` | Fast repo search used by agents and scripts |
| `bats` | Shell test runner |
| `shellcheck` | Shell lint parity with CI |
| `gitleaks` | Local secret scanning |
| `node` + `pnpm` | Control Tower and Node service builds |
| `python3` + `uvx` | Python helper scripts and ad-hoc package runners |
| `claude` | Claude Code agent runtime |
| `codex` | Codex CLI review/runtime integration |

## Manifests

| Surface | Manifest |
|---|---|
| macOS workstation packages | `setup/Brewfile` |
| Runtime versions | `setup/mise.toml.example` |
| Node workspaces | `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml` |
| Control Tower app | `apps/control-tower/package.json` |
| Optional Python helpers | `setup/requirements/python-optional.txt` |
| Self-hosted services | `compose.yml`, `setup/walter-host/services/**/compose.yml` |

## Python Packages

The repo does not install all optional Python packages globally by default.
Most Python helpers use the standard library or `uvx --from <package>`.
Install the optional pinned set only when using the related profiles:

```bash
python3 -m pip install -r setup/requirements/python-optional.txt
```

The Singer tap ecosystem changes frequently; profile-specific tap install
commands remain documented next to the runner in `setup/walter-host/singer/`.
