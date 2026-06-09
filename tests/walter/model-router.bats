#!/usr/bin/env bats
# tests/walter/model-router.bats
#
# Covers issue #24 core routing contract: domain defaults, operator overrides,
# comma-separated parallel routes, and the PHI local-model lock.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER="$REPO_ROOT/scripts/walter/lib/model-router.sh"
  DOMAINS="$REPO_ROOT/scripts/walter/lib/model-domains.tsv"
  TMP_CONFIG=""
  [[ -f "$ROUTER" ]] || skip "model-router.sh not present"
  TMP_CONFIG="$(mktemp -d)"
  export WALTER_CONFIG="$TMP_CONFIG"
  unset WALTER_AI_CAPABILITIES_FILE
  unset WALTER_MODEL_DOMAINS_FILE
  unset WALTER_MODEL_OVERRIDE
  unset WALTER_MODEL_BACKEND_REVIEW
  unset WALTER_MODEL_FRONTEND
  unset WALTER_MODEL_LONGFORM
  unset WALTER_MODEL_QUICK_REFACTOR
  unset WALTER_MODEL_PHI
  unset WALTER_MODEL_BRAINSTORM
  unset WALTER_MODEL_DEFAULT
}

teardown() {
  [[ -n "${TMP_CONFIG:-}" && -d "$TMP_CONFIG" ]] && rm -rf "$TMP_CONFIG"
}

@test "model-router: domains come from canonical table" {
  local expected
  [[ -f "$DOMAINS" ]]
  expected="$(awk -F '\t' '$0 !~ /^#/ && NF >= 3 { print $1 }' "$DOMAINS" | paste -sd, -)"
  [[ -n "$expected" ]]

  run bash -c "source '$ROUTER'; walter_model_domains | paste -sd, -"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "model-router: unset backend_review uses Codex default" {
  run bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "model-router: per-domain env override wins" {
  run env WALTER_MODEL_FRONTEND=claude-opus bash -c "source '$ROUTER'; walter_model_for frontend"

  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus" ]
}

@test "model-router: comma-separated parallel route is preserved" {
  run env WALTER_MODEL_BRAINSTORM=claude,codex,gemini bash -c "source '$ROUTER'; walter_model_for brainstorm"

  [ "$status" -eq 0 ]
  [ "$output" = "claude,codex,gemini" ]
}

@test "model-router: primary selector chooses first route and preserves domain" {
  run env WALTER_MODEL_BRAINSTORM=claude,codex,gemini bash -c "source '$ROUTER'; model=''; walter_model_select_primary brainstorm model; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  [ "$output" = "claude|brainstorm" ]
}

@test "model-router: resolve alias assigns without losing domain metadata" {
  run env WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; model=''; walter_model_resolve backend_review model; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  [ "$output" = "codex|backend_review" ]
}

@test "model-router: routing examples avoid command substitution when metadata matters" {
  run bash -c "grep -RInE '=\\\"?\\$\\(walter_model_for (backend_review|frontend|longform|brainstorm)' docs/operational/multi-model-routing.md docs/specs/multi-model-preference-wizard.md skills/web-security-baseline/SKILL.md skills/pr-review/SKILL.md skills/frontend-quality/SKILL.md skills/content-writer/SKILL.md agents/architect.md commands/pr.md"

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
}

@test "model-router: WALTER_MODEL_OVERRIDE wins for non-PHI domains" {
  run env WALTER_MODEL_OVERRIDE=gemini-pro WALTER_MODEL_BACKEND_REVIEW=claude bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  [ "$output" = "gemini-pro" ]
}

@test "model-router: PHI ignores WALTER_MODEL_OVERRIDE" {
  run env WALTER_MODEL_OVERRIDE=codex WALTER_MODEL_PHI=ollama/llama3.3 bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3.3" ]
}

@test "model-router: PHI rejects non-local route and falls back closed" {
  run env WALTER_MODEL_PHI=codex bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI stays local when canonical table is missing" {
  run env WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" WALTER_MODEL_PHI=codex bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: walter_model_domains fails when canonical table is missing" {
  run env WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "source '$ROUTER'; walter_model_domains" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: CRLF domain table rows do not leak carriage returns" {
  local domains_file="$TMP_CONFIG/model-domains-crlf.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex\tBackend review\r\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "model-router: malformed domain row falls back without empty model" {
  local domains_file="$TMP_CONFIG/model-domains.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: walter_model_domains fails when all rows are malformed" {
  local domains_file="$TMP_CONFIG/model-domains-invalid.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\n' > "$domains_file"

  run env WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_domains" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"no valid rows"* ]]
}

@test "model-router: print effective fails when canonical table is missing" {
  run env WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "source '$ROUTER'; walter_models_print_effective" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts comma-separated local routes" {
  run env WALTER_MODEL_PHI='ollama/llama3,127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3,127.0.0.1:11434" ]
}

@test "model-router: PHI rejects mixed local and remote routes" {
  run env WALTER_MODEL_PHI='ollama/llama3,codex' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI mode reports phi metadata domain" {
  run env WALTER_PHI_MODE=1 WALTER_MODEL_PHI=ollama/llama3 bash -c "source '$ROUTER'; tmp=\"\$(mktemp)\"; walter_model_for backend_review > \"\$tmp\"; model=\"\$(cat \"\$tmp\")\"; rm -f \"\$tmp\"; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  [ "$output" = "ollama/llama3|phi" ]
}

@test "model-router: PHI rejects remote ollama-looking URLs" {
  run env WALTER_MODEL_PHI='https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects ollama URL-like aliases" {
  run env WALTER_MODEL_PHI='ollama:https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects local URL-like aliases" {
  run env WALTER_MODEL_PHI='local/https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects localhost-looking DNS names" {
  run env WALTER_MODEL_PHI='localhost.com:443' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts explicit loopback aliases" {
  run env WALTER_MODEL_PHI='127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "127.0.0.1:11434" ]
}

@test "model-router: PHI accepts bracketed IPv6 loopback aliases" {
  run env WALTER_MODEL_PHI='[::1]:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  [ "$output" = "[::1]:11434" ]
}

@test "model-router: invalid model values are rejected" {
  run env WALTER_MODEL_DEFAULT='claude; rm -rf /' bash -c "source '$ROUTER'; walter_model_for default" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: warns when route provider is disabled in ai-capabilities" {
  local tmpdir capabilities
  tmpdir="$(mktemp -d)"
  capabilities="$tmpdir/ai-capabilities.yaml"
  cat >"$capabilities" <<'YAML'
profile: claude-only
provider_claude: enabled
provider_codex: disabled
provider_copilot: disabled
provider_gemini: disabled
provider_ollama: disabled
route_code_review: claude
route_infra_security_backend: claude
route_planning: claude
route_ux_ui: claude
route_image_generation: none
route_research: claude
route_compliance_local_only: none
YAML

  run env WALTER_AI_CAPABILITIES_FILE="$capabilities" WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"provider_codex is disabled"* ]]
}

@test "model-router: unreadable ai-capabilities file is ignored quietly" {
  local tmpdir capabilities
  tmpdir="$(mktemp -d)"
  capabilities="$tmpdir/ai-capabilities.yaml"
  touch "$capabilities"
  chmod 000 "$capabilities"

  run env WALTER_AI_CAPABILITIES_FILE="$capabilities" WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  chmod 600 "$capabilities"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}
