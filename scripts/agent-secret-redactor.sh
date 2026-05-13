#!/usr/bin/env bash
# agent-secret-redactor.sh — read stdin, write to stdout with anything
# that looks like a secret replaced by `<REDACTED:type>`.
#
# Defense-in-depth for agent stdout/stderr passing through audit logs,
# Plane comments, Telegram messages, lessons.db. Pattern coverage is
# intentionally generous (false positives accepted; false negatives are
# the failure mode that hurts).
#
# Spec: docs/specs/multi-agent-autonomy.md §11 (rail: no-secrets-in-logs)
#
# Usage:
#   echo "ANTHROPIC_API_KEY=sk-ant-foo..." | agent-secret-redactor.sh
#   → ANTHROPIC_API_KEY=<REDACTED:anthropic>
#
# Pipe-friendly: errors don't kill the stream.
#
# Why `s{...}{...}` instead of `s|...|...|`:
#   Several patterns contain `|` for alternation (Stripe `(sk|rk|pk)`,
#   generic-secret `(API_KEY|TOKEN|...)`). Using `|` as the s/// delimiter
#   makes Perl mis-parse those alternations and exit 255 (the bug this
#   script lived with until Phase M caught it). Paired-brace delimiters
#   are unambiguous.
#
# Why `-0777` (slurp):
#   PEM private-key blocks span multiple lines. Slurp mode lets one regex
#   match the BEGIN..END span. Inputs are bounded (log lines, chat
#   messages, comments), so the memory cost is negligible.

set -uo pipefail

# Prefer perl (PCRE, lookaheads, multiline). Fall back to sed -E otherwise.
if command -v perl >/dev/null 2>&1; then
  exec perl -0777 -pe '
    # ---- multi-line PEM private keys (run first so internal base64
    # cannot accidentally match other patterns) -------------------------
    s{-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z]+ )?PRIVATE KEY-----}{<REDACTED:private-key>}g;

    # ---- LLM provider keys -------------------------------------------
    # Anthropic must come before OpenAI legacy, otherwise OpenAI would
    # swallow "sk-ant-..." once the char class allows hyphens.
    s{sk-ant-[A-Za-z0-9_\-]{40,}}{<REDACTED:anthropic>}g;
    s{sk-proj-[A-Za-z0-9_\-]{40,}}{<REDACTED:openai>}g;
    s{sk-[A-Za-z0-9_\-]{40,}}{<REDACTED:openai>}g;
    s{AIza[0-9A-Za-z_\-]{35}}{<REDACTED:google>}g;

    # ---- Stripe ------------------------------------------------------
    s{(?:sk|rk|pk)_(?:test|live)_[A-Za-z0-9]{24,}}{<REDACTED:stripe>}g;

    # ---- Forge tokens ------------------------------------------------
    s{gh[pousr]_[A-Za-z0-9]{36,}}{<REDACTED:github>}g;
    s{glpat-[A-Za-z0-9\-]{20,}}{<REDACTED:gitlab>}g;

    # ---- Slack -------------------------------------------------------
    s{xox[baprs]-[A-Za-z0-9\-]{10,}}{<REDACTED:slack>}g;

    # ---- JWT (header.payload.signature) ------------------------------
    s{eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+}{<REDACTED:jwt>}g;

    # ---- AWS ---------------------------------------------------------
    s{AKIA[0-9A-Z]{16}}{<REDACTED:aws-access>}g;

    # ---- Bearer tokens in Authorization headers ----------------------
    # Char class excludes <>:, so a previously-redacted "<REDACTED:jwt>"
    # is not re-matched here.
    s{(Authorization:\s*Bearer\s+)[A-Za-z0-9_\-\.=]{20,}}{$1<REDACTED:bearer>}gi;

    # ---- Generic VAR=secret / VAR: secret ----------------------------
    s{(\b(?:API[_-]?KEY|TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE[_-]?KEY)\b\s*[=:]\s*)(["'\'']?)[A-Za-z0-9+/=_\-\.]{16,}\2}{$1<REDACTED:generic>}gi;
  '
fi

# sed fallback — same patterns, no PCRE features. Uses `#` as delimiter
# so `|` (alternation) inside patterns is unambiguous.
exec sed -E \
  -e 's#sk-ant-[A-Za-z0-9_-]{40,}#<REDACTED:anthropic>#g' \
  -e 's#sk-proj-[A-Za-z0-9_-]{40,}#<REDACTED:openai>#g' \
  -e 's#sk-[A-Za-z0-9_-]{40,}#<REDACTED:openai>#g' \
  -e 's#AIza[0-9A-Za-z_-]{35}#<REDACTED:google>#g' \
  -e 's#(sk|rk|pk)_(test|live)_[A-Za-z0-9]{24,}#<REDACTED:stripe>#g' \
  -e 's#gh[pousr]_[A-Za-z0-9]{36,}#<REDACTED:github>#g' \
  -e 's#glpat-[A-Za-z0-9-]{20,}#<REDACTED:gitlab>#g' \
  -e 's#xox[baprs]-[A-Za-z0-9-]{10,}#<REDACTED:slack>#g' \
  -e 's#eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+#<REDACTED:jwt>#g' \
  -e 's#AKIA[0-9A-Z]{16}#<REDACTED:aws-access>#g' \
  -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9_.=-]{20,}#\1<REDACTED:bearer>#g'
