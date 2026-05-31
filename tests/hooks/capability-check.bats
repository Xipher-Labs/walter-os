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

@test "Bash access to capability bearer tokens is high-tier" {
  output="$(_hook_json Bash command 'cat ~/.config/walter-os/state/caps-abc/cap-token.paseto')"

  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'no valid token'
}

@test "high-tier enforcement without python3 fails closed with actionable reason" {
  mkdir -p "$BATS_TEST_TMPDIR/no-python-bin"
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/no-python-bin/dirname"
  ln -s "$(command -v jq)" "$BATS_TEST_TMPDIR/no-python-bin/jq"
  ln -s "$(command -v mktemp)" "$BATS_TEST_TMPDIR/no-python-bin/mktemp"
  ln -s "$(command -v rm)" "$BATS_TEST_TMPDIR/no-python-bin/rm"

  input="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "curl https://api.github.com/repos/x/y" | jq -Rs .)")"
  output="$(printf '%s' "$input" \
    | PATH="$BATS_TEST_TMPDIR/no-python-bin" WALTER_SESSION_REPO="$REPO_UNDER_TEST" /bin/bash "$HOOK")"

  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'python3 is required'
}

@test "low-tier Bash without python3 passes through" {
  mkdir -p "$BATS_TEST_TMPDIR/no-python-bin"
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/no-python-bin/dirname"
  ln -s "$(command -v jq)" "$BATS_TEST_TMPDIR/no-python-bin/jq"
  ln -s "$(command -v mktemp)" "$BATS_TEST_TMPDIR/no-python-bin/mktemp"
  ln -s "$(command -v rm)" "$BATS_TEST_TMPDIR/no-python-bin/rm"

  input="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "echo hello" | jq -Rs .)")"
  output="$(printf '%s' "$input" \
    | PATH="$BATS_TEST_TMPDIR/no-python-bin" WALTER_SESSION_REPO="$REPO_UNDER_TEST" /bin/bash "$HOOK")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "invalid pattern capability is a quiet non-match" {
  _mint Bash --patterns '[' --duration 30m >/dev/null

  input="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "curl https://api.github.com/repos/x/y" | jq -Rs .)")"
  run /bin/bash -c 'printf "%s" "$1" | WALTER_SESSION_REPO="$2" bash "$3"' _ "$input" "$REPO_UNDER_TEST" "$HOOK"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  ! grep -qi 'grep' <<< "$output"
}

@test "high-tier block reason summarizes multiline targets" {
  long_command=$'curl https://api.github.com/repos/x/y\nprintf secret'

  output="$(_hook_json Bash command "$long_command")"

  echo "$output" | jq -e '.decision == "block"'
  reason="$(echo "$output" | jq -er '.reason')"
  [[ "$reason" != *$'\n'* ]]
}

