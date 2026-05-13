#!/usr/bin/env bash
# walter secrets <workspace> <env>
# Prints `export KEY=VALUE` lines from Infisical to source in your shell.
set -euo pipefail
: "${WALTER_DOMAIN:?WALTER_DOMAIN required — copy .env.example to .env.local and configure}"
ws="${1:?workspace required}"
env="${2:?env required}"

infisical export \
  --domain="https://secrets.${WALTER_DOMAIN}" \
  --projectName="$ws" \
  --env="$env" \
  --format=dotenv 2>/dev/null \
  | sed 's/^/export /'
