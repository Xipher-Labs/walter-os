#!/usr/bin/env bats
# tests/cli/preview.bats
#
# Covers: docs/specs/preview-environment-bundle.md
#
# shellcheck disable=SC2030,SC2031

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_DIR="$(mktemp -d)"
  export HOME="$TMP_DIR/home"
  export WALTER_CONFIG="$TMP_DIR/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$HOME" "$WALTER_CONFIG"
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || exit
  case "$TMP_DIR" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_DIR" ;;
  esac
  true
}

write_preview_artifacts() {
  seed_file="$TMP_DIR/seed.json"
  shot_file="$TMP_DIR/home.png"
  printf '{"users":[{"id":"demo-user"}]}\n' > "$seed_file"
  printf 'fake png bytes\n' > "$shot_file"
}

write_preview_config() {
  config_file="$TMP_DIR/walter-repo-config.yaml"
  cat > "$config_file" <<'YAML'
autonomy_mode: guided
profile: balanced
capability_tier_ceiling: 1
auto_merge:
  enabled: false
  allowed_branches: []
  forbidden_branches:
    - main
  require_green_ci: true
  min_walter_score: 90
  max_risk: low
verification: risk_based
preview_deploy: true
human_approval_required_for:
  - auth
  - payments
  - secrets
  - prod_infra
  - db_migrations
  - destructive_ops
YAML
}

install_fake_npx() {
  fake_bin="$TMP_DIR/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/npx" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_NPX_LOG:?}"
output=""
for arg in "$@"; do
  output="$arg"
done
if [[ -z "$output" ]]; then
  echo "missing screenshot path" >&2
  exit 2
fi
printf '%s\n' "$output" > "${FAKE_NPX_OUTPUT:?}"
printf 'fake png bytes\n' > "$output"
SH
  chmod +x "$fake_bin/npx"
  export PATH="$fake_bin:$PATH"
  export WALTER_PREVIEW_NPX="$fake_bin/npx"
  export FAKE_NPX_LOG="$TMP_DIR/npx.log"
  export FAKE_NPX_OUTPUT="$TMP_DIR/npx-output.log"
}

@test "preview capture writes a screenshot artifact with Playwright CLI" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pr == 235'
  echo "$output" | jq -e '.url == "https://preview.example/pr-235"'
  echo "$output" | jq -e '.screenshot.path | endswith("screenshots/home.png")'
  echo "$output" | jq -e '.screenshot.sha256 | length == 64'
  echo "$output" | jq -e '.safety.deploy == "not performed"'
  [[ -f "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
  [[ "$(cat "$FAKE_NPX_LOG")" == *"--no-install playwright screenshot"* ]]
  [[ "$(cat "$FAKE_NPX_LOG")" == *"--wait-for-timeout 1000"* ]]
}

@test "preview capture rejects npx override symlinks" {
  install_fake_npx
  mv "$fake_bin/npx" "$fake_bin/npx-real"
  ln -s "$fake_bin/npx-real" "$fake_bin/npx"
  export WALTER_PREVIEW_NPX="$fake_bin/npx"

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 4 ]
  [[ "$output" == *"npx is required for preview capture"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
}

@test "preview capture writes to a temp file before publishing screenshot" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  [[ -f "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
  [[ "$(cat "$FAKE_NPX_OUTPUT")" != "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
  [[ "$(cat "$FAKE_NPX_OUTPUT")" == "$TMP_DIR/out/preview-pr-235/screenshots/."*".tmp."* ]]
  [[ ! -e "$(cat "$FAKE_NPX_OUTPUT")" ]]
}

@test "preview capture reports non-overwrite publish failures as runtime errors" {
  install_fake_npx
  cat > "$fake_bin/ln" <<'SH'
#!/usr/bin/env bash
echo "hardlink exploded" >&2
exit 1
SH
  chmod +x "$fake_bin/ln"

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 4 ]
  [[ "$output" == *"hardlink exploded"* ]]
  [[ "$output" == *"could not publish screenshot"* ]]
  [[ "$output" != *"screenshot already exists"* ]]
}

@test "preview capture treats wait-ms values as base 10" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out" \
    --wait-ms 08

  [ "$status" -eq 0 ]
  [[ -f "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
}

@test "preview capture rejects non-http preview URLs" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url file:///tmp/preview.html \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"preview URL must start with http:// or https://"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/screenshots/home.png" ]]
}

@test "preview capture requires npx" {
  export WALTER_PREVIEW_NPX="$TMP_DIR/missing-npx"

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 4 ]
  [[ "$output" == *"npx is required for preview capture"* ]]
}

@test "preview capture rejects npx override directories" {
  mkdir -p "$TMP_DIR/fake-npx-dir"
  export WALTER_PREVIEW_NPX="$TMP_DIR/fake-npx-dir"

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 4 ]
  [[ "$output" == *"npx is required for preview capture"* ]]
}

@test "preview capture rejects unsafe screenshot names" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name "../home" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--name must be a safe slug"* ]]
}

@test "preview capture rejects secret-like names before invoking Playwright" {
  install_fake_npx

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name token \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"refusing secret-like artifact"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/screenshots/token.png" ]]
  [[ ! -e "$FAKE_NPX_LOG" ]]
}

@test "preview capture refuses to overwrite existing screenshots" {
  install_fake_npx
  mkdir -p "$TMP_DIR/out/preview-pr-235/screenshots"
  printf 'existing\n' > "$TMP_DIR/out/preview-pr-235/screenshots/home.png"

  run bash "$WALTER_OS_BIN" preview capture \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --name home \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"screenshot already exists"* ]]
  [[ "$(cat "$TMP_DIR/out/preview-pr-235/screenshots/home.png")" == "existing" ]]
}

