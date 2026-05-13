#!/usr/bin/env python3
"""
Detect MCP servers in a Claude Code settings.json that are NOT pinned to an
*exact* version. Prints unpinned server names, one per line.

Usage: check-pinning.py <path-to-settings.json>
Exit codes:
  0  always (findings are on stdout; absence = clean)
  2  usage error (missing arg or unreadable file)

Pin syntaxes accepted (and ONLY these):

  npm:   @scope/pkg@<exact-semver>
  npm:   plain-pkg@<exact-semver>
       where <exact-semver> matches  X.Y.Z(-prerelease)?(+build)?
       per semver.org (digits-and-dots core, alphanumeric-and-dot
       prerelease, alphanumeric-and-dot build metadata).

  uvx:   pkg==<exact-semver>        (PEP-440 equality only)

  git:   pkg#<commit-sha>           (7+ hex chars after `#`)

Explicitly REJECTED (Codex R2 review HIGH-1 / HIGH-2):
  - npm dist-tags:   pkg@latest, pkg@next, pkg@beta, pkg@alpha, etc.
  - npm ranges:      pkg@^1.2.3, pkg@~1.2.3, pkg@>=1.0.0, pkg@1.x, etc.
  - PEP-440 ranges:  pkg>=x, pkg<=x, pkg~=x, pkg>x, pkg<x, pkg!=x

The previous jq-based check in audit.sh had a false-positive bug: its regex
matched the `-y` flag of every `npx -y …` invocation. This script replaces
that logic with explicit, testable detection.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Exact semver per semver.org §2 & §11, simplified:
#   <numeric core>(-<prerelease>)?(+<build>)?
#   numeric core   = N.N.N where N is one or more digits (we don't enforce
#                    "no leading zero" because real-world packages like
#                    CalVer-flavoured @scope/server@2026.1.14 use month/day
#                    fields that *can* have leading zeros).
#   prerelease     = dot-separated [0-9A-Za-z-]+ identifiers
#   build metadata = dot-separated [0-9A-Za-z-]+ identifiers
_EXACT_SEMVER = re.compile(
    r"^\d+\.\d+\.\d+"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)

# npm spec splitter: (@scope/)?name@version. Captures version after the LAST
# `@`. Scoped packages start with `@` so we handle them explicitly.
_NPM_SCOPED = re.compile(r"^(@[^/]+/[^@]+)@(.+)$")
_NPM_PLAIN = re.compile(r"^([^@][^@]*)@(.+)$")

# uvx PEP-440 spec splitter. We split on the FIRST operator we find. Operators
# considered: ==, ===, ~=, >=, <=, !=, >, <. We only accept `==` as a pin
# (and treat `===` arbitrary-equality as a pin too, since it requires an
# exact string match). All others are explicit ranges → rejected.
_UVX_OP_RE = re.compile(r"(===|==|~=|>=|<=|!=|>|<)")


def find_spec_arg(args: list[str]) -> str | None:
    """
    Locate the package-spec argument in an `npx` / `uvx` argv.
      uvx --from <spec> <entry-point>  -> spec sits after --from
      uvx <spec>                       -> first non-flag arg
      npx -y <spec> [paths...]         -> first non-flag, non-path arg
    """
    if "--from" in args:
        i = args.index("--from")
        if i + 1 < len(args):
            return args[i + 1]
        return None
    for a in args:
        if a in ("-y", "--yes"):
            continue
        if a.startswith("-"):       # any other flag
            continue
        if a.startswith("/"):       # absolute path positional
            continue
        if a.startswith("$"):       # env-var placeholder
            continue
        return a
    return None


def _is_exact_semver(version: str) -> bool:
    return bool(_EXACT_SEMVER.match(version))


def _is_git_sha_pin(spec: str) -> bool:
    """`pkg#<commit-sha>` with 7+ hex chars is a pin."""
    if "#" not in spec:
        return False
    sha = spec.split("#", 1)[1]
    return len(sha) >= 7 and all(c in "0123456789abcdef" for c in sha.lower())


def _npm_is_pinned(spec: str) -> bool:
    """npm-style spec: only `(@scope/)?name@<exact-semver>` is pinned."""
    m = _NPM_SCOPED.match(spec) if spec.startswith("@") else _NPM_PLAIN.match(spec)
    if not m:
        return False
    version = m.group(2)
    return _is_exact_semver(version)


def _uvx_is_pinned(spec: str) -> bool:
    """PEP-440-style spec: only `name==<exact-semver>` (or `===`) is pinned."""
    m = _UVX_OP_RE.search(spec)
    if not m:
        return False
    op = m.group(1)
    if op not in ("==", "==="):
        return False
    # split once on the operator; whatever follows must be exact semver.
    version = spec[m.end():]
    # PEP-440 allows comma-joined operators (e.g. `pkg>=1.0,<2.0`). Any of
    # those means it's a range, not a pin — reject.
    if "," in version:
        return False
    # Strip any whitespace just in case.
    version = version.strip()
    return _is_exact_semver(version)


def is_pinned(spec: str) -> bool:
    """
    Return True iff `spec` is pinned to an exact version per the rules in the
    module docstring. False for tags (`@latest`), ranges (`^1`, `>=1`),
    PEP-440 non-equality operators, and missing versions.
    """
    if not spec:
        return False
    # git commit-sha form takes precedence — applies to either npm or uvx.
    if _is_git_sha_pin(spec):
        return True
    # Distinguish npm spec (contains `@` after the name) from uvx spec
    # (contains a PEP-440 operator). They're disjoint in practice because
    # npm uses `@` as the version separator and uvx uses `==`/`>=`/etc.
    if "@" in spec[1:]:  # skip leading `@` of scoped npm packages
        return _npm_is_pinned(spec)
    if _UVX_OP_RE.search(spec):
        return _uvx_is_pinned(spec)
    return False


def unpinned_servers(settings: dict) -> list[str]:
    out: list[str] = []
    for name, cfg in (settings.get("mcpServers") or {}).items():
        cmd = cfg.get("command", "")
        if cmd not in ("npx", "uvx"):
            continue
        spec = find_spec_arg(cfg.get("args") or [])
        if spec is None:
            continue
        if not is_pinned(spec):
            out.append(name)
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check-pinning.py <settings.json>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    if not path.is_file():
        print(f"check-pinning.py: not a file: {path}", file=sys.stderr)
        return 2
    try:
        settings = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        print(f"check-pinning.py: invalid JSON in {path}: {e}", file=sys.stderr)
        return 2
    for name in unpinned_servers(settings):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
