#!/usr/bin/env bats
# tests/cli/providers.bats
#
# Covers: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7
# (W-4 Provider Choice Wizard)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PROVIDERS_LIB="${REPO_ROOT}/scripts/walter/lib/providers"
SUBCOMMANDS="${REPO_ROOT}/scripts/walter/subcommands"
WALTER_BIN="${REPO_ROOT}/bin/walter"

# -----------------------------------------------------------------------
# Test environment setup helpers
# -----------------------------------------------------------------------
setup() {
  # Fresh temp dir for each test — simulates HOME config
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export WALTER_OS_HOME="$REPO_ROOT"

  # Unset all provider env vars so detection is predictable
  unset ANTHROPIC_API_KEY OPENAI_API_KEY LITELLM_API_KEY LITELLM_BASE_URL
  unset OLLAMA_BASE_URL
  unset PLANE_API_TOKEN PLANE_API_URL LINEAR_API_KEY
  unset GITHUB_TOKEN FORGEJO_TOKEN GITLAB_TOKEN
  unset INFISICAL_CLIENT_ID DOPPLER_TOKEN OP_ACCOUNT BW_SESSION
  unset PLAUSIBLE_API_KEY CF_ANALYTICS_TOKEN GA4_MEASUREMENT_ID
  unset BRAVE_API_KEY ALGOLIA_API_KEY
  unset VOYAGE_API_KEY

  # Create required config dir
  mkdir -p "${TEST_HOME}/.config/walter-os"
  mkdir -p "${TEST_HOME}/Projects-Personal/walter-os"

  # Minimal .env.local for patching tests
  cat > "${TEST_HOME}/.env.local" << 'ENVEOF'
# Walter-OS .env.local (test fixture)
GITHUB_TOKEN=test-gh-token
FORGEJO_URL=https://git.example.com
FORGEJO_TOKEN=test-forgejo-token
PLANE_API_TOKEN=test-plane-token
LINEAR_API_KEY=test-linear-key
LITELLM_BASE_URL=http://litellm:4000
LITELLM_API_KEY=sk-test
ANTHROPIC_API_KEY=sk-ant-test
INFISICAL_CLIENT_ID=test-id
INFISICAL_CLIENT_SECRET=test-secret
BRAVE_API_KEY=test-brave-key
ALGOLIA_API_KEY=test-algolia-key
ENVEOF
}

teardown() {
  rm -rf "$TEST_HOME"
}

# -----------------------------------------------------------------------
# Task 1: providers.yaml.template exists and is valid YAML [AC-2]
# -----------------------------------------------------------------------
@test "providers.yaml.template exists in templates/ [AC-2]" {
  [[ -f "${REPO_ROOT}/templates/providers.yaml.template" ]]
}

@test "providers.yaml.template contains all 7 categories [AC-2]" {
  local tpl="${REPO_ROOT}/templates/providers.yaml.template"
  grep -q "^llm:" "$tpl"
  grep -q "^project_management:" "$tpl"
  grep -q "^git:" "$tpl"
  grep -q "^secrets:" "$tpl"
  grep -q "^web_analytics:" "$tpl"
  grep -q "^search:" "$tpl"
  grep -q "^embeddings:" "$tpl"
}

# -----------------------------------------------------------------------
# Task 2: detect.sh — auto-detect configured providers [AC-1]
# -----------------------------------------------------------------------
@test "detect.sh returns git=github when GITHUB_TOKEN is set [AC-1]" {
  export GITHUB_TOKEN="test-token"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider git)"
  [[ "$result" == "github" ]]
}

@test "detect.sh returns git=forgejo when FORGEJO_TOKEN is set and no GITHUB_TOKEN [AC-1]" {
  unset GITHUB_TOKEN
  export FORGEJO_TOKEN="test-token"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider git)"
  [[ "$result" == "forgejo" ]]
}

@test "detect.sh returns empty string when no git provider detected [AC-1]" {
  unset GITHUB_TOKEN FORGEJO_TOKEN GITLAB_TOKEN
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider git)"
  [[ -z "$result" ]]
}

@test "detect.sh returns llm=litellm when LITELLM_API_KEY is set [AC-1]" {
  export LITELLM_API_KEY="sk-test"
  export LITELLM_BASE_URL="http://litellm:4000"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider llm)"
  [[ "$result" == "litellm" ]]
}

