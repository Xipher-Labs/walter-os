#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "public docs do not claim YubiKey is mandatory" {
  run bash -c "cd '$REPO_ROOT' && rg -n -i 'hard-required|yubikey-gated|yubiKey-gated|requires yubi|yubikey is hard|must be present.*yubi' docs/operational docs/specs skills README.md bin install.sh scripts -g '!docs/specs/archive/**'"
  [ "$status" -eq 1 ]
}

@test "canonical secrets bootstrap command is documented" {
  run bash -c "cd '$REPO_ROOT' && rg -n 'walter-os secrets-identity-init' docs/operational docs/specs skills install.sh bin"
  [ "$status" -eq 0 ]
}

@test "legacy keychain command is documented as deprecated alias" {
  run bash -c "cd '$REPO_ROOT' && rg -n 'secrets-keychain-init.*DEPRECATED|deprecated.*secrets-keychain-init|compatibility alias' bin docs/specs scripts"
  [ "$status" -eq 0 ]
}

@test "Linux credential-store requirements are documented" {
  run bash -c "cd '$REPO_ROOT' && rg -n 'libsecret-tools|secret-tool|pass.*gnupg|pass \\+ GPG' docs/operational/requirements.md docs/specs/secrets-runtime-architecture.md"
  [ "$status" -eq 0 ]
}
