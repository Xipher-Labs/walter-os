"""
Tests for check-release-age.py [AC-4, AC-5]

Covers: cache hit, cache miss, network error, age < min, age >= min,
non-expired justify, expired justify, PyPI ecosystem.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Helpers to locate the module under test
# ---------------------------------------------------------------------------

SCRIPTS_DIR = Path(__file__).parent.parent.parent / "skills" / "daily-supply-chain-audit" / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import importlib.util

def _load_module(name: str):
    spec = importlib.util.spec_from_file_location(
        name, SCRIPTS_DIR / f"{name}.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

@pytest.fixture
def module():
    return _load_module("check-release-age")

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def tmp_cache(tmp_path):
    return tmp_path / "release-date-cache.json"

@pytest.fixture
def tmp_justify(tmp_path):
    return tmp_path / "justify-log.jsonl"

def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def _days_ago_iso(n: int) -> str:
    dt = datetime.now(timezone.utc) - timedelta(days=n)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def _days_from_now_iso(n: int) -> str:
    dt = datetime.now(timezone.utc) + timedelta(days=n)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestCacheHit:
    """Cache hit: no network call made."""

    def test_cache_hit_returns_cached_value(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(30)
        fetched = _now_iso()
        cache_data = {
            "lodash@4.17.21": {"published": published, "fetched_at": fetched}
        }
        tmp_cache.write_text(json.dumps(cache_data))

        with patch.object(module, "_fetch_published_date", side_effect=AssertionError("should not call network")):
            findings = module.check_packages(
                ["lodash@4.17.21"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f["ok"] is True
        assert f["age_days"] >= 30
        assert f.get("network_error") is not True


class TestCacheMiss:
    """Cache miss: network call made, cache populated."""

    def test_cache_miss_fetches_and_populates_cache(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(25)

        with patch.object(module, "_fetch_published_date", return_value=published) as mock_fetch:
            findings = module.check_packages(
                ["react@18.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        mock_fetch.assert_called_once()
        assert tmp_cache.exists()
        cache = json.loads(tmp_cache.read_text())
        assert "react@18.0.0" in cache
        assert len(findings) == 1
        assert findings[0]["ok"] is True


class TestNetworkError:
    """Network error: network_error flag set, exit code 0 (no fail)."""

    def test_network_error_sets_flag_no_fail(self, module, tmp_cache, tmp_justify):
        with patch.object(module, "_fetch_published_date", side_effect=OSError("no network")):
            findings = module.check_packages(
                ["unknown-pkg@1.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f.get("network_error") is True
        # Should NOT be a hard fail (ok may be True or undefined but not False triggering exit 1)
        assert f.get("ok") is not False


class TestAgeTooYoung:
    """Package age < min_age_days: ok=false, exit 1."""

    def test_too_young_package_fails(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(2)

        with patch.object(module, "_fetch_published_date", return_value=published):
            findings = module.check_packages(
                ["new-pkg@1.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f["ok"] is False
        assert f["age_days"] < 21
        assert f.get("justified") is not True


class TestAgeOk:
    """Package age >= min_age_days: ok=true, exit 0."""

    def test_old_enough_package_passes(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(30)

        with patch.object(module, "_fetch_published_date", return_value=published):
            findings = module.check_packages(
                ["old-pkg@2.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f["ok"] is True
        assert f["age_days"] >= 21


class TestJustifyEntry:
    """Non-expired justify entry: ok=true, justified=true."""

    def test_non_expired_justify_suppresses_finding(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(2)
        # Write a valid justify entry
        entry = {
            "ts": _days_ago_iso(1),
            "pkg": "new-pkg",
            "version": "1.0.0",
            "level": "production",
            "reason": "critical security patch, need now",
            "operator": "nico",
            "expires": _days_from_now_iso(89),
        }
        tmp_justify.write_text(json.dumps(entry) + "\n")

        with patch.object(module, "_fetch_published_date", return_value=published):
            findings = module.check_packages(
                ["new-pkg@1.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f["ok"] is True
        assert f.get("justified") is True

    def test_expired_justify_does_not_suppress(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(2)
        entry = {
            "ts": _days_ago_iso(91),
            "pkg": "new-pkg",
            "version": "1.0.0",
            "level": "production",
            "reason": "old justified entry, now expired",
            "operator": "nico",
            "expires": _days_ago_iso(1),  # expired yesterday
        }
        tmp_justify.write_text(json.dumps(entry) + "\n")

        with patch.object(module, "_fetch_published_date", return_value=published):
            findings = module.check_packages(
                ["new-pkg@1.0.0"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        assert f["ok"] is False


class TestPyPI:
    """PyPI ecosystem path."""

    def test_pypi_ecosystem_resolves(self, module, tmp_cache, tmp_justify):
        published = _days_ago_iso(40)

        with patch.object(module, "_fetch_published_date", return_value=published) as mock_fetch:
            findings = module.check_packages(
                ["requests@2.31.0"],
                ecosystem="pypi",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        mock_fetch.assert_called_once()
        # Verify pypi ecosystem was passed
        call_args = mock_fetch.call_args
        assert call_args[1].get("ecosystem") == "pypi" or call_args[0][1] == "pypi"
        assert findings[0]["ok"] is True


# ---------------------------------------------------------------------------
# Regression tests — HIGH-1 (npm registry URL bug)
# ---------------------------------------------------------------------------

class TestNpmRegistryUrl:
    """HIGH-1 regression: npm lookup must use package-level URL, not version URL.

    The package-level endpoint (`https://registry.npmjs.org/<pkg>`) returns a
    document with a top-level `.time` map (version -> ISO date). The
    version-level endpoint (`https://registry.npmjs.org/<pkg>/<version>`)
    returns version metadata with NO `time` map. The original code hit the
    version endpoint and raised ValueError on every real npm package, which
    audit.sh then silently swallowed.
    """

    def test_npm_lookup_uses_package_level_url(self, module):
        """The URL built for an npm lookup must NOT include the version path segment."""
        captured = {}

        class FakeResponse:
            def __init__(self, payload: bytes) -> None:
                self._payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return self._payload

        def fake_urlopen(url, timeout=None):
            captured["url"] = url
            payload = json.dumps({"time": {"1.0.0": "2020-01-01T00:00:00.000Z"}}).encode()
            return FakeResponse(payload)

        with patch.object(module, "urlopen", side_effect=fake_urlopen):
            result = module._fetch_published_date("lodash", "1.0.0", ecosystem="npm")

        assert result == "2020-01-01T00:00:00.000Z"
        url = captured["url"]
        # Must hit the package-level endpoint
        assert url.startswith("https://registry.npmjs.org/")
        # Must NOT include /<version> on the path — that's the broken pattern
        assert not url.endswith("/1.0.0"), f"npm URL still includes version path: {url}"

    def test_npm_lookup_scoped_package_url_encoding(self, module):
        """Scoped npm packages (`@scope/name`) must URL-encode the slash."""
        captured = {}

        class FakeResponse:
            def __init__(self, payload: bytes) -> None:
                self._payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return self._payload

        def fake_urlopen(url, timeout=None):
            captured["url"] = url
            payload = json.dumps({"time": {"2.0.0": "2021-06-01T12:00:00.000Z"}}).encode()
            return FakeResponse(payload)

        with patch.object(module, "urlopen", side_effect=fake_urlopen):
            result = module._fetch_published_date("@scope/pkg", "2.0.0", ecosystem="npm")

        assert result == "2021-06-01T12:00:00.000Z"
        url = captured["url"]
        # The "/" between @scope and pkg must be percent-encoded for the registry.
        assert "%2F" in url or "%2f" in url, f"scoped pkg slash not URL-encoded: {url}"

    def test_npm_lookup_unknown_version_returns_none(self, module, tmp_cache, tmp_justify):
        """If the package exists but the requested version is missing from
        `.time`, the check should return a network-error finding (info), not
        crash with an uncaught exception (which audit.sh would swallow)."""

        class FakeResponse:
            def __init__(self, payload: bytes) -> None:
                self._payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return self._payload

        def fake_urlopen(url, timeout=None):
            # Return a doc that does NOT contain version 99.99.99.
            payload = json.dumps({"time": {"1.0.0": "2020-01-01T00:00:00.000Z"}}).encode()
            return FakeResponse(payload)

        with patch.object(module, "urlopen", side_effect=fake_urlopen):
            findings = module.check_packages(
                ["lodash@99.99.99"],
                ecosystem="npm",
                min_age_days=21,
                cache_file=tmp_cache,
                justify_log=tmp_justify,
            )

        assert len(findings) == 1
        f = findings[0]
        # Treated as a data-not-available error: info-only, no hard fail.
        assert f.get("network_error") is True
        assert f.get("ok") is not False


# ---------------------------------------------------------------------------
# M7: cache write race — concurrent _save_cache calls must not lose entries
# ---------------------------------------------------------------------------


class TestSaveCacheConcurrency:
    """Codex R2 MEDIUM M7: the previous _save_cache wrote to a fixed
    `release-date-cache.tmp` path next to the final cache, then renamed.
    Two concurrent audits would clobber each other's tmp file or race on
    the rename — losing entries or corrupting the file. _save_cache must
    use a unique per-process tmp path and atomically replace.
    """

    def test_concurrent_save_cache_preserves_valid_json(self, module, tmp_path):
        """Spin up N threads that each call _save_cache with distinct
        entries plus small sleeps to widen the race window. After they all
        finish, the final cache file must be valid JSON (no corruption /
        half-written state). Last-writer-wins is acceptable; partial
        writes are not.

        Threads are sufficient: the race is on filesystem ops
        (write → rename), not GIL-protected state, and threading sidesteps
        macOS-spawn pickling limits.
        """
        import threading
        import time

        cache_file = tmp_path / "release-date-cache.json"
        errors: list[BaseException] = []

        def worker(idx: int):
            try:
                # Stagger slightly to widen the race window
                time.sleep(0.001 * (idx % 5))
                module._save_cache(
                    cache_file,
                    {f"pkg{idx}@1.0.0": {"published": "2020-01-01T00:00:00Z",
                                         "fetched_at": "2026-01-01T00:00:00Z"}},
                )
            except BaseException as e:  # noqa: BLE001
                errors.append(e)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)
        assert not errors, f"worker raised: {errors!r}"

        # Final file must be valid JSON.
        assert cache_file.exists()
        data = json.loads(cache_file.read_text())
        assert isinstance(data, dict)
        # And it must be one of the worker payloads (no garbage).
        assert len(data) == 1
        only_key = next(iter(data.keys()))
        assert only_key.startswith("pkg") and only_key.endswith("@1.0.0")

    def test_concurrent_save_cache_no_leftover_fixed_tmp(self, module, tmp_path):
        """The previous fixed-path `release-date-cache.tmp` could be left
        behind on crash and would also collide between concurrent runs.
        The fix uses tempfile.NamedTemporaryFile + os.replace, so the
        fixed tmp name must NOT appear after the writes."""
        import threading
        import time

        cache_file = tmp_path / "release-date-cache.json"

        def worker(idx: int):
            time.sleep(0.001 * (idx % 3))
            module._save_cache(
                cache_file,
                {f"pkg{idx}@1.0.0": {"published": "2020-01-01T00:00:00Z",
                                     "fetched_at": "2026-01-01T00:00:00Z"}},
            )

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(16)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        leftover_fixed = tmp_path / "release-date-cache.tmp"
        assert not leftover_fixed.exists(), \
            "fixed tmp path was used (race-prone) — fix must use per-process tmp"
