# Security audit snapshots

This directory stores pre-release security audit outputs committed before each
version tag.

## Convention

Before tagging a release:
1. Run `make audit` locally from the repo root.
2. Create a directory `docs/audits/<version>/self/`.
3. Redirect each tool's output to a file in that directory:
   - `shellcheck.txt` — shellcheck output
   - `gitleaks.txt` — gitleaks output
   - `osv-scanner.json` — osv-scanner JSON report
4. Commit: `git add docs/audits/<version>/ && git commit -m "chore: audit snapshot <version>"`
5. Tag the release.

CI uploads the SBOM to GitHub Releases as a separate artifact; this directory
stores human-readable snapshots for historical reference.

## Example

```bash
VERSION="v0.2.0"
mkdir -p docs/audits/${VERSION}/self/

# Shell audit
shellcheck -e SC2155,SC1091,SC1083,SC2317 hooks/*.sh \
  > docs/audits/${VERSION}/self/shellcheck.txt 2>&1 || true

# Secret scan
gitleaks detect --config=.gitleaks.toml --no-git --source=. \
  --report-format=json --report-path=docs/audits/${VERSION}/self/gitleaks.json 2>&1 \
  | tee docs/audits/${VERSION}/self/gitleaks.txt || true

# Dependency scan (if osv-scanner installed)
osv-scanner --lockfile=pnpm-lock.yaml \
  --format=json > docs/audits/${VERSION}/self/osv-scanner.json 2>&1 || true

git add docs/audits/${VERSION}/
git commit -m "chore: audit snapshot ${VERSION}"
git tag "${VERSION}"
```

## Current snapshots

| Version | Date | Status |
|---------|------|--------|
| (none yet) | — | — |
