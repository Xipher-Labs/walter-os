# Onboarding Planner

## Problem

Walter-OS has operator setup docs and multi-device sync docs, but there is no
single CLI entrypoint that tells an operator what to do when adding a second
device or a second person to an existing Walter domain. That makes onboarding
feel like reading the whole repository before taking the first step.

## Scope

Add a read-only CLI planner:

- `walter-os onboard device --dry-run`
- `walter-os onboard teammate --dry-run`

The command prints a checklist and documentation pointers only. It must not
create users, tokens, secrets, Cloudflare Access rules, Authentik users, Forgejo
accounts, Plane memberships, Syncthing devices, or optional stack modules.

## Acceptance Criteria

- Device onboarding prints steps for secrets identity, profile bootstrap, agent
  memory, Syncthing, Headscale or Tailscale, and doctor/status checks.
- Teammate onboarding prints steps for Cloudflare Access or Authentik, Forgejo,
  Plane, ntfy, role boundaries, and optional modules.
- Optional modules mention Authentik, Forgejo Actions Runner, Renovate,
  Langfuse, Listmonk, ntfy, and the knowledge/bookmarking profile.
- The command requires `--dry-run` and exits non-zero without it.
- The command does not print secret-like values.
- Every referenced documentation path exists.

## Non-Goals

- No account provisioning.
- No access-control mutation.
- No optional module installation.
- No credential, token, or secret output.

## Verification

- `bats tests/cli/onboard.bats`
- `bash -n bin/walter-os scripts/walter/subcommands/onboard.sh`
- `shellcheck bin/walter-os scripts/walter/subcommands/onboard.sh tests/cli/onboard.bats`
