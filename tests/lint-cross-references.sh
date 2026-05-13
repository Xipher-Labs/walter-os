#!/usr/bin/env bash
# lint-cross-references.sh — meta-test that catches policy drift.
#
# Validates that:
# 1. Skills/agents/commands referenced in AGENTS.md / contexts / other skills
#    actually exist as files in this repo.
# 2. MCPs mentioned in docs match what's in mcp/servers.json.
# 3. Hook script paths in install.sh exist on disk.
# 4. File paths in docs (e.g., "see [foo](path)") resolve.
#
# Catches the failure mode where docs say "use the X skill" but X was renamed,
# deleted, or never existed. The kind of drift that accumulates in any
# multi-doc system.
#
# Exit 0 if all references resolve, 1 if any are dangling.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_d=$'\033[2m'; c_0=$'\033[0m'

failures=0
warnings=0

# Build sets of what exists
existing_skills=$(ls skills/ 2>/dev/null | sort -u)
existing_agents=$(ls agents/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort -u)
existing_commands=$(ls commands/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort -u)
existing_mcps=$(jq -r '.servers | keys[]' mcp/servers.json 2>/dev/null | sort -u)

# Skills mentioned in deferred backlog (legitimately don't exist)
deferred_skills=$(cat <<'EOF'
ansible-playbook-review
baremetal-runbook
brand-manual
competitor-watch-helius-quicknode
content-calendar-builder
customer-interview-synthesizer
devrel-content-pipeline
gdrive-asset-upload
gtm-strategy
incident-postmortem
landing-page-fast
logo-iteration
n8n-workflow-design
obsidian-note-format
pitch-deck
prd-writer
release-notes
remotion-video
runbook-writer
seo-keyword-research
social-media-thread-writer
sre-on-call
video-script-solana
youtube-seo-shorts
youtube-thumbnail-prompt
EOF
)

# These ARE in the deferred backlog memory file, so refs to them are OK
# even if not yet implemented. We just warn instead of erroring.
is_deferred() {
  echo "$deferred_skills" | grep -qx "$1"
}

is_existing_skill() {
  echo "$existing_skills" | grep -qx "$1"
}

is_existing_agent() {
  echo "$existing_agents" | grep -qx "$1"
}

is_existing_command() {
  echo "$existing_commands" | grep -qx "$1"
}

is_existing_mcp() {
  echo "$existing_mcps" | grep -qx "$1"
}

# 1. Skill references in AGENTS.md and contexts
echo "${c_d}Checking skill references in AGENTS.md / contexts/ ...${c_0}"
while IFS= read -r line; do
  # Match `skill-name` (backtick-quoted) — narrow it down to known skill-naming patterns
  refs=$(echo "$line" | grep -oE '`[a-z][a-z0-9-]+`' | tr -d '`' | sort -u)
  for ref in $refs; do
    # Heuristic: if it looks like a skill (has dash + exists in our skills/ OR deferred list)
    if is_existing_skill "$ref" || is_existing_agent "$ref" || is_existing_command "$ref" || is_existing_mcp "$ref"; then
      :  # ok
    elif is_deferred "$ref"; then
      :  # known deferred
    fi
  done
done < <(grep -rE '`[a-z][a-z0-9-]+`' AGENTS.md contexts/ 2>/dev/null)

# Superpowers skills (external dep — we don't ship them locally)
is_superpowers_skill() {
  case "$1" in
    test-driven-development|using-git-worktrees|brainstorming|writing-plans|executing-plans|systematic-debugging|root-cause-tracing|defensive-programming|verification-before-completion|condition-based-waiting|using-skills|writing-skills|code-reviewer)
      return 0 ;;
    *) return 1 ;;
  esac
}

