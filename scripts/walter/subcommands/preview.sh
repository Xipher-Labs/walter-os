#!/usr/bin/env bash
# scripts/walter/subcommands/preview.sh
# Preview environment evidence bundling for AD-10.

set -euo pipefail

USAGE_ERROR_EXIT=64
RUNTIME_ERROR_EXIT=4

usage() {
  cat <<'EOF'
Usage: walter-os preview bundle --pr <number> --url <url> --seed <path> --screenshot <path> [--screenshot <path>...] [--out <dir>] [--json]
       walter-os preview plan --dry-run --pr <number> --provider <provider> --app <name> --branch <branch> --seed <path> [--config <path>] [--out <dir>] [--json]
       walter-os preview capture --pr <number> --url <url> --name <slug> [--out <dir>] [--wait-ms <ms>] [--json]
       walter-os preview local --pr <number> --url <loopback-url> --seed <path> --screenshot <path> [--screenshot <path>...] [--config <path>] [--out <dir>] [--json]
       walter-os preview verify --pr <number> [--out <dir>] [--json]

Creates a local preview evidence bundle from an existing preview URL, captures
screenshots, writes a dry-run preview deployment plan, or records a loopback
local preview adapter result. The commands do not deploy to cloud providers,
mint credentials, or touch production secrets.

Subcommands:
  bundle    Build .walter/previews/preview-pr-<number>/ evidence bundle.
  capture   Capture a screenshot artifact from an existing preview URL.
  local     Package a loopback local preview as provider=local evidence.
  plan      Write a dry-run preview deployment plan.
  verify    Validate preview report or dry-run plan evidence.

Options for bundle:
  --pr <number>          Pull request number.
  --url <url>            Preview URL. Must start with http:// or https://.
  --seed <path>          Seed data manifest or fixture used for preview.
  --screenshot <path>    Screenshot artifact. Repeat for multiple screenshots.
  --out <dir>            Output root. Defaults to .walter/previews.
  --json                 Print preview-report JSON instead of a short summary.

Options for capture:
  --pr <number>          Pull request number.
  --url <url>            Preview URL. Must start with http:// or https://.
  --name <slug>          Screenshot basename without extension.
  --out <dir>            Output root. Defaults to .walter/previews.
  --wait-ms <ms>         Playwright wait timeout before capture. Defaults to 1000.
  --json                 Print screenshot artifact JSON.

Options for plan:
  --dry-run              Required. Plan only; never deploy.
  --pr <number>          Pull request number.
  --provider <provider>  One of local, vercel, cloudflare-pages, netlify,
                         railway, forgejo-actions.
  --app <name>           App/project slug for the preview target.
  --branch <branch>      Branch/ref to deploy.
  --seed <path>          Seed data manifest or fixture used for preview.
  --config <path>        walter-repo-config.yaml path. Defaults to cwd.
  --out <dir>            Output root. Defaults to .walter/previews.
  --json                 Print preview-plan JSON instead of a short summary.

Options for local:
  --pr <number>          Pull request number.
  --url <loopback-url>   Existing local preview URL. Must use localhost,
                         127.0.0.1, or [::1].
  --seed <path>          Seed data manifest or fixture used for preview.
  --screenshot <path>    Screenshot artifact. Repeat for multiple screenshots.
  --config <path>        walter-repo-config.yaml path. Defaults to cwd.
  --out <dir>            Output root. Defaults to .walter/previews.
  --json                 Print preview-report JSON instead of a short summary.

Options for verify:
  --pr <number>          Pull request number.
  --out <dir>            Output root. Defaults to .walter/previews.
  --json                 Print verification JSON instead of a short summary.
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

resolve_npx() {
  if [[ -n "${WALTER_PREVIEW_NPX:-}" ]]; then
    if [[ -f "$WALTER_PREVIEW_NPX" && -x "$WALTER_PREVIEW_NPX" && ! -L "$WALTER_PREVIEW_NPX" ]]; then
      printf '%s\n' "$WALTER_PREVIEW_NPX"
      return 0
    fi
    die_runtime "npx is required for preview capture"
  fi
  if command -v npx >/dev/null 2>&1; then
    command -v npx
    return 0
  fi
  die_runtime "npx is required for preview capture"
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

cp_operand() {
  local path="$1"
  case "$path" in
    -*)
      printf './%s\n' "$path"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
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

validate_positive_pr() {
  local pr="$1"
  [[ "$pr" =~ ^[1-9][0-9]*$ ]] || die_usage "--pr must be a positive integer"
}

validate_provider() {
  local provider="$1"
  case "$provider" in
    local|vercel|cloudflare-pages|netlify|railway|forgejo-actions)
      ;;
    *)
      die_usage "unsupported preview provider: $provider"
      ;;
  esac
}