@test "semicolon-adjacent Bash egress without capability is blocked" {
  output="$(_hook_json Bash command "true;curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "backtick Bash egress without capability is blocked" {
  output="$(_hook_json Bash command 'echo `curl https://api.github.com/repos/x/y`')"

  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -er '.reason' | grep -q 'no valid token'
}

@test "quoted command substitution egress without capability is blocked" {
  output="$(_hook_json Bash command 'echo "$(curl https://api.github.com/repos/x/y)"')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "assignment command substitution egress without capability is blocked" {
  output="$(_hook_json Bash command 'body="$(curl https://api.github.com/repos/x/y)"; echo "$body"')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash tokenization failure is treated as high-tier" {
  output="$(_hook_json Bash command "curl 'https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash egress with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress inside control-flow bodies without capability is blocked" {
  output="$(_hook_json Bash command "{ curl https://api.github.com/repos/x/y; }")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "if curl https://api.github.com/repos/x/y; then :; fi")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "while curl https://api.github.com/repos/x/y; do break; done")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "Bash egress inside control-flow bodies allows matching capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "{ curl https://api.github.com/repos/x/y; }")"
  echo "$output" | jq -e '.decision == "allow"'

  output="$(_hook_json Bash command "if curl https://api.github.com/repos/x/y; then :; fi")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "Bash egress matches normalized network capability values" {
  _mint Bash --network HTTPS://API.GITHUB.COM/repos/example --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "adjacent shell separator is stripped from extracted hosts" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl https://api.github.com&&echo ok")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "backtick Bash egress with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command 'echo `curl https://api.github.com/repos/x/y`')"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "quoted command substitution egress with matching capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command 'echo "$(curl https://api.github.com/repos/x/y)"')"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "shell -c Bash egress without capability is blocked" {
  output="$(_hook_json Bash command "sh -c 'curl https://api.github.com/repos/x/y'")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "shell -c Bash egress with matching network capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "bash -c 'curl https://api.github.com/repos/x/y'")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "shell-expanded network command word without capability is blocked" {
  output="$(_hook_json Bash command 'curl${IFS}https://api.github.com/repos/x/y')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "shell-expanded network command word with matching capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command 'curl${IFS}https://api.github.com/repos/x/y')"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "variable-expanded network command word without capability is blocked" {
  output="$(_hook_json Bash command 'cmd=curl; $cmd https://api.github.com/repos/x/y')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "variable-expanded network command word with matching capability is allowed" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command 'cmd=curl; $cmd https://api.github.com/repos/x/y')"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "variable-expanded command word without static URL is blocked" {
  output="$(_hook_json Bash command 'cmd=ssh; $cmd git@github.com')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "variable-expanded command word with matching pattern capability is allowed" {
  _mint Bash --patterns '^cmd=ssh; [$]cmd git@github[.]com$' --duration 30m >/dev/null

  output="$(_hook_json Bash command 'cmd=ssh; $cmd git@github.com')"
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

@test "curl proxy host must be covered by network capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --proxy http://proxy.example:8080 https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "curl socks proxy host must be covered by network capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --socks5 evil.example https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "curl connect-to host must be covered by network capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --connect-to api.github.com:443:evil.example:443 https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "curl proxy host is allowed when all hosts are covered" {
  _mint Bash --network api.github.com --network proxy.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --proxy http://proxy.example:8080 https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "curl resolve host must be covered by network capability" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --resolve api.github.com:443:evil.example https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "curl resolve host is allowed when all hosts are covered" {
  _mint Bash --network api.github.com --network evil.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --resolve api.github.com:443:evil.example https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "curl header URL is not treated as network destination" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl -H 'Referer: https://example.com/x' https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "curl data URL is not treated as network destination" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "curl --data-raw '{\"callback\":\"https://app.example/hook\"}' https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "git ssh URL with matching network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "git clone ssh://git@github.com/org/repo")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "git ssh command override host must be covered" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "GIT_SSH_COMMAND='ssh evil.example' git fetch git@github.com:org/repo")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "git -c core.sshCommand='ssh evil.example' fetch git@github.com:org/repo")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "git ssh command override is allowed when all hosts are covered" {
  _mint Bash --network github.com --network evil.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "GIT_SSH_COMMAND='ssh evil.example' git fetch git@github.com:org/repo")"

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

@test "git submodule update is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git submodule update --init --recursive")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "git extension network subcommands are high-tier" {
  output="$(_hook_json Bash command "git lfs pull")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "git svn fetch")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "git remote update is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git remote update")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "git remote network subcommands are high-tier" {
  output="$(_hook_json Bash command "git remote show origin")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "git remote prune origin")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "git remote set-head origin --auto")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "git remote implicit host operation allows matching pattern capability" {
  _mint Bash --patterns '^git[[:space:]]+remote[[:space:]]+show[[:space:]]+origin$' --duration 30m >/dev/null

  output="$(_hook_json Bash command "git remote show origin")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "git shell alias is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "git -c alias.pwn='!curl https://api.github.com/repos/x/y' pwn")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh api is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "wrapped network commands are high-tier" {
  output="$(_hook_json Bash command "sudo curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "command gh api repos/Xipher-Labs/walter-os")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "wrapped network commands behind wrapper options are high-tier" {
  output="$(_hook_json Bash command "env -u GH_HOST curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "command -p curl https://api.github.com/repos/x/y")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "env split-string network payload is high-tier" {
  output="$(_hook_json Bash command "env -S 'curl https://api.github.com/repos/x/y'")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "command lookup probes remain low-tier" {
  output="$(_hook_json Bash command "command -v curl && command -V gh")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "gh api with github.com network capability is allowed" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "inline GH_HOST requires matching network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "GH_HOST=github.enterprise.example gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "inline GH_HOST with matching network capability is allowed" {
  _mint Bash --network github.enterprise.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "GH_HOST=github.enterprise.example gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "env-wrapped GH_HOST requires matching network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "env GH_HOST=ghe.example gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "env-wrapped GH_HOST with matching network capability is allowed" {
  _mint Bash --network ghe.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "env GH_HOST=ghe.example gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "exported GH_HOST requires matching network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "export GH_HOST=ghe.example; gh api repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh help short flag is not parsed as a hostname override" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh -h pr review 244 --approve")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh hostname flag after subcommand requires matching capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh api --hostname ghe.example repos/Xipher-Labs/walter-os")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh repo host requires matching capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh -R ghe.example/Xipher-Labs/walter-os pr view 244")"

  echo "$output" | jq -e '.decision == "block"'
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

@test "gh pr review short approve flag requires pattern capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh pr review 244 -a")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "shell -c gh pr approve requires pattern capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "sh -c 'gh pr review 244 --approve'")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh pr approve with repo flag requires pattern capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh -R Xipher-Labs/walter-os pr review 244 --approve")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "gh comment body URL is not treated as network destination" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "gh pr comment 244 --body 'see https://example.com for context'")"

  echo "$output" | jq -e '.decision == "allow"'
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

