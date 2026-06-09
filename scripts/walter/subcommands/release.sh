#!/usr/bin/env bash
# scripts/walter/subcommands/release.sh
# Read-only release readiness checks.

set -euo pipefail

RUNTIME_ERROR_EXIT=4
USAGE_ERROR_EXIT=64

WALTER_OS_HOME="${WALTER_OS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

usage() {
  cat <<'EOF'
Usage: walter-os release doctor --target <vX.Y.Z|X.Y.Z> [--base <branch>] [--post-release] [--expected-commit <sha>] [--json] [--fixture <path>]

Read-only release operations diagnostics. The doctor checks version,
changelog, tag, open-PR check/review status, issue closure hygiene, and stacked
PR retarget warnings. It never merges PRs, pushes tags, edits files, or creates
GitHub releases.

Subcommands:
  doctor        Run release-readiness diagnostics.

Options:
  --target      Target release tag, for example v0.6.1 or 0.6.1.
  --base        Release base branch. Default: main.
  --post-release
                Verify an existing GitHub Release and its artifact metadata.
  --expected-commit
                Expected commit SHA for the release tag in --post-release mode.
                Defaults to the collected tag target when evidence includes one.
  --json        Print machine-readable JSON.
  --fixture     Read release evidence JSON from a file for tests/local audits.
EOF
}

runtime_error() {
  echo "walter-os release doctor: $1" >&2
  exit "$RUNTIME_ERROR_EXIT"
}

usage_error() {
  echo "walter-os release doctor: $1" >&2
  exit "$USAGE_ERROR_EXIT"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    runtime_error "jq is required"
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    runtime_error "gh is required unless --fixture is used"
  fi
}

json_array_contains() {
  local array_json="$1" needle="$2"
  jq -e --arg needle "$needle" 'index($needle) != null' >/dev/null <<<"$array_json"
}

json_string_array_from_lines() {
  jq -Rsc 'split("\n") | map(select(length > 0))'
}

valid_target_tag() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