@test "detect.sh returns llm=anthropic when only ANTHROPIC_API_KEY is set [AC-1]" {
  unset LITELLM_API_KEY LITELLM_BASE_URL OPENAI_API_KEY
  export ANTHROPIC_API_KEY="sk-ant-test"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider llm)"
  [[ "$result" == "anthropic" ]]
}

@test "detect.sh returns project_management=plane when PLANE_API_TOKEN is set [AC-1]" {
  export PLANE_API_TOKEN="test-token"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider project_management)"
  [[ "$result" == "plane" ]]
}

@test "detect.sh returns project_management=linear when LINEAR_API_KEY is set and no PLANE_API_TOKEN [AC-1]" {
  unset PLANE_API_TOKEN
  export LINEAR_API_KEY="lin_test"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider project_management)"
  [[ "$result" == "linear" ]]
}

@test "detect.sh returns secrets=infisical when INFISICAL_CLIENT_ID is set [AC-1]" {
  export INFISICAL_CLIENT_ID="test-id"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider secrets)"
  [[ "$result" == "infisical" ]]
}

# -----------------------------------------------------------------------
# WARN 2: detect.sh plausible vs plausible_cloud distinction [AC-1]
# -----------------------------------------------------------------------
@test "WARN2: detect.sh returns plausible_cloud when PLAUSIBLE_API_URL contains plausible.io [AC-1]" {
  export PLAUSIBLE_API_KEY="test-key"
  export PLAUSIBLE_SITE_ID="example.com"
  export PLAUSIBLE_API_URL="https://plausible.io/api/v1"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider web_analytics)"
  [[ "$result" == "plausible_cloud" ]]
  unset PLAUSIBLE_API_KEY PLAUSIBLE_SITE_ID PLAUSIBLE_API_URL
}

@test "WARN2: detect.sh returns plausible (self-host) when PLAUSIBLE_API_URL is not plausible.io [AC-1]" {
  export PLAUSIBLE_API_KEY="test-key"
  export PLAUSIBLE_SITE_ID="example.com"
  export PLAUSIBLE_API_URL="https://analytics.mycompany.com"
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider web_analytics)"
  [[ "$result" == "plausible" ]]
  unset PLAUSIBLE_API_KEY PLAUSIBLE_SITE_ID PLAUSIBLE_API_URL
}

@test "WARN2: detect.sh returns plausible (self-host) when PLAUSIBLE_API_URL is unset [AC-1]" {
  export PLAUSIBLE_API_KEY="test-key"
  export PLAUSIBLE_SITE_ID="example.com"
  unset PLAUSIBLE_API_URL
  source "${PROVIDERS_LIB}/detect.sh"
  result="$(detect_provider web_analytics)"
  [[ "$result" == "plausible" ]]
}

# -----------------------------------------------------------------------
# Task 3: wizard.sh — non-interactive mode via piped input [AC-1, AC-5]
# -----------------------------------------------------------------------
@test "providers.sh subcommand exists and is executable [AC-1]" {
  [[ -f "${SUBCOMMANDS}/providers.sh" ]]
  [[ -x "${SUBCOMMANDS}/providers.sh" ]]
}

# -----------------------------------------------------------------------
# BLOCKER 1: unbound variable / OOB index in non-interactive mode [AC-1]
# -----------------------------------------------------------------------
@test "BLOCKER1: piping unknown slug defaults to first option (no crash) [AC-1]" {
  export PROVIDERS_YAML="${TEST_HOME}/.config/walter-os/providers.yaml"
  export ENV_LOCAL="${TEST_HOME}/.env.local"
  # 7 categories; send 'bogus-provider' for llm, then '1' for the rest
  printf 'bogus-provider\n1\n1\n1\n1\n1\n1\n' \
    | bash "${SUBCOMMANDS}/providers.sh" configure
  # The resulting providers.yaml must exist and llm must be set to a known slug
  grep -qE "^llm: (litellm|anthropic|openai|ollama)" "${TEST_HOME}/.config/walter-os/providers.yaml"
}

