#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/setup/personal-overlay-init.sh"
}

@test "personal-overlay-init does not duplicate model routing header" {
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/.config/walter-os/overlay"
  cat > "$tmpdir/.config/walter-os/overlay/personal.env" <<'ENV'
# === MODEL ROUTING ===
WALTER_MODEL_BACKEND_REVIEW=codex
ENV

  run env HOME="$tmpdir" "$SCRIPT"

  [ "$status" -eq 0 ]
  header_count="$(grep -c '^# === MODEL ROUTING ===$' "$tmpdir/.config/walter-os/overlay/personal.env")"
  [ "$header_count" -eq 1 ]
  rm -rf "$tmpdir"
}

@test "personal-overlay-init respects exported model routing keys" {
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/.config/walter-os/overlay"
  cat > "$tmpdir/.config/walter-os/overlay/personal.env" <<'ENV'
export WALTER_MODEL_BACKEND_REVIEW=codex
ENV

  run env HOME="$tmpdir" "$SCRIPT"

  [ "$status" -eq 0 ]
  key_count="$(grep -c 'WALTER_MODEL_BACKEND_REVIEW=' "$tmpdir/.config/walter-os/overlay/personal.env")"
  [ "$key_count" -eq 1 ]
  rm -rf "$tmpdir"
}

@test "personal overlay skeleton documents model routing keys" {
  skeleton="$REPO_ROOT/contexts/_examples/walter-personal-skeleton/personal.env.template"
  [[ -f "$skeleton" ]]

  grep -q "^WALTER_MODEL_BACKEND_REVIEW=" "$skeleton"
  grep -q "^WALTER_MODEL_FRONTEND=" "$skeleton"
  grep -q "^WALTER_MODEL_LONGFORM=" "$skeleton"
  grep -q "^WALTER_MODEL_QUICK_REFACTOR=" "$skeleton"
  grep -q "^WALTER_MODEL_PHI=" "$skeleton"
  grep -q "^WALTER_MODEL_BRAINSTORM=" "$skeleton"
  grep -q "^WALTER_MODEL_DEFAULT=" "$skeleton"
  grep -q "walter ai configure" "$skeleton"
}
