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
  export WALTER_PHI_MODE=0
  unset WALTER_MODEL_DOMAIN
}

teardown() {
  [[ -n "${TMP_CONFIG:-}" && -d "$TMP_CONFIG" ]] && rm -rf "$TMP_CONFIG"
}

run_router() {
  env -i \
    HOME="${HOME:-}" \
    PATH="${PATH:-/usr/bin:/bin}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    WALTER_CONFIG="$WALTER_CONFIG" \
    WALTER_PHI_MODE=0 \
    "$@"
}

output_is_exactly() {
  [ "$(output_without_router_warnings)" = "$1" ]
}

output_without_router_warnings() {
  printf '%s\n' "$output" | grep -v '^walter-model-router: WARN' || true
}

@test "model-router: domains come from canonical table" {
  local expected
  [[ -f "$DOMAINS" ]]
  expected="$(awk -F '\t' '$0 !~ /^#/ && NF >= 3 { print $1 }' "$DOMAINS")"
  [[ -n "$expected" ]]

  run run_router bash -c "source '$ROUTER'; walter_model_domains"

  [ "$status" -eq 0 ]
  [ "$(output_without_router_warnings)" = "$expected" ]
}

@test "model-router: unset backend_review uses Codex default" {
  run run_router bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: per-domain env override wins" {
  run run_router WALTER_MODEL_FRONTEND=claude-opus bash -c "source '$ROUTER'; walter_model_for frontend"

  [ "$status" -eq 0 ]
  output_is_exactly "claude-opus"
}

@test "model-router: comma-separated parallel route is preserved" {
  run run_router WALTER_MODEL_BRAINSTORM=claude,codex,gemini bash -c "source '$ROUTER'; walter_model_for brainstorm"

  [ "$status" -eq 0 ]
  output_is_exactly "claude,codex,gemini"
}

@test "model-router: primary selector chooses first route and preserves domain" {
  run run_router WALTER_MODEL_BRAINSTORM=claude,codex,gemini bash -c "source '$ROUTER'; model=''; walter_model_select_primary brainstorm model; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  output_is_exactly "claude|brainstorm"
}

@test "model-router: resolve alias assigns without losing domain metadata" {
  run run_router WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; model=''; walter_model_resolve backend_review model; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  output_is_exactly "codex|backend_review"
}

@test "model-router: routing examples avoid command substitution when metadata matters" {
  run run_router bash -c "grep -RInE '=\\\"?\\$\\(walter_model_for (backend_review|frontend|longform|brainstorm)' docs/operational/multi-model-routing.md docs/specs/multi-model-preference-wizard.md skills/web-security-baseline/SKILL.md skills/pr-review/SKILL.md skills/frontend-quality/SKILL.md skills/content-writer/SKILL.md agents/architect.md commands/pr.md"

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
}

@test "model-router: WALTER_MODEL_OVERRIDE wins for non-PHI domains" {
  run run_router WALTER_MODEL_OVERRIDE=gemini-pro WALTER_MODEL_BACKEND_REVIEW=claude bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  output_is_exactly "gemini-pro"
}

@test "model-router: PHI ignores WALTER_MODEL_OVERRIDE" {
  run run_router WALTER_MODEL_OVERRIDE=codex WALTER_MODEL_PHI=ollama/llama3.3 bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  output_is_exactly "ollama/llama3.3"
}

