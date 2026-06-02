# Renovate self-hosted optional app

Walter-OS ships an optional, disabled-by-default Renovate runner at
`setup/walter-host/services/renovate/`.

Use it for dependency hygiene when a GitHub or Forgejo repository should receive
Renovate onboarding and update PRs from a self-hosted bot. The runner is not
part of the all-in-one core compose stack and exposes no HTTP service.

Operational source of truth:

- `setup/walter-host/services/renovate/README.md`
- `setup/walter-host/services/renovate/compose.yml`
- `setup/walter-host/services/renovate/config.js`

PR title suggestion for this issue:

```text
[FEAT] -SECURITY- add Renovate self-hosted profile
```