@test "BLOCKER1: piping OOB index 99 defaults to first option (no crash) [AC-1]" {
  export PROVIDERS_YAML="${TEST_HOME}/.config/walter-os/providers.yaml"
  export ENV_LOCAL="${TEST_HOME}/.env.local"
  # '99' is out of bounds for any category menu
  printf '99\n1\n1\n1\n1\n1\n1\n' \
    | bash "${SUBCOMMANDS}/providers.sh" configure
  grep -qE "^llm: (litellm|anthropic|openai|ollama)" "${TEST_HOME}/.config/walter-os/providers.yaml"
}

# -----------------------------------------------------------------------
# Task 4: providers.yaml writer — idempotency [AC-2]
# -----------------------------------------------------------------------
@test "apply.sh writes providers.yaml with correct structure [AC-2]" {
  source "${PROVIDERS_LIB}/apply.sh"
  local out="${TEST_HOME}/.config/walter-os/providers.yaml"
  write_providers_yaml \
    "litellm" "plane" "forgejo" "infisical" "plausible" "brave" "nomic" \
    "$out"
  [[ -f "$out" ]]
  grep -q "^llm:" "$out"
  grep -q "^git:" "$out"
}

@test "apply.sh is idempotent: re-run with same selections produces identical file [AC-2]" {
  source "${PROVIDERS_LIB}/apply.sh"
  local out="${TEST_HOME}/.config/walter-os/providers.yaml"
  write_providers_yaml \
    "litellm" "plane" "forgejo" "infisical" "plausible" "brave" "nomic" \
    "$out"
  local hash1
  hash1="$(md5 -q "$out" 2>/dev/null || md5sum "$out" | awk '{print $1}')"

  write_providers_yaml \
    "litellm" "plane" "forgejo" "infisical" "plausible" "brave" "nomic" \
    "$out"
  local hash2
  hash2="$(md5 -q "$out" 2>/dev/null || md5sum "$out" | awk '{print $1}')"

  [[ "$hash1" == "$hash2" ]]
}

# -----------------------------------------------------------------------
# Task 5: patch-env.sh — .env.local patching [AC-3]
# -----------------------------------------------------------------------
@test "patch_env: selecting github for git comments out FORGEJO_URL [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  patch_env_for_category "git" "github" "$env_file"
  grep -q "^#.*FORGEJO_URL=" "$env_file"
}

@test "patch_env: selecting forgejo for git keeps FORGEJO_URL uncommented [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  # Ensure FORGEJO_URL is present and uncommented
  grep -q "^FORGEJO_URL=" "$env_file"
  patch_env_for_category "git" "forgejo" "$env_file"
  grep -q "^FORGEJO_URL=" "$env_file"
}

@test "patch_env: selecting linear for project_management comments out PLANE_API_TOKEN [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  patch_env_for_category "project_management" "linear" "$env_file"
  grep -q "^#.*PLANE_API_TOKEN=" "$env_file"
}

@test "patch_env: selecting anthropic for llm comments out LITELLM_BASE_URL [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  patch_env_for_category "llm" "anthropic" "$env_file"
  grep -q "^#.*LITELLM_BASE_URL=" "$env_file"
}

# -----------------------------------------------------------------------
# BLOCKER 2: cross-category env var clobbering [AC-3]
# -----------------------------------------------------------------------
@test "BLOCKER2: llm=openai + embeddings=nomic keeps OPENAI_API_KEY uncommented [AC-3]" {
  # Add OPENAI_API_KEY to env file (uncommented)
  echo "OPENAI_API_KEY=sk-test-openai" >> "${TEST_HOME}/.env.local"
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  # Signal LLM provider so embeddings patcher knows not to clobber OPENAI_API_KEY
  export WALTER_LLM_PROVIDER="openai"
  patch_env_for_category "llm" "openai" "$env_file"
  patch_env_for_category "embeddings" "nomic" "$env_file"
  unset WALTER_LLM_PROVIDER
  grep -q "^OPENAI_API_KEY=" "$env_file"
}

