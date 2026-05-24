#!/usr/bin/env bash
# scripts/walter/lib/egress-loader.sh
#
# Egress allowlist parser for Walter-OS network-gate. Used by
# `hooks/network-gate.sh` and `bin/walter-os egress` to decide whether
# a hostname is in the operator's allowlist.
#
# OSS Trust epic A-2 — spec: docs/specs/network-egress-allowlist.md
# Parent issue: #122
# Sibling pattern: scripts/walter/lib/env-loader.sh (P1-09 — same shape:
#   text file, one entry per line, NO eval, allowlist semantics).
#
# Threat model: `~/.config/walter-os/egress-allowlist.txt` is operator-
# owned. The loader must NEVER eval / source / shell-expand its contents.
# It is a flat string file; matching is pure string compare + per-label
# wildcards.
#
# File format (spec D-1 + D-5):
#   - One host per line: `api.github.com`
#   - Single-label `*` wildcard: `*.openrouter.ai` matches `api.openrouter.ai`
#     but NOT `openrouter.ai` and NOT `a.b.openrouter.ai`. Multi-level
#     requires explicit additional patterns (e.g. `*.*.openrouter.ai`).
#   - `# comments` allowed (must start the line; mid-line `#` is part of
#     the host string and won't match real DNS).
#   - Blank lines allowed.
#   - Whitespace around entries is stripped.
#   - Default-deny: missing/empty file → every host returns 1 (denied).
#
# Usage:
#   source "$WALTER_OS_HOME/scripts/walter/lib/egress-loader.sh"
#   if walter_egress_host_allowed "api.github.com"; then ... fi
#
# Exit codes for walter_egress_host_allowed:
#   0 — host matches an entry (allowed)
#   1 — host does NOT match (denied / fail-closed default)
#
# Companion helper:
#   walter_egress_allowlist_path  — prints the resolved allowlist path

# Resolve the on-disk allowlist path. Honours $WALTER_CONFIG; falls back to
# ${XDG_CONFIG_HOME:-$HOME/.config}/walter-os. Operator-overridable via env
# so tests and the install.sh first-run prompt can point at an alternate
# location.
walter_egress_allowlist_path() {
  # Resolve from $WALTER_CONFIG, falling back to the repo-standard
  # ~/.config/walter-os (matches install.sh + the rest of the codebase).
  # We deliberately do NOT honour $XDG_CONFIG_HOME here — the rest of
  # Walter-OS doesn't, and a partial XDG implementation would cause
  # `walter-os egress {add,list}` and the loader to read from different
  # files when XDG_CONFIG_HOME is set. Copilot R2 finding.
  local base="${WALTER_CONFIG:-$HOME/.config/walter-os}"
  printf '%s/egress-allowlist.txt' "$base"
}

# walter_egress_host_allowed <host>
#
# Returns 0 if <host> matches a line in the allowlist (literal or
# wildcard, per spec D-5). Returns 1 otherwise. Default-deny when the
# allowlist file is absent or empty.
walter_egress_host_allowed() {
  local host="$1"
  [[ -z "$host" ]] && return 1

  # DNS is case-insensitive — lowercase the host before comparing.
  # `tr` is portable across bash 3 / 4 / 5 (we avoid the `${var,,}` syntax
  # which doesn't exist in bash 3.2 / the macOS default shell).
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

  local file
  file="$(walter_egress_allowlist_path)"
  [[ -f "$file" ]] || return 1

  # Split host into labels using a temporary IFS assignment. This is a
  # bash-builtin scope: IFS is restored on the next statement.
  local -a host_labels
  IFS='.' read -r -a host_labels <<< "$host"
  local host_n="${#host_labels[@]}"

  local line lowered
  local -a pat_labels
  local pat_n i match
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # Strip trailing whitespace (POSIX-safe parameter expansion)
    line="${line%"${line##*[![:space:]]}"}"
    # Skip blanks + full-line comments
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    # Lowercase the pattern, then split by `.` into labels.
    lowered="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    IFS='.' read -r -a pat_labels <<< "$lowered"
    pat_n="${#pat_labels[@]}"

    # A bare single-label `*` is REJECTED. Under per-label semantics it
    # would otherwise match every 1-label hostname — including
    # `localhost` and any unqualified host an operator might pass to
    # `ssh hostname`. R2 finding (network-egress-allowlist) — the
    # original "wildcard star alone is NOT a catch-all" claim was only
    # true for multi-label hosts. Fix-closed: refuse to match.
    if [[ "$pat_n" -eq 1 && "${pat_labels[0]}" == "*" ]]; then
      continue
    fi

    # Per spec D-5: `*` does NOT cross dots. Patterns and hosts must
    # therefore have the same label count. `*.foo.com` (3 labels) only
    # matches `X.foo.com` (3 labels), never `foo.com` (2) or `a.b.foo.com`
    # (4).
    [[ "$pat_n" -eq "$host_n" ]] || continue

    match=1
    for ((i = 0; i < pat_n; i++)); do
      # A single `*` token matches exactly one label. Mid-label glob
      # (`a*b`) is treated as a LITERAL string match against the host
      # label (no fnmatch-style expansion) — `a*b.example.com` only
      # matches a host whose first label is literally `a*b`.
      [[ "${pat_labels[$i]}" == "*" ]] && continue
      # Otherwise literal compare (already lowercased on both sides).
      [[ "${pat_labels[$i]}" == "${host_labels[$i]}" ]] && continue
      match=0
      break
    done

    if [[ "$match" -eq 1 ]]; then
      return 0
    fi
  done < "$file"

  return 1
}
