# Workflow Token Permissions

Walter-OS workflows must default to read-only `GITHUB_TOKEN` permissions at the
workflow level. Any write permission must be scoped to the smallest job that
needs it and documented next to the permission.

## Current Write Scopes

| Workflow | Job | Permission | Why it is needed |
|---|---|---|---|
| `.github/workflows/codeql.yml` | `analyze` | `security-events: write` | CodeQL uploads SARIF results to code scanning. |
| `.github/workflows/osv-scanner.yml` | `scan` | `security-events: write` | The pinned OSV reusable workflow uploads SARIF results to code scanning. |
| `.github/workflows/cla.yml` | `cla-assistant` | `issues: write` | Contributor Assistant comments on CLA signatures. |
| `.github/workflows/cla.yml` | `cla-assistant` | `pull-requests: write` | Contributor Assistant labels and updates PR state. |
| `.github/workflows/cla.yml` | `cla-assistant` | `statuses: write` | Contributor Assistant publishes CLA commit status. |

## Scorecard Notes

OpenSSF Scorecard may still report `TokenPermissionsID` for job-level
`security-events: write` in `.github/workflows/osv-scanner.yml` because the OSV
scanner is invoked as a reusable workflow. That permission is intentionally kept
at the job level and is required for SARIF upload. If GitHub code scanning keeps
the alert open after the workflow scoping change, dismiss that alert with this
document as the rationale rather than removing SARIF upload.

## Regression Coverage

`tests/github-actions/workflow-permissions.bats` verifies that:

- read-only workflows declare explicit read or empty token permissions;
- CodeQL and CLA write scopes are not granted at workflow top level;
- OSV keeps SARIF upload permission scoped to the reusable workflow job;
- release write scopes remain limited to release/provenance jobs.