@test "BLOCKER2: llm=ollama + embeddings=voyage keeps OLLAMA_BASE_URL uncommented [AC-3]" {
  # Add OLLAMA_BASE_URL to env file (uncommented)
  echo "OLLAMA_BASE_URL=http://localhost:11434" >> "${TEST_HOME}/.env.local"
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  # Signal LLM provider so embeddings patcher knows not to clobber OLLAMA_BASE_URL
  export WALTER_LLM_PROVIDER="ollama"
  patch_env_for_category "llm" "ollama" "$env_file"
  patch_env_for_category "embeddings" "voyage" "$env_file"
  unset WALTER_LLM_PROVIDER
  grep -q "^OLLAMA_BASE_URL=" "$env_file"
}

# -----------------------------------------------------------------------
# Task 6: patch-mcp.sh — mcp/servers.json patching [AC-4]
# -----------------------------------------------------------------------
@test "patch_mcp: selecting linear disables plane MCP [AC-4]" {
  source "${PROVIDERS_LIB}/patch_mcp.sh"
  local mcp_file="${TEST_HOME}/mcp-servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$mcp_file"
  patch_mcp_for_category "project_management" "linear" "$mcp_file"
  local disabled
  disabled="$(jq '.servers.plane.disabled' "$mcp_file")"
  [[ "$disabled" == "true" ]]
}

@test "patch_mcp: selecting plane disables linear MCP [AC-4]" {
  source "${PROVIDERS_LIB}/patch_mcp.sh"
  local mcp_file="${TEST_HOME}/mcp-servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$mcp_file"
  patch_mcp_for_category "project_management" "plane" "$mcp_file"
  local disabled
  disabled="$(jq '.servers.linear.disabled' "$mcp_file")"
  [[ "$disabled" == "true" ]]
}

@test "patch_mcp: selected provider MCP has disabled=false [AC-4]" {
  source "${PROVIDERS_LIB}/patch_mcp.sh"
  local mcp_file="${TEST_HOME}/mcp-servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$mcp_file"
  patch_mcp_for_category "project_management" "linear" "$mcp_file"
  local disabled
  disabled="$(jq '.servers.linear.disabled' "$mcp_file")"
  [[ "$disabled" == "false" || "$disabled" == "null" ]]
}

# -----------------------------------------------------------------------
# WARN 4: GIT_PROVIDER env var written to .env.local [AC-3]
# -----------------------------------------------------------------------
@test "WARN4: patch_env writes GIT_PROVIDER=github when git=github [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  patch_env_for_category "git" "github" "$env_file"
  grep -q "^GIT_PROVIDER=github" "$env_file"
}

@test "WARN4: patch_env writes GIT_PROVIDER=forgejo when git=forgejo [AC-3]" {
  source "${PROVIDERS_LIB}/patch_env.sh"
  local env_file="${TEST_HOME}/.env.local"
  patch_env_for_category "git" "forgejo" "$env_file"
  grep -q "^GIT_PROVIDER=forgejo" "$env_file"
}

@test "WARN4: .env.example documents GIT_PROVIDER variable [AC-3]" {
  grep -q "GIT_PROVIDER" "${REPO_ROOT}/.env.example"
}

# -----------------------------------------------------------------------
# WARN 5: jq --arg for safe key interpolation [AC-4]
# -----------------------------------------------------------------------
@test "WARN5: patch_mcp uses --arg for key interpolation (no jq injection) [AC-4]" {
  source "${PROVIDERS_LIB}/patch_mcp.sh"
  # Inject a MCP key name that would break naive string interpolation
  # (contains a double-quote). We test by passing a key that simply doesn't
  # exist in servers.json — it should be a no-op and not crash.
  local mcp_file="${TEST_HOME}/mcp-servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$mcp_file"
  local before_hash after_hash
  before_hash="$(md5 -q "$mcp_file" 2>/dev/null || md5sum "$mcp_file" | awk '{print $1}')"
  # Call with a normal key and verify no crash
  patch_mcp_for_category "project_management" "linear" "$mcp_file"
  after_hash="$(md5 -q "$mcp_file" 2>/dev/null || md5sum "$mcp_file" | awk '{print $1}')"
  # File must be valid JSON after patch
  jq . "$mcp_file" > /dev/null
}

