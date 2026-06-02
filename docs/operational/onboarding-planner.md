# Onboarding Planner

Use the onboarding planner when Walter-OS is already installed somewhere and an
operator needs to add either another device or another person.

```bash
walter-os onboard device --dry-run
walter-os onboard teammate --dry-run
```

Both modes are read-only. They print the next actions and documentation pointers
without creating users, tokens, access rules, Syncthing devices, or optional
modules.

## Device Mode

Use `device` when the same operator is adding another laptop, desktop, or
workstation to an existing Walter domain.

The checklist focuses on:

- secrets identity initialization
- profile bootstrap for Claude, Codex, or both
- agent memory setup
- Syncthing folder membership
- Headscale or Tailscale reachability
- `walter-os doctor` and `walter-os status --models`

## Teammate Mode

Use `teammate` when a second person will share the same Walter-VM. Treat this as
identity and authorization work, not as a normal device sync.

The checklist focuses on:

- Cloudflare Access or Authentik identity gates
- Forgejo access with least privilege
- Plane workspace and project membership
- ntfy notification routing
- explicit role boundaries
- optional modules for team operations

## Optional Modules

| Module | Value for a small team | Default stance |
| --- | --- | --- |
| Authentik | Central SSO and app-level identity | Optional |
| Forgejo Actions Runner | Self-hosted CI for Forgejo repos | Optional |
| Renovate | Dependency update PRs | Optional |
| Langfuse | LLM tracing and prompt observability | Optional |
| Listmonk | Email newsletter and lightweight campaigns | Optional |
| ntfy | Push notifications for operators and teammates | Optional |
| Knowledge/bookmarking | Outline, Linkwarden, or Obsidian-style capture | Optional |

## Related Docs

- docs/operational/operator-setup-runbook.md
- docs/operational/multi-device-sync.md
- docs/operational/onboarding-checklist.md
- docs/operational/authentik-sso.md
- docs/operational/knowledge-profile.md
- docs/operational/renovate-self-hosted.md
- docs/operational/langfuse.md
