# Walter-OS Requirements

Walter-OS has two install surfaces:

- **Client-only**: local agent contract, skills, hooks, CLI, and personal overlay.
- **walter-host**: optional self-hosted service stack with Docker Compose.

Run this first from a clean clone:

```bash
./install.sh --check
```

## Platform Contract

Walter-OS supports macOS and Ubuntu/Debian-like Linux for the client/install
path. Ubuntu 24.04 is the reference Linux target; Ubuntu 22.04 is expected to
work with the same package families. Other Linux distributions are best-effort
manual installs.

| Tool / surface | macOS | Ubuntu 22.04/24.04 |
|---|---|---|
| Package manager | Homebrew (`brew`) | `apt-get`; `snap` only for Mike Farah `yq` unless using direct binary install |
| `git`, `curl`, `jq` | Required; auto-installable with `brew install` | Required; auto-installable with `sudo apt-get install -y` |
| `yq` | Required; `brew install yq` (Mike Farah `yq`) | Required; `sudo snap install yq` or direct Mike Farah binary. Do not use `apt install yq` (kislyuk/Python `yq`) |
| Docker | Required for walter-host; Docker Desktop or OrbStack | Required for walter-host; Docker Engine plus `docker-compose-plugin` |
| `bats`, `shellcheck`, `ripgrep` | Recommended; `brew install bats-core shellcheck ripgrep` | Recommended; `sudo apt-get install -y bats shellcheck ripgrep` |
| `gitleaks` | Recommended; `brew install gitleaks` | Recommended; use the upstream release or package repo |
| Python | Required for capability token operations; `brew install python` | Required for capability token operations; `sudo apt-get install -y python3` |
| Node, `pnpm`, `uv` | Recommended via `mise install node@22 pnpm@9 uv@latest` | Recommended via `mise install node@22 pnpm@9 uv@latest` |
| Infisical CLI | Recommended; `brew install infisical/get-cli/infisical` | Recommended; follow Infisical CLI Linux docs |
| Secrets backend | macOS Keychain via built-in `security` | Secret Service via `secret-tool`, or `pass` + GPG for headless systems |

## Minimum Local Tools

| Tool | Required for | Install hint |
|---|---|---|
| `git` | Clone/update Walter-OS | `brew install git` or `sudo apt-get install -y git` |
| `curl` | Installer downloads and health checks | `brew install curl` or `sudo apt-get install -y curl` |
| `jq` | Installer, hooks, MCP config generation | `brew install jq` or `sudo apt-get install -y jq` |
| `python3` | Capability token operations | `brew install python` or `sudo apt-get install -y python3` |
| `openssl` | Session capability-key generation | `brew install openssl` or `sudo apt-get install -y openssl`; export `WALTER_OPENSSL_BIN` in the launching shell only if OpenSSL 3 is outside known paths |
| `yq` | Hooks and trust-tier evaluation | `brew install yq` or `sudo snap install yq` (Mike Farah `yq`) |
| `docker` + Compose plugin | Full walter-host stack | Docker Desktop/OrbStack on macOS, Docker Engine plus `docker-compose-plugin` on Ubuntu |

## Secrets Bootstrap Tools

Walter-OS stores the Infisical Machine Identity in the local OS credential
store. Hardware security keys are optional hardening; they are not required by
the default bootstrap path.

| Platform | Required backend | Install hint |
|---|---|---|
| macOS | Keychain via `security` | Built in |
| Linux | Secret Service via `secret-tool` | `sudo apt-get install -y libsecret-tools gnome-keyring` |
| Linux fallback | `pass` + `gpg` | `sudo apt-get install -y pass gnupg` |

On headless Ubuntu, Secret Service usually requires a D-Bus session and a
running keyring. If that is not available, use the `pass` + GPG fallback before
running secrets bootstrap.

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