@test "ssh host extraction stops at shell separator" {
  _mint Bash --network api.github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -i key; curl https://api.github.com/repos/x/y")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "ssh jump host requires its own network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -J evil.example git@github.com")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "ssh ProxyCommand host requires its own network capability" {
  _mint Bash --network github.com --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -o 'ProxyCommand=ssh evil.example nc %h %p' git@github.com")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "ssh ProxyCommand with all hosts covered is allowed" {
  _mint Bash --network github.com --network evil.example --duration 30m >/dev/null

  output="$(_hook_json Bash command "ssh -o 'ProxyCommand=ssh evil.example nc %h %p' git@github.com")"

  echo "$output" | jq -e '.decision == "allow"'
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

@test "scp bracketed IPv6 remote path matches network capability" {
  _mint Bash --network '[::1]' --duration 30m >/dev/null

  output="$(_hook_json Bash command "scp file.txt '[::1]:/tmp/file.txt'")"

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

@test "package manager network subcommands are high-tier" {
  output="$(_hook_json Bash command "npm ci")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "npm audit")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "pnpm fetch")"
  echo "$output" | jq -e '.decision == "block"'

  output="$(_hook_json Bash command "yarn info react")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "npm install behind global flags is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "npm --prefix ui install left-pad")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "npm install behind value-taking global flags is high-tier" {
  output="$(_hook_json Bash command "npm --registry https://registry.npmjs.org install left-pad")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "python -m pip install is high-tier and blocked without capability" {
  output="$(_hook_json Bash command "python -m pip install requests")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "pip install behind value-taking global flags is high-tier" {
  output="$(_hook_json Bash command "pip --proxy http://proxy.example install requests")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "python -m pip install behind value-taking flags is high-tier" {
  output="$(_hook_json Bash command "python -m pip --proxy http://proxy.example install requests")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "uv pip install behind value-taking global flags is high-tier" {
  output="$(_hook_json Bash command "uv --directory /tmp/repo pip install requests")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "python -m pip install with matching pattern capability is allowed" {
  _mint Bash --patterns '^python -m pip install requests$' --duration 30m >/dev/null

  output="$(_hook_json Bash command "python -m pip install requests")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "local npm test remains low-tier without capability" {
  output="$(_hook_json Bash command "npm test")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "quoted network command example remains low-tier" {
  output="$(_hook_json Bash command "printf '%s\n' 'curl https://api.github.com'")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "quoted shell-expanded network text remains low-tier" {
  output="$(_hook_json Bash command "echo 'curl\${IFS}https://api.github.com'")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "network CLI names as arguments remain low-tier" {
  output="$(_hook_json Bash command "echo curl && printf '%s\n' gh")"

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

@test "cap mint with command substitution egress requires capability" {
  output="$(_hook_json Bash command 'walter-os cap mint Bash --network $(curl https://evil.example) --duration 30m')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "cap mint with shell-expanded network value requires capability" {
  output="$(_hook_json Bash command 'walter-os cap mint Bash --network $HOST --duration 30m')"

  echo "$output" | jq -e '.decision == "block"'
}

@test "cap mint with braced shell-expanded network value requires capability" {
  output="$(_hook_json Bash command 'walter-os cap mint Bash --network ${HOST} --duration 30m')"

  echo "$output" | jq -e '.decision == "block"'
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
  _mint Write --paths 'hooks/*.sh' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "hooks/example.sh")"
  echo "$output" | jq -e '.decision == "allow"'
}

@test "medium-tier Write without capability passes through" {
  output="$(_hook_json Write file_path "docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write absolute repo path matches relative path capability" {
  _mint Write --paths 'hooks/*.sh' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "$(cd "$REPO_UNDER_TEST" && pwd -P)/hooks/example.sh")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write dot-relative path capability matches target" {
  _mint Write --paths './docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write directory path capability covers descendants" {
  _mint Write --paths 'docs' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "docs/specs/example.md")"

  echo "$output" | jq -e '.decision == "allow"'
}

@test "Write exact path capability does not match suffix elsewhere" {
  _mint Write --paths 'AGENTS.md' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "contexts/work/AGENTS.md")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write without matching path capability is blocked" {
  _mint Write --paths 'docs/**' --duration 30m >/dev/null

  output="$(_hook_json Write file_path "hooks/approval-gate.sh")"
  echo "$output" | jq -e '.decision == "block"'
}

@test "Write capability verifier library without capability is blocked" {
  output="$(_hook_json Write file_path "scripts/walter/lib/capability-token.sh")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write absolute home ssh path is blocked as high-tier" {
  output="$(_hook_json Write file_path "$TMP_HOME/.ssh/id_ed25519")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write capability minting entrypoint without capability is blocked" {
  output="$(_hook_json Write file_path "scripts/walter/subcommands/cap.sh")"

  echo "$output" | jq -e '.decision == "block"'
}

@test "Write walter-os dispatcher without capability is blocked" {
  output="$(_hook_json Write file_path "bin/walter-os")"

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

@test "Write relative reentry traversal to protected path is blocked" {
  output="$(_hook_json Write file_path "../$(basename "$REPO_UNDER_TEST")/hooks/approval-gate.sh")"

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
