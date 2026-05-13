#!/usr/bin/env bash
# POSITIVE fixture: this file SHOULD trip
# walter-os-python-eval-injection / walter-os-python-triple-quote-interpolation.
# DO NOT "fix" these — they exist to validate the rules.
# shellcheck disable=all

# Variant 1: triple-quoted interpolation (the exact bug PR #27 caught).
VAR="hello"
python3 -c "x = '''$VAR'''; print(x)"

# Variant 2: double-quoted interpolation.
SCORE="0.5"
python3 -c "import sys; print(float('$SCORE'))"

# Variant 3: braced variable.
PAYLOAD="data"
python3 -c "print('${PAYLOAD}')"
