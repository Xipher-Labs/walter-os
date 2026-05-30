#!/usr/bin/env bash
# setup/personal-overlay-init.sh
# Scaffold ~/.config/walter-os/overlay/ from the repo's example templates.
#
# Usage:
#   ./setup/personal-overlay-init.sh                      # scaffold overlay (idempotent)
#   ./setup/personal-overlay-init.sh --dry-run            # show what would happen
#   ./setup/personal-overlay-init.sh --from-skeleton      # copy walter-personal-skeleton wholesale
#   ./setup/personal-overlay-init.sh --from-skeleton --dry-run  # preview skeleton copy
#   ./setup/personal-overlay-init.sh --git-clone <url>    # clone private walter-personal repo as overlay
#   ./setup/personal-overlay-init.sh --git-clone <url> --dry-run  # preview clone command
#
# Flags:
#   --from-skeleton   Copy contexts/_examples/walter-personal-skeleton/ to the overlay.
#                     Useful for operators who want to track their overlay in a private git repo.
#   --git-clone <url> Clone an existing private walter-personal repo as the overlay.
#                     Aborts if ~/.config/walter-os/overlay/ already exists.
#   --dry-run         Print planned operations without writing anything.
#
# After running:
#   1. Edit ~/.config/walter-os/overlay/profile.md with your operator profile
#   2. Edit ~/.config/walter-os/overlay/contexts/work/AGENTS.md for your company
#   3. Edit ~/.config/walter-os/overlay/contexts/projects-personal/AGENTS.md
#   4. Edit ~/.config/walter-os/overlay/contexts/personal/AGENTS.md
#   5. (Optional) Edit ~/.config/walter-os/overlay/contexts/hackathons/AGENTS.md
#      Activate with: export WALTER_CONTEXT=hackathons
#
# The overlay is loaded by the global AGENTS.md cascade when present.
# Files in the overlay take precedence over the repo's generic templates.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="${HOME}/.config/walter-os/overlay"
EXAMPLES_DIR="${REPO_ROOT}/contexts/_examples"

DRY_RUN=0
FROM_SKELETON=0
GIT_CLONE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=1 ; shift ;;
    --from-skeleton) FROM_SKELETON=1 ; shift ;;
    --git-clone)
      if [[ -z "${2:-}" ]]; then
        echo "--git-clone requires a URL argument" >&2; exit 2
      fi
      GIT_CLONE_URL="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---- helpers ----

say()  { printf "%s\n" "$*"; }
ok()   { printf "\033[32m✓\033[0m %s\n" "$*"; }
skip() { printf "\033[33m→\033[0m %s (already exists, skipping)\n" "$*"; }
dry()  { printf "\033[2m[dry-run]\033[0m %s\n" "$*"; }

copy_template() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ -f "$dst" ]]; then
    skip "$label"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would copy $src → $dst"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  ok "Created $label"
}

create_file() {
  local dst="$1"
  local label="$2"
  local content="$3"

  if [[ -f "$dst" ]]; then
    skip "$label"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would create $dst"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  printf "%s\n" "$content" > "$dst"
  ok "Created $label"
}

model_pref_default() {
  case "$1" in
    WALTER_MODEL_BACKEND_REVIEW) echo "codex" ;;
    WALTER_MODEL_FRONTEND) echo "claude" ;;
    WALTER_MODEL_LONGFORM) echo "claude" ;;
    WALTER_MODEL_QUICK_REFACTOR) echo "codex" ;;
    WALTER_MODEL_PHI) echo "local-ollama" ;;
    WALTER_MODEL_BRAINSTORM) echo "claude,codex" ;;
    WALTER_MODEL_DEFAULT) echo "claude" ;;
    *) echo "" ;;
  esac
}

ensure_model_preferences() {
  local env_file="$OVERLAY_DIR/personal.env"
  local keys=(
    WALTER_MODEL_BACKEND_REVIEW
    WALTER_MODEL_FRONTEND
    WALTER_MODEL_LONGFORM
    WALTER_MODEL_QUICK_REFACTOR
    WALTER_MODEL_PHI
    WALTER_MODEL_BRAINSTORM
    WALTER_MODEL_DEFAULT
  )
  local key default value wrote_header=0

  for key in "${keys[@]}"; do
    if [[ -f "$env_file" ]] && grep -qE "^${key}=" "$env_file"; then
      skip "$key"
      continue
    fi

    default="$(model_pref_default "$key")"
    value="$default"
    if [[ $DRY_RUN -eq 0 && -t 0 ]]; then
      printf "%s [%s]: " "$key" "$default" >&2
      IFS= read -r value
      value="${value:-$default}"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
      dry "would add $key=$default to $env_file"
      continue
    fi

    if [[ "$wrote_header" -eq 0 ]]; then
      {
        printf "\n# === MODEL ROUTING ===\n"
        printf "# LiteLLM-style aliases. PHI must remain local.\n"
      } >> "$env_file"
      wrote_header=1
    fi
    printf "%s=%s\n" "$key" "$value" >> "$env_file"
    ok "Added $key=$value"
  done
}