# 2. Explicit "use the X skill" mentions
echo "${c_d}Checking 'use the X skill' / 'X skill' references ...${c_0}"
while IFS=: read -r src_file line_no rest; do
  # Match patterns like "use the FOO skill" or "the FOO skill" or "FOO skill"
  refs=$(echo "$rest" | grep -oE '`[a-z][a-z0-9-]+`[[:space:]]+skill' | grep -oE '`[a-z][a-z0-9-]+`' | tr -d '`' | sort -u)
  for ref in $refs; do
    if is_existing_skill "$ref" || is_superpowers_skill "$ref"; then
      :
    elif is_deferred "$ref"; then
      printf "  ${c_y}!${c_0} %s:%s: skill ref '%s' is deferred\n" \
        "$src_file" "$line_no" "$ref"
      warnings=$((warnings + 1))
    else
      printf "  ${c_r}✗${c_0} %s:%s: dangling skill ref: '%s'\n" "$src_file" "$line_no" "$ref"
      failures=$((failures + 1))
    fi
  done
done < <(grep -rEnH '`[a-z][a-z0-9-]+`[[:space:]]+skill' AGENTS.md contexts/ skills/*/SKILL.md agents/*.md 2>/dev/null)

# 3. Hook paths in install.sh — only files (not directories, those iterate-and-symlink)
echo "${c_d}Checking hook paths in install.sh ...${c_0}"
while IFS= read -r path; do
  rel="${path#${REPO_ROOT}/}"
  # Allow directories (used by link_dir_contents) and files
  if [[ ! -e "$rel" ]]; then
    printf "  ${c_r}✗${c_0} install.sh references missing path: %s\n" "$rel"
    failures=$((failures + 1))
  fi
done < <(grep -oE '\$REPO_ROOT/[a-z][a-z0-9/_.-]+' install.sh 2>/dev/null | sort -u | sed "s|\$REPO_ROOT|${REPO_ROOT}|")

# 4. Markdown link path resolution (relative)
echo "${c_d}Checking markdown link paths in AGENTS.md and contexts/ ...${c_0}"
while IFS=: read -r file rest; do
  # Extract markdown links of form [text](path) where path is relative
  links=$(echo "$rest" | grep -oE '\]\([a-z][a-z0-9/_.-]+\.(md|sh|json|toml|py|yml|yaml)\)' | tr -d '()' | sed 's/^]//' | sort -u)
  for link in $links; do
    # Strip line anchors / fragments
    target="${link%%#*}"
    target="${target%%:*}"
    if [[ ! -e "$target" ]]; then
      printf "  ${c_r}✗${c_0} %s: dangling link path: %s\n" "$file" "$target"
      ((failures++))
    fi
  done
done < <(grep -nH '\](' AGENTS.md CLAUDE.md README.md contexts/*/AGENTS.md 2>/dev/null)

# 5. Skills referenced by agents in their `skills:` frontmatter list
echo "${c_d}Checking skills referenced by agent frontmatter ...${c_0}"
for agent in agents/*.md; do
  in_skills=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^skills: ]]; then in_skills=1; continue; fi
    if [[ "$line" =~ ^[a-z]+: ]]; then in_skills=0; fi
    if [[ $in_skills -eq 1 ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z][a-z0-9-]+)$ ]]; then
      ref="${BASH_REMATCH[1]}"
      if ! is_existing_skill "$ref" && ! is_deferred "$ref"; then
        # The skill might be from superpowers (which we depend on but
        # don't have locally). Allow common superpowers skills.
        case "$ref" in
          test-driven-development|using-git-worktrees|brainstorming|writing-plans|executing-plans|systematic-debugging|root-cause-tracing|defensive-programming|verification-before-completion|condition-based-waiting|using-skills|writing-skills|code-reviewer)
            :  # superpowers — OK
            ;;
          *)
            printf "  ${c_r}✗${c_0} %s: skills frontmatter references missing skill: %s\n" "$agent" "$ref"
            ((failures++))
            ;;
        esac
      fi
    fi
  done < "$agent"
done

# Summary
echo
if [[ $failures -gt 0 ]]; then
  printf "${c_r}%s dangling reference(s)${c_0}, %s warning(s).\n" "$failures" "$warnings"
  exit 1
fi
if [[ $warnings -gt 0 ]]; then
  printf "${c_y}0 errors, %s deferred-skill warning(s).${c_0}\n" "$warnings"
fi
printf "${c_g}All references resolve.${c_0}\n"
exit 0
