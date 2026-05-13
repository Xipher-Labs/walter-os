#!/usr/bin/env bash
# wiki.sh — operator-facing CLI for the LLM-maintained knowledge wiki.
# Wraps the agent-driven skills (wiki-ingest, wiki-query, wiki-lint).
#
# Most of the heavy lifting (reading sources, identifying entities,
# updating pages with [[wikilinks]]) is done by the agent invoking
# the skills. This script is the deterministic glue: file checks,
# index rebuild, log appends, git commits to the private mirror.
#
# Subcommands:
#   wiki status                report wiki state (page counts, last lint)
#   wiki lint [--apply]        run health checks; --apply rebuilds index.md
#   wiki ingest <url-or-path>  hand off to agent (prints prompt for /ingest)
#   wiki commit <msg>          stage all wiki/ changes + commit + push to private
#   wiki query <terms...>      grep wiki for terms (cheap pre-flight)
#
# Note: Authoritative `wiki ingest` happens THROUGH the agent (skill
# triggers on description match). This CLI command exists so the
# operator can invoke from outside an agent session and get a prompt
# they can paste into Claude Code.

set -euo pipefail

: "${WALTER_DOMAIN:?WALTER_DOMAIN required — copy .env.example to .env.local and configure}"

WIKI_DIR="${WALTER_WIKI_DIR:-${WALTER_OS_HOME}/wiki}"
WIKI_PRIVATE_REMOTE="${WALTER_WIKI_REMOTE:-git@git.${WALTER_DOMAIN}:operator/walter-wiki.git}"