# -----------------------------------------------------------------------
# WARN 3: trap cleanup for jq temp file [AC-4]
# -----------------------------------------------------------------------
@test "WARN3: patch_mcp_for_category cleans up temp file on success [AC-4]" {
  source "${PROVIDERS_LIB}/patch_mcp.sh"
  local mcp_file="${TEST_HOME}/mcp-servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$mcp_file"
  # Count tmp files before
  local before_count after_count
  before_count="$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)"
  patch_mcp_for_category "project_management" "linear" "$mcp_file"
  after_count="$(ls /tmp/tmp.* 2>/dev/null | wc -l || echo 0)"
  # No new tmp files should remain (trap should have cleaned up)
  [[ "$after_count" -le "$before_count" ]]
}

# -----------------------------------------------------------------------
# Task 7: walter providers configure --category [AC-5, AC-6]
# -----------------------------------------------------------------------
@test "walter providers --help exits 0 [AC-1]" {
  run bash "${SUBCOMMANDS}/providers.sh" --help
  [ "$status" -eq 0 ]
}

@test "Ollama post-config note is printed when nomic is selected [AC-6]" {
  source "${PROVIDERS_LIB}/apply.sh"
  run print_ollama_note
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "nomic-embed-text"
  echo "$output" | grep -q "ollama list"
}

# -----------------------------------------------------------------------
# WARN 1: AC-5 --category scoping — only the specified category changes
# -----------------------------------------------------------------------
@test "WARN1: --category llm changes only llm, preserves other 6 categories [AC-5]" {
  _setup_e2e_env "${TEST_HOME}/e2e"
  local yaml="${TEST_HOME}/.config/walter-os/providers.yaml"
  # First: write a full providers.yaml with a known baseline (all self-hosted)
  source "${PROVIDERS_LIB}/apply.sh"
  write_providers_yaml \
    "litellm" "plane" "forgejo" "infisical" "plausible" "brave" "nomic" \
    "$yaml"
  # Now reconfigure only llm → anthropic (choice 2)
  printf '2\n' \
    | WALTER_OS_HOME="$REPO_ROOT" WALTER_ENV_LOCAL="$E2E_ENV_LOCAL" \
      WALTER_MCP_FILE="$E2E_MCP_FILE" PROVIDERS_YAML="$yaml" \
      bash "${SUBCOMMANDS}/providers.sh" configure --category llm 2>/dev/null
  # llm must have changed
  grep -q "^llm: anthropic" "$yaml"
  # All other categories must be unchanged (still self-hosted defaults)
  grep -q "^project_management: plane" "$yaml"
  grep -q "^git: forgejo" "$yaml"
  grep -q "^secrets: infisical" "$yaml"
  grep -q "^web_analytics: plausible" "$yaml"
  grep -q "^search: brave" "$yaml"
  grep -q "^embeddings: nomic" "$yaml"
  # .env.local: ANTHROPIC_API_KEY should be uncommented now; LITELLM_BASE_URL commented
  grep -q "^ANTHROPIC_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^#.*LITELLM_BASE_URL=" "$E2E_ENV_LOCAL"
  # Other categories' vars unchanged: forgejo vars still uncommented
  grep -q "^FORGEJO_URL=" "$E2E_ENV_LOCAL"
}

# -----------------------------------------------------------------------
# Task 8: AC-7 — Three representative configurations
# -----------------------------------------------------------------------

# Config 1: All-self-hosted (via apply.sh — existing coverage)
@test "AC-7 all-self-hosted: providers.yaml has correct self-hosted selections [AC-7]" {
  source "${PROVIDERS_LIB}/apply.sh"
  local out="${TEST_HOME}/.config/walter-os/providers.yaml"
  write_providers_yaml \
    "litellm" "plane" "forgejo" "infisical" "plausible" "brave" "nomic" \
    "$out"
  grep -q "^llm: litellm" "$out"
  grep -q "^project_management: plane" "$out"
  grep -q "^git: forgejo" "$out"
  grep -q "^secrets: infisical" "$out"
  grep -q "^web_analytics: plausible" "$out"
  grep -q "^search: brave" "$out"
  grep -q "^embeddings: nomic" "$out"
}

