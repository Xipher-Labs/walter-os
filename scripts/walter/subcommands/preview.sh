#!/usr/bin/env bash
# scripts/walter/subcommands/preview.sh
# Preview environment evidence bundling for AD-10.

set -euo pipefail

USAGE_ERROR_EXIT=64
RUNTIME_ERROR_EXIT=4

usage() {
  cat <<'EOF'
Usage: walter-os preview bundle --pr <number> --url <url> --seed <path> --screenshot <path> [--screenshot <path>...] [--out <dir>] [--json]

Creates a local preview evidence bundle from an existing preview URL, seed
manifest, and screenshots. The command does not deploy, mint credentials, or
touch production secrets.

Subcommands:
  bundle    Build .walter/previews/preview-pr-<number>/ evidence bundle.

Options for bundle:
  --pr <number>          Pull request number.
  --url <url>            Preview URL. Must start with http:// or https://.
  --seed <path>          Seed data manifest or fixture used for preview.
  --screenshot <path>    Screenshot artifact. Repeat for multiple screenshots.
  --out <dir>            Output root. Defaults to .walter/previews.
  --json                 Print preview-report JSON instead of a short summary.
EOF
}

die_usage() {
  echo "walter-os preview: $1" >&2
  echo >&2
  usage >&2
  exit "$USAGE_ERROR_EXIT"
}

die_runtime() {
  echo "walter-os preview: $1" >&2
  exit "$RUNTIME_ERROR_EXIT"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die_runtime "jq is required"
  fi
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  else
    die_runtime "sha256sum or shasum is required"
  fi
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

path_base() {
  local path="$1"
  printf '%s\n' "${path##*/}"
}

reject_secret_like_artifact() {
  local path="$1" base lower
  base="$(path_base "$path")"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    .env|.env.*|*.env|*.pem|*.key|*.p12|*.pfx|id_rsa|id_dsa|id_ed25519|*secret*|*token*|*credential*)
      die_usage "refusing secret-like artifact: $path"
      ;;
  esac
}

validate_artifact() {
  local path="$1"
  if [[ -z "$path" ]]; then
    die_usage "artifact path cannot be empty"
  fi
  if [[ -L "$path" ]]; then
    die_usage "refusing symlink artifact: $path"
  fi
  if [[ ! -f "$path" || ! -r "$path" ]]; then
    die_usage "artifact is not a readable file: $path"
  fi
  reject_secret_like_artifact "$path"
}

artifact_json() {
  local source="$1" dest="$2"
  jq -nc \
    --arg source "$source" \
    --arg path "$dest" \
    --arg sha256 "$(sha256_file "$source")" \
    --argjson bytes "$(file_size "$source")" \
    '{
      source: $source,
      path: $path,
      sha256: $sha256,
      bytes: $bytes
    }'
}

copy_artifact() {
  local source="$1" dest_dir="$2" dest
  dest="${dest_dir}/$(path_base "$source")"
  if [[ -e "$dest" ]]; then
    die_usage "duplicate artifact basename: $(path_base "$source")"
  fi
  cp -p -- "$source" "$dest"
  printf '%s\n' "$dest"
}

cmd_bundle() {
  require_jq

  local pr="" url="" seed="" out_root=".walter/previews" json_output=0
  local -a screenshots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr)
        pr="${2:-}"
        [[ -n "$pr" ]] || die_usage "--pr requires a value"
        shift 2
        ;;
      --url)
        url="${2:-}"
        [[ -n "$url" ]] || die_usage "--url requires a value"
        shift 2
        ;;
      --seed)
        seed="${2:-}"
        [[ -n "$seed" ]] || die_usage "--seed requires a value"
        shift 2
        ;;
      --screenshot)
        screenshots+=("${2:-}")
        [[ -n "${2:-}" ]] || die_usage "--screenshot requires a value"
        shift 2
        ;;
      --out)
        out_root="${2:-}"
        [[ -n "$out_root" ]] || die_usage "--out requires a value"
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
        die_usage "unknown option: $1"
        ;;
      *)
        die_usage "unexpected argument: $1"
        ;;
    esac
  done

  [[ "$pr" =~ ^[1-9][0-9]*$ ]] || die_usage "--pr must be a positive integer"
  [[ "$url" =~ ^https?:// ]] || die_usage "preview URL must start with http:// or https://"
  [[ -n "$seed" ]] || die_usage "--seed is required"
  [[ "${#screenshots[@]}" -gt 0 ]] || die_usage "at least one --screenshot is required"

  validate_artifact "$seed"
  local screenshot
  for screenshot in "${screenshots[@]}"; do
    validate_artifact "$screenshot"
  done

  local bundle_dir seed_dir screenshot_dir report_path readme_path
  bundle_dir="${out_root%/}/preview-pr-${pr}"
  seed_dir="${bundle_dir}/seed"
  screenshot_dir="${bundle_dir}/screenshots"
  report_path="${bundle_dir}/preview-report.json"
  readme_path="${bundle_dir}/README.md"

  mkdir -p "$seed_dir" "$screenshot_dir"

  local seed_dest screenshots_json="[]" screenshot_dest
  seed_dest="$(copy_artifact "$seed" "$seed_dir")"
  for screenshot in "${screenshots[@]}"; do
    screenshot_dest="$(copy_artifact "$screenshot" "$screenshot_dir")"
    screenshots_json="$(jq -c \
      --argjson item "$(artifact_json "$screenshot" "$screenshot_dest")" \
      '. + [$item]' <<<"$screenshots_json")"
  done

  local generated_at report_json
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  report_json="$(jq -nc \
    --argjson pr "$pr" \
    --arg url "$url" \
    --arg generated_at "$generated_at" \
    --arg bundle_dir "$bundle_dir" \
    --argjson seed_manifest "$(artifact_json "$seed" "$seed_dest")" \
    --argjson screenshots "$screenshots_json" \
    '{
      schema_version: 1,
      pr: $pr,
      url: $url,
      generated_at: $generated_at,
      bundle_dir: $bundle_dir,
      seed_manifest: $seed_manifest,
      screenshots: $screenshots,
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved"
      }
    }')"

  printf '%s\n' "$report_json" | jq . > "$report_path"
  {
    printf '# Preview Bundle PR #%s\n\n' "$pr"
    printf -- '- URL: %s\n' "$url"
    printf -- "- Seed manifest: \`%s\`\n" "${seed_dest#"$bundle_dir"/}"
    printf -- '- Screenshots: %s\n' "${#screenshots[@]}"
    printf -- '- Safety: production secrets rejected; deploy not performed.\n'
  } > "$readme_path"

  if [[ "$json_output" -eq 1 ]]; then
    printf '%s\n' "$report_json" | jq .
  else
    printf 'preview: bundle written %s\n' "$bundle_dir"
    printf 'preview: report %s\n' "$report_path"
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  bundle)
    cmd_bundle "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die_usage "unknown command: $cmd"
    ;;
esac
