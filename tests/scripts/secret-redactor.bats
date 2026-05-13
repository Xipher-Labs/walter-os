#!/usr/bin/env bats
# Tests for scripts/agent-secret-redactor.sh
#
# Background: agent-secret-redactor.sh sanitizes agent stdout/stderr before
# it lands in audit logs, Plane comments, Telegram messages, lessons.db.
# A regression in the Perl regex (the `|` delimiter clashed with `|` inside
# alternations like `(sk|rk|pk)`) made the script exit 255 with no output,
# silently disabling redaction system-wide. Phase M reviewer round 1 caught it.
#
# These tests pin the contract: every supported pattern is redacted, the
# script always exits 0, redaction is idempotent, and normal prose is left
# alone.

setup() {
  REDACTOR="$BATS_TEST_DIRNAME/../../scripts/agent-secret-redactor.sh"
  [[ -x "$REDACTOR" ]] || skip "agent-secret-redactor.sh not found / not executable"
}

# Helper: run the redactor over a string and stash output + status.
run_redact() {
  run bash -c "printf '%s' \"\$1\" | '$REDACTOR'" -- "$1"
}

stripe_key() {
  printf '%s_%s_%s' "$1" "$2" "$3"
}

prefixed_key() {
  printf '%s%s' "$1" "$2"
}

# -------- Exit code contract -----------------------------------------------

@test "exits 0 on plain text" {
  run_redact "hello world, nothing to see"
  [ "$status" -eq 0 ]
}

@test "exits 0 on input with secrets" {
  run_redact "$(prefixed_key sk-ant- aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)"
  [ "$status" -eq 0 ]
}

@test "exits 0 on empty input" {
  run bash -c "printf '' | '$REDACTOR'"
  [ "$status" -eq 0 ]
}

# -------- Stripe ------------------------------------------------------------

@test "redacts Stripe live secret key (sk_live_)" {
  key="$(stripe_key sk live AAAAAAAAAAAAAAAAAAAAAAAA)"
  run_redact "key=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:stripe>"* ]]
  [[ "$output" != *"$(stripe_key sk live AAAA)"* ]]
}

@test "redacts Stripe live restricted key (rk_live_)" {
  key="$(stripe_key rk live BBBBBBBBBBBBBBBBBBBBBBBB)"
  run_redact "key=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:stripe>"* ]]
  [[ "$output" != *"$(stripe_key rk live BBBB)"* ]]
}

@test "redacts Stripe live publishable key (pk_live_)" {
  key="$(stripe_key pk live CCCCCCCCCCCCCCCCCCCCCCCC)"
  run_redact "key=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:stripe>"* ]]
  [[ "$output" != *"$(stripe_key pk live CCCC)"* ]]
}

@test "redacts Stripe test keys (sk_test_, rk_test_, pk_test_)" {
  secret="$(stripe_key sk test 111111111111111111111111)"
  restricted="$(stripe_key rk test 222222222222222222222222)"
  publishable="$(stripe_key pk test 333333333333333333333333)"
  run_redact "$secret $restricted $publishable"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$(stripe_key sk test 1111)"* ]]
  [[ "$output" != *"$(stripe_key rk test 2222)"* ]]
  [[ "$output" != *"$(stripe_key pk test 3333)"* ]]
  # Three matches expected.
  matches=$(grep -o "<REDACTED:stripe>" <<<"$output" | wc -l | tr -d ' ')
  [ "$matches" -eq 3 ]
}

# -------- Anthropic / OpenAI / Google --------------------------------------

@test "redacts Anthropic API key (sk-ant-)" {
  key="$(prefixed_key sk-ant- aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)"
  run_redact "ANTHROPIC_API_KEY=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:anthropic>"* ]]
  [[ "$output" != *"$(prefixed_key sk-ant- aaaa)"* ]]
}

@test "redacts OpenAI legacy API key (sk-)" {
  key="$(prefixed_key sk- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)"
  run_redact "OPENAI_API_KEY=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:openai>"* ]]
  [[ "$output" != *"$(prefixed_key sk- AAAAAAAAAAAAAAAA)"* ]]
}

@test "redacts OpenAI project key (sk-proj-)" {
  key="$(prefixed_key sk-proj- ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ)"
  run_redact "OPENAI_API_KEY=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:openai>"* ]]
  [[ "$output" != *"$(prefixed_key sk-proj- ZZZZ)"* ]]
}

@test "redacts Google API key (AIza)" {
  key="$(prefixed_key AIza SyABCDEFGHIJKLMNOPQRSTUVWXYZ0123456)"
  run_redact "GOOGLE_API_KEY=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:google>"* ]]
  [[ "$output" != *"$(prefixed_key AIza SyABCDE)"* ]]
}

# -------- GitHub / GitLab / Slack ------------------------------------------

@test "redacts GitHub PAT (ghp_)" {
  run_redact "$(prefixed_key ghp_ AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:github>"* ]]
}

@test "redacts GitHub OAuth (gho_)" {
  run_redact "$(prefixed_key gho_ BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:github>"* ]]
}

@test "redacts GitHub server (ghs_) and user (ghu_) tokens" {
  server="$(prefixed_key ghs_ CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC)"
  user="$(prefixed_key ghu_ DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD)"
  run_redact "$server $user"
  [ "$status" -eq 0 ]
  matches=$(grep -o "<REDACTED:github>" <<<"$output" | wc -l | tr -d ' ')
  [ "$matches" -eq 2 ]
}

