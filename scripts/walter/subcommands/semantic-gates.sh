#!/usr/bin/env bash
# walter-os semantic-gates - run semantic readiness checks for a spec.
#
# Usage:
#   walter-os semantic-gates <docs/specs/name.md> [--repo DIR] [--tests-dir DIR] [--json]
#   walter-os semantic-gates help
#
# Gates:
#   spec-completeness  Required problem/non-goals/AC/test-plan sections.
#   ac-testability     AC bullets must use observable verification language.
#   architecture-review Decision/review/risk evidence must exist in the spec.
#   test-relevance     At least one test file must reference the spec path.
set -euo pipefail

print_help() {
  awk '/^[^#]/ && NR > 1 { exit } /^#( |$)/ { sub(/^# ?/, ""); print }' "$0"
}

abs_path() {
  local target="$1"
  if [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
  else
    local dir base
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
  fi
}

usage_error() {
  echo "semantic-gates: $*" >&2
  print_help >&2
  exit 2
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

add_failure() {
  local gate="$1" message="$2"
  case "$gate" in
    spec-completeness) spec_failures="${spec_failures}${message}"$'\n' ;;
    ac-testability) ac_failures="${ac_failures}${message}"$'\n' ;;
    architecture-review) arch_failures="${arch_failures}${message}"$'\n' ;;
    test-relevance) test_failures="${test_failures}${message}"$'\n' ;;
  esac
}

add_evidence() {
  local gate="$1" message="$2"
  case "$gate" in
    spec-completeness) spec_evidence="${spec_evidence}${message}"$'\n' ;;
    ac-testability) ac_evidence="${ac_evidence}${message}"$'\n' ;;
    architecture-review) arch_evidence="${arch_evidence}${message}"$'\n' ;;
    test-relevance) test_evidence="${test_evidence}${message}"$'\n' ;;
  esac
}

has_heading() {
  local pattern="$1"
  grep -Eiq "^#{2,3}[[:space:]]+${pattern}([[:space:]]|$)" "$spec_file"
}

section_body() {
  local pattern="$1"
  awk -v pattern="$pattern" '
    BEGIN { in_section = 0 }
    /^#{2,3}[[:space:]]+/ {
      heading = $0
      sub(/^#{2,3}[[:space:]]+/, "", heading)
      if (heading ~ pattern) {
        in_section = 1
        next
      }
      if (in_section) {
        exit
      }
    }
    in_section { print }
  ' "$spec_file"
}

check_spec_completeness() {
  if has_heading "(Problem|Goal|Goals|Context)"; then
    add_evidence "spec-completeness" "problem/context section present"
  else
    add_failure "spec-completeness" "missing problem/context section"
  fi

  if has_heading "Non-goals"; then
    add_evidence "spec-completeness" "non-goals section present"
  else
    add_failure "spec-completeness" "missing non-goals section"
  fi

  if has_heading "Acceptance criteria"; then
    add_evidence "spec-completeness" "acceptance criteria section present"
  else
    add_failure "spec-completeness" "missing acceptance criteria section"
  fi

  if has_heading "(Test plan|Verification|Tests)"; then
    add_evidence "spec-completeness" "test/verification section present"
  else
    add_failure "spec-completeness" "missing test/verification section"
  fi
}

check_ac_testability() {
  local ac_body ac_lines weak_lines
  ac_body="$(section_body "^(Acceptance criteria|Acceptance Criteria)")"
  ac_lines="$(printf '%s\n' "$ac_body" | grep -Ei '^[[:space:]]*[-*][[:space:]]+\[[ xX]?\][[:space:]]*(AC-[0-9]+|[A-Z]+-[0-9]+|[A-Za-z0-9 _/-]+:)' || true)"

  if [[ -z "$ac_lines" ]]; then
    add_failure "ac-testability" "missing checkbox AC bullets"
    return
  fi

  weak_lines="$(printf '%s\n' "$ac_lines" | grep -Eiv '(test|verify|assert|coverage|exit|fail|pass|emit|block|allow|return|record|create|update|validate|refuse|render|link|include)' || true)"
  if [[ -n "$weak_lines" ]]; then
    add_failure "ac-testability" "AC bullets must include observable verification language"
    while IFS= read -r line; do
      [[ -n "$line" ]] && add_failure "ac-testability" "weak AC: $line"
    done <<<"$weak_lines"
  else
    add_evidence "ac-testability" "AC bullets use observable verification language"
  fi
}

check_architecture_review() {
  if has_heading "(Architecture review|Architecture|Decisions|Cross-cutting decisions|Threat model|Risks)"; then
    add_evidence "architecture-review" "architecture/decision/risk section present"
  else
    add_failure "architecture-review" "missing architecture/decision/risk section"
  fi

  if grep -Eiq '(ADR-[0-9]+|DEC-[0-9]+|decision|rationale|risk|threat|review)' "$spec_file"; then
    add_evidence "architecture-review" "reviewable decision/risk language present"
  else
    add_failure "architecture-review" "missing reviewable decision/risk language"
  fi
}

