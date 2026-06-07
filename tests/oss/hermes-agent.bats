#!/usr/bin/env bats
# tests/oss/hermes-agent.bats
# AC-9: Hermes Agent service files are well-formed.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SERVICE_DIR="$REPO_ROOT/setup/walter-host/services/hermes-agent"

@test "compose.yml exists" {
    [ -f "$SERVICE_DIR/compose.yml" ]
}

@test "compose.yml contains no :latest tags" {
    run grep ":latest" "$SERVICE_DIR/compose.yml"
    [ "$status" -ne 0 ]
}

@test "compose.yml has a healthcheck" {
    grep -q "healthcheck:" "$SERVICE_DIR/compose.yml"
}

@test "compose.yml references litellm_net or similar named network" {
    grep -q "litellm_net" "$SERVICE_DIR/compose.yml"
}

@test ".env.template has LLM backend section" {
    grep -q "LLM backend" "$SERVICE_DIR/.env.template"
}

@test ".env.template declares the Hermes base image version" {
    grep -q '^HERMES_AGENT_BASE_VERSION=v[0-9]' "$SERVICE_DIR/.env.template"
    grep -q '^HERMES_AGENT_BASE_IMAGE_REF=nousresearch/hermes-agent:v[0-9].*@sha256:[a-f0-9]\{64\}$' "$SERVICE_DIR/.env.template"
}

@test ".env.template has LITELLM_HERMES_KEY" {
    grep -q "LITELLM_HERMES_KEY" "$SERVICE_DIR/.env.template"
}

@test ".env.template has API server section" {
    grep -q "HERMES_API_SERVER_ENABLED" "$SERVICE_DIR/.env.template"
}

@test ".env.template has Curator section" {
    grep -q "HERMES_CURATOR_ENABLED" "$SERVICE_DIR/.env.template"
}

@test ".env.template has platform integrations section" {
    grep -q "HERMES_TELEGRAM_BOT_TOKEN" "$SERVICE_DIR/.env.template"
}

@test "SUGGESTIONS.md has all 5 required sections" {
    grep -q "## 1\. When to use Hermes Agent vs OpenClaw" "$SERVICE_DIR/SUGGESTIONS.md"
    grep -q "## 2\. When to use Hermes Agent vs not at all" "$SERVICE_DIR/SUGGESTIONS.md"
    grep -q "## 3\. Configuring the skill-learning" "$SERVICE_DIR/SUGGESTIONS.md"
    grep -q "## 4\. Connecting to Walter-Bridge" "$SERVICE_DIR/SUGGESTIONS.md"
    grep -q "## 5\. Platform integrations" "$SERVICE_DIR/SUGGESTIONS.md"
}

@test "Caddy stanza exists for hermes domain" {
    CADDY="$REPO_ROOT/setup/walter-host/caddy/Caddyfile.template"
    [ -f "$CADDY" ]
    grep -q 'hermes\.' "$CADDY"
}

@test "Dockerfile re-declares BASE_VERSION after FROM for labels" {
    awk '
        /^FROM / { after_from=1; next }
        after_from && /^ARG BASE_VERSION$/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$SERVICE_DIR/Dockerfile"
    awk '
        /^FROM / { after_from=1; next }
        after_from && /^ARG BASE_IMAGE_REF$/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$SERVICE_DIR/Dockerfile"
}

@test "Dockerfile pins faster-whisper version" {
    grep -q 'faster-whisper==${FASTER_WHISPER_VERSION}' "$SERVICE_DIR/Dockerfile"
    grep -q '^ARG FASTER_WHISPER_VERSION=[0-9]' "$SERVICE_DIR/Dockerfile"
}

@test "Dockerfile uses uv supported no-cache flag" {
    grep -q -- '--no-cache' "$SERVICE_DIR/Dockerfile"
    run grep -q -- '--no-cache-dir' "$SERVICE_DIR/Dockerfile"
    [ "$status" -ne 0 ]
}

@test "Dockerfile persists Hugging Face cache under hermes_data volume" {
    grep -q '^ENV HF_HOME=/opt/data/.cache/huggingface$' "$SERVICE_DIR/Dockerfile"
}

@test ".dockerignore keeps local secrets out of build context" {
    [ -f "$SERVICE_DIR/.dockerignore" ]
    grep -q '^\.env$' "$SERVICE_DIR/.dockerignore"
    grep -q '^\.env\.\*$' "$SERVICE_DIR/.dockerignore"
    grep -q '^\*\.pem$' "$SERVICE_DIR/.dockerignore"
    grep -q '^\*\.key$' "$SERVICE_DIR/.dockerignore"
}

@test "compose.yml uses one Hermes base version variable for image and build arg" {
    expected_version="$(sed -n 's/^HERMES_AGENT_BASE_VERSION=//p' "$SERVICE_DIR/.env.template")"
    expected_ref="$(sed -n 's/^HERMES_AGENT_BASE_IMAGE_REF=//p' "$SERVICE_DIR/.env.template")"
    [ -n "$expected_version" ]
    [ -n "$expected_ref" ]
    grep -q "^ARG BASE_VERSION=${expected_version}$" "$SERVICE_DIR/Dockerfile"
    grep -q "^ARG BASE_IMAGE_REF=${expected_ref}$" "$SERVICE_DIR/Dockerfile"
    grep -q "image: walter-os/hermes-agent:\${HERMES_AGENT_BASE_VERSION:-${expected_version}}-stt" "$SERVICE_DIR/compose.yml"
    grep -q "BASE_VERSION: \${HERMES_AGENT_BASE_VERSION:-${expected_version}}" "$SERVICE_DIR/compose.yml"
    grep -q "BASE_IMAGE_REF: \${HERMES_AGENT_BASE_IMAGE_REF:-${expected_ref}}" "$SERVICE_DIR/compose.yml"
}

@test "services inventory documents the Walter Hermes STT image" {
    grep -q 'walter-os/hermes-agent:${HERMES_AGENT_BASE_VERSION}-stt' "$REPO_ROOT/setup/SERVICES-INVENTORY.md"
}