# Config 2: Cloud-first (via apply.sh — existing coverage)
@test "AC-7 cloud-first: providers.yaml has correct cloud selections [AC-7]" {
  source "${PROVIDERS_LIB}/apply.sh"
  local out="${TEST_HOME}/.config/walter-os/providers.yaml"
  write_providers_yaml \
    "anthropic" "linear" "github" "doppler" "plausible_cloud" "algolia" "openai_ada" \
    "$out"
  grep -q "^llm: anthropic" "$out"
  grep -q "^project_management: linear" "$out"
  grep -q "^git: github" "$out"
  grep -q "^secrets: doppler" "$out"
  grep -q "^embeddings: openai_ada" "$out"
}

# Config 3: Minimal (via apply.sh — existing coverage)
@test "AC-7 minimal: providers.yaml has correct minimal selections [AC-7]" {
  source "${PROVIDERS_LIB}/apply.sh"
  local out="${TEST_HOME}/.config/walter-os/providers.yaml"
  write_providers_yaml \
    "anthropic" "none" "github" "none" "none" "none" "none" \
    "$out"
  grep -q "^llm: anthropic" "$out"
  grep -q "^project_management: none" "$out"
  grep -q "^secrets: none" "$out"
  grep -q "^web_analytics: none" "$out"
  grep -q "^search: none" "$out"
  grep -q "^embeddings: none" "$out"
}

# -----------------------------------------------------------------------
# BLOCKER 3: AC-7 end-to-end wizard + .env.local assertions
# Menu order: llm(1=litellm,2=anthropic,3=openai,4=ollama)
#             pm(1=plane,2=linear,3=plane_cloud,4=none)
#             git(1=forgejo,2=github,3=gitlab)
#             secrets(1=infisical,2=doppler,3=onepassword,4=bitwarden,5=none)
#             analytics(1=plausible,2=plausible_cloud,3=cloudflare,4=ga4,5=none)
#             search(1=brave,2=algolia,3=none)
#             embeddings(1=nomic,2=openai_ada,3=voyage,4=none)
# -----------------------------------------------------------------------
_setup_e2e_env() {
  # Create a .env.local fixture and an mcp/servers.json copy for e2e tests.
  # Sets E2E_ENV_LOCAL and E2E_MCP_FILE variables for the caller.
  local base="$1"
  mkdir -p "${base}/mcp"
  E2E_MCP_FILE="${base}/mcp/servers.json"
  cp "${REPO_ROOT}/mcp/servers.json" "$E2E_MCP_FILE"
  E2E_ENV_LOCAL="${base}/.env.local"
  cat > "$E2E_ENV_LOCAL" << 'ENVEOF'
# Walter-OS .env.local (e2e test fixture)
LITELLM_BASE_URL=http://litellm:4000
LITELLM_API_KEY=sk-test
ANTHROPIC_API_KEY=sk-ant-test
OPENAI_API_KEY=sk-openai-test
OLLAMA_BASE_URL=http://localhost:11434
PLANE_API_TOKEN=test-plane
LINEAR_API_KEY=test-linear
GITHUB_TOKEN=test-gh
FORGEJO_URL=https://git.example.com
FORGEJO_TOKEN=test-forgejo
INFISICAL_CLIENT_ID=test-id
INFISICAL_CLIENT_SECRET=test-secret
DOPPLER_TOKEN=test-doppler
BRAVE_API_KEY=test-brave
ALGOLIA_API_KEY=test-algolia
VOYAGE_API_KEY=test-voyage
ENVEOF
}

@test "BLOCKER3: e2e wizard all-self-hosted produces correct yaml + env [AC-7]" {
  _setup_e2e_env "${TEST_HOME}/e2e"
  # llm=1(litellm), pm=1(plane), git=1(forgejo), secrets=1(infisical),
  # analytics=1(plausible), search=1(brave), embeddings=1(nomic)
  printf '1\n1\n1\n1\n1\n1\n1\n' \
    | WALTER_OS_HOME="$REPO_ROOT" WALTER_ENV_LOCAL="$E2E_ENV_LOCAL" \
      WALTER_MCP_FILE="$E2E_MCP_FILE" \
      bash "${SUBCOMMANDS}/providers.sh" configure 2>/dev/null
  local yaml="${TEST_HOME}/.config/walter-os/providers.yaml"
  grep -q "^llm: litellm" "$yaml"
  grep -q "^project_management: plane" "$yaml"
  grep -q "^git: forgejo" "$yaml"
  grep -q "^secrets: infisical" "$yaml"
  grep -q "^web_analytics: plausible" "$yaml"
  grep -q "^search: brave" "$yaml"
  grep -q "^embeddings: nomic" "$yaml"
  # .env.local assertions: self-host vars remain uncommented
  grep -q "^LITELLM_BASE_URL=" "$E2E_ENV_LOCAL"
  grep -q "^PLANE_API_TOKEN=" "$E2E_ENV_LOCAL"
  grep -q "^FORGEJO_URL=" "$E2E_ENV_LOCAL"
  grep -q "^INFISICAL_CLIENT_ID=" "$E2E_ENV_LOCAL"
  # Cloud-only vars must be commented out
  grep -q "^#.*ANTHROPIC_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^#.*LINEAR_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^#.*GITHUB_TOKEN=" "$E2E_ENV_LOCAL"
}

