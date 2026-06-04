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

Print the bounded hackathon preset with:

```bash
walter-os repo-config defaults hackathon
```

The hackathon preset is an opt-in template for short-lived, demo-driven
projects. It sets `autonomy_mode: full`, `profile: hackathon`,
`verification: prototype`, `preview_deploy: true`, and a lower Walter Score
threshold while still requiring green CI and restricting auto-merge eligibility
to `hackathon/*` source branches. It keeps the same hard-floor human approval
categories as the balanced default.

## Autonomy Modes

`autonomy_mode` is a policy axis, not an install tier. A repo can run a small
client-only install or a full self-hosted stack with any autonomy mode.

| Mode | Contract |
|---|---|
| `lite` | Plan, report, and request approval. No autonomous code, PR, deploy, or merge progression. |
| `guided` | Default human-in-the-loop delivery. Agents may prepare work and PRs; humans approve intent, architecture, merge, and production deploy. |
| `full` | Policy-bounded autonomy for eligible non-protected paths. Protected actions, secrets, money, PHI, auth, destructive operations, and production deploys still require humans. |

`walter-os repo-config validate` prints the effective mode and reminds callers
that the hard-limit floor is non-overridable in every mode.

## Verification Plan

Use `verification-plan` to turn the repo policy plus changed paths into an
advisory checklist:

```bash
walter-os repo-config verification-plan . --risk low --path docs/operational/repo-config.md
walter-os repo-config verification-plan . --risk medium --path scripts/walter/lib/repo-config.sh
walter-os repo-config verification-plan . --risk low --path install.sh
```

The command is read-only. It validates the policy file first, then reports:

- configured `verification` mode (`prototype`, `risk_based`, or `production`)
- input risk from `--risk low|medium|high`
- path-derived risk from changed paths
- effective risk after taking the maximum
- whether a hard-floor path was touched
- the required verification checks

`prototype` keeps the short demo/MVP check set: `lint`, `typecheck`,
`smoke_test`, and `critical_path_test`. `risk_based` uses prototype checks for
low-risk work, `targeted_tests`, `integration_tests`, and
`acceptance_criteria_check` for medium-risk work, and production checks for
high-risk work. `production` always requires the full verification set.
For UI paths, the command appends `screenshot_validation` to whichever plan is
selected.

The hard-limit floor still wins in every mode. Paths such as `install.sh`,
`AGENTS.md`, `hooks/*`, `mcp/servers.json`, auth/crypto/env/key files,
workflow files, and migrations force `plan: production` and
`human_gate: required` even when the repo uses the hackathon prototype preset.

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
