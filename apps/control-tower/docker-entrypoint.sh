#!/bin/sh
set -eu

default_state_dir="/var/lib/walter-os/control-tower"

if [ -z "${WALTER_CONFIG_DIR:-}" ] && [ -n "${WALTER_CONFIG:-}" ]; then
  export WALTER_CONFIG_DIR="$WALTER_CONFIG"
fi

if [ -z "${WALTER_CONFIG:-}" ] && [ -n "${WALTER_CONFIG_DIR:-}" ]; then
  export WALTER_CONFIG="$WALTER_CONFIG_DIR"
fi

export WALTER_CONFIG="${WALTER_CONFIG:-$default_state_dir}"
export WALTER_CONFIG_DIR="${WALTER_CONFIG_DIR:-$WALTER_CONFIG}"

mkdir -p "$WALTER_CONFIG_DIR"
chown -R node:node "$WALTER_CONFIG_DIR"
chmod 700 "$WALTER_CONFIG_DIR"

exec su-exec node "$@"
