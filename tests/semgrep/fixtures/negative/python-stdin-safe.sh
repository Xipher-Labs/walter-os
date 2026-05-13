#!/usr/bin/env bash
# NEGATIVE fixture: the SAFE patterns. Should NOT trigger any rule.
# shellcheck disable=all

VAR="hello"

# Safe pattern 1: pipe via stdin, read sys.stdin in Python.
printf '%s' "$VAR" | python3 -c "import sys; data = sys.stdin.read(); print(data)"

# Safe pattern 2: pass via env var, read os.environ.
PAYLOAD="data" python3 -c "import os; print(os.environ['PAYLOAD'])"

# Safe pattern 3: no interpolation at all.
python3 -c "import json; print(json.dumps([]))"

# Safe pattern 4: pass as positional argument.
SCORE="0.5"
python3 -c "import sys; print(float(sys.argv[1]))" "$SCORE"
