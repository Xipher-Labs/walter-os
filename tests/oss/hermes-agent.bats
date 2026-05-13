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
