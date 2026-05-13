#!/usr/bin/env bash
# NEGATIVE fixture: safe shell patterns. Should NOT trigger.
# shellcheck disable=all

VAR="value"

# Direct invocation — no eval.
ls -la "$VAR"

# bash -c with positional arg, value never interpolated into code.
bash -c 'echo "$1"' _ "$VAR"

# curl with intermediate file + verification (safe-by-design).
curl -sSL https://example.com/install.sh -o /tmp/install.sh
sha256sum -c /tmp/install.sh.sha256
bash /tmp/install.sh

# Bare 'eval' string in a comment / quoted literal should not match.
echo "we used to use eval here, but no longer"
