# Per-repo auto-merge touchfile — superseded

**Status**: Superseded by
[`ADR-0026`](../decisions/0026-walter-repo-config-schema.md) and
[`walter-repo-config.yaml`](../operational/repo-config.md).
**Original path**: `.walter-os/auto-merge-authorized`.
**Replacement**: `walter-repo-config.yaml` -> `auto_merge`.

## Why This Changed

The original proposal used a committed touchfile to opt a repository into
bounded auto-merge after all review, CI, and Definition-of-Done gates passed.
That solved the immediate "operator must click merge for every low-risk PR"
friction, but it created a second per-repo policy surface beside the newer
autonomy controls.

ADR-0026 folds this into one committed file:

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

## Migration

Repos that used the touchfile should commit `walter-repo-config.yaml` instead:

1. Set `auto_merge.enabled: true`.
2. Restrict `auto_merge.allowed_branches` to feature/demo namespaces.
3. Keep protected branches in `auto_merge.forbidden_branches`.
4. Keep every hard-floor `human_approval_required_for` category.
5. Remove the old touchfile from the repo.

The first authorization remains manual: a PR that adds or loosens
`walter-repo-config.yaml` cannot benefit from that looser policy. Runtime
consumers must read the default-branch policy that existed before the PR.

## Preserved Security Requirements

The replacement keeps the important parts of the original proposal:

- Auto-merge is opt-in per repository.
- All review, CI, DoD, branch, and risk gates still apply.
- Protected branches remain forbidden.
- The hard approval floor is non-overridable.
- Policy travels with the repo as committed code.
- Removing or disabling the policy restores manual merge.

## Historical Reference

This file is retained so old links remain meaningful. Do not implement new
logic against the touchfile path; use `walter-repo-config.yaml` and
[`docs/operational/repo-config.md`](../operational/repo-config.md).
