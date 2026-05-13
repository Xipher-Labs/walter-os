#!/usr/bin/env bash
# Mock LLM script for contradiction detection tests.
# Reads stdin prompt; if it contains both "1232" and "1644", answers YES.
# Otherwise answers NO.
# Usage: echo "prompt" | mock-llm-contradiction.sh

input="$(cat)"
if echo "$input" | grep -q "1232" && echo "$input" | grep -q "1644"; then
  echo "YES - These pages contradict each other: one states 1232 bytes, the other 1644 bytes."
else
  echo "NO - These pages do not contradict each other."
fi
