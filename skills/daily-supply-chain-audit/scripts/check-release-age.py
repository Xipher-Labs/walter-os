#!/usr/bin/env python3
"""check-release-age.py — verify minimum release age for packages.

Queries npm and PyPI release dates, caches results (24h TTL), and checks
against a configurable minimum age. Supports a justify-log to suppress
findings for explicitly justified packages.

Usage:
  check-release-age.py <pkg>@<ver> [<pkg>@<ver> ...]
    --ecosystem npm|pypi   (default: npm)
    --min-age-days <N>
    --cache-file <path>    (default: ~/.config/walter-os/release-date-cache.json)
    --justify-log <path>   (default: ~/.config/walter-os/justify-log.jsonl)

Exit codes:
  0 = all packages meet the age requirement or are justified
  1 = one or more packages are too young and not justified

Output: JSON array of findings to stdout.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import urlopen

# Cache TTL in hours
CACHE_TTL_HOURS = 24

# ---------------------------------------------------------------------------
# Date helpers
# ---------------------------------------------------------------------------

def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _parse_iso(s: str) -> datetime:
    """Parse ISO 8601 datetime string."""
    # Handle trailing Z
    s = s.rstrip("Z")
    # Try with microseconds first
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"Cannot parse datetime: {s}")


def _age_days(published_iso: str) -> int:
    """Return how many full days since publication."""
    pub = _parse_iso(published_iso)
    return (_now_utc() - pub).days


# ---------------------------------------------------------------------------
# Registry fetchers
# ---------------------------------------------------------------------------

def _fetch_published_date(pkg: str, version: str, ecosystem: str = "npm") -> str:
    """Fetch publication date from npm or PyPI registry.

    Returns ISO 8601 string. Raises OSError / URLError on network failure.
    """
    if ecosystem == "npm":
        # IMPORTANT: hit the PACKAGE-level endpoint, not the version-level one.
        #   https://registry.npmjs.org/<pkg>            -> doc with `.time` map
        #   https://registry.npmjs.org/<pkg>/<version>  -> version metadata WITHOUT `.time`
        # The version-level endpoint was a long-standing bug (HIGH-1, PR #56 R2):
        # every real package raised ValueError, which audit.sh silently swallowed.
        # Scoped packages (`@scope/name`) require the slash to be URL-encoded.
        url = f"https://registry.npmjs.org/{quote(pkg, safe='')}"
        # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
        # The scheme and host are fixed here; package names are URL-quoted.
        with urlopen(url, timeout=10) as resp:  # nosemgrep
            data = json.loads(resp.read())
        # time map: version -> ISO8601
        times = data.get("time", {})
        if version in times:
            return times[version]
        # Version not present in the registry doc — treat as a data-availability
        # error so the caller routes it to the network-error path (info-only,
        # not a hard fail). Avoid a bare ValueError that would propagate.
        raise LookupError(f"No time entry for {pkg}@{version} in npm registry response")

    elif ecosystem == "pypi":
        url = f"https://pypi.org/pypi/{quote(pkg, safe='')}/{quote(version, safe='')}/json"
        # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
        # The scheme and host are fixed here; package/version are URL-quoted.
        with urlopen(url, timeout=10) as resp:  # nosemgrep
            data = json.loads(resp.read())
        urls = data.get("urls", [])
        if urls:
            return urls[0].get("upload_time", "")
        raise LookupError(f"No urls in PyPI response for {pkg}@{version}")

    else:
        raise ValueError(f"Unknown ecosystem: {ecosystem}")


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

def _load_cache(cache_file: Path) -> dict:
    if not cache_file.exists():
        return {}
    try:
        return json.loads(cache_file.read_text())
    except Exception:
        return {}


def _save_cache(cache_file: Path, cache: dict) -> None:
    """Atomic, concurrency-safe cache write.

    Codex R2 MEDIUM M7: the previous implementation wrote to a fixed
    `<cache>.tmp` path and renamed. Two concurrent audits would clobber
    each other's tmp file and race on the rename — losing entries or
    crashing with FileNotFoundError. Now each write uses a unique
    `NamedTemporaryFile` in the same directory (so `os.replace` is atomic
    on POSIX), and the temp file is removed on any failure.
    """
    import os
    import tempfile

    cache_file.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(cache, indent=2)

    # delete=False so we can rename. dir= matches the cache dir so
    # os.replace is atomic (same filesystem).
    fd, tmp_path = tempfile.mkstemp(
        prefix=".release-date-cache.",
        suffix=".tmp",
        dir=str(cache_file.parent),
    )
    try:
        with os.fdopen(fd, "w") as fp:
            fp.write(payload)
            fp.flush()
            try:
                os.fsync(fp.fileno())
            except OSError:
                # fsync may fail on some FS (e.g., /tmp on some configs);
                # the os.replace below still gives last-writer-wins
                # atomicity, which is all this cache needs.
                pass
        os.replace(tmp_path, cache_file)
    except BaseException:
        # On any failure, remove the orphan tmp file to avoid leaking.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _cache_key(pkg: str, version: str) -> str:
    return f"{pkg}@{version}"


def _is_cache_fresh(entry: dict) -> bool:
    try:
        fetched = _parse_iso(entry["fetched_at"])
        return (_now_utc() - fetched).total_seconds() < CACHE_TTL_HOURS * 3600
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Justify log
# ---------------------------------------------------------------------------

def _load_live_justifications(justify_log: Path) -> set[tuple[str, str]]:
    """Return set of (pkg, version) pairs with non-expired justify entries."""
    if not justify_log.exists():
        return set()
    now = _now_utc()
    live: set[tuple[str, str]] = set()
    try:
        for line in justify_log.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            expires_str = entry.get("expires", "")
            try:
                expires = _parse_iso(expires_str)
            except Exception:
                continue
            if expires > now:
                live.add((entry.get("pkg", ""), entry.get("version", "")))
    except Exception:
        pass
    return live


# ---------------------------------------------------------------------------
# Main check function
# ---------------------------------------------------------------------------

def check_packages(
    pkg_specs: list[str],
    ecosystem: str = "npm",
    min_age_days: int = 21,
    cache_file: Path | None = None,
    justify_log: Path | None = None,
) -> list[dict]:
    """Check a list of 'pkg@version' specs against the minimum release age.

    Returns a list of finding dicts.
    """
    if cache_file is None:
        cache_file = Path.home() / ".config" / "walter-os" / "release-date-cache.json"
    if justify_log is None:
        justify_log = Path.home() / ".config" / "walter-os" / "justify-log.jsonl"

    cache = _load_cache(cache_file)
    live_justifications = _load_live_justifications(justify_log)
    cache_dirty = False
    findings: list[dict] = []

    for spec in pkg_specs:
        if "@" not in spec or spec.startswith("@"):
            # Scoped package: @scope/pkg@ver — split on last @
            parts = spec.rsplit("@", 1)
            if len(parts) != 2:
                findings.append({"pkg": spec, "error": "invalid spec format", "ok": False})
                continue
            pkg = f"@{parts[0].lstrip('@')}" if spec.startswith("@") else parts[0]
            version = parts[1]
        else:
            pkg, version = spec.rsplit("@", 1)

        key = _cache_key(pkg, version)
        finding: dict = {"pkg": spec, "min_age_days": min_age_days}

        # Check justify
        is_justified = (pkg, version) in live_justifications

        # Try cache first
        published: str | None = None
        cached_entry = cache.get(key)
        if cached_entry and _is_cache_fresh(cached_entry):
            published = cached_entry["published"]
        else:
            # Fetch from registry
            try:
                published = _fetch_published_date(pkg, version, ecosystem=ecosystem)
                now_iso = _now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")
                cache[key] = {"published": published, "fetched_at": now_iso}
                cache_dirty = True
            except (OSError, URLError, TimeoutError, LookupError) as exc:
                # Network or data-availability failure — use stale cache if available.
                # LookupError covers "version not in registry response" (the
                # HIGH-1 path) — treat it as info, never as a hard fail, so we
                # don't block work on registry / data hiccups.
                if cached_entry:
                    published = cached_entry["published"]
                    finding["stale_cache"] = True
                else:
                    finding["network_error"] = True
                    finding["network_error_msg"] = str(exc)
                    # Info-only: don't fail
                    finding["ok"] = True  # not a hard fail per AC-5
                    findings.append(finding)
                    continue

        age = _age_days(published)
        finding["published"] = published
        finding["age_days"] = age

        if is_justified:
            finding["ok"] = True
            finding["justified"] = True
        elif age >= min_age_days:
            finding["ok"] = True
            finding["justified"] = False
        else:
            finding["ok"] = False
            finding["justified"] = False

        findings.append(finding)

    if cache_dirty:
        _save_cache(cache_file, cache)

    return findings


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", nargs="+", help="pkg@ver specs to check")
    parser.add_argument("--ecosystem", default="npm", choices=["npm", "pypi"])
    parser.add_argument("--min-age-days", type=int, default=21)
    parser.add_argument(
        "--cache-file",
        default=str(Path.home() / ".config" / "walter-os" / "release-date-cache.json"),
    )
    parser.add_argument(
        "--justify-log",
        default=str(Path.home() / ".config" / "walter-os" / "justify-log.jsonl"),
    )
    parser.add_argument(
        "--skip-network",
        action="store_true",
        help="Simulate offline mode: skip network calls, report network_error for uncached packages",
    )
    args = parser.parse_args()

    if args.skip_network:
        # Monkey-patch _fetch_published_date to always raise (offline simulation)
        import builtins
        _orig_fetch = globals()["_fetch_published_date"]
        globals()["_fetch_published_date"] = lambda *a, **kw: (_ for _ in ()).throw(
            OSError("network disabled via --skip-network")
        )

    findings = check_packages(
        args.packages,
        ecosystem=args.ecosystem,
        min_age_days=args.min_age_days,
        cache_file=Path(args.cache_file),
        justify_log=Path(args.justify_log),
    )

    print(json.dumps(findings, indent=2))

    # Exit 1 if any package fails (not justified, not a network error)
    any_fail = any(
        f.get("ok") is False for f in findings
        if not f.get("network_error")
    )
    sys.exit(1 if any_fail else 0)


if __name__ == "__main__":
    main()