@test "preview plan writes dry-run plan when preview_deploy is enabled" {
  write_preview_artifacts
  write_preview_config

  run bash "$WALTER_OS_BIN" preview plan \
    --dry-run \
    --pr 235 \
    --provider vercel \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.kind == "preview-plan"'
  echo "$output" | jq -e '.provider == "vercel"'
  echo "$output" | jq -e '.app == "control-tower"'
  echo "$output" | jq -e '.branch == "feature/preview-plan"'
  echo "$output" | jq -e '.actions | index("deploy_ephemeral_preview")'
  echo "$output" | jq -e '.safety.dry_run == true'
  echo "$output" | jq -e '.safety.credentials == "not minted"'
  echo "$output" | jq -e '.safety.deploy == "not performed"'
  [[ -f "$TMP_DIR/out/preview-pr-235/preview-plan.json" ]]
}

@test "preview plan requires explicit dry-run" {
  write_preview_artifacts
  write_preview_config

  run bash "$WALTER_OS_BIN" preview plan \
    --pr 235 \
    --provider vercel \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"preview plan requires --dry-run"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/preview-plan.json" ]]
}

@test "preview plan accepts YAML boolean case variants" {
  write_preview_artifacts
  config_file="$TMP_DIR/walter-repo-config.yaml"
  printf 'preview_deploy: True\n' > "$config_file"

  run bash "$WALTER_OS_BIN" preview plan \
    --dry-run \
    --pr 235 \
    --provider vercel \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.safety.preview_deploy == true'
}

@test "preview plan fails closed unless preview_deploy is enabled" {
  write_preview_artifacts
  config_file="$TMP_DIR/walter-repo-config.yaml"
  printf 'preview_deploy: false\n' > "$config_file"

  run bash "$WALTER_OS_BIN" preview plan \
    --dry-run \
    --pr 235 \
    --provider vercel \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"preview_deploy is not enabled"* ]]
  [[ "$output" == *"$config_file"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/preview-plan.json" ]]
}

@test "preview plan rejects config paths that are not readable files" {
  write_preview_artifacts
  config_file="$TMP_DIR/config-dir"
  mkdir -p "$config_file"

  run bash "$WALTER_OS_BIN" preview plan \
    --dry-run \
    --pr 235 \
    --provider vercel \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"config is not a readable file"* ]]
  [[ "$output" == *"$config_file"* ]]
}

@test "preview plan rejects unsupported providers" {
  write_preview_artifacts
  write_preview_config

  run bash "$WALTER_OS_BIN" preview plan \
    --dry-run \
    --pr 235 \
    --provider prod-shell \
    --app control-tower \
    --branch feature/preview-plan \
    --seed "$seed_file" \
    --config "$config_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"unsupported preview provider: prod-shell"* ]]
}