@test "redacts GitLab PAT (glpat-)" {
  key="$(prefixed_key glpat- AAAAAAAAAAAAAAAAAAAA)"
  run_redact "GITLAB_TOKEN=$key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:gitlab>"* ]]
  [[ "$output" != *"$(prefixed_key glpat- AAAA)"* ]]
}

@test "redacts Slack bot/app/user token" {
  sample="xoxb-1234567890-"
  sample+="1234567890-"
  sample+="abcdefghijklmnop"
  run_redact "$sample"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:slack>"* ]]
}

# -------- JWT --------------------------------------------------------------

@test "redacts JWT (eyJ header + 2 segments)" {
  # Synthetic header.payload.signature; all start with eyJ as standard JWTs do.
  sample="eyJhbGciOiJIUzI1NiJ9."
  sample+="eyJzdWIiOiIxMjM0NTY3ODkwIn0."
  sample+="SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
  run_redact "Authorization: $sample"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:jwt>"* ]]
  [[ "$output" != *"eyJzdWIi"* ]]
}

# -------- AWS --------------------------------------------------------------

@test "redacts AWS access key ID (AKIA + 16 upper alnum)" {
  sample="AKIA"
  sample+="ABCDEFGHIJKLMNOP"
  run_redact "aws_access_key_id=$sample"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:aws-access>"* ]]
  [[ "$output" != *"$sample"* ]]
}

# -------- Private keys (multi-line PEM) ------------------------------------

@test "redacts RSA private key PEM block" {
  pem="-----BEGIN RSA PRIVATE"" KEY-----"$'\n'
  pem+="MIIEpAIBAAKCAQEAvQLkdmVfake1"$'\n'
  pem+="fakeBASE64fakeBASE64fakeBASE6"$'\n'
  pem+="-----END RSA PRIVATE"" KEY-----"
  run_redact "$pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:private-key>"* ]]
  [[ "$output" != *"MIIEpAIBAAKCAQ"* ]]
}

@test "redacts generic PRIVATE KEY PEM block (no algo prefix)" {
  pem="-----BEGIN PRIVATE"" KEY-----"$'\n'
  pem+="MIIfakeBASE64payload"$'\n'
  pem+="-----END PRIVATE"" KEY-----"
  run_redact "$pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:private-key>"* ]]
  [[ "$output" != *"MIIfakeBASE64payload"* ]]
}

@test "redacts EC private key PEM block" {
  pem="-----BEGIN EC PRIVATE"" KEY-----"$'\n'
  pem+="MHcCAQEEIfakeECbase64payload"$'\n'
  pem+="-----END EC PRIVATE"" KEY-----"
  run_redact "$pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:private-key>"* ]]
  [[ "$output" != *"MHcCAQEEIfake"* ]]
}

# -------- Bearer tokens ----------------------------------------------------

@test "redacts Bearer token in Authorization header" {
  run_redact "Authorization: Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:bearer>"* ]]
  [[ "$output" != *"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]]
}

# -------- Generic VAR=secret pattern ---------------------------------------

@test "redacts generic API_KEY=... assignment" {
  run_redact "API_KEY=verysecretstringthatislongenough123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:generic>"* ]]
}

@test "redacts generic SECRET=... assignment" {
  run_redact "SECRET=verysecretstringthatislongenough123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:generic>"* ]]
}

# -------- Idempotency ------------------------------------------------------

@test "redacting an already-redacted string is a no-op" {
  run_redact "value=<REDACTED:anthropic>"
  [ "$status" -eq 0 ]
  [[ "$output" == "value=<REDACTED:anthropic>" ]]
}

@test "double redaction yields same output" {
  raw="key=$(stripe_key sk live AAAAAAAAAAAAAAAAAAAAAAAA)"
  once=$(printf '%s' "$raw" | "$REDACTOR")
  twice=$(printf '%s' "$once" | "$REDACTOR")
  [ "$once" = "$twice" ]
}

# -------- No false positives on normal prose -------------------------------

@test "plain English passes through unchanged" {
  raw="The deployment is healthy and no errors were logged."
  run_redact "$raw"
  [ "$status" -eq 0 ]
  [ "$output" = "$raw" ]
}

@test "Spanish prose with accents passes through unchanged" {
  raw="La integración funcionó después del último despliegue."
  run_redact "$raw"
  [ "$status" -eq 0 ]
  [ "$output" = "$raw" ]
}

@test "short identifiers (under threshold) pass through" {
  raw="user_id=42 name=alice short_key=ab12"
  run_redact "$raw"
  [ "$status" -eq 0 ]
  [ "$output" = "$raw" ]
}

@test "URL with query string passes through" {
  raw="GET https://example.com/api?page=1&sort=desc"
  run_redact "$raw"
  [ "$status" -eq 0 ]
  [ "$output" = "$raw" ]
}

# -------- Multiline / streaming -------------------------------------------

@test "redacts secrets across multiple lines" {
  multi="line1: sk-ant-""aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"$'\n'
  multi+="line2: plain text"$'\n'
  multi+="line3: AKIA""ABCDEFGHIJKLMNOP"
  run_redact "$multi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<REDACTED:anthropic>"* ]]
  [[ "$output" == *"<REDACTED:aws-access>"* ]]
  [[ "$output" == *"line2: plain text"* ]]
}
