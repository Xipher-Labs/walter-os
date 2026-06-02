# Authentik SSO runbook

Authentik is an optional identity layer for Walter-OS. It should stay disabled
for solo or personal installs until there is a real need for central OIDC,
shared users, group policy, or stronger MFA workflows across multiple apps.

## Network model

`setup/walter-host/services/authentik/compose.yml` does not publish public host
ports. The expected routing chain is:

```text
browser -> Cloudflare Access -> cloudflared/Caddy -> authentik-server:9000
```

Use `auth.${WALTER_DOMAIN}` for the public hostname. Caddy should proxy to the
Docker service name on the Authentik network, or cloudflared should target a
local Caddy route that does the same. Keep Cloudflare Access enabled during
bootstrap and recovery so the initial setup flow is not exposed directly.

## OIDC rollout

Create one Authentik OIDC provider and application per Walter-OS app. Use exact
redirect URIs, rotate each client secret independently, and bind access through
groups instead of allowing every Authentik user into every app.

Recommended rollout order:

1. Configure Authentik admin MFA and a break-glass local admin account.
2. Add a non-critical Walter-OS app as the first OIDC client.
3. Verify login, logout, token refresh, and group-based access.
4. Move higher-value apps only after backup and restore have been tested.

## Bootstrap policy

After opening `https://auth.${WALTER_DOMAIN}/if/flow/initial-setup/`, create
the first admin user and enable MFA before adding application clients. Keep one
local break-glass admin account outside external OIDC dependencies. Store its
recovery procedure in the private operator runbook, not in this repository.

Create groups before onboarding users:

- `walter-admins` for operators who can administer Authentik and critical apps.
- `walter-members` for normal internal app access.
- Per-app groups such as `forgejo-users` or `grafana-admins` when an app needs
  narrower authorization than the broad Walter-OS member role.

## Application notes

These are integration targets, not default enablement. Configure each only when
that service is present in the deployment.

| App | SSO role |
| --- | --- |
| Forgejo | Use an Authentik OIDC provider with exact Forgejo callback URL and map allowed groups. |
| Plane | Use OIDC when the installed Plane edition supports it; otherwise keep Cloudflare Access and local auth. |
| Grafana | Configure generic OAuth/OIDC and map Authentik groups to Grafana roles. |
| n8n | Keep Cloudflare Access as the perimeter gate; use app-level SSO only if the deployed n8n auth mode supports it. |
| Outline | Configure Authentik OIDC with the Outline callback URL and workspace-appropriate groups. |
| Langfuse | Use Authentik as the OIDC issuer when the deployed Langfuse plan and version support custom SSO. |

For each app, record the issuer URL, client ID location, redirect URI, group
mapping, and rollback path in the service runbook before making SSO mandatory.

## Offboarding

Offboarding is a two-step process: remove the user from Authentik groups, then
disable or delete the Authentik user after confirming app sessions have been
revoked where the app supports revocation. For critical apps, also rotate any
app-local API tokens that user could access outside browser SSO.

Keep Cloudflare Access policy membership aligned with Authentik membership.
Cloudflare Access remains the perimeter gate; Authentik is the app identity
layer. A user removed from one layer but not the other can create confusing
partial access.

## Backup requirements

Back up the PostgreSQL database and named volumes for data, certs, and custom
templates. Store `AUTHENTIK_SECRET_KEY` separately in the operator secret store;
without that key, restored encrypted data is not usable.

Minimum restore evidence:

- A recent `pg_dump` from `authentik-postgresql`.
- Restic or equivalent snapshots for `authentik-data`, `authentik-certs`, and
  `authentik-templates`.
- A documented restore drill before Authentik protects critical apps.

## Optional by design

Cloudflare Access is enough for many single-operator deployments. Authentik
adds value when Walter-OS needs internal app SSO, group-aware authorization, or
more portable OIDC identity. It also adds a database, Redis, secrets, backup
work, and an outage mode. Keep it off until those trade-offs are justified.
