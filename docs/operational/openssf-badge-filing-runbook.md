# OpenSSF Best Practices Badge Filing Runbook

This runbook covers the manual OpenSSF Best Practices badge filing step for
Walter-OS. It addresses the Scorecard `CIIBestPracticesID` alert tracked in
issue #423.

The badge application is intentionally operator-driven. Do not add an OpenSSF
Best Practices badge to `README.md` until bestpractices.dev assigns an approved
project URL for Walter-OS.

## Current State

- Scorecard alert: `CIIBestPracticesID`
- Current expected state: no approved OpenSSF Best Practices project URL yet
- Repository evidence today:
  - `SECURITY.md` and `.github/SECURITY.md`
  - `CONTRIBUTING.md`
  - `CHANGELOG.md`
  - `.github/workflows/ci.yml`
  - `.github/workflows/scorecard.yml`
  - `.github/workflows/gitleaks.yml`
  - `.github/workflows/semgrep.yml`
  - `docs/security/openssf-silver-checklist.md`
  - `docs/operational/scorecard-hygiene.md`
  - `docs/specs/openssf-badges.md`

## Before Filing

1. Confirm the public repository URL:

   ```bash
   gh repo view --json url -q .url
   ```

2. Confirm current community-health files are present:

   ```bash
   test -f README.md
   test -f LICENSE
   test -f CONTRIBUTING.md
   test -f SECURITY.md
   test -f CHANGELOG.md
   ```

3. Confirm the Scorecard workflow exists and publishes results:

   ```bash
   sed -n '1,120p' .github/workflows/scorecard.yml
   ```

4. Review the current Silver self-assessment and known gaps:

   ```bash
   sed -n '1,240p' docs/security/openssf-silver-checklist.md
   ```

5. Open the OpenSSF Best Practices Passing criteria:

   ```text
   https://www.bestpractices.dev/en/criteria/0
   ```

## Filing Steps

1. Sign in to bestpractices.dev with the operator account.
2. Create a new project:

   ```text
   https://www.bestpractices.dev/en/projects/new
   ```

3. Use the GitHub repository URL as the project URL.
4. Answer the Passing questionnaire honestly from repository evidence.
5. For criteria that Walter-OS does not meet yet, answer not met rather than
   stretching an automated or aspirational control into a human/process claim.
6. Submit the project for review.
7. Record the assigned project URL in issue #423.

## After Approval

Once bestpractices.dev assigns an approved Walter-OS project URL:

1. Add the official badge to the README badge block:

   ```markdown
   [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/<PROJECT_ID>/badge)](https://www.bestpractices.dev/projects/<PROJECT_ID>)
   ```

2. Add the same project URL to `docs/operational/scorecard-hygiene.md`.
3. Add a changelog note under the next release.
4. Re-run Scorecard from the GitHub Actions UI or wait for the next scheduled
   run.
5. Confirm GitHub code scanning alert #48 is closed or update issue #423 with
   the latest Scorecard evidence.

## Do Not Claim Silver Prematurely

Passing is the prerequisite for Silver. The current Silver self-assessment
still records open gaps such as governance continuity, release signing, and
human review depth. File Silver only after Passing is approved and the remaining
Silver gaps are either fixed or honestly marked not met.

## References

- Issue #423: OpenSSF CII metadata / Scorecard `CIIBestPracticesID`
- OpenSSF Best Practices: <https://www.bestpractices.dev/>
- Passing criteria: <https://www.bestpractices.dev/en/criteria/0>
- Silver criteria: <https://www.bestpractices.dev/en/criteria/1>