@test "preview bundle copies seed and screenshots into a report bundle" {
  write_preview_artifacts

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --seed "$seed_file" \
    --screenshot "$shot_file" \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pr == 235'
  echo "$output" | jq -e '.url == "https://preview.example/pr-235"'
  echo "$output" | jq -e '.bundle_dir | endswith("preview-pr-235")'
  echo "$output" | jq -e '.seed_manifest.sha256 | length == 64'
  echo "$output" | jq -e '.screenshots[0].sha256 | length == 64'
  echo "$output" | jq -e '.safety.production_secrets == "rejected"'

  bundle_dir="$TMP_DIR/out/preview-pr-235"
  [[ -f "$bundle_dir/preview-report.json" ]]
  [[ -f "$bundle_dir/README.md" ]]
  [[ -f "$bundle_dir/seed/seed.json" ]]
  [[ -f "$bundle_dir/screenshots/home.png" ]]
}

@test "preview bundle defaults to .walter/previews under the current repo" {
  write_preview_artifacts
  cd "$TMP_DIR"

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 12 \
    --url http://localhost:3000 \
    --seed "$seed_file" \
    --screenshot "$shot_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *".walter/previews/preview-pr-12"* ]]
  [[ -f "$TMP_DIR/.walter/previews/preview-pr-12/preview-report.json" ]]
}

@test "preview bundle rejects secret-like artifacts" {
  secret_file="$TMP_DIR/.env"
  shot_file="$TMP_DIR/home.png"
  printf 'TOKEN=do-not-copy\n' > "$secret_file"
  printf 'fake png bytes\n' > "$shot_file"

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --seed "$secret_file" \
    --screenshot "$shot_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"refusing secret-like artifact"* ]]
  [[ ! -e "$TMP_DIR/out/preview-pr-235/seed/.env" ]]
}

@test "preview bundle handles artifact filenames that start with dash" {
  cd "$TMP_DIR"
  printf '{"users":[{"id":"dash-demo"}]}\n' > ./-seed.json
  printf 'fake png bytes\n' > ./-screen.png
  fake_bin="$TMP_DIR/fake-cp-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/cp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ "$arg" == "--" ]]; then
    echo "BSD cp does not support --" >&2
    exit 64
  fi
done
exec /bin/cp "$@"
SH
  chmod +x "$fake_bin/cp"
  export PATH="$fake_bin:$PATH"

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --seed -seed.json \
    --screenshot -screen.png \
    --out "$TMP_DIR/out" \
    --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.seed_manifest.sha256 | length == 64'
  echo "$output" | jq -e '.screenshots[0].sha256 | length == 64'
  [[ -f "$TMP_DIR/out/preview-pr-235/seed/-seed.json" ]]
  [[ -f "$TMP_DIR/out/preview-pr-235/screenshots/-screen.png" ]]
}

@test "preview bundle rejects non-http preview URLs" {
  write_preview_artifacts

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 235 \
    --url file:///tmp/preview.html \
    --seed "$seed_file" \
    --screenshot "$shot_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"preview URL must start with http:// or https://"* ]]
}

@test "preview bundle requires at least one screenshot" {
  write_preview_artifacts

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 235 \
    --url https://preview.example/pr-235 \
    --seed "$seed_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"at least one --screenshot is required"* ]]
}

@test "preview bundle rejects zero PR numbers" {
  write_preview_artifacts

  run bash "$WALTER_OS_BIN" preview bundle \
    --pr 0 \
    --url https://preview.example/pr-0 \
    --seed "$seed_file" \
    --screenshot "$shot_file" \
    --out "$TMP_DIR/out"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--pr must be a positive integer"* ]]
}

@test "preview bundle shows usage for unknown options" {
  run bash "$WALTER_OS_BIN" preview bundle --wat

  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown option: --wat"* ]]
  [[ "$output" == *"Usage: walter-os preview bundle"* ]]
}

@test "help documents preview bundle" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"preview bundle"* ]]
  [[ "$output" == *"preview plan"* ]]
}
