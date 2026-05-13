#!/usr/bin/env python3
"""parse-manifest.py — resolve Walter-OS protection level for a repo.

Reads <repo-dir>/walter-os.toml, merges with the bundle definitions from
protection-levels.toml, and emits the resolved config as JSON to stdout.

Exit codes:
  0  always (warnings on stderr, never crashes)

Usage:
  python3 parse-manifest.py [--repo-dir <path>] [--bundles-file <path>]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# TOML loading — try tomllib (Python 3.11+), fall back to tomli, then stub.
# ---------------------------------------------------------------------------

def _load_toml(path: Path) -> dict:
    """Load a TOML file. Returns empty dict on any parse error."""
    raw = path.read_bytes()
    try:
        import tomllib  # type: ignore[import-not-found]
        return tomllib.loads(raw.decode())
    except ImportError:
        pass
    try:
        import tomli  # type: ignore[import-not-found]
        return tomli.loads(raw.decode())
    except ImportError:
        pass
    # Last resort: minimal configparser-based reader for flat TOML.
    return _configparser_toml(raw.decode())


def _configparser_toml(text: str) -> dict:
    """Very minimal TOML reader using configparser as a fallback.
    Only handles flat [section] tables with key = "value" pairs.
    Sufficient for protection-levels.toml and simple walter-os.toml.
    """
    import configparser
    # configparser needs a dummy DEFAULT section if none present
    adjusted = "[__root__]\n" + text
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    try:
        cp.read_string(adjusted)
    except configparser.Error:
        raise ValueError("configparser could not parse TOML")
    result: dict = {}
    for section in cp.sections():
        if section == "__root__":
            for k, v in cp.items(section):
                result[k] = _unquote(v)
        else:
            # Reconstruct nested structure for dotted sections like walter.overrides
            parts = section.split(".")
            node = result
            for part in parts:
                node = node.setdefault(part, {})
            for k, v in cp.items(section):
                node[k] = _unquote(v)
    return result


def _unquote(value: str) -> str:
    """Strip surrounding quotes from a configparser value."""
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
        return value[1:-1]
    return value


# ---------------------------------------------------------------------------
# Age string parsing
# ---------------------------------------------------------------------------

_AGE_RE = re.compile(r"^(\d+)([dDhHmM]?)$")

def parse_age_days(age_str: str) -> int:
    """Convert age string like '21d' to integer days. '0' -> 0."""
    m = _AGE_RE.match(str(age_str).strip())
    if not m:
        return 0
    n, unit = int(m.group(1)), m.group(2).lower()
    if unit in ("", "d"):
        return n
    if unit == "h":
        return n // 24
    if unit == "m":
        return n // (24 * 60)
    return n


# ---------------------------------------------------------------------------
# Auto-assignment
# ---------------------------------------------------------------------------

def auto_assign_level(repo_dir: Path) -> str:
    """Infer protection level from repo path when no manifest exists."""
    path_str = str(repo_dir).lower()
    home = Path.home()

    # Check if path is under ~/work/*
    work_dir = home / "work"
    if repo_dir.is_relative_to(work_dir):
        return "production"

    # Check whether the remote belongs to the configured production org
    # (best-effort, no crash).
    try:
        import subprocess
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=3
        )
        production_org = os.environ.get("WALTER_WORK_GITHUB_ORG", "").lower()
        if production_org and production_org in result.stdout.lower():
            return "production"
    except Exception:
        pass

    # Check repo name for hackathon
    if "hackathon" in repo_dir.name.lower():
        return "sandbox"

    # ~/Projects-Personal/* or default -> staging
    return "staging"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def resolve(repo_dir: Path, bundles_file: Path) -> dict:
    """Resolve protection level config for repo_dir."""
    # Load bundle definitions
    try:
        bundles = _load_toml(bundles_file)
    except Exception as exc:
        print(f"[ERROR] Failed to load bundles file {bundles_file}: {exc}", file=sys.stderr)
        sys.exit(1)

    # Load manifest
    manifest_path = repo_dir / "walter-os.toml"
    source = "auto-assigned"
    level = None
    overrides: dict = {}

    if manifest_path.exists():
        try:
            raw = _load_toml(manifest_path)
            # walter may be missing or, with a malformed manifest, the wrong
            # type (e.g. `walter = "broken"` makes raw["walter"] a string).
            walter = raw.get("walter", {}) if isinstance(raw, dict) else {}
            if not isinstance(walter, dict):
                print(
                    f"[WARNING] walter-os.toml at {manifest_path}: [walter] "
                    f"is type {type(walter).__name__}, expected table — ignoring",
                    file=sys.stderr,
                )
                walter = {}
            # protection must be a string. Anything else (list/int/bool/table)
            # is rejected here so the set-membership check below cannot raise
            # `TypeError: unhashable type: 'list'`.
            level_raw = walter.get("protection", None)
            if level_raw is not None and not isinstance(level_raw, str):
                # CODEX R2 P1: malformed `protection` MUST NOT silently
                # downgrade. The operator clearly intended to declare a level
                # but typoed (e.g. `protection = ["production"]`). Fail closed
                # to the STRICTEST bundle so a production typo never lowers
                # minReleaseAge / audit-gate behind the operator's back.
                print(
                    f"[WARNING] walter-os.toml at {manifest_path}: "
                    f"`protection` is type {type(level_raw).__name__}, expected string — "
                    f"FAILING CLOSED to production (strictest bundle)",
                    file=sys.stderr,
                )
                level = "production"
            else:
                level = level_raw
            # overrides must be a dict (table). A string/list/int would crash
            # bundle.update(...) below with TypeError.
            overrides = walter.get("overrides", {})
            if not isinstance(overrides, dict):
                print(
                    f"[WARNING] walter-os.toml at {manifest_path}: "
                    f"`walter.overrides` is type {type(overrides).__name__}, expected table — "
                    f"ignoring overrides",
                    file=sys.stderr,
                )
                overrides = {}
            source = f"manifest ({manifest_path})"
        except Exception as exc:
            # Defense in depth: any unexpected TypeError / AttributeError /
            # KeyError / ValueError from the schema-coercion path must NOT
            # propagate. Codex R2 MEDIUM M6 + P1: a manifest that exists but
            # is structurally broken means the operator INTENDED to configure
            # something — fail closed to production rather than silently
            # downgrade to staging.
            print(
                f"[WARNING] malformed walter-os.toml at {manifest_path}: "
                f"{type(exc).__name__}: {exc} — FAILING CLOSED to production "
                f"(strictest bundle)",
                file=sys.stderr,
            )
            level = "production"
            overrides = {}
            source = "malformed-manifest-fallback"
    else:
        print(
            f"[WARNING] no manifest found at {manifest_path}, using auto-assigned level",
            file=sys.stderr,
        )
        level = auto_assign_level(repo_dir)

    # Validate level
    valid_levels = {"experimental", "sandbox", "staging", "production"}
    if level not in valid_levels:
        # CODEX R2 P1: unknown level string (typo'd by operator) means they
        # were trying to set SOMETHING — fail closed to production.
        print(
            f"[WARNING] Unknown protection level '{level}' in manifest — "
            f"FAILING CLOSED to production (strictest bundle)",
            file=sys.stderr,
        )
        level = "production"

    # Merge bundle with overrides (last-line defense — overrides was already
    # type-checked above, but wrap the merge so a bundle-side oddity still
    # falls back rather than crashing).
    try:
        bundle = dict(bundles.get(level, {}))
        bundle.update(overrides)
    except (TypeError, AttributeError, ValueError) as exc:
        print(
            f"[WARNING] failed to merge bundle/overrides "
            f"({type(exc).__name__}: {exc}) — using bare bundle",
            file=sys.stderr,
        )
        bundle = dict(bundles.get(level, {})) if isinstance(bundles, dict) else {}

    # Compute minReleaseAgeDays as integer
    min_age_str = bundle.get("minReleaseAge", "0d")
    min_age_days = parse_age_days(min_age_str)

    result = {
        "level": level,
        "minReleaseAge": min_age_str,
        "minReleaseAgeDays": min_age_days,
        "pinStrategy": bundle.get("pinStrategy", "exact"),
        "auditGate": bundle.get("auditGate", "high"),
        "review": bundle.get("review", "reviewer"),
        "source": source,
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-dir",
        default=os.getcwd(),
        help="Path to repo root (default: cwd)",
    )
    parser.add_argument(
        "--bundles-file",
        default=None,
        help="Path to protection-levels.toml (default: auto-detect from script location)",
    )
    args = parser.parse_args()

    repo_dir = Path(args.repo_dir).resolve()

    if args.bundles_file:
        bundles_file = Path(args.bundles_file).resolve()
    else:
        # Auto-detect: script is at <walter-os-home>/scripts/parse-manifest.py
        script_dir = Path(__file__).parent
        bundles_file = (
            script_dir.parent
            / "skills"
            / "daily-supply-chain-audit"
            / "protection-levels.toml"
        )

    config = resolve(repo_dir, bundles_file)
    print(json.dumps(config, indent=2))


if __name__ == "__main__":
    main()
