#!/usr/bin/env bats
# tests/hooks/capability-check.bats
#
# OSS Trust #122 / capability-tokens AC-3.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/capability-check.sh"
  CLI="$REPO_ROOT/bin/walter-os"
  SESSION_LIB="$REPO_ROOT/scripts/walter/lib/session-state.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export WALTER_CONFIG="$TMP_HOME/.config/walter-os"
  export WALTER_OS_HOME="$REPO_ROOT"
  export WALTER_SESSION_TEST_CLOCK=1
  export WALTER_SESSION_NOW_EPOCH=1767225600
  REPO_UNDER_TEST="$TMP_HOME/work/repo"
  mkdir -p "$WALTER_CONFIG" "$REPO_UNDER_TEST"
  bash -c "source '$SESSION_LIB'; _walter_session_openssl" >/dev/null \
    || skip "ED25519-capable openssl required"
}

teardown() {
  chmod -R u+w "$TMP_HOME" 2>/dev/null || true
  case "$TMP_HOME" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -r "$TMP_HOME" ;;
  esac
}

_hook_json() {
  local tool="$1" key="$2" value="$3"
  printf '{"tool_name":"%s","tool_input":{"%s":%s}}' \
    "$tool" "$key" "$(printf '%s' "$value" | jq -Rs .)" \
    | WALTER_SESSION_REPO="$REPO_UNDER_TEST" bash "$HOOK"
}

_mint() {
  (cd "$REPO_UNDER_TEST" && "$CLI" cap mint "$@")
}

@test "malformed hook JSON fails closed" {
  output="$(printf '{"tool_name":"Bash"' | WALTER_SESSION_REPO="$REPO_UNDER_TEST" bash "$HOOK")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "empty hook JSON fails closed" {
  output="$(printf '' | WALTER_SESSION_REPO="$REPO_UNDER_TEST" bash "$HOOK")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash hook event without command fails closed" {
  output="$(printf '{"tool_name":"Bash","tool_input":{}}' | WALTER_SESSION_REPO="$REPO_UNDER_TEST" bash "$HOOK")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "hook sources libraries from its own checkout" {
  output="$(WALTER_OS_HOME="$TMP_HOME/other-checkout" _hook_json Bash command "echo hello")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "high-tier Bash egress without capability is blocked" {
  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'no valid token'
}

@test "semicolon-adjacent Bash egress without capability is blocked" {
  output="$(_hook_json Bash command "true;curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash egress with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress with query-only URL matches host capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com?per_page=1")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress lowercases and trims URL shell punctuation" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://API.GITHUB.COM;")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress with IPv6 literal matches bracket capability" {
  _mint Bash --network '[::1]' --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl http://[::1]:8080")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "network wildcard matches any host" {
  _mint Bash --network '*' --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://evil.example")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "network subdomain wildcard matches subdomains only" {
  _mint Bash --network '*.github.com' --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "allow"'

  output="$(_hook_json Bash command "curl https://github.com")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "absolute-path curl without capability is blocked" {
  output="$(_hook_json Bash command "/usr/bin/curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "absolute-path curl with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "/usr/bin/curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "git ssh URL with matching network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "git clone ssh://git@github.com/org/repo")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "absolute-path git fetch is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "/opt/homebrew/bin/git fetch")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "git fetch behind global flags is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git -C /tmp/repo fetch origin")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh api is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh api with github.com network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "compound gh commands require every hostname capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh --hostname github.com api repos/Xipher-Labs/walter-os && gh --hostname evil.example api repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh pr approve requires pattern capability beyond github.com network" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh pr review 244 --approve")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh pr approve with repo flag requires pattern capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh -R Xipher-Labs/walter-os pr review 244 --approve")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "ssh with github.com network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh git@github.com")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "ssh with option argument extracts destination host" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -p 2222 git@github.com")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "ssh jump host requires its own network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -J evil.example git@github.com")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "ssh lowercases and trims positional host punctuation" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh git@GitHub.com;")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "scp skips local path before remote destination" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "scp file.txt git@github.com:/tmp/file.txt")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "nc with github.com network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "nc github.com 443")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "npm install is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "npm install left-pad")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "npm install behind global flags is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "npm --prefix ui install left-pad")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "local npm test remains low-tier without capability" {
  output="$(_hook_json Bash command "npm test")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "quoted network command example remains low-tier" {
  output="$(_hook_json Bash command "printf '%s\n' 'curl https://api.github.com'")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress requires capability coverage for every destination" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y && curl https://uploads.github.com/upload")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash egress with all network destinations covered is allowed" {
  _mint Bash --network api.github.com --network uploads.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y && curl https://uploads.github.com/upload")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress with matching pattern capability is allowed" {
  _mint Bash --patterns '^curl[[:space:]].*api[.]github[.]com' --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "argument-less git fetch is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git fetch")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "argument-less git fetch with matching pattern capability is allowed" {
  _mint Bash --patterns '^git[[:space:]]+fetch$' --duration 30m >/dev/null

  output="$(_hook_json Bash command "git fetch")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash command with matching pattern capability is allowed" {
  _mint Bash --patterns '^gh[[:space:]]+pr[[:space:]]+review.*--approve' --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh pr review 243 --approve")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "expired capability is ignored and high-tier Bash blocks" {
  _mint Bash --network api.github.com --duration 5m >/dev/null
  export WALTER_SESSION_NOW_EPOCH=1767225961

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "low-tier Bash with no capability passes through" {
  output="$(_hook_json Bash command "echo hello")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "walter-os cap mint bootstraps without requiring an existing cap" {
  output="$(_hook_json Bash command "walter-os cap mint Bash --network api.github.com --duration 30m")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "walter-os cap mint with quoted regex alternation bootstraps" {
  output="$(_hook_json Bash command "walter-os cap mint Bash --patterns 'curl|wget' --duration 30m")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "compound cap mint plus egress still requires capability" {
  output="$(_hook_json Bash command "walter-os cap mint Bash --network github.com --duration 30m; curl https://evil.example")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "newline cap mint plus egress still requires capability" {
  output="$(_hook_json Bash command $'walter-os cap mint Bash --network github.com --duration 30m\ncurl https://evil.example')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write with matching path capability is allowed" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "docs/specs/example.md")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "medium-tier Write without capability passes through" {
  output="$(_hook_json Write file_path "docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write absolute repo path matches relative path capability" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "$REPO_UNDER_TEST/docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write without matching path capability is blocked" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "hooks/approval-gate.sh")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "Write dot-relative protected path without capability is blocked" {
  output="$(_hook_json Write file_path "./install.sh")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write path traversal to protected path without capability is blocked" {
  output="$(_hook_json Write file_path "docs/../hooks/approval-gate.sh")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write absolute reentry traversal to protected path is blocked" {
  output="$(_hook_json Write file_path "$REPO_UNDER_TEST/../$(basename "$REPO_UNDER_TEST")/hooks/approval-gate.sh")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "NotebookEdit sensitive notebook_path without capability is blocked" {
  output="$(_hook_json NotebookEdit notebook_path "personal/health/notes.ipynb")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "NotebookEdit sensitive notebook_path with matching capability is allowed" {
  _mint NotebookEdit --paths 'personal/health/**' --duration 30m >/dev/null

  output="$(_hook_json NotebookEdit notebook_path "personal/health/notes.ipynb")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "two-factor Bash bypass allows high-tier no-cap command with warning" {
  export WALTER_CAP_BYPASS=1

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y --allow-no-cap")"
  echo "$output" | jq -e '.decision == "allow" and (.systemMessage | test("capability-check"))'
}