@test "model-router: PHI rejects non-local route and falls back closed" {
  run run_router WALTER_MODEL_PHI=codex bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI stays local when canonical table is missing" {
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" WALTER_MODEL_PHI=codex bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: walter_model_domains fails when canonical table is missing" {
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "source '$ROUTER'; walter_model_domains" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: missing domain table preserves legacy domain default" {
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: missing domain table preserves domain env override" {
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" WALTER_MODEL_BACKEND_REVIEW=claude-opus bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "claude-opus"
}

@test "model-router: sourcing does not create warning temp dirs" {
  local warn_tmp
  warn_tmp="$TMP_CONFIG/router-warnings"
  mkdir -p "$warn_tmp"
  export TMPDIR="$warn_tmp"

  run run_router bash -c "source '$ROUTER'"

  [ "$status" -eq 0 ]
  [ -z "$(find "$warn_tmp" -maxdepth 1 -type d -name 'walter-model-router-warnings.*' -print -quit)" ]
}

@test "model-router: missing domain table warning is emitted once" {
  local count
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "
    source '$ROUTER'
    walter_model_domains >/dev/null
    walter_models_print_effective >/dev/null
  " 2>&1

  [ "$status" -ne 0 ]
  count="$(printf '%s\n' "$output" | grep -c "model domain table is missing or unreadable" || true)"
  [ "$count" -eq 1 ]
}

@test "model-router: recovers when missing domain table appears later" {
  local domains_file="$TMP_CONFIG/model-domains-late.tsv"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "
    source '$ROUTER'
    walter_model_domains >/dev/null 2>&1 || true
    printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex\tBackend review\n' > \"\$WALTER_MODEL_DOMAINS_FILE\"
    walter_model_for backend_review
  " 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: CRLF domain table rows do not leak carriage returns" {
  local domains_file="$TMP_CONFIG/model-domains-crlf.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex\tBackend review\r\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review"

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: malformed domain row falls back without empty model" {
  local domains_file="$TMP_CONFIG/model-domains.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: whitespace-only domain table rows are ignored" {
  local domains_file="$TMP_CONFIG/model-domains-whitespace.tsv"
  printf '   \t  \nbackend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex\tBackend review\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: invalid default route rows are ignored" {
  local domains_file="$TMP_CONFIG/model-domains-invalid-default.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex;rm\tBackend review\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: trailing comma default route rows are ignored" {
  local domains_file="$TMP_CONFIG/model-domains-trailing-comma.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex,\tBackend review\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: malformed row warning is emitted once" {
  local count domains_file="$TMP_CONFIG/model-domains-malformed.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\nfrontend\tWALTER_MODEL_FRONTEND\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "
    source '$ROUTER'
    walter_model_for backend_review >/dev/null
    walter_models_print_effective >/dev/null
  " 2>&1

  [ "$status" -ne 0 ]
  count="$(printf '%s\n' "$output" | grep -c "ignoring malformed model domain row" || true)"
  [ "$count" -eq 1 ]
}

@test "model-router: walter_model_domains fails when all rows are malformed" {
  local domains_file="$TMP_CONFIG/model-domains-invalid.tsv"
  printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "source '$ROUTER'; walter_model_domains" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"no valid rows"* ]]
}

@test "model-router: empty domain table warning is emitted once" {
  local count domains_file="$TMP_CONFIG/model-domains-empty.tsv"
  printf '# domain\tenv\tdefault\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "
    source '$ROUTER'
    walter_model_domains >/dev/null
    walter_models_print_effective >/dev/null
  " 2>&1

  [ "$status" -ne 0 ]
  count="$(printf '%s\n' "$output" | grep -c "model domain table has no valid rows" || true)"
  [ "$count" -eq 1 ]
}

@test "model-router: recovers when empty domain table is fixed later" {
  local domains_file="$TMP_CONFIG/model-domains-empty-then-fixed.tsv"
  printf '# domain\tenv\tdefault\tdescription\n' > "$domains_file"

  run run_router WALTER_MODEL_DOMAINS_FILE="$domains_file" bash -c "
    source '$ROUTER'
    walter_model_domains >/dev/null 2>&1 || true
    printf 'backend_review\tWALTER_MODEL_BACKEND_REVIEW\tcodex\tBackend review\n' > \"\$WALTER_MODEL_DOMAINS_FILE\"
    walter_model_for backend_review
  " 2>&1

  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}

@test "model-router: print effective fails when canonical table is missing" {
  run run_router WALTER_MODEL_DOMAINS_FILE="$TMP_CONFIG/missing-model-domains.tsv" bash -c "source '$ROUTER'; walter_models_print_effective" 2>&1

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts comma-separated local routes" {
  run run_router WALTER_MODEL_PHI='ollama/llama3,127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  output_is_exactly "ollama/llama3,127.0.0.1:11434"
}

@test "model-router: PHI rejects mixed local and remote routes" {
  run run_router WALTER_MODEL_PHI='ollama/llama3,codex' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI mode reports phi metadata domain" {
  run run_router WALTER_PHI_MODE=1 WALTER_MODEL_PHI=ollama/llama3 bash -c "source '$ROUTER'; tmp=\"\$(mktemp)\"; walter_model_for backend_review > \"\$tmp\"; model=\"\$(cat \"\$tmp\")\"; rm -f \"\$tmp\"; printf '%s|%s\n' \"\$model\" \"\$WALTER_MODEL_DOMAIN\""

  [ "$status" -eq 0 ]
  output_is_exactly "ollama/llama3|phi"
}

@test "model-router: PHI rejects remote ollama-looking URLs" {
  run run_router WALTER_MODEL_PHI='https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects ollama URL-like aliases" {
  run run_router WALTER_MODEL_PHI='ollama:https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects local URL-like aliases" {
  run run_router WALTER_MODEL_PHI='local/https://evil.example/ollama-proxy' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI rejects localhost-looking DNS names" {
  run run_router WALTER_MODEL_PHI='localhost.com:443' bash -c "source '$ROUTER'; walter_model_for phi" 2>&1

  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ollama"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "model-router: PHI accepts explicit loopback aliases" {
  run run_router WALTER_MODEL_PHI='127.0.0.1:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  output_is_exactly "127.0.0.1:11434"
}

@test "model-router: PHI accepts bracketed IPv6 loopback aliases" {
  run run_router WALTER_MODEL_PHI='[::1]:11434' bash -c "source '$ROUTER'; walter_model_for phi"

  [ "$status" -eq 0 ]
  output_is_exactly "[::1]:11434"
}

@test "model-router: invalid model values are rejected" {
  run run_router WALTER_MODEL_DEFAULT='claude; rm -rf /' bash -c "source '$ROUTER'; walter_model_for default" 2>&1

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

  run run_router WALTER_AI_CAPABILITIES_FILE="$capabilities" WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

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

  run run_router WALTER_AI_CAPABILITIES_FILE="$capabilities" WALTER_MODEL_BACKEND_REVIEW=codex bash -c "source '$ROUTER'; walter_model_for backend_review" 2>&1

  chmod 600 "$capabilities"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  output_is_exactly "codex"
}