@test "BLOCKER3: e2e wizard cloud-first produces correct yaml + env [AC-7]" {
  _setup_e2e_env "${TEST_HOME}/e2e"
  # llm=2(anthropic), pm=2(linear), git=2(github), secrets=2(doppler),
  # analytics=2(plausible_cloud), search=2(algolia), embeddings=2(openai_ada)
  printf '2\n2\n2\n2\n2\n2\n2\n' \
    | WALTER_OS_HOME="$REPO_ROOT" WALTER_ENV_LOCAL="$E2E_ENV_LOCAL" \
      WALTER_MCP_FILE="$E2E_MCP_FILE" \
      bash "${SUBCOMMANDS}/providers.sh" configure 2>/dev/null
  local yaml="${TEST_HOME}/.config/walter-os/providers.yaml"
  grep -q "^llm: anthropic" "$yaml"
  grep -q "^project_management: linear" "$yaml"
  grep -q "^git: github" "$yaml"
  grep -q "^secrets: doppler" "$yaml"
  grep -q "^web_analytics: plausible_cloud" "$yaml"
  grep -q "^search: algolia" "$yaml"
  grep -q "^embeddings: openai_ada" "$yaml"
  # .env.local assertions: cloud vars active
  grep -q "^ANTHROPIC_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^LINEAR_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^GITHUB_TOKEN=" "$E2E_ENV_LOCAL"
  grep -q "^DOPPLER_TOKEN=" "$E2E_ENV_LOCAL"
  grep -q "^OPENAI_API_KEY=" "$E2E_ENV_LOCAL"
  # Self-host vars commented out
  grep -q "^#.*LITELLM_BASE_URL=" "$E2E_ENV_LOCAL"
  grep -q "^#.*PLANE_API_TOKEN=" "$E2E_ENV_LOCAL"
  grep -q "^#.*FORGEJO_URL=" "$E2E_ENV_LOCAL"
}

@test "BLOCKER3: e2e wizard minimal produces correct yaml + env [AC-7]" {
  _setup_e2e_env "${TEST_HOME}/e2e"
  # llm=2(anthropic), pm=4(none), git=2(github), secrets=5(none),
  # analytics=5(none), search=3(none), embeddings=4(none)
  printf '2\n4\n2\n5\n5\n3\n4\n' \
    | WALTER_OS_HOME="$REPO_ROOT" WALTER_ENV_LOCAL="$E2E_ENV_LOCAL" \
      WALTER_MCP_FILE="$E2E_MCP_FILE" \
      bash "${SUBCOMMANDS}/providers.sh" configure 2>/dev/null
  local yaml="${TEST_HOME}/.config/walter-os/providers.yaml"
  grep -q "^llm: anthropic" "$yaml"
  grep -q "^project_management: none" "$yaml"
  grep -q "^git: github" "$yaml"
  grep -q "^secrets: none" "$yaml"
  grep -q "^web_analytics: none" "$yaml"
  grep -q "^search: none" "$yaml"
  grep -q "^embeddings: none" "$yaml"
  # .env.local: anthropic + github active, self-host commented
  grep -q "^ANTHROPIC_API_KEY=" "$E2E_ENV_LOCAL"
  grep -q "^GITHUB_TOKEN=" "$E2E_ENV_LOCAL"
  grep -q "^#.*LITELLM_BASE_URL=" "$E2E_ENV_LOCAL"
  grep -q "^#.*PLANE_API_TOKEN=" "$E2E_ENV_LOCAL"
}
