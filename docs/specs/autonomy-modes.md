# Autonomy Modes

**Status**: Implemented
**Owner**: Operator
**Created**: 2026-06-03
**Issue**: #231

## Problem

Walter-OS already has a committed per-repo policy file,
`walter-repo-config.yaml`, with an `autonomy_mode` enum. Before AD-6, that enum
was valid YAML but not a complete operator contract: users could see
`lite`, `guided`, or `full` without a precise explanation of what those modes
allow, what they do not allow, and how they relate to install tiers.

That ambiguity is dangerous because "full" can sound like "all gates off."
Walter-OS needs the opposite framing: autonomy is a policy axis that widens
only the discretionary delivery surface while the approval-gate hard-limit
floor remains non-overridable in every mode.

## Proposed Solution

Formalize `lite`, `guided`, and `full` as autonomy policy modes in
`walter-repo-config.yaml`, orthogonal to install tier. The repo-config
validator reports the effective mode and the non-overridable hard-limit floor
whenever it validates a repo policy or applies absent-file defaults.

The modes are:

| Mode | Meaning |
|---|---|
| `lite` | Plan, report, and request approval. No autonomous code, PR, deploy, or merge progression. |
| `guided` | Default human-in-the-loop delivery. Agents may prepare work and PRs; humans approve intent, architecture, merge, and production deploy. |
| `full` | Policy-bounded autonomy for eligible non-protected paths. Protected actions, secrets, money, PHI, auth, destructive operations, and production deploys still require humans. |

## Acceptance Criteria

- [AC-1] Repos without `walter-repo-config.yaml` report `guided` as the
  effective autonomy mode.
- [AC-2] `walter-os repo-config validate` reports that autonomy is a policy
  axis, not an install tier.
- [AC-3] `walter-os repo-config validate` reports that the hard-limit floor is
  non-overridable in every autonomy mode.
- [AC-4] `autonomy_mode: full` still fails validation if the config removes any
  hard-floor human approval category.
- [AC-5] The bounded hackathon/full-autonomy defaults remain schema-valid and
  report `full` as the effective mode.

## Non-Goals

- Do not wire autonomy modes into `/full-cycle`; that is AD-3.
- Do not implement evidence-based capability tier computation; that is AD-7.
- Do not change `approval-gate.sh` behavior or relax any blocked-for-all action.
- Do not introduce auto-merge behavior in this slice.

## References

- `docs/specs/autonomous-delivery-roadmap.md` (AD-6)
- `docs/decisions/0026-walter-repo-config-schema.md`
- `docs/decisions/0023-capability-tiers.md`
- `docs/decisions/0024-risk-based-verification.md`
- `docs/operational/repo-config.md`
