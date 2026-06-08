#!/usr/bin/env bats
# Tests for hooks/daily-audit-gate.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/daily-audit-gate.sh"

  TMPDIR_TEST="$(mktemp -d)"
  export HOME="$TMPDIR_TEST"
  export WALTER_CONFIG="$TMPDIR_TEST/.config/walter-os"
  mkdir -p "$WALTER_CONFIG"
  TODAY="$(date +%Y-%m-%d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "allows when no audit script exists" {
  # Empty WALTER_OS_HOME, no audit script
  export WALTER_OS_HOME="$TMPDIR_TEST/walter-os"
  result="$("$HOOK" </dev/null)"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows when today's audit is clean (severity 0)" {
  cat > "$WALTER_CONFIG/audit-${TODAY}.md" <<EOF
# Audit
EOF
  jq -n --arg date "$TODAY" '{date:$date,severity:0,info:0,high:0,critical:0}' \
    > "$WALTER_CONFIG/audit-status.json"
  result="$("$HOOK" </dev/null)"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
}

@test "allows with banner when severity is HIGH (2)" {
  cat > "$WALTER_CONFIG/audit-${TODAY}.md" <<EOF
# Audit
EOF
  jq -n --arg date "$TODAY" '{date:$date,severity:2,info:0,high:1,critical:0}' \
    > "$WALTER_CONFIG/audit-status.json"
  result="$("$HOOK" </dev/null)"
  [ "$(jq -r '.decision' <<<"$result")" = "allow" ]
  msg="$(jq -r '.systemMessage // ""' <<<"$result")"
  [[ "$msg" == *"HIGH"* ]]
}

@test "blocks when severity is CRITICAL (3)" {
  jq -n --arg date "$TODAY" '{date:$date,severity:3,info:0,high:0,critical:1}' \
    > "$WALTER_CONFIG/audit-status.json"
  result="$("$HOOK" </dev/null)"
  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}

@test "env file cannot redirect audit status root" {
  evil_cfg="$TMPDIR_TEST/evil-config"
  mkdir -p "$evil_cfg"
  jq -n --arg date "$TODAY" '{date:$date,severity:3,info:0,high:0,critical:1}' \
    > "$WALTER_CONFIG/audit-status.json"
  jq -n --arg date "$TODAY" '{date:$date,severity:0,info:0,high:0,critical:0}' \
    > "$evil_cfg/audit-status.json"
  echo "WALTER_CONFIG=$evil_cfg" > "$WALTER_CONFIG/env"

  result="$("$HOOK" </dev/null)"

  [ "$(jq -r '.decision' <<<"$result")" = "block" ]
}
