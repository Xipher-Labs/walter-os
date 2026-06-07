#!/usr/bin/env bats
# tests/walter/providers-detect.bats
# Covers: C-11 — litellm detection requires BOTH LITELLM_BASE_URL and LITELLM_API_KEY

DETECT_SH="$BATS_TEST_DIRNAME/../../scripts/walter/lib/providers/detect.sh"

setup() {
  # Start from a clean env — unset all LLM-related vars
  unset LITELLM_BASE_URL LITELLM_API_KEY ANTHROPIC_API_KEY ANTHROPIC_ENTERPRISE_KEY OPENAI_API_KEY GEMINI_API_KEY OLLAMA_BASE_URL
}

@test "detect_provider llm: LITELLM_API_KEY alone does NOT return litellm" {
  # shellcheck source=/dev/null
  source "$DETECT_SH"
  export LITELLM_API_KEY="sk-test-key"
  result="$(detect_provider llm)"
  [[ "$result" != "litellm" ]]
}

@test "detect_provider llm: LITELLM_BASE_URL alone does NOT return litellm" {
  # shellcheck source=/dev/null
  source "$DETECT_SH"
  export LITELLM_BASE_URL="http://litellm:4000"
  result="$(detect_provider llm)"
  [[ "$result" != "litellm" ]]
}

@test "detect_provider llm: both LITELLM_BASE_URL and LITELLM_API_KEY returns litellm" {
  # shellcheck source=/dev/null
  source "$DETECT_SH"
  export LITELLM_BASE_URL="http://litellm:4000"
  export LITELLM_API_KEY="sk-test-key"
  result="$(detect_provider llm)"
  [[ "$result" == "litellm" ]]
}

@test "detect_provider llm: GEMINI_API_KEY returns gemini" {
  # shellcheck source=/dev/null
  source "$DETECT_SH"
  export GEMINI_API_KEY="gemini-test-key"
  result="$(detect_provider llm)"
  [[ "$result" == "gemini" ]]
}