check_test_relevance() {
  local tests_dir="$1" match_file rel_match
  if [[ ! -d "$tests_dir" ]]; then
    add_failure "test-relevance" "tests directory not found: $tests_dir"
    return
  fi

  match_file="$(mktemp "${TMPDIR:-/tmp}/walter-semantic-gates.XXXXXX")"
  find "$tests_dir" -type f \( -name '*.bats' -o -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.tsx' \) -print |
    while IFS= read -r file; do
      if grep -qF "$spec_rel" "$file"; then
        printf '%s\n' "$file" >> "$match_file"
      fi
    done

  if [[ ! -s "$match_file" ]]; then
    rm -f "$match_file"
    add_failure "test-relevance" "no test file references $spec_rel"
    return
  fi

  while IFS= read -r match; do
    rel_match="$match"
    case "$rel_match" in
      "$repo_dir"/*) rel_match="${rel_match#"$repo_dir"/}" ;;
    esac
    add_evidence "test-relevance" "$rel_match"
  done < "$match_file"
  rm -f "$match_file"
}

print_gate_text() {
  local name="$1" failures="$2" evidence="$3"
  if [[ -n "$failures" ]]; then
    printf '%s: fail\n' "$name"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '  - %s\n' "$line"
    done <<<"$failures"
  else
    printf '%s: pass\n' "$name"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '  - %s\n' "$line"
    done <<<"$evidence"
  fi
  return 0
}

json_array_from_lines() {
  local lines="$1" first=1 line
  printf '['
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$first" -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$line")"
  done <<<"$lines"
  printf ']'
  return 0
}

print_gate_json() {
  local name="$1" failures="$2" evidence="$3" status="pass"
  [[ -n "$failures" ]] && status="fail"
  printf '"%s":{"status":"%s","messages":' "$name" "$status"
  json_array_from_lines "$failures"
  printf ',"evidence":'
  json_array_from_lines "$evidence"
  printf '}'
  return 0
}

cmd="${1:-help}"
if [[ "$cmd" =~ ^(-h|--help|help)$ ]]; then
  print_help
  exit 0
fi

spec_arg=""
repo_arg=""
tests_arg=""
json_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || usage_error "--repo requires a directory"
      repo_arg="$2"
      shift 2
      ;;
    --tests-dir)
      [[ $# -ge 2 ]] || usage_error "--tests-dir requires a directory"
      tests_arg="$2"
      shift 2
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help|help)
      print_help
      exit 0
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      if [[ -n "$spec_arg" ]]; then
        usage_error "unexpected argument: $1"
      fi
      spec_arg="$1"
      shift
      ;;
  esac
done

[[ -n "$spec_arg" ]] || usage_error "missing spec file"
[[ -f "$spec_arg" ]] || usage_error "spec file not found: $spec_arg"

spec_file="$(abs_path "$spec_arg")"
repo_dir="${repo_arg:-}"
if [[ -z "$repo_dir" ]]; then
  if repo_dir="$(git -C "$(dirname "$spec_file")" rev-parse --show-toplevel 2>/dev/null)"; then
    repo_dir="$(abs_path "$repo_dir")"
  else
    repo_dir="$(abs_path "$(dirname "$spec_file")/../..")"
  fi
else
  [[ -d "$repo_arg" ]] || usage_error "repo directory not found: $repo_arg"
  repo_dir="$(abs_path "$repo_arg")"
fi

tests_dir="${tests_arg:-${repo_dir}/tests}"
tests_dir="$(abs_path "$tests_dir" 2>/dev/null || printf '%s\n' "$tests_dir")"

spec_rel="$spec_file"
case "$spec_rel" in
  "$repo_dir"/*) spec_rel="${spec_rel#"$repo_dir"/}" ;;
esac

spec_failures=""
ac_failures=""
arch_failures=""
test_failures=""
spec_evidence=""
ac_evidence=""
arch_evidence=""
test_evidence=""

check_spec_completeness
check_ac_testability
check_architecture_review
check_test_relevance "$tests_dir"

status="pass"
if [[ -n "$spec_failures$ac_failures$arch_failures$test_failures" ]]; then
  status="fail"
fi

if [[ "$json_output" -eq 1 ]]; then
  printf '{"status":"%s","spec":"%s","gates":{' "$status" "$(json_escape "$spec_rel")"
  print_gate_json "spec-completeness" "$spec_failures" "$spec_evidence"
  printf ','
  print_gate_json "ac-testability" "$ac_failures" "$ac_evidence"
  printf ','
  print_gate_json "architecture-review" "$arch_failures" "$arch_evidence"
  printf ','
  print_gate_json "test-relevance" "$test_failures" "$test_evidence"
  printf '}}\n'
else
  printf 'semantic-gates: %s\n' "$status"
  printf 'spec: %s\n' "$spec_rel"
  print_gate_text "spec-completeness" "$spec_failures" "$spec_evidence"
  print_gate_text "ac-testability" "$ac_failures" "$ac_evidence"
  print_gate_text "architecture-review" "$arch_failures" "$arch_evidence"
  print_gate_text "test-relevance" "$test_failures" "$test_evidence"
fi

[[ "$status" == "pass" ]] || exit 1
