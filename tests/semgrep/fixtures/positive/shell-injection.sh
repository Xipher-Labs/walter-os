#!/usr/bin/env bash
# POSITIVE fixture: should trip walter-os-eval-with-variable
# and walter-os-bash-c-with-variable.
# shellcheck disable=all

CMD="ls -la"
eval "$CMD"

# Unquoted eval (worse).
eval $CMD

# bash -c with interpolation.
bash -c "echo $CMD"

# sh -c variant.
sh -c "ls $HOME"
