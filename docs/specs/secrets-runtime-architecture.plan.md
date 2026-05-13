# Plan: secrets bootstrap auth policy

## Summary

Issue #33 removes the hard YubiKey gate from secrets bootstrap while keeping
the security invariant: the Infisical Machine Identity must live in a local OS
credential store, never in plaintext dotenv.

## Implementation Steps

1. Add `walter-os secrets-identity-init` as the canonical bootstrap command.
2. Support `--store auto|macos-keychain|secret-service|pass`.
3. Keep `walter-os secrets-keychain-init` as a deprecated compatibility alias.
4. Update `docs/specs/secrets-runtime-architecture.md` and operator runbooks to
   define hardware keys as optional hardening.
5. Rewrite the legacy-named `secrets-yubikey-unlock` skill as a generic OS
   credential-store guide.
6. Add Bats coverage for macOS Keychain, Linux Secret Service, Linux pass+GPG,
   missing backend, missing domain, replacement confirmation, and docs drift.

## Verification

```bash
shellcheck scripts/secrets-*.sh bin/walter-os install.sh
bats tests/scripts/secrets-identity-init.bats tests/oss/secrets-runtime-docs.bats
./install.sh --check
HOME="$(mktemp -d)" ./install.sh --dry-run
./tests/lint-frontmatter.sh
./tests/lint-cross-references.sh
gitleaks detect --config=.gitleaks.toml --no-git --source=. --redact
```

## Acceptance Criteria Mapping

- Fresh macOS without YubiKey: `tests/scripts/secrets-identity-init.bats`.
- Linux Secret Service and pass+GPG: `tests/scripts/secrets-identity-init.bats`.
- Missing backend/domain fail closed: `tests/scripts/secrets-identity-init.bats`.
- Docs do not claim YubiKey is mandatory: `tests/oss/secrets-runtime-docs.bats`.
- Canonical command and legacy alias are documented:
  `tests/oss/secrets-runtime-docs.bats`.
