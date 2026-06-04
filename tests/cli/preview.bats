#!/usr/bin/env bats
# tests/cli/preview.bats
#
# Covers: docs/specs/preview-environment-bundle.md

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

@test "help documents preview bundle" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"preview bundle"* ]]
}