repo_slug_from_origin() {
  local origin_url="$1"
  local slug="$origin_url"

  case "$origin_url" in
    https://github.com/*)
      slug="${origin_url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${origin_url#http://github.com/}"
      ;;
    git@github.com:*)
      slug="${origin_url#git@github.com:}"
      ;;
    git@github.com/*)
      slug="${origin_url#git@github.com/}"
      ;;
    ssh://git@github.com/*)
      slug="${origin_url#ssh://git@github.com/}"
      ;;
    *)
      printf '%s\n' "$origin_url"
      return 0
      ;;
  esac

  printf '%s\n' "${slug%.git}"
}

body_has_verification() {
  local body="$1"
  grep -Eiq '(Verification|Test plan)' <<<"$body" \
    && grep -Eiq '(bats|shellcheck|pytest|pnpm|npm|git diff --check|cargo test|go test)' <<<"$body"
}

body_has_closing_keyword() {
  local body="$1"
  grep -Eiq '(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+' <<<"$body"
}

fetch_review_threads() {
  local owner="$1" repo="$2" number="$3"
  # shellcheck disable=SC2016 # GraphQL variables are intentionally literal.
  gh api graphql \
    -f owner="$owner" \
    -f repo="$repo" \
    -F number="$number" \
    -f query='query($owner:String!, $repo:String!, $number:Int!) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$number) {
          reviewThreads(first:100) {
            totalCount
            nodes { isResolved isOutdated }
          }
        }
      }
    }' \
    --jq '.data.repository.pullRequest.reviewThreads'
}

release_batch_prs() {
  local base_branch="$1" pr_list="$2"

  jq -c --arg base "$base_branch" '
    . as $all
    | def expand($selected):
        ($selected | map(.number) | unique) as $selected_numbers
        | ($selected | map(.headRefName) | unique) as $heads
        | ($selected + [
            $all[]
            | . as $candidate
            | select(($selected_numbers | index($candidate.number)) | not)
            | select($heads | index($candidate.baseRefName))
          ]) as $next
        | if ($next | length) == ($selected | length) then
            $next
          else
            expand($next)
          end;
      expand([$all[] | select(.baseRefName == $base)])
  ' <<<"$pr_list"
}

collect_evidence() {
  local base_branch="$1" target_tag="${2:-}" post_release="${3:-0}"

  require_gh

  local version_file="${WALTER_OS_HOME}/VERSION"
  local changelog_file="${WALTER_OS_HOME}/CHANGELOG.md"
  local version=""
  local changelog_versions='[]'
  local tags='[]'
  local tag_targets='{}'
  local github_release='{"exists":false}'
  local prs='[]'
  local repo_json owner repo repo_slug origin_url repo_ref all_pr_list pr_list pr_count index pr number threads pr_with_threads
  local local_tags remote_tags
  local release_view release_stderr release_error
  local pr_list_limit=1000
  local -a pr_objects=()

  if [[ -r "$version_file" ]]; then
    version="$(tr -d '[:space:]' < "$version_file")"
  fi

  if [[ -r "$changelog_file" ]]; then
    changelog_versions="$(
      { grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog_file" || true; } \
        | sed -E 's/^## \[([^]]+)\].*/\1/' \
        | json_string_array_from_lines
    )"
  fi

  if ! local_tags="$(git -C "$WALTER_OS_HOME" tag --list 'v[0-9]*')"; then
    runtime_error "failed to read local git tags"
  fi
  if ! remote_tags="$(git -C "$WALTER_OS_HOME" ls-remote --tags --refs origin 'v[0-9]*' 2>/dev/null \
      | awk '{sub("refs/tags/", "", $2); print $2}')"; then
    runtime_error "failed to read remote git tags from origin"
  fi
  tags="$(printf '%s\n%s\n' "$local_tags" "$remote_tags" | sort -u | json_string_array_from_lines)"

  if [[ "$post_release" -eq 1 && -n "$target_tag" ]]; then
    local local_target_commit="" remote_target_commit="" target_commit=""
    local_target_commit="$(git -C "$WALTER_OS_HOME" rev-list -n 1 "$target_tag" 2>/dev/null || true)"
    remote_target_commit="$({ git -C "$WALTER_OS_HOME" ls-remote --tags origin "${target_tag}^{}" 2>/dev/null || true; } | awk 'NR == 1 {print $1}')"
    if [[ -z "$remote_target_commit" ]]; then
      remote_target_commit="$({ git -C "$WALTER_OS_HOME" ls-remote --tags --refs origin "$target_tag" 2>/dev/null || true; } | awk 'NR == 1 {print $1}')"
    fi
    target_commit="${remote_target_commit:-$local_target_commit}"
    if [[ -n "$target_commit" ]]; then
      tag_targets="$(jq -nc --arg tag "$target_tag" --arg commit "$target_commit" '{($tag): $commit}')"
    fi
  fi

  if ! origin_url="$(git -C "$WALTER_OS_HOME" remote get-url origin)"; then
    runtime_error "failed to read origin remote from $WALTER_OS_HOME"
  fi

  repo_ref="$(repo_slug_from_origin "$origin_url")"
  if ! repo_json="$(gh repo view "$repo_ref" --json owner,name)"; then
    runtime_error "failed to read repository data with gh"
  fi
  owner="$(jq -r '.owner.login' <<<"$repo_json")"
  repo="$(jq -r '.name' <<<"$repo_json")"
  repo_slug="$owner/$repo"

  if [[ "$post_release" -eq 1 && -n "$target_tag" ]]; then
    release_stderr="$(mktemp "${TMPDIR:-/tmp}/walter-release-view.XXXXXX")" \
      || runtime_error "failed to create temporary stderr file for gh release view"
    if release_view="$(gh release view "$target_tag" --repo "$repo_slug" \
        --json tagName,targetCommitish,isDraft,isPrerelease,assets,url 2>"$release_stderr")"; then
      github_release="$(jq -c '. + {exists: true}' <<<"$release_view")"
    else
      release_error="$(tr '\n' ' ' < "$release_stderr" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
      rm -f "$release_stderr"
      if [[ ! "$release_error" =~ [Nn]ot[[:space:]-][Ff]ound && ! "$release_error" =~ 404 ]]; then
        runtime_error "failed to read GitHub Release $target_tag with gh: ${release_error:-unknown error}"
      fi
      release_stderr=""
    fi
    [[ -z "${release_stderr:-}" ]] || rm -f "$release_stderr"
  fi

  if [[ "$post_release" -eq 1 ]]; then
    jq -nc \
      --arg version "$version" \
      --argjson changelog_versions "$changelog_versions" \
      --argjson tags "$tags" \
      --argjson tag_targets "$tag_targets" \
      --argjson github_release "$github_release" \
      '{release: {version: $version, changelog_versions: $changelog_versions, tags: $tags, tag_targets: $tag_targets, github_release: $github_release}, prs: []}'
    return 0
  fi

  if ! all_pr_list="$(gh pr list --repo "$repo_slug" --state open --limit "$pr_list_limit" \
      --json number,title,body,baseRefName,headRefName,mergeable,reviewRequests,reviewDecision,closingIssuesReferences,statusCheckRollup)"; then
    runtime_error "failed to read open PRs with gh"
  fi
  if ! pr_list="$(release_batch_prs "$base_branch" "$all_pr_list")"; then
    runtime_error "failed to scope open PRs to release batch"
  fi

  pr_count="$(jq 'length' <<<"$pr_list")"
  for ((index = 0; index < pr_count; index++)); do
    pr="$(jq -c ".[$index]" <<<"$pr_list")"
    number="$(jq -r '.number' <<<"$pr")"
    if ! threads="$(fetch_review_threads "$owner" "$repo" "$number")"; then
      runtime_error "failed to read review threads for PR #$number"
    fi
    if ! pr_with_threads="$(jq -nc --argjson pr "$pr" --argjson threads "$threads" \
      '$pr + {
        reviewThreads: ($threads.nodes // []),
        reviewThreadsTotalCount: ($threads.totalCount // ($threads.nodes // [] | length))
      }')"; then
      runtime_error "failed to merge review-thread evidence for PR #$number"
    fi
    pr_objects+=("$pr_with_threads")
  done

  if ((${#pr_objects[@]} > 0)); then
    if ! prs="$(printf '%s\n' "${pr_objects[@]}" | jq -s -c '.')"; then
      runtime_error "failed to assemble PR evidence"
    fi
  fi

  jq -nc \
    --arg version "$version" \
    --argjson changelog_versions "$changelog_versions" \
    --argjson tags "$tags" \
    --argjson tag_targets "$tag_targets" \
    --argjson github_release "$github_release" \
    --argjson prs "$prs" \
    '{release: {version: $version, changelog_versions: $changelog_versions, tags: $tags, tag_targets: $tag_targets, github_release: $github_release}, prs: $prs}'
}

cmd_doctor() {
  local target="" base_branch="main" fixture="" json_output=0 post_release=0 expected_commit=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        target="${2:-}"
        [[ -n "$target" ]] || usage_error "--target requires a value"
        shift 2
        ;;
      --base)
        base_branch="${2:-}"
        [[ -n "$base_branch" ]] || usage_error "--base requires a branch"
        shift 2
        ;;
      --fixture)
        fixture="${2:-}"
        [[ -n "$fixture" ]] || usage_error "--fixture requires a path"
        shift 2
        ;;
      --post-release)
        post_release=1
        shift
        ;;
      --expected-commit)
        expected_commit="${2:-}"
        [[ -n "$expected_commit" ]] || usage_error "--expected-commit requires a value"
        shift 2
        ;;
      --json)
        json_output=1
        shift
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      -*)
        echo "walter-os release doctor: unknown option: $1" >&2
        usage >&2
        exit "$USAGE_ERROR_EXIT"
        ;;
      *)
        echo "walter-os release doctor: unexpected argument: $1" >&2
        usage >&2
        exit "$USAGE_ERROR_EXIT"
        ;;
    esac
  done

  require_jq

  [[ -n "$target" ]] || usage_error "--target is required"
  valid_target_tag "$target" || usage_error "--target must look like vX.Y.Z or X.Y.Z"
  if [[ -n "$expected_commit" && "$post_release" -eq 0 ]]; then
    usage_error "--expected-commit requires --post-release"
  fi

  local target_version="${target#v}"
  local target_tag="v${target_version}"
  local mode="pre-release"
  if [[ "$post_release" -eq 1 ]]; then
    mode="post-release"
  fi
  local evidence_json

  if [[ -n "$fixture" ]]; then
    [[ -f "$fixture" ]] || usage_error "fixture is not a regular file: $fixture"
    [[ -r "$fixture" ]] || usage_error "fixture is not readable: $fixture"
    evidence_json="$(cat -- "$fixture")"
  else
    evidence_json="$(collect_evidence "$base_branch" "$target_tag" "$post_release")"
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"$evidence_json"; then
    runtime_error "evidence is not valid JSON"
  fi

  local findings_json='[]'
  local warnings_json='[]'
  local release_artifact_findings_json='[]'
  add_finding() {
    findings_json="$(jq -c --arg msg "$1" '. + [$msg]' <<<"$findings_json")"
  }
  add_warning() {
    warnings_json="$(jq -c --arg msg "$1" '. + [$msg]' <<<"$warnings_json")"
  }
  add_release_artifact_finding() {
    release_artifact_findings_json="$(jq -c --arg msg "$1" '. + [$msg]' <<<"$release_artifact_findings_json")"
  }

  local version changelog_versions tags
  version="$(jq -r '.release.version // ""' <<<"$evidence_json")"
  changelog_versions="$(jq -c '.release.changelog_versions // []' <<<"$evidence_json")"
  tags="$(jq -c '.release.tags // []' <<<"$evidence_json")"

  if [[ "$post_release" -eq 0 ]]; then
    if [[ "$version" != "$target_version" ]]; then
      add_finding "VERSION is ${version:-missing}, expected $target_version"
    fi
    if ! json_array_contains "$changelog_versions" "$target_version"; then
      add_finding "CHANGELOG.md is missing ## [$target_version]"
    fi
  fi
  if [[ "$post_release" -eq 1 ]]; then
    if ! json_array_contains "$tags" "$target_tag"; then
      add_release_artifact_finding "tag missing: $target_tag"
    fi
  elif json_array_contains "$tags" "$target_tag"; then
    add_finding "tag already exists: $target_tag"
  fi

  if [[ "$post_release" -eq 1 ]]; then
    local tag_target github_release release_exists release_tag release_draft release_prerelease
    local release_assets required_assets_json missing_assets_json missing_digest_json expected
    tag_target="$(jq -r --arg tag "$target_tag" '.release.tag_targets[$tag] // ""' <<<"$evidence_json")"
    expected="${expected_commit:-$tag_target}"
    if [[ -z "$tag_target" ]] && json_array_contains "$tags" "$target_tag"; then
      if [[ -n "$expected_commit" ]]; then
        add_release_artifact_finding "tag $target_tag target could not be resolved for expected commit $expected_commit"
      else
        add_release_artifact_finding "tag $target_tag target could not be resolved"
      fi
    elif [[ -n "$expected" && -n "$tag_target" && "$tag_target" != "$expected" ]]; then
      add_release_artifact_finding "tag $target_tag points at $tag_target, expected $expected"
    fi

    github_release="$(jq -c '.release.github_release // {exists:false}' <<<"$evidence_json")"
    release_exists="$(jq -r '.exists // false' <<<"$github_release")"
    if [[ "$release_exists" != "true" ]]; then
      add_release_artifact_finding "GitHub Release missing: $target_tag"
    else
      release_tag="$(jq -r '.tagName // ""' <<<"$github_release")"
      release_draft="$(jq -r '.isDraft // false' <<<"$github_release")"
      release_prerelease="$(jq -r '.isPrerelease // false' <<<"$github_release")"
      if [[ "$release_tag" != "$target_tag" ]]; then
        add_release_artifact_finding "GitHub Release tag is ${release_tag:-missing}, expected $target_tag"
      fi
      if [[ "$release_draft" == "true" ]]; then
        add_release_artifact_finding "GitHub Release is draft: $target_tag"
      fi
      if [[ "$release_prerelease" == "true" ]]; then
        add_release_artifact_finding "GitHub Release is prerelease: $target_tag"
      fi

      required_assets_json="$(jq -nc --arg tag "$target_tag" '[
        "checksums.sha256",
        "checksums.sha256.cosign.bundle",
        "walter-os-\($tag).intoto.jsonl",
        "walter-os-\($tag).sbom.cdx.json",
        "walter-os-\($tag).source.tar.gz"
      ]')"
      release_assets="$(jq -c '.assets // []' <<<"$github_release")"
      missing_assets_json="$(jq -nc --argjson required "$required_assets_json" --argjson assets "$release_assets" '
        ($assets | map(.name // "")) as $names
        | [$required[] as $asset | select(($names | index($asset)) | not) | $asset]
      ')"
      while IFS= read -r expected_asset; do
        [[ -n "$expected_asset" ]] || continue
        add_release_artifact_finding "release asset missing: $expected_asset"
      done < <(jq -r '.[]' <<<"$missing_assets_json")

      missing_digest_json="$(jq -nc --argjson required "$required_assets_json" --argjson assets "$release_assets" '
        [
          $required[] as $name
          | $assets[]
          | select((.name // "") == $name)
          | select((.digest // "") == "")
          | $name
        ]
      ')"
      while IFS= read -r asset_without_digest; do
        [[ -n "$asset_without_digest" ]] || continue
        add_release_artifact_finding "release asset missing digest: $asset_without_digest"
      done < <(jq -r '.[]' <<<"$missing_digest_json")
    fi
  fi

  local prs_total pr_blockers=0 pr_warnings=0
  local pr number base mergeable body checks_total checks_failed checks_pending
  local unresolved_threads closing_count body_closes closes_issues review_requests review_decision
  local review_threads_fetched review_threads_total
  prs_total="$(jq '[.prs[]?] | length' <<<"$evidence_json")"

  while IFS= read -r pr; do
    [[ -n "$pr" ]] || continue
    number="$(jq -r '.number // "unknown"' <<<"$pr")"
    base="$(jq -r '.baseRefName // ""' <<<"$pr")"
    mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr")"
    body="$(jq -r '.body // ""' <<<"$pr")"

    checks_total="$(jq '[.statusCheckRollup[]?] | length' <<<"$pr")"
    checks_failed="$(jq '[
      .statusCheckRollup[]?
      | if ((.__typename // "") == "StatusContext" or ((.state // "") != "" and (.status // "") == "")) then
          select(((.state // "") | tostring | ascii_upcase) == "FAILURE" or ((.state // "") | tostring | ascii_upcase) == "ERROR")
        else
          select(((.status // "") | tostring | ascii_upcase) == "COMPLETED")
          | select((.conclusion // "") != "")
          | select(
              ((.conclusion // "") | tostring | ascii_upcase) != "SUCCESS"
              and ((.conclusion // "") | tostring | ascii_upcase) != "SKIPPED"
              and ((.conclusion // "") | tostring | ascii_upcase) != "NEUTRAL"
            )
        end
    ] | length' <<<"$pr")"
    checks_pending="$(jq '[
      .statusCheckRollup[]?
      | if ((.__typename // "") == "StatusContext" or ((.state // "") != "" and (.status // "") == "")) then
          select(
            ((.state // "") | tostring | ascii_upcase) != "SUCCESS"
            and ((.state // "") | tostring | ascii_upcase) != "FAILURE"
            and ((.state // "") | tostring | ascii_upcase) != "ERROR"
          )
        else
          select(((.status // "") | tostring | ascii_upcase) != "COMPLETED" or (.conclusion // "") == "")
        end
    ] | length' <<<"$pr")"
    if [[ "$checks_total" -eq 0 ]]; then
      checks_pending=1
    fi
    unresolved_threads="$(jq '[.reviewThreads[]? | select(.isResolved != true and (.isOutdated != true))] | length' <<<"$pr")"
    review_threads_fetched="$(jq '[.reviewThreads[]?] | length' <<<"$pr")"
    review_threads_total="$(jq '.reviewThreadsTotalCount // ([.reviewThreads[]?] | length)' <<<"$pr")"
    closing_count="$(jq '[.closingIssuesReferences[]?] | length' <<<"$pr")"
    body_closes=0
    if body_has_closing_keyword "$body"; then
      body_closes=1
    fi
    closes_issues=$((closing_count + body_closes))
    review_requests="$(jq '[.reviewRequests[]?] | length' <<<"$pr")"
    review_decision="$(jq -r '.reviewDecision // ""' <<<"$pr")"

    if [[ "$base" != "$base_branch" ]]; then
      add_warning "PR #$number is stacked on $base; merge base first, then retarget to $base_branch"
      pr_warnings=$((pr_warnings + 1))
      if [[ "$closes_issues" -gt 0 ]]; then
        add_finding "PR #$number is stacked but closes issues; retarget to $base_branch or use Refs"
        pr_blockers=$((pr_blockers + 1))
      fi
    fi

    if [[ "$mergeable" == "CONFLICTING" ]]; then
      add_finding "PR #$number has merge conflicts"
      pr_blockers=$((pr_blockers + 1))
    elif [[ "$mergeable" != "MERGEABLE" ]]; then
      add_finding "PR #$number mergeability is $mergeable"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$checks_failed" -gt 0 ]]; then
      add_finding "PR #$number has failing checks: $checks_failed"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$checks_pending" -gt 0 ]]; then
      add_finding "PR #$number has pending checks: $checks_pending"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$unresolved_threads" -gt 0 ]]; then
      add_finding "PR #$number has unresolved review threads: $unresolved_threads"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$review_threads_total" -gt "$review_threads_fetched" ]]; then
      add_finding "PR #$number review thread page incomplete: fetched $review_threads_fetched of $review_threads_total"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$review_requests" -gt 0 ]]; then
      add_finding "PR #$number has pending review requests: $review_requests"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$review_decision" != "APPROVED" ]]; then
      add_finding "PR #$number review decision is ${review_decision:-missing}"
      pr_blockers=$((pr_blockers + 1))
    fi

    if [[ "$closes_issues" -gt 0 ]] && ! body_has_verification "$body"; then
      add_finding "PR #$number closes issues but lacks verification evidence"
      pr_blockers=$((pr_blockers + 1))
    fi
  done < <(jq -c '.prs[]?' <<<"$evidence_json")

  local findings_count warnings_count decision exit_code
  local release_artifact_findings_count
  release_artifact_findings_count="$(jq 'length' <<<"$release_artifact_findings_json")"
  findings_count="$(jq 'length' <<<"$findings_json")"
  warnings_count="$(jq 'length' <<<"$warnings_json")"
  decision="ready"
  exit_code=0
  if [[ "$findings_count" -gt 0 || "$release_artifact_findings_count" -gt 0 ]]; then
    decision="block"
    exit_code=1
  elif [[ "$warnings_count" -gt 0 ]]; then
    decision="warn"
  fi

  local counts_json
  counts_json="$(jq -nc \
    --argjson prs "$prs_total" \
    --argjson findings "$findings_count" \
    --argjson warnings "$warnings_count" \
    --argjson release_artifact_findings "$release_artifact_findings_count" \
    --argjson pr_blockers "$pr_blockers" \
    --argjson pr_warnings "$pr_warnings" \
    '{prs: $prs, findings: $findings, warnings: $warnings, release_artifact_findings: $release_artifact_findings, pr_blockers: $pr_blockers, pr_warnings: $pr_warnings}')"

  if [[ "$json_output" -eq 1 ]]; then
    jq -nc \
      --arg target "$target_tag" \
      --arg mode "$mode" \
      --arg decision "$decision" \
      --arg base "$base_branch" \
      --argjson counts "$counts_json" \
      --argjson findings "$findings_json" \
      --argjson warnings "$warnings_json" \
      --argjson release_artifact_findings "$release_artifact_findings_json" \
      '{target: $target, mode: $mode, base: $base, decision: $decision, counts: $counts, findings: $findings, warnings: $warnings, release_artifact_findings: $release_artifact_findings}'
    exit "$exit_code"
  fi

  printf 'Walter-OS release doctor\n'
  printf 'Target: %s\n' "$target_tag"
  printf 'Mode: %s\n' "$mode"
  printf 'Base: %s\n' "$base_branch"
  local status_label="PASS"
  if [[ "$decision" == "block" ]]; then
    status_label="FAIL"
  elif [[ "$decision" == "warn" ]]; then
    status_label="WARN"
  fi
  printf 'Status: %s\n' "$status_label"
  printf 'Decision: %s\n' "$decision"
  printf '\nCounts:\n'
  jq -r 'to_entries[] | "  \(.key): \(.value)"' <<<"$counts_json"
  printf '\nFindings:\n'
  if [[ "$findings_count" -eq 0 ]]; then
    printf '  none\n'
  else
    jq -r '.[] | "  - \(.)"' <<<"$findings_json"
  fi
  printf '\nRelease artifact findings:\n'
  if [[ "$release_artifact_findings_count" -eq 0 ]]; then
    printf '  none\n'
  else
    jq -r '.[] | "  - \(.)"' <<<"$release_artifact_findings_json"
  fi
  printf '\nWarnings:\n'
  if [[ "$warnings_count" -eq 0 ]]; then
    printf '  none\n'
  else
    jq -r '.[] | "  - \(.)"' <<<"$warnings_json"
  fi

  exit "$exit_code"
}

subcommand="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$subcommand" in
  doctor)
    cmd_doctor "$@"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "walter-os release: unknown subcommand: $subcommand" >&2
    usage >&2
    exit "$USAGE_ERROR_EXIT"
    ;;
esac
