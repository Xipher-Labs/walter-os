#!/usr/bin/env bats
# tests/cli/release-doctor.bats
#
# Covers: docs/specs/release-operations-automation.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WALTER_OS_BIN="$REPO_ROOT/bin/walter-os"
  TMP_DIR="$(mktemp -d)"
  export HOME="$TMP_DIR/home"
  export WALTER_CONFIG="$TMP_DIR/config"
  export WALTER_OS_HOME="$REPO_ROOT"
  mkdir -p "$HOME" "$WALTER_CONFIG"
}

teardown() {
  cd "$BATS_TEST_DIRNAME" || exit
  case "$TMP_DIR" in
    /tmp/*|/var/folders/*|/var/tmp/*) rm -rf "$TMP_DIR" ;;
  esac
  true
}

write_fixture() {
  local path="$1"
  local version="${2:-0.6.1}"
  local changelog_versions="${3:-[\"0.6.1\"]}"
  local tags="${4:-[\"v0.6.0\"]}"
  local prs="${5:-[]}"

  jq -nc \
    --arg version "$version" \
    --argjson changelog_versions "$changelog_versions" \
    --argjson tags "$tags" \
    --argjson prs "$prs" \
    '{
      release: {
        version: $version,
        changelog_versions: $changelog_versions,
        tags: $tags
      },
      prs: $prs
    }' > "$path"
}

write_post_release_fixture() {
  local path="$1"
  local tag_target="${2:-abc123}"
  local release_json="${3:-}"

  if [[ -z "$release_json" ]]; then
    release_json="$(jq -nc '
      {
        exists: true,
        tagName: "v0.6.1",
        targetCommitish: "main",
        isDraft: false,
        isPrerelease: false,
        assets: [
          {name: "checksums.sha256", digest: "sha256:111"},
          {name: "checksums.sha256.cosign.bundle", digest: "sha256:222"},
          {name: "walter-os-v0.6.1.intoto.jsonl", digest: "sha256:333"},
          {name: "walter-os-v0.6.1.sbom.cdx.json", digest: "sha256:444"},
          {name: "walter-os-v0.6.1.source.tar.gz", digest: "sha256:555"}
        ]
      }')"
  fi

  jq -nc \
    --arg tag_target "$tag_target" \
    --argjson release_json "$release_json" \
    '{
      release: {
        version: "0.6.1",
        changelog_versions: ["0.6.1"],
        tags: ["v0.6.1"],
        tag_targets: {"v0.6.1": $tag_target},
        github_release: $release_json
      },
      prs: []
    }' > "$path"
}

healthy_prs='[
  {
    "number": 304,
    "title": "[FEAT] -SECURITY- add signed Forgejo PR webhook",
    "body": "Closes #302\n\n## Verification\n- bats tests/agents/plane-pr-sync-webhook.bats",
    "baseRefName": "main",
    "headRefName": "codex/issue-302-signed-forgejo-webhook",
    "mergeable": "MERGEABLE",
    "closingIssuesReferences": [{"number": 302}],
    "statusCheckRollup": [{"name": "ci", "status": "COMPLETED", "conclusion": "SUCCESS"}],
    "reviewRequests": [],
    "reviewDecision": "APPROVED",
    "reviewThreads": []
  }
]'

@test "AC1: help documents release doctor" {
  run bash "$WALTER_OS_BIN" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"release doctor"* ]]
  [[ "$output" == *"--target vX.Y.Z|X.Y.Z"* ]]
}

@test "AC2: clean release evidence returns ready" {
  local fixture="$TMP_DIR/ready.json"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: PASS"* ]]
  [[ "$output" == *"Decision: ready"* ]]
  [[ "$output" == *"Findings:"* ]]
  [[ "$output" == *"none"* ]]
}

@test "AC2: relative fixture path beginning with dash is readable" {
  local fixture="$TMP_DIR/-ready.json"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$healthy_prs"

  cd "$TMP_DIR"
  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture -ready.json

  [ "$status" -eq 0 ]
  [[ "$output" == *"Decision: ready"* ]]
}

@test "AC2: fixture directory is rejected as usage error" {
  local fixture="$TMP_DIR/fixture-dir"
  mkdir -p "$fixture"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture"

  [ "$status" -eq 64 ]
  [[ "$output" == *"fixture is not a regular file"* ]]
}

@test "AC3: version drift blocks release" {
  local fixture="$TMP_DIR/version-drift.json"
  write_fixture "$fixture" "0.6.0" '["0.6.1"]' '["v0.6.0"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.findings | index("VERSION is 0.6.0, expected 0.6.1")'
}

@test "AC3: invalid target is a usage error" {
  local fixture="$TMP_DIR/invalid-target.json"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target next --fixture "$fixture"

  [ "$status" -eq 64 ]
  [[ "$output" == *"--target must look like vX.Y.Z or X.Y.Z"* ]]
}

@test "regression: non-git checkout exits with controlled runtime error" {
  local fake_bin="$TMP_DIR/bin"
  local not_repo="$TMP_DIR/not-a-repo"
  mkdir -p "$fake_bin" "$not_repo"
  cat > "$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh should not be called before local tag inspection" >&2
exit 42
SH
  chmod +x "$fake_bin/gh"

  run env PATH="$fake_bin:$PATH" WALTER_OS_HOME="$not_repo" \
    bash "$REPO_ROOT/scripts/walter/subcommands/release.sh" doctor --target v0.6.1 --json

  [ "$status" -eq 4 ]
  [[ "$output" == *"failed to read local git tags"* ]]
}

@test "regression: live collection anchors gh repo and scopes release batch" {
  local fake_bin="$TMP_DIR/bin"
  local release_repo="$TMP_DIR/release-repo"
  local other_dir="$TMP_DIR/other"
  mkdir -p "$fake_bin" "$release_repo" "$other_dir"
  printf '0.6.1\n' > "$release_repo/VERSION"
  printf '## [0.6.1]\n' > "$release_repo/CHANGELOG.md"

  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  tag)
    printf 'v0.6.0\n'
    ;;
  ls-remote)
    exit 0
    ;;
  remote)
    if [[ "${2:-}" == "get-url" && "${3:-}" == "origin" ]]; then
      printf 'git@github.com/Xipher-Labs/walter-os.git\n'
      exit 0
    fi
    echo "unexpected git remote invocation: $*" >&2
    exit 97
    ;;
  *)
    echo "unexpected git invocation: $*" >&2
    exit 98
    ;;
esac
SH

  cat > "$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "repo view")
    [[ "${3:-}" == "Xipher-Labs/walter-os" ]] || {
      echo "repo view did not receive parsed OWNER/REPO slug" >&2
      exit 90
    }
    printf '{"name":"walter-os","owner":{"login":"Xipher-Labs"}}\n'
    ;;
  "pr list")
    args=" $* "
    [[ "$args" == *" --repo Xipher-Labs/walter-os "* ]] || {
      echo "pr list was not anchored with --repo" >&2
      exit 91
    }
    [[ "$args" == *" --limit 1000 "* ]] || {
      echo "pr list did not request the high open-PR limit" >&2
      exit 92
    }
    cat <<'JSON'
[
  {
    "number": 304,
    "title": "[FEAT] -SECURITY- add signed Forgejo PR webhook",
    "body": "Closes #302\n\n## Verification\n- bats tests/agents/plane-pr-sync-webhook.bats",
    "baseRefName": "main",
    "headRefName": "codex/issue-302-signed-forgejo-webhook",
    "mergeable": "MERGEABLE",
    "closingIssuesReferences": [{"number": 302}],
    "statusCheckRollup": [{"name": "ci", "status": "COMPLETED", "conclusion": "SUCCESS"}],
    "reviewRequests": [],
    "reviewDecision": "APPROVED"
  },
  {
    "number": 306,
    "title": "[FIX] -TECHNICAL- persist Forgejo issue markers",
    "body": "Refs #305\n\n## Verification\n- bats tests/agents/plane-pr-sync-webhook.bats",
    "baseRefName": "codex/issue-302-signed-forgejo-webhook",
    "headRefName": "codex/issue-305-forgejo-marker-persistence",
    "mergeable": "MERGEABLE",
    "closingIssuesReferences": [],
    "statusCheckRollup": [{"name": "ci", "status": "COMPLETED", "conclusion": "SUCCESS"}],
    "reviewRequests": [],
    "reviewDecision": "APPROVED"
  },
  {
    "number": 400,
    "title": "[FEAT] -TECHNICAL- unrelated feature branch",
    "body": "Closes #400",
    "baseRefName": "feature/unrelated-base",
    "headRefName": "feature/unrelated-child",
    "mergeable": "CONFLICTING",
    "closingIssuesReferences": [{"number": 400}],
    "statusCheckRollup": [{"name": "ci", "status": "IN_PROGRESS", "conclusion": null}],
    "reviewRequests": [{"login": "reviewer"}],
    "reviewDecision": "REVIEW_REQUIRED"
  }
]
JSON
    ;;
  "api graphql")
    printf '{"totalCount":0,"nodes":[]}\n'
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 93
    ;;
esac
SH
  chmod +x "$fake_bin/git" "$fake_bin/gh"

  cd "$other_dir"
  run env PATH="$fake_bin:$PATH" WALTER_OS_HOME="$release_repo" \
    bash "$REPO_ROOT/scripts/walter/subcommands/release.sh" doctor --target v0.6.1 --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "warn"'
  echo "$output" | jq -e '.counts.prs == 2'
  echo "$output" | jq -e '.findings == []'
  echo "$output" | jq -e '.warnings | index("PR #306 is stacked on codex/issue-302-signed-forgejo-webhook; merge base first, then retarget to main")'
  [[ "$output" != *"#400"* ]]
}

@test "#499: post-release live collection resolves remote-only tag target" {
  local fake_bin="$TMP_DIR/bin"
  local release_repo="$TMP_DIR/release-repo"
  mkdir -p "$fake_bin" "$release_repo"
  printf '0.6.1\n' > "$release_repo/VERSION"
  printf '## [0.6.1]\n' > "$release_repo/CHANGELOG.md"

  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
  tag)
    exit 0
    ;;
  rev-list)
    exit 128
    ;;
  ls-remote)
    if [[ "$*" == *"--tags --refs origin v[0-9]*"* ]]; then
      printf 'def456\trefs/tags/v0.6.1\n'
      exit 0
    fi
    if [[ "$*" == *"--tags origin v0.6.1^{}"* ]]; then
      exit 0
    fi
    if [[ "$*" == *"--tags --refs origin v0.6.1"* ]]; then
      printf 'def456\trefs/tags/v0.6.1\n'
      exit 0
    fi
    exit 0
    ;;
  remote)
    if [[ "${2:-}" == "get-url" && "${3:-}" == "origin" ]]; then
      printf 'git@github.com/Xipher-Labs/walter-os.git\n'
      exit 0
    fi
    echo "unexpected git remote invocation: $*" >&2
    exit 97
    ;;
  *)
    echo "unexpected git invocation: $*" >&2
    exit 98
    ;;
esac
SH

  cat > "$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "repo view")
    printf '{"name":"walter-os","owner":{"login":"Xipher-Labs"}}\n'
    ;;
  "release view")
    printf '{"tagName":"v0.6.1","targetCommitish":"main","isDraft":false,"isPrerelease":false,"assets":[{"name":"checksums.sha256","digest":"sha256:111"},{"name":"checksums.sha256.cosign.bundle","digest":"sha256:222"},{"name":"walter-os-v0.6.1.intoto.jsonl","digest":"sha256:333"},{"name":"walter-os-v0.6.1.sbom.cdx.json","digest":"sha256:444"},{"name":"walter-os-v0.6.1.source.tar.gz","digest":"sha256:555"}],"url":"https://github.com/Xipher-Labs/walter-os/releases/tag/v0.6.1"}\n'
    ;;
  "pr list")
    echo "post-release mode should not collect PRs" >&2
    exit 96
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 98
    ;;
esac
SH
  chmod +x "$fake_bin/git" "$fake_bin/gh"

  run env PATH="$fake_bin:$PATH" WALTER_OS_HOME="$release_repo" \
    bash "$REPO_ROOT/scripts/walter/subcommands/release.sh" doctor --target v0.6.1 --post-release --expected-commit def456 --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "ready"'
  echo "$output" | jq -e '.release_artifact_findings == []'
}

@test "AC3: missing changelog entry blocks release" {
  local fixture="$TMP_DIR/changelog-drift.json"
  write_fixture "$fixture" "0.6.1" '["0.6.0"]' '["v0.6.0"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("CHANGELOG.md is missing ## [0.6.1]")'
}

@test "AC3: existing target tag blocks release" {
  local fixture="$TMP_DIR/tag-drift.json"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.1"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("tag already exists: v0.6.1")'
}

@test "#499: pre-release doctor still blocks an existing target tag" {
  local fixture="$TMP_DIR/post-release-ready.json"
  write_post_release_fixture "$fixture"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.findings | index("tag already exists: v0.6.1")'
}

@test "#499: post-release mode accepts an existing tag and complete release assets" {
  local fixture="$TMP_DIR/post-release-ready.json"
  write_post_release_fixture "$fixture"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --post-release --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "post-release"'
  echo "$output" | jq -e '.decision == "ready"'
  echo "$output" | jq -e '.findings == []'
}

@test "#499: post-release mode reports release-artifact drift separately" {
  local fixture="$TMP_DIR/post-release-drift.json"
  local release_json
  release_json="$(jq -nc '
    {
      exists: true,
      tagName: "v0.6.1",
      targetCommitish: "main",
      isDraft: true,
      isPrerelease: true,
      assets: [
        {name: "checksums.sha256", digest: "sha256:111"},
        {name: "walter-os-v0.6.1.source.tar.gz", digest: null}
      ]
    }')"
  write_post_release_fixture "$fixture" "abc123" "$release_json"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --post-release --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.counts.release_artifact_findings > 0'
  echo "$output" | jq -e '.release_artifact_findings | index("GitHub Release is draft: v0.6.1")'
  echo "$output" | jq -e '.release_artifact_findings | index("GitHub Release is prerelease: v0.6.1")'
  echo "$output" | jq -e '.release_artifact_findings | index("release asset missing: checksums.sha256.cosign.bundle")'
  echo "$output" | jq -e '.release_artifact_findings | index("release asset missing digest: walter-os-v0.6.1.source.tar.gz")'
}

@test "#499: post-release mode validates tag target when evidence names one" {
  local fixture="$TMP_DIR/post-release-tag-drift.json"
  write_post_release_fixture "$fixture" "abc123"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --post-release --expected-commit def456 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.release_artifact_findings | index("tag v0.6.1 points at abc123, expected def456")'
}

@test "#499: post-release mode reports unresolved expected tag target" {
  local fixture="$TMP_DIR/post-release-missing-tag-target.json"
  local release_json
  release_json="$(jq -nc '
    {
      exists: true,
      tagName: "v0.6.1",
      targetCommitish: "main",
      isDraft: false,
      isPrerelease: false,
      assets: [
        {name: "checksums.sha256", digest: "sha256:111"},
        {name: "checksums.sha256.cosign.bundle", digest: "sha256:222"},
        {name: "walter-os-v0.6.1.intoto.jsonl", digest: "sha256:333"},
        {name: "walter-os-v0.6.1.sbom.cdx.json", digest: "sha256:444"},
        {name: "walter-os-v0.6.1.source.tar.gz", digest: "sha256:555"}
      ]
    }')"
  jq -nc \
    --argjson release_json "$release_json" \
    '{
      release: {
        version: "0.6.1",
        changelog_versions: ["0.6.1"],
        tags: ["v0.6.1"],
        tag_targets: {},
        github_release: $release_json
      },
      prs: []
    }' > "$fixture"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --post-release --expected-commit def456 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.release_artifact_findings | index("tag v0.6.1 target could not be resolved for expected commit def456")'
}

@test "AC4: unresolved review threads block release" {
  local fixture="$TMP_DIR/unresolved.json"
  local prs
  prs="$(jq -c '.[0].reviewThreads = [{"isResolved": false, "isOutdated": false}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 has unresolved review threads: 1")'
}

@test "AC4: pending checks block release" {
  local fixture="$TMP_DIR/pending-checks.json"
  local prs
  prs="$(jq -c '.[0].statusCheckRollup = [{"name": "ci", "status": "IN_PROGRESS", "conclusion": null}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 has pending checks: 1")'
}

@test "AC4: missing check rollup blocks release as pending" {
  local fixture="$TMP_DIR/missing-check-rollup.json"
  local prs
  prs="$(jq -c '.[0].statusCheckRollup = []' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 has pending checks: 1")'
}

@test "AC4: successful status contexts do not count as pending checks" {
  local fixture="$TMP_DIR/status-context-success.json"
  local prs
  prs="$(jq -c '.[0].statusCheckRollup = [{"__typename": "StatusContext", "context": "legacy-ci", "state": "SUCCESS"}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "ready"'
  echo "$output" | jq -e '.findings == []'
}

@test "AC4: failing status contexts block release" {
  local fixture="$TMP_DIR/status-context-failure.json"
  local prs
  prs="$(jq -c '.[0].statusCheckRollup = [{"__typename": "StatusContext", "context": "legacy-ci", "state": "FAILURE"}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 has failing checks: 1")'
}

@test "AC4: incomplete review thread page blocks release" {
  local fixture="$TMP_DIR/incomplete-threads.json"
  local prs
  prs="$(jq -c '.[0].reviewThreads = [] | .[0].reviewThreadsTotalCount = 101' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 review thread page incomplete: fetched 0 of 101")'
}

@test "AC4: pending review requests block release" {
  local fixture="$TMP_DIR/pending-review-request.json"
  local prs
  prs="$(jq -c '.[0].reviewRequests = [{"login": "Copilot"}] | .[0].reviewDecision = "REVIEW_REQUIRED"' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 has pending review requests: 1")'
  echo "$output" | jq -e '.findings | index("PR #304 review decision is REVIEW_REQUIRED")'
}

@test "AC4: missing approval evidence blocks release" {
  local fixture="$TMP_DIR/missing-review-decision.json"
  local prs
  prs="$(jq -c '.[0] | del(.reviewDecision) | [.]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 review decision is missing")'
}

@test "AC5: stacked PRs warn with merge-order guidance" {
  local fixture="$TMP_DIR/stacked.json"
  local prs
  prs="$(jq -c '.[0].number = 306 | .[0].baseRefName = "codex/issue-302-signed-forgejo-webhook" | .[0].headRefName = "codex/issue-305-forgejo-marker-persistence" | .[0].body = "Refs #305\n\n## Verification\n- bats tests/agents/plane-pr-sync-webhook.bats" | .[0].closingIssuesReferences = []' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "warn"'
  echo "$output" | jq -e '.warnings | index("PR #306 is stacked on codex/issue-302-signed-forgejo-webhook; merge base first, then retarget to main")'
}

@test "AC6: stacked PRs with closing issue references block release" {
  local fixture="$TMP_DIR/stacked-closes.json"
  local prs
  prs="$(jq -c '.[0].number = 306 | .[0].baseRefName = "codex/issue-302-signed-forgejo-webhook" | .[0].headRefName = "codex/issue-305-forgejo-marker-persistence" | .[0].closingIssuesReferences = [{"number": 305}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.warnings | index("PR #306 is stacked on codex/issue-302-signed-forgejo-webhook; merge base first, then retarget to main")'
  echo "$output" | jq -e '.findings | index("PR #306 is stacked but closes issues; retarget to main or use Refs")'
}

@test "AC6: stacked PRs with closing keywords block release" {
  local fixture="$TMP_DIR/stacked-closing-keyword.json"
  local prs
  prs="$(jq -c '.[0].number = 306 | .[0].baseRefName = "codex/issue-302-signed-forgejo-webhook" | .[0].headRefName = "codex/issue-305-forgejo-marker-persistence" | .[0].body = "Closes: #305\n\n## Verification\n- bats tests/agents/plane-pr-sync-webhook.bats" | .[0].closingIssuesReferences = []' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.warnings | index("PR #306 is stacked on codex/issue-302-signed-forgejo-webhook; merge base first, then retarget to main")'
  echo "$output" | jq -e '.findings | index("PR #306 is stacked but closes issues; retarget to main or use Refs")'
}

@test "AC6: closing issue without verification evidence blocks release" {
  local fixture="$TMP_DIR/closure-hygiene.json"
  local prs
  prs="$(jq -c '.[0].body = "Closes #302" | .[0].closingIssuesReferences = [{"number": 302}]' <<<"$healthy_prs")"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.findings | index("PR #304 closes issues but lacks verification evidence")'
}

@test "AC7: --json emits release doctor contract" {
  local fixture="$TMP_DIR/ready-json.json"
  write_fixture "$fixture" "0.6.1" '["0.6.1"]' '["v0.6.0"]' "$healthy_prs"

  run bash "$WALTER_OS_BIN" release doctor --target v0.6.1 --fixture "$fixture" --json

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.target == "v0.6.1"'
  echo "$output" | jq -e '.decision == "ready"'
  echo "$output" | jq -e '.counts.prs == 1'
  echo "$output" | jq -e '.findings == []'
  echo "$output" | jq -e '.warnings == []'
}
