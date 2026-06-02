# Walter Repo Config

`walter-repo-config.yaml` is the committed per-repo policy file for Walter-OS
autonomy settings. It is the AD-5 primitive from
[`docs/specs/autonomous-delivery-roadmap.md`](../specs/autonomous-delivery-roadmap.md)
and follows [`ADR-0026`](../decisions/0026-walter-repo-config-schema.md).

## Validate

From a repository root:

```bash
walter-os repo-config validate
```

Or validate another repository/path:

```bash
walter-os repo-config validate /path/to/repo
walter-os repo-config validate /path/to/repo/walter-repo-config.yaml
```

`walter-os doctor --repo-config` runs only this check. Full `walter-os doctor`
also validates the current repository policy.

## Defaults

When the file is absent, Walter-OS applies the safest defaults:

```yaml
autonomy_mode: guided
profile: balanced
capability_tier_ceiling: 1
auto_merge:
  enabled: false
  allowed_branches: []
  forbidden_branches:
    - main
    - master
    - staging
    - production
    - "release/*"
  require_green_ci: true
  min_walter_score: 90
  max_risk: low
verification: risk_based
preview_deploy: false
human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
```

Print the current default template with:

```bash
walter-os repo-config defaults
```

## Validation Rules

The validator fails closed for malformed YAML, invalid enum values, wrong
types, out-of-range numbers, and attempts to remove the hard-floor human
approval categories. Unknown top-level or `auto_merge` keys warn, but do not
fail, so future schema additions can be staged without breaking older installs.

`auto_merge.allowed_branches` must not include protected branches such as
`main`, `master`, `staging`, `production`, or `release/*`.

## Safety Floor

No value in `walter-repo-config.yaml` can relax the `approval-gate.sh`
"blocked for ALL tiers" floor. `autonomy_mode: full`, `profile: hackathon`,
and `auto_merge.enabled: true` may only widen future discretionary automation.
They do not authorize protected branch merges, force-pushes, destructive shell
or SQL, money-spending operations, secret writes, PHI/auth/crypto changes,
production DB migrations, or edits to hooks/AGENTS/install surfaces.

First authorization is manual: a PR that adds or loosens the file cannot use
the looser policy to authorize itself. Later runtime consumers must read the
policy from the default branch state that existed before the PR.