# ---- mutual exclusion guard ----

if [[ $FROM_SKELETON -eq 1 && -n "$GIT_CLONE_URL" ]]; then
  echo "Error: --from-skeleton and --git-clone are mutually exclusive." >&2
  exit 2
fi

# ---- --git-clone path ----

if [[ -n "$GIT_CLONE_URL" ]]; then
  if [[ -d "$OVERLAY_DIR" ]]; then
    say "Error: overlay directory already exists at $OVERLAY_DIR"
    say "Delete or back it up first, then re-run with --git-clone."
    say "  mv $OVERLAY_DIR ${OVERLAY_DIR}.bak"
    exit 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would run: git clone $GIT_CLONE_URL $OVERLAY_DIR"
    say "DRY RUN COMPLETE."
    exit 0
  fi
  git clone "$GIT_CLONE_URL" "$OVERLAY_DIR"
  if [[ ! -f "$OVERLAY_DIR/personal.env" && ! -f "$OVERLAY_DIR/personal.env.template" ]]; then
    say "Warning: cloned repo does not contain personal.env or personal.env.template."
    say "Ensure this is a valid walter-personal repo before proceeding."
  else
    ok "Cloned walter-personal repo to $OVERLAY_DIR"
  fi
  say "Overlay active. Run 'walter doctor' to verify."
  exit 0
fi

# ---- --from-skeleton path ----

if [[ $FROM_SKELETON -eq 1 ]]; then
  skeleton_dir="$REPO_ROOT/contexts/_examples/walter-personal-skeleton"
  if [[ ! -d "$skeleton_dir" ]]; then
    echo "Error: skeleton not found at $skeleton_dir" >&2; exit 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would copy $skeleton_dir/ → $OVERLAY_DIR/"
    while IFS= read -r f; do
      rel="${f#"$skeleton_dir"/}"
      dry "  $rel"
    done < <(find "$skeleton_dir" -type f | sort)
    say "DRY RUN COMPLETE."
    exit 0
  fi
  mkdir -p "$OVERLAY_DIR"
  cp -r "$skeleton_dir/." "$OVERLAY_DIR/"
  ok "Copied skeleton to $OVERLAY_DIR"
  say ""
  say "Next: rename *.template files to their final names and fill in TODO values."
  say "Then: cd $OVERLAY_DIR && git init && git add . && git commit -m 'initial'"
  exit 0
fi

# ---- check overlay already initialized ----

if [[ -d "$OVERLAY_DIR" ]]; then
  say "Personal overlay directory already exists at: $OVERLAY_DIR"
  say "Running in idempotent mode — only missing files will be created."
  say ""
else
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$OVERLAY_DIR"
    ok "Created overlay directory: $OVERLAY_DIR"
  else
    dry "would create overlay directory: $OVERLAY_DIR"
  fi
fi

# ---- scaffold structure ----

say "Scaffolding overlay structure..."
say ""

# Profile
create_file \
  "$OVERLAY_DIR/profile.md" \
  "profile.md (operator profile)" \
  "# Operator Profile

<!-- Fill in your personal profile here. This is loaded by the global AGENTS.md
     cascade when present, replacing the generic 'working with the operator' text.

     Example:
     You are working with [Your Name], [your role] at [your company], based in
     [your location]. [Disciplines]. [Language preferences].
     Tone: [your preferred communication style].
-->

You are working with **[YOUR NAME]**, [YOUR ROLE] at [YOUR COMPANY], based in
[YOUR LOCATION]. [DISCIPLINES].

Tone: direct, no padding, no sycophancy. Push back on bad ideas with reasoning.
When uncertain, say so explicitly. Accuracy beats agreement.
"

# Context: work
copy_template \
  "$EXAMPLES_DIR/work-template.example.md" \
  "$OVERLAY_DIR/contexts/work/AGENTS.md" \
  "contexts/work/AGENTS.md (work context)"

# Context: projects-personal
copy_template \
  "$EXAMPLES_DIR/projects-personal-template.example.md" \
  "$OVERLAY_DIR/contexts/projects-personal/AGENTS.md" \
  "contexts/projects-personal/AGENTS.md (personal projects)"

# Context: personal
copy_template \
  "$EXAMPLES_DIR/personal-template.example.md" \
  "$OVERLAY_DIR/contexts/personal/AGENTS.md" \
  "contexts/personal/AGENTS.md (personal life)"

