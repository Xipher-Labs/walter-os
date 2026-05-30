#!/usr/bin/env bats
# Optional Renovate self-hosted profile regression checks.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
RENOVATE_DIR="$REPO_ROOT/setup/walter-host/services/renovate"

@test "renovate optional service files exist" {
  [ -f "$RENOVATE_DIR/compose.yml" ]
  [ -f "$RENOVATE_DIR/config.js" ]
  [ -f "$RENOVATE_DIR/.env.template" ]
  [ -f "$RENOVATE_DIR/cron.example" ]
  [ -f "$RENOVATE_DIR/README.md" ]
}

@test "renovate compose is opt-in and pinned" {
  grep -q "profiles: \\[renovate\\]" "$RENOVATE_DIR/compose.yml"
  grep -Eq "image: renovate/renovate:[0-9]+\\.[0-9]+\\.[0-9]+" "$RENOVATE_DIR/compose.yml"
  ! grep -Eq "image: renovate/renovate:(latest|stable|[0-9]+|[0-9]+\\.[0-9]+)([^0-9.]|$)" "$RENOVATE_DIR/compose.yml"
}

@test "renovate compose fails closed without approved secret-loaded token" {
  grep -q 'RENOVATE_TOKEN:?required' "$RENOVATE_DIR/compose.yml"
  grep -q 'RENOVATE_CONFIG_FILE=/usr/src/app/config.js' "$RENOVATE_DIR/compose.yml"
  ! grep -q 'RENOVATE_TOKEN=' "$RENOVATE_DIR/.env.template"
}

@test "renovate config uses conservative defaults" {
  grep -q "automerge: false" "$RENOVATE_DIR/config.js"
  grep -q "minimumReleaseAge: '7 days'" "$RENOVATE_DIR/config.js"
  grep -q "internalChecksFilter: 'strict'" "$RENOVATE_DIR/config.js"
  grep -q "allowedCommands: \\[\\]" "$RENOVATE_DIR/config.js"
  grep -q "allowedUnsafeExecutions: \\[\\]" "$RENOVATE_DIR/config.js"
  grep -q "allowScripts: false" "$RENOVATE_DIR/config.js"
}

@test "renovate docs cover GitHub, Forgejo, dry-run, onboarding, and security" {
  grep -qi "GitHub mode" "$RENOVATE_DIR/README.md"
  grep -qi "Forgejo mode" "$RENOVATE_DIR/README.md"
  grep -qi "autodiscover" "$RENOVATE_DIR/README.md"
  grep -qi "onboarding PR" "$RENOVATE_DIR/README.md"
  grep -qi "dry-run" "$RENOVATE_DIR/README.md"
  grep -qi "allowedCommands" "$RENOVATE_DIR/README.md"
  grep -qi "postUpgradeTasks" "$RENOVATE_DIR/README.md"
  grep -q "RENOVATE_DRY_RUN=full" "$RENOVATE_DIR/README.md"
}

@test "renovate cron example is disabled by default and uses walter-run" {
  grep -q "/usr/local/bin/walter-run renovate" "$RENOVATE_DIR/cron.example"
  ! grep -Eq '^[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+[[:space:]]+[0-9*,-/]+' "$RENOVATE_DIR/cron.example"
}

@test "renovate docs avoid operator-specific repo handles" {
  ! grep -Rqi "f0x1777" "$RENOVATE_DIR" "$REPO_ROOT/docs/operational/renovate-self-hosted.md"
}
