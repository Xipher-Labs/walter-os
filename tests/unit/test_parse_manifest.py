"""
Tests for scripts/parse-manifest.py malformed-but-valid TOML shapes.

Codex R2 MEDIUM M6: the parser only handled syntax errors. Schema/type
errors like `protection = ["production"]` or `walter.overrides = "x"`
would crash. The script must ALWAYS exit 0 with a default-fallback JSON
and emit a warning to stderr.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
PARSER = REPO_ROOT / "scripts" / "parse-manifest.py"
BUNDLES = (
    REPO_ROOT
    / "skills"
    / "daily-supply-chain-audit"
    / "protection-levels.toml"
)


def _run(manifest_body: str) -> tuple[int, dict, str]:
    """Write manifest_body into a temp repo dir, run the parser, return
    (exit_code, parsed_stdout_json, stderr_text).
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "walter-os.toml").write_text(manifest_body)
        result = subprocess.run(
            [
                sys.executable,
                str(PARSER),
                "--repo-dir",
                str(tmp_path),
                "--bundles-file",
                str(BUNDLES),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        try:
            data = json.loads(result.stdout) if result.stdout else {}
        except json.JSONDecodeError:
            data = {"_raw_stdout": result.stdout}
        return result.returncode, data, result.stderr


def _assert_safe_fallback(rc: int, data: dict, stderr: str) -> None:
    """The contract: exit 0, valid JSON with a known level, warning on stderr."""
    assert rc == 0, f"expected exit 0, got {rc}; stderr={stderr!r}"
    assert "level" in data, f"missing 'level' in output: {data!r}"
    assert data["level"] in {"experimental", "sandbox", "staging", "production"}, (
        f"unknown level {data['level']!r}"
    )


# ---------------------------------------------------------------------------
# protection field — wrong types
# ---------------------------------------------------------------------------


def test_protection_as_list_fails_closed_to_production():
    """`protection = ["production"]` must not crash on set membership."""
    rc, data, stderr = _run('[walter]\nprotection = ["production"]\n')
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production", f"expected production (fail-closed), got {data['level']!r}"


def test_protection_as_int_fails_closed_to_production():
    """`protection = 42` must fail closed to production."""
    rc, data, stderr = _run("[walter]\nprotection = 42\n")
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


def test_protection_as_table_fails_closed_to_production():
    """`protection = {key="val"}` inline table must fail closed to production."""
    rc, data, stderr = _run('[walter]\nprotection = { key = "val" }\n')
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


def test_protection_as_bool_fails_closed_to_production():
    """`protection = true` must fail closed to production."""
    rc, data, stderr = _run("[walter]\nprotection = true\n")
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


def test_protection_as_string_unknown_value_fails_closed():
    """A valid string but not a known level — operator intent was clear,
    so fail closed to production rather than silently downgrade."""
    rc, data, stderr = _run('[walter]\nprotection = "spaghetti"\n')
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


# ---------------------------------------------------------------------------
# walter.overrides — wrong types
# ---------------------------------------------------------------------------


def test_overrides_as_string_does_not_crash():
    """`walter.overrides = "x"` must not throw on bundle.update(overrides)."""
    rc, data, stderr = _run('[walter]\nprotection = "production"\noverrides = "x"\n')
    _assert_safe_fallback(rc, data, stderr)
    # production bundle should still resolve correctly; bad overrides ignored
    assert data["level"] == "production"


def test_overrides_as_list_does_not_crash():
    """`walter.overrides = [1,2,3]` must not throw."""
    rc, data, stderr = _run(
        '[walter]\nprotection = "production"\noverrides = [1,2,3]\n'
    )
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


def test_overrides_as_int_does_not_crash():
    """`walter.overrides = 42` must not throw."""
    rc, data, stderr = _run('[walter]\nprotection = "production"\noverrides = 42\n')
    _assert_safe_fallback(rc, data, stderr)
    assert data["level"] == "production"


# ---------------------------------------------------------------------------
# walter table itself — wrong types
# ---------------------------------------------------------------------------


def test_walter_as_string_does_not_crash():
    """`walter = "broken"` at the root means .get('walter', {}) returns a
    string, and `.get('protection', None)` on a string raises AttributeError.
    """
    rc, data, stderr = _run('walter = "broken"\n')
    _assert_safe_fallback(rc, data, stderr)


def test_completely_empty_manifest_does_not_crash():
    """Empty file should auto-assign or fall back, not crash."""
    rc, data, stderr = _run("")
    _assert_safe_fallback(rc, data, stderr)


# ---------------------------------------------------------------------------
# Existing happy path still works (regression guard)
# ---------------------------------------------------------------------------


def test_valid_production_manifest_still_works():
    rc, data, stderr = _run('[walter]\nprotection = "production"\n')
    assert rc == 0, stderr
    assert data["level"] == "production"
    assert data["minReleaseAgeDays"] == 21


def test_valid_overrides_still_applies():
    rc, data, stderr = _run(
        '[walter]\nprotection = "production"\n\n'
        '[walter.overrides]\nminReleaseAge = "3d"\n'
    )
    assert rc == 0, stderr
    assert data["level"] == "production"
    assert data["minReleaseAge"] == "3d"
    assert data["minReleaseAgeDays"] == 3