# Context: hackathons (use repo template directly — no separate example file)
copy_template \
  "$REPO_ROOT/contexts/hackathons/AGENTS.md" \
  "$OVERLAY_DIR/contexts/hackathons/AGENTS.md" \
  "contexts/hackathons/AGENTS.md (hackathons / time-boxed events)"

# personal.env (operator-specific env vars, shared across checkouts)
# If not yet present, scaffold it and inject WALTER_OS_HOME pointing at
# the actual checkout path so scripts can fail-loud when unset.
if [[ ! -f "$OVERLAY_DIR/personal.env" ]]; then
  # Portable path canonicalization: prefer `cd && pwd -P` (works on macOS
  # BSD without GNU coreutils). Fall back to realpath if available.
  if command -v realpath >/dev/null 2>&1; then
    detected_home="$(realpath "$REPO_ROOT" 2>/dev/null || echo "")"
  fi
  if [[ -z "${detected_home:-}" ]]; then
    detected_home="$(cd "$REPO_ROOT" && pwd -P)"
  fi
  if [[ -z "$detected_home" || ! -d "$detected_home" ]]; then
    echo "personal-overlay-init: cannot canonicalize REPO_ROOT='$REPO_ROOT'" >&2
    echo "  Set WALTER_OS_HOME manually in $OVERLAY_DIR/personal.env" >&2
    exit 2
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "would create $OVERLAY_DIR/personal.env with WALTER_OS_HOME=$detected_home"
  else
    mkdir -p "$(dirname "$OVERLAY_DIR/personal.env")"
    cp "$EXAMPLES_DIR/personal.env.example" "$OVERLAY_DIR/personal.env"
    # Prepend WALTER_OS_HOME pointing at this checkout (detected at scaffold time)
    {
      printf "# Auto-detected checkout path (set by personal-overlay-init.sh)\n"
      printf "# Update if you move the repo.\n"
      printf "WALTER_OS_HOME=%s\n\n" "$detected_home"
      cat "$OVERLAY_DIR/personal.env"
    } > "${OVERLAY_DIR}/personal.env.tmp" && mv "${OVERLAY_DIR}/personal.env.tmp" "$OVERLAY_DIR/personal.env"
    ok "Created personal.env (operator-specific config) with WALTER_OS_HOME=$detected_home"
  fi
else
  skip "personal.env (operator-specific config)"
fi

ensure_model_preferences

# Skills directory (empty, for operator-specific skills)
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$OVERLAY_DIR/skills"
  if [[ ! -f "$OVERLAY_DIR/skills/.gitkeep" ]]; then
    touch "$OVERLAY_DIR/skills/.gitkeep"
    ok "Created skills/ directory"
  else
    skip "skills/ directory"
  fi
else
  dry "would create $OVERLAY_DIR/skills/"
fi

# ---- summary ----

say ""
say "═══════════════════════════════════════════════════════════════"
if [[ $DRY_RUN -eq 1 ]]; then
  say "DRY RUN COMPLETE. Run without --dry-run to apply changes."
else
  say "Overlay scaffolded at: $OVERLAY_DIR"
  say ""
  say "Next steps:"
  say "  1. Edit $OVERLAY_DIR/personal.env"
  say "     → Set WALTER_DOMAIN, GITHUB_USER, and other operator-specific values"
  say "     → This file is loaded before .env.local on every install/CLI invocation"
  say ""
  say "  2. Edit $OVERLAY_DIR/profile.md"
  say "     → Add your name, role, company, location, language preferences"
  say ""
  say "  3. Edit $OVERLAY_DIR/contexts/work/AGENTS.md"
  say "     → Add your company stack, workflow rules, project tracker"
  say "     → Reference: contexts/_examples/work-*.example.md (complete examples)"
  say ""
  say "  4. Edit $OVERLAY_DIR/contexts/projects-personal/AGENTS.md"
  say "     → Add your active personal projects"
  say "     → Reference: contexts/_examples/projects-personal/*.example.md"
  say ""
  say "  5. Edit $OVERLAY_DIR/contexts/personal/AGENTS.md"
  say "     → Add your locale, tax authority, language preferences"
  say "     → Reference: contexts/_examples/personal/*.example.md"
  say ""
  say "  6. (Optional) Edit $OVERLAY_DIR/contexts/hackathons/AGENTS.md"
  say "     → Customize for your preferred hackathon stack and sponsor APIs"
  say "     → Activate with: export WALTER_CONTEXT=hackathons (or set in .env.local)"
  say ""
  say "  7. (Optional) Add operator-specific skills to:"
  say "     $OVERLAY_DIR/skills/<skill-name>/SKILL.md"
  say ""
  say "The overlay takes precedence over the repo's generic templates."
  say "Run ./install.sh --upgrade to wire the overlay into the install."
fi
say "═══════════════════════════════════════════════════════════════"