c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[1m'; c_d=$'\033[2m'; c_0=$'\033[0m'
ok()   { printf "${c_g}✓${c_0} %s\n" "$*"; }
info() { printf "${c_d}·${c_0} %s\n" "$*"; }
warn() { printf "${c_y}!${c_0} %s\n" "$*"; }
err()  { printf "${c_r}✗${c_0} %s\n" "$*" >&2; }
step() { printf "\n${c_b}==>${c_0} ${c_b}%s${c_0}\n" "$*"; }

[[ -d "$WIKI_DIR" ]] || { err "Wiki dir missing: $WIKI_DIR"; err "  Did you clone walter-os and run install.sh?"; exit 1; }

cmd="${1:-status}"
shift || true

case "$cmd" in
  status)
    step "Walter-OS wiki status"
    echo "Location: $WIKI_DIR"
    echo
    for dir in people companies concepts decisions tools topics sources; do
      local_count=$(find "$WIKI_DIR/$dir" -mindepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
      printf "  %-12s %s pages\n" "$dir/" "$local_count"
    done
    echo
    if [[ -f "$WIKI_DIR/log.md" ]]; then
      last_op=$(grep '^## \[' "$WIKI_DIR/log.md" | tail -1)
      [[ -n "$last_op" ]] && info "Last entry: $last_op"
    fi
    ;;

  lint)
    step "Walter-OS wiki lint"
    apply=0
    [[ "${1:-}" == "--apply" ]] && apply=1

    # --- Broken [[wikilinks]] ---
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      grep -oE '\[\[([^]|]+)' "$f" 2>/dev/null | sed 's/\[\[//' | while read -r link; do
        # Resolve link: try exact path, or try in each canonical dir
        if [[ -f "$WIKI_DIR/$link.md" || -f "$WIKI_DIR/$link" ]]; then
          continue
        fi
        found=0
        for d in people companies concepts decisions tools topics sources; do
          [[ -f "$WIKI_DIR/$d/$(basename "$link").md" ]] && { found=1; break; }
        done
        (( found == 0 )) && printf '🚨 broken: [[%s]] referenced in %s\n' "$link" "${f#"$WIKI_DIR/"}"
      done
    done < <(find "$WIKI_DIR" -name '*.md' -not -name 'index.md' -not -name 'log.md' -not -name 'SCHEMA.md' -not -name 'README.md')

    # --- index.md drift ---
    if [[ -f "$WIKI_DIR/index.md" ]]; then
      total_pages=$(find "$WIKI_DIR" -name '*.md' \
        -not -name 'index.md' -not -name 'log.md' \
        -not -name 'SCHEMA.md' -not -name 'README.md' | wc -l | tr -d ' ')
      indexed_pages=$(grep -cE '^- \[\[' "$WIKI_DIR/index.md" 2>/dev/null || echo 0)
      if (( total_pages != indexed_pages )); then
        echo "ℹ️  index.md drift: $indexed_pages indexed / $total_pages on disk"
        if (( apply )); then
          # Trivial regen: list every page under each canonical dir
          {
            echo "# Index — last rebuilt $(date '+%Y-%m-%d %H:%M')"
            echo
            for d in people companies concepts decisions tools topics sources; do
              count=$(find "$WIKI_DIR/$d" -mindepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
              echo "## $d ($count)"
              echo
              find "$WIKI_DIR/$d" -mindepth 1 -name '*.md' 2>/dev/null | sort | while read -r p; do
                slug=$(basename "$p" .md)
                title=$(grep -m1 '^# ' "$p" 2>/dev/null | sed 's/^# *//')
                summary=$(awk '/^## /{exit} NR>2 && /[A-Za-z]/{print; exit}' "$p" 2>/dev/null)
                printf -- "- [[%s/%s]] — %s\n" "$d" "$slug" "${summary:-${title:-no summary}}"
              done
              echo
            done
          } > "$WIKI_DIR/index.md.new" && mv "$WIKI_DIR/index.md.new" "$WIKI_DIR/index.md"
          ok "index.md rebuilt ($total_pages pages)"
          # Append to log (single redirect, per shellcheck SC2129)
          {
            echo ""
            echo "## [$(date '+%Y-%m-%d %H:%M')] lint | rebuild-index"
            echo "Indexed $total_pages pages."
          } >> "$WIKI_DIR/log.md"
        fi
      else
        ok "index.md in sync ($total_pages pages)"
      fi
    fi

    # --- Orphan detection (high) — pages with no inbound links ---
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      slug="${f#"$WIKI_DIR/"}"; slug="${slug%.md}"
      # Check if any other page links to this slug
      if ! grep -rqE "\\[\\[$slug(\\|[^]]*)?\\]\\]" "$WIKI_DIR" --include='*.md' \
          --exclude="$(basename "$f")" 2>/dev/null; then
        # Topics are roots, allowed
        [[ "$slug" == topics/* ]] && continue
        # Check if front-matter has orphan: justified
        head -20 "$f" | grep -q '^orphan: justified' && continue
        echo "⚠️  orphan: $slug (no inbound links)"
      fi
    done < <(find "$WIKI_DIR" -mindepth 2 -name '*.md' \
      -not -path '*/index.md' -not -path '*/log.md')

    info "(content checks: missing-entities, stale-claims, contradictions — agent-driven, run via /lint slash command)"
    ;;

  ingest)
    target="${1:?Usage: walter-os wiki ingest <url-or-path>}"
    step "Wiki ingest"
    cat <<HINT
Hand-off prompt for an agent (Claude Code or Codex). Paste the next
two lines into a session that has the wiki-ingest skill loaded:

  /ingest $target

  (or, if no slash command:)
  Apply the wiki-ingest skill. Source: $target.
  Wiki dir: $WIKI_DIR. Schema: $WIKI_DIR/SCHEMA.md.

The agent will:
  1. Read the source
  2. Draft sources/$(date +%Y-%m-%d)-<slug>.md
  3. Identify referenced entities + create stubs
  4. Update relevant topic hubs
  5. Show you the proposed changes for approval
  6. After approval, commit to the private wiki mirror.
HINT
    ;;

  query)
    [[ $# -eq 0 ]] && { err "Usage: walter-os wiki query <terms...>"; exit 2; }
    step "Wiki query (cheap grep — let an agent do the real work)"
    info "Pages matching: $*"
    grep -rilE "$(printf '%s|' "$@" | sed 's/|$//')" \
        "$WIKI_DIR/people" "$WIKI_DIR/companies" "$WIKI_DIR/concepts" \
        "$WIKI_DIR/decisions" "$WIKI_DIR/tools" "$WIKI_DIR/topics" \
        "$WIKI_DIR/sources" 2>/dev/null \
      | sed "s|$WIKI_DIR/|  |"
    echo
    info "For a real answer, use the wiki-query skill in an agent session."
    ;;

  commit)
    msg="${1:?Usage: walter-os wiki commit <message>}"
    step "Commit + push wiki to private remote"
    cd "$WIKI_DIR/.." || exit 1
    git add wiki/
    git diff --cached --stat | tail -5
    git commit -m "wiki: $msg" 2>/dev/null || warn "Nothing to commit"
    # Push to PRIVATE remote (separate from public walter-os origin)
    if git remote get-url wiki-private >/dev/null 2>&1; then
      git push wiki-private HEAD:main 2>&1 | tail -3
    else
      warn "Remote 'wiki-private' not configured. Add with:"
      warn "  cd $WIKI_DIR/.. && git remote add wiki-private $WIKI_PRIVATE_REMOTE"
    fi
    ;;

  *)
    cat <<USAGE
Usage: walter-os wiki <subcommand> [args]

  status                       Report page counts + last log entry
  lint [--apply]               Health check; --apply rebuilds index.md
  ingest <url-or-path>         Hand-off prompt for an agent session
  query <terms...>             Cheap grep across wiki dirs
  commit <message>             Stage + commit + push to private remote

Wiki dir: $WIKI_DIR
USAGE
    [[ "$cmd" == "help" || "$cmd" == "-h" || "$cmd" == "--help" ]] || exit 2
    ;;
esac