validate_slug() {
  local label="$1" value="$2"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die_usage "${label} must be a safe slug"
}

validate_branch_ref() {
  local branch="$1"
  [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || die_usage "--branch must be a safe branch/ref"
  case "$branch" in
    /*|*..*|*//*)
      die_usage "--branch must be a safe branch/ref"
      ;;
  esac
}

validate_wait_ms() {
  local wait_ms="$1" normalized
  [[ "$wait_ms" =~ ^[0-9]+$ ]] || die_usage "--wait-ms must be a non-negative integer"
  normalized="$wait_ms"
  while [[ "$normalized" == 0* && "${#normalized}" -gt 1 ]]; do
    normalized="${normalized#0}"
  done
  [[ "${#normalized}" -le 5 ]] || die_usage "--wait-ms must be <= 30000"
  (( 10#$normalized <= 30000 )) || die_usage "--wait-ms must be <= 30000"
}

validate_loopback_preview_url() {
  local url="$1" loopback_url_re='^https?://(localhost|127\.0\.0\.1|\[::1\])($|[:/?#])'
  [[ "$url" =~ ^https?:// ]] || die_usage "preview URL must start with http:// or https://"
  [[ "$url" =~ $loopback_url_re ]] \
    || die_usage "local preview URL must use localhost, 127.0.0.1, or [::1]"
}

repo_config_path() {
  local configured="$1"
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
  else
    printf '%s\n' "$(pwd)/walter-repo-config.yaml"
  fi
}

preview_deploy_enabled() {
  local config_path="$1"
  if [[ -e "$config_path" && ( ! -f "$config_path" || ! -r "$config_path" ) ]]; then
    die_usage "config is not a readable file: $config_path"
  fi
  if [[ ! -f "$config_path" ]]; then
    printf 'false\n'
    return 0
  fi

  local key_count value="" parsed
  key_count="$(grep -Ec '^preview_deploy[[:space:]]*:' < "$config_path" || true)"

  if (( key_count > 1 )); then
    die_usage "multiple preview_deploy keys in config: $config_path"
  fi
  if (( key_count == 1 )); then
    parsed="$(sed -nE 's/^preview_deploy[[:space:]]*:[[:space:]]*([Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee])[[:space:]]*(#.*)?$/\1/p' < "$config_path")"
    if [[ -z "$parsed" ]]; then
      die_usage "preview_deploy must be true or false in config: $config_path"
    fi
    value="$(printf '%s' "$parsed" | tr '[:upper:]' '[:lower:]')"
  fi

  printf '%s\n' "${value:-false}"
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
  local source="$1" dest_dir="$2" dest source_operand dest_operand
  dest="${dest_dir}/$(path_base "$source")"
  if [[ -e "$dest" ]]; then
    die_usage "duplicate artifact basename: $(path_base "$source")"
  fi
  source_operand="$(cp_operand "$source")"
  dest_operand="$(cp_operand "$dest")"
  cp -p "$source_operand" "$dest_operand"
  printf '%s\n' "$dest"
}

findings_json() {
  if [[ "$#" -eq 0 ]]; then
    printf '[]\n'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

resolve_evidence_path() {
  local bundle_dir="$1" path="$2"
  local bundle_trimmed="${bundle_dir%/}" bundle_abs relative_path bundle_prefix bundle_abs_prefix

  case "$path" in
    ..|../*|*/..|*/../*)
      return 1
      ;;
  esac

  if ! bundle_abs="$(cd "$bundle_trimmed" 2>/dev/null && pwd -P)"; then
    return 1
  fi

  bundle_prefix="${bundle_trimmed}/"
  bundle_abs_prefix="${bundle_abs}/"
  if [[ "${path:0:${#bundle_prefix}}" == "$bundle_prefix" ]]; then
    relative_path="${path:${#bundle_prefix}}"
    printf '%s\n' "${bundle_trimmed}/${relative_path}"
  elif [[ "${path:0:${#bundle_abs_prefix}}" == "$bundle_abs_prefix" ]]; then
    relative_path="${path:${#bundle_abs_prefix}}"
    printf '%s\n' "${bundle_trimmed}/${relative_path}"
  elif [[ "$path" == /* ]]; then
    return 1
  else
    printf '%s\n' "${bundle_trimmed}/${path}"
  fi
}

verify_hash_artifact() {
  local bundle_dir="$1" label="$2" path="$3" expected_sha="$4"
  local resolved actual_sha bundle_physical resolved_base resolved_dir resolved_dir_physical resolved_physical

  if [[ -z "$path" || "$path" == "null" ]]; then
    printf '%s\n' "${label} path is missing"
    return 0
  fi
  if [[ -z "$expected_sha" || "$expected_sha" == "null" || ! "$expected_sha" =~ ^[a-f0-9]{64}$ ]]; then
    printf '%s\n' "${label} hash is missing or invalid"
    return 0
  fi

  if ! resolved="$(resolve_evidence_path "$bundle_dir" "$path")"; then
    printf '%s\n' "${label} path escapes preview bundle"
    return 0
  fi
  if [[ -L "$resolved" ]]; then
    printf '%s\n' "${label} is a symlink"
    return 0
  fi
  if [[ ! -f "$resolved" || ! -r "$resolved" ]]; then
    printf '%s\n' "${label} file is missing or unreadable"
    return 0
  fi
  if ! bundle_physical="$(cd "$bundle_dir" 2>/dev/null && pwd -P)"; then
    printf '%s\n' "${label} path escapes preview bundle"
    return 0
  fi
  resolved_base="$(path_base "$resolved")"
  resolved_dir="${resolved%/*}"
  if [[ "$resolved_dir" == "$resolved" ]]; then
    resolved_dir="."
  fi
  if ! resolved_dir_physical="$(cd "$resolved_dir" 2>/dev/null && pwd -P)"; then
    printf '%s\n' "${label} file is missing or unreadable"
    return 0
  fi
  resolved_physical="${resolved_dir_physical}/${resolved_base}"
  local bundle_physical_prefix="${bundle_physical}/"
  if [[ "${resolved_physical:0:${#bundle_physical_prefix}}" != "$bundle_physical_prefix" ]]; then
    printf '%s\n' "${label} path escapes preview bundle"
    return 0
  fi

  actual_sha="$(sha256_file "$resolved")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    case "$label" in
      screenshot\ *)
        printf '%s\n' "screenshot hash mismatch: ${label#screenshot }"
        ;;
      *)
        printf '%s\n' "${label} hash mismatch"
        ;;
    esac
  fi
}

validate_evidence_json_file() {
  local label="$1" path="$2"

  if [[ -L "$path" ]]; then
    printf '%s\n' "${label} is a symlink"
    return 1
  fi
  if [[ ! -f "$path" || ! -r "$path" ]]; then
    printf '%s\n' "${label} file is missing or unreadable"
    return 1
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    printf '%s\n' "${label} is not valid JSON"
    return 1
  fi
}

cmd_capture() {
  require_jq

  local pr="" url="" name="" out_root=".walter/previews" wait_ms=1000 json_output=0

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
      --name)
        name="${2:-}"
        [[ -n "$name" ]] || die_usage "--name requires a value"
        shift 2
        ;;
      --out)
        out_root="${2:-}"
        [[ -n "$out_root" ]] || die_usage "--out requires a value"
        shift 2
        ;;
      --wait-ms)
        wait_ms="${2:-}"
        [[ -n "$wait_ms" ]] || die_usage "--wait-ms requires a value"
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

  validate_positive_pr "$pr"
  [[ "$url" =~ ^https?:// ]] || die_usage "preview URL must start with http:// or https://"
  [[ -n "$name" ]] || die_usage "--name is required"
  validate_slug "--name" "$name"
  validate_wait_ms "$wait_ms"

  local npx_path bundle_dir screenshot_dir screenshot_path screenshot_tmp generated_at capture_json ln_output
  npx_path="$(resolve_npx)"
  bundle_dir="${out_root%/}/preview-pr-${pr}"
  screenshot_dir="${bundle_dir}/screenshots"
  screenshot_path="${screenshot_dir}/${name}.png"
  reject_secret_like_artifact "$screenshot_path"
  mkdir -p -- "$screenshot_dir"

  if [[ -e "$screenshot_path" ]]; then
    die_usage "screenshot already exists: $screenshot_path"
  fi

  screenshot_tmp="$(mktemp "${screenshot_dir}/.${name}.tmp.XXXXXX")" \
    || die_runtime "could not create temporary screenshot path"
  if ! "$npx_path" --no-install playwright screenshot --wait-for-timeout "$wait_ms" "$url" "$screenshot_tmp"; then
    rm -f -- "$screenshot_tmp"
    die_runtime "preview screenshot capture failed"
  fi
  validate_artifact "$screenshot_tmp"
  if ! ln_output="$(ln -- "$screenshot_tmp" "$screenshot_path" 2>&1)"; then
    rm -f -- "$screenshot_tmp"
    if [[ -e "$screenshot_path" ]]; then
      die_usage "screenshot already exists: $screenshot_path"
    fi
    if [[ -n "$ln_output" ]]; then
      printf '%s\n' "$ln_output" >&2
    fi
    die_runtime "could not publish screenshot: $screenshot_path"
  fi
  rm -f -- "$screenshot_tmp"
  validate_artifact "$screenshot_path"

  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  capture_json="$(jq -nc \
    --argjson pr "$pr" \
    --arg url "$url" \
    --arg generated_at "$generated_at" \
    --arg bundle_dir "$bundle_dir" \
    --argjson screenshot "$(artifact_json "$screenshot_path" "$screenshot_path")" \
    '{
      schema_version: 1,
      kind: "preview-screenshot",
      pr: $pr,
      url: $url,
      generated_at: $generated_at,
      bundle_dir: $bundle_dir,
      screenshot: $screenshot,
      safety: {
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved"
      }
    }')"

  if [[ "$json_output" -eq 1 ]]; then
    printf '%s\n' "$capture_json" | jq .
  else
    printf 'preview: screenshot written %s\n' "$screenshot_path"
  fi
}

cmd_plan() {
  require_jq

  local pr="" provider="" app="" branch="" seed="" config="" out_root=".walter/previews" json_output=0 dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --pr)
        pr="${2:-}"
        [[ -n "$pr" ]] || die_usage "--pr requires a value"
        shift 2
        ;;
      --provider)
        provider="${2:-}"
        [[ -n "$provider" ]] || die_usage "--provider requires a value"
        shift 2
        ;;
      --app)
        app="${2:-}"
        [[ -n "$app" ]] || die_usage "--app requires a value"
        shift 2
        ;;
      --branch)
        branch="${2:-}"
        [[ -n "$branch" ]] || die_usage "--branch requires a value"
        shift 2
        ;;
      --seed)
        seed="${2:-}"
        [[ -n "$seed" ]] || die_usage "--seed requires a value"
        shift 2
        ;;
      --config)
        config="${2:-}"
        [[ -n "$config" ]] || die_usage "--config requires a value"
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

  [[ "$dry_run" -eq 1 ]] || die_usage "preview plan requires --dry-run"
  validate_positive_pr "$pr"
  [[ -n "$provider" ]] || die_usage "--provider is required"
  [[ -n "$app" ]] || die_usage "--app is required"
  [[ -n "$branch" ]] || die_usage "--branch is required"
  [[ -n "$seed" ]] || die_usage "--seed is required"
  validate_provider "$provider"
  validate_slug "--app" "$app"
  validate_branch_ref "$branch"
  validate_artifact "$seed"

  local config_path preview_enabled
  config_path="$(repo_config_path "$config")"
  preview_enabled="$(preview_deploy_enabled "$config_path")"
  if [[ "$preview_enabled" != "true" ]]; then
    die_usage "preview_deploy is not enabled in config: $config_path"
  fi

  local bundle_dir seed_dir plan_path generated_at plan_json seed_dest
  bundle_dir="${out_root%/}/preview-pr-${pr}"
  seed_dir="${bundle_dir}/seed"
  plan_path="${bundle_dir}/preview-plan.json"
  mkdir -p -- "$seed_dir"

  seed_dest="$(copy_artifact "$seed" "$seed_dir")"
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  plan_json="$(jq -nc \
    --argjson pr "$pr" \
    --arg provider "$provider" \
    --arg app "$app" \
    --arg branch "$branch" \
    --arg config_path "$config_path" \
    --arg generated_at "$generated_at" \
    --arg bundle_dir "$bundle_dir" \
    --argjson seed "$(artifact_json "$seed" "$seed_dest")" \
    '{
      schema_version: 1,
      kind: "preview-plan",
      pr: $pr,
      provider: $provider,
      app: $app,
      branch: $branch,
      generated_at: $generated_at,
      bundle_dir: $bundle_dir,
      config_path: $config_path,
      seed_manifest: $seed,
      actions: [
        "deploy_ephemeral_preview",
        "apply_seed_fixture",
        "capture_screenshots",
        "write_preview_bundle"
      ],
      safety: {
        dry_run: true,
        preview_deploy: true,
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved"
      }
    }')"

  printf '%s\n' "$plan_json" | jq . > "$plan_path"

  if [[ "$json_output" -eq 1 ]]; then
    printf '%s\n' "$plan_json" | jq .
  else
    printf 'preview: dry-run plan written %s\n' "$plan_path"
    printf 'preview: provider %s app %s branch %s\n' "$provider" "$app" "$branch"
  fi
}

cmd_local() {
  require_jq

  local pr="" url="" seed="" config="" out_root=".walter/previews" json_output=0
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
      --config)
        config="${2:-}"
        [[ -n "$config" ]] || die_usage "--config requires a value"
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

  validate_positive_pr "$pr"
  validate_loopback_preview_url "$url"
  [[ -n "$seed" ]] || die_usage "--seed is required"
  [[ "${#screenshots[@]}" -gt 0 ]] || die_usage "at least one --screenshot is required"
  validate_artifact "$seed"

  local screenshot
  for screenshot in "${screenshots[@]}"; do
    validate_artifact "$screenshot"
  done

  local config_path preview_enabled
  config_path="$(repo_config_path "$config")"
  preview_enabled="$(preview_deploy_enabled "$config_path")"
  if [[ "$preview_enabled" != "true" ]]; then
    die_usage "preview_deploy is not enabled in config: $config_path"
  fi

  local bundle_dir seed_dir screenshot_dir report_path readme_path
  bundle_dir="${out_root%/}/preview-pr-${pr}"
  seed_dir="${bundle_dir}/seed"
  screenshot_dir="${bundle_dir}/screenshots"
  report_path="${bundle_dir}/preview-report.json"
  readme_path="${bundle_dir}/README.md"

  mkdir -p -- "$seed_dir" "$screenshot_dir"

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
    --arg provider "local" \
    --arg generated_at "$generated_at" \
    --arg bundle_dir "$bundle_dir" \
    --arg config_path "$config_path" \
    --argjson seed_manifest "$(artifact_json "$seed" "$seed_dest")" \
    --argjson screenshots "$screenshots_json" \
    '{
      schema_version: 1,
      kind: "preview-report",
      provider: $provider,
      pr: $pr,
      url: $url,
      generated_at: $generated_at,
      bundle_dir: $bundle_dir,
      config_path: $config_path,
      seed_manifest: $seed_manifest,
      screenshots: $screenshots,
      actions: [
        "use_existing_local_preview",
        "apply_seed_fixture",
        "capture_screenshots",
        "write_preview_bundle"
      ],
      safety: {
        preview_deploy: true,
        production_secrets: "rejected",
        credentials: "not minted",
        deploy: "not performed",
        hard_limit_floor: "preserved"
      }
    }')"

  printf '%s\n' "$report_json" | jq . > "$report_path"
  {
    printf '# Local Preview Bundle PR #%s\n\n' "$pr"
    printf -- '- URL: %s\n' "$url"
    printf -- '- Provider: local\n'
    printf -- "- Seed manifest: \`%s\`\n" "${seed_dest#"$bundle_dir"/}"
    printf -- '- Screenshots: %s\n' "${#screenshots[@]}"
    printf -- '- Safety: preview deploy enabled; credentials not minted; deploy not performed.\n'
  } > "$readme_path"

  if [[ "$json_output" -eq 1 ]]; then
    printf '%s\n' "$report_json" | jq .
  else
    printf 'preview: local bundle written %s\n' "$bundle_dir"
    printf 'preview: report %s\n' "$report_path"
  fi
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

  mkdir -p -- "$seed_dir" "$screenshot_dir"

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

cmd_verify() {
  require_jq

  local pr="" out_root=".walter/previews" json_output=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr)
        pr="${2:-}"
        [[ -n "$pr" ]] || die_usage "--pr requires a value"
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

  validate_positive_pr "$pr"

  local bundle_dir report_path plan_path status kind screenshots_count=0
  local -a findings=()
  bundle_dir="${out_root%/}/preview-pr-${pr}"
  report_path="${bundle_dir}/preview-report.json"
  plan_path="${bundle_dir}/preview-plan.json"

  if [[ -e "$report_path" ]]; then
    kind="preview-report"
    local evidence_finding
    if ! evidence_finding="$(validate_evidence_json_file "preview report" "$report_path")"; then
      findings+=("$evidence_finding")
    else
      local report_pr report_kind report_schema report_url report_seed_path report_seed_sha
      report_pr="$(jq -r '.pr // empty' "$report_path")"
      report_kind="$(jq -r '.kind // "preview-report"' "$report_path")"
      report_schema="$(jq -r '.schema_version // empty' "$report_path")"
      report_url="$(jq -r '.url // empty' "$report_path")"
      report_seed_path="$(jq -r '.seed_manifest.path // empty' "$report_path")"
      report_seed_sha="$(jq -r '.seed_manifest.sha256 // empty' "$report_path")"
      screenshots_count="$(jq -r 'if (.screenshots | type) == "array" then (.screenshots | length) else 0 end' "$report_path")"

      [[ "$report_schema" == "1" ]] || findings+=("preview report schema is unsupported")
      [[ "$report_kind" == "preview-report" ]] || findings+=("preview report kind is unsupported")
      [[ "$report_pr" == "$pr" ]] || findings+=("preview report PR does not match")
      [[ "$report_url" =~ ^https?:// ]] || findings+=("preview report URL is missing or invalid")
      [[ "$(jq -r '.safety.production_secrets // empty' "$report_path")" == "rejected" ]] \
        || findings+=("preview report production secret invariant failed")
      [[ "$(jq -r '.safety.credentials // empty' "$report_path")" == "not minted" ]] \
        || findings+=("preview report credential invariant failed")
      [[ "$(jq -r '.safety.deploy // empty' "$report_path")" == "not performed" ]] \
        || findings+=("preview report deploy invariant failed")
      [[ "$(jq -r '.safety.hard_limit_floor // empty' "$report_path")" == "preserved" ]] \
        || findings+=("preview report hard-limit invariant failed")

      while IFS= read -r finding; do
        [[ -n "$finding" ]] && findings+=("$finding")
      done < <(verify_hash_artifact "$bundle_dir" "seed" "$report_seed_path" "$report_seed_sha")

      if [[ "$screenshots_count" =~ ^[0-9]+$ ]] && (( screenshots_count > 0 )); then
        local index screenshot_path screenshot_sha screenshot_label
        for (( index = 0; index < screenshots_count; index++ )); do
          screenshot_path="$(jq -r --argjson i "$index" '.screenshots[$i].path // empty' "$report_path")"
          screenshot_sha="$(jq -r --argjson i "$index" '.screenshots[$i].sha256 // empty' "$report_path")"
          screenshot_label="screenshot"
          if [[ -n "$screenshot_path" ]]; then
            screenshot_label="screenshot $(path_base "$screenshot_path")"
          fi
          while IFS= read -r finding; do
            [[ -n "$finding" ]] && findings+=("$finding")
          done < <(verify_hash_artifact "$bundle_dir" "$screenshot_label" "$screenshot_path" "$screenshot_sha")
        done
      else
        findings+=("preview report screenshots are missing")
      fi
    fi
    if [[ "${#findings[@]}" -eq 0 ]]; then
      status="ready"
    else
      status="invalid"
    fi
  elif [[ -e "$plan_path" ]]; then
    kind="preview-plan"
    local evidence_finding
    if ! evidence_finding="$(validate_evidence_json_file "preview plan" "$plan_path")"; then
      findings+=("$evidence_finding")
    else
      local plan_pr plan_schema plan_kind plan_seed_path plan_seed_sha
      plan_pr="$(jq -r '.pr // empty' "$plan_path")"
      plan_schema="$(jq -r '.schema_version // empty' "$plan_path")"
      plan_kind="$(jq -r '.kind // empty' "$plan_path")"
      plan_seed_path="$(jq -r '.seed_manifest.path // empty' "$plan_path")"
      plan_seed_sha="$(jq -r '.seed_manifest.sha256 // empty' "$plan_path")"

      [[ "$plan_schema" == "1" ]] || findings+=("preview plan schema is unsupported")
      [[ "$plan_kind" == "preview-plan" ]] || findings+=("preview plan kind is unsupported")
      [[ "$plan_pr" == "$pr" ]] || findings+=("preview plan PR does not match")
      [[ "$(jq -r '.safety.dry_run // empty' "$plan_path")" == "true" ]] \
        || findings+=("preview plan dry-run invariant failed")
      [[ "$(jq -r '.safety.preview_deploy // empty' "$plan_path")" == "true" ]] \
        || findings+=("preview plan preview_deploy invariant failed")
      [[ "$(jq -r '.safety.production_secrets // empty' "$plan_path")" == "rejected" ]] \
        || findings+=("preview plan production secret invariant failed")
      [[ "$(jq -r '.safety.credentials // empty' "$plan_path")" == "not minted" ]] \
        || findings+=("preview plan credential invariant failed")
      [[ "$(jq -r '.safety.deploy // empty' "$plan_path")" == "not performed" ]] \
        || findings+=("preview plan deploy invariant failed")
      [[ "$(jq -r '.safety.hard_limit_floor // empty' "$plan_path")" == "preserved" ]] \
        || findings+=("preview plan hard-limit invariant failed")

      while IFS= read -r finding; do
        [[ -n "$finding" ]] && findings+=("$finding")
      done < <(verify_hash_artifact "$bundle_dir" "seed" "$plan_seed_path" "$plan_seed_sha")
    fi
    if [[ "${#findings[@]}" -eq 0 ]]; then
      status="planned"
    else
      status="invalid"
    fi
  else
    kind="missing"
    status="missing"
    findings+=("preview evidence missing")
  fi

  local verify_json findings_payload
  findings_payload="$(findings_json "${findings[@]}")"
  verify_json="$(jq -nc \
    --argjson pr "$pr" \
    --arg status "$status" \
    --arg kind "$kind" \
    --arg bundle_dir "$bundle_dir" \
    --argjson screenshots "$screenshots_count" \
    --argjson findings "$findings_payload" \
    '{
      schema_version: 1,
      kind: $kind,
      pr: $pr,
      status: $status,
      bundle_dir: $bundle_dir,
      screenshots: $screenshots,
      findings: $findings
    }')"

  if [[ "$json_output" -eq 1 ]]; then
    printf '%s\n' "$verify_json" | jq .
  else
    printf 'preview: %s %s\n' "$status" "$bundle_dir"
    if [[ "${#findings[@]}" -gt 0 ]]; then
      printf '%s\n' "${findings[@]}" >&2
    fi
  fi

  [[ "$status" == "ready" || "$status" == "planned" ]]
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  capture)
    cmd_capture "$@"
    ;;
  plan)
    cmd_plan "$@"
    ;;
  bundle)
    cmd_bundle "$@"
    ;;
  local)
    cmd_local "$@"
    ;;
  verify)
    cmd_verify "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die_usage "unknown command: $cmd"
    ;;
esac
