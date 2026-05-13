#!/usr/bin/env python3
"""patch-toml-key.py — set a single key in a TOML file without destroying other content.

Limited to the known flat shapes of ~/.bunfig.toml. Handles:
  [section]
  key = "value"

Usage:
  python3 patch-toml-key.py <file> <section> <key> <value>

Examples:
  python3 patch-toml-key.py ~/.bunfig.toml install minimumReleaseAge "1209600s"
  python3 patch-toml-key.py ~/.bunfig.toml install minimumReleaseAge "0s"
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def patch_toml_key(filepath: Path, section: str, key: str, value: str) -> None:
    """Set [section] key = "value" in filepath, creating file/section if needed.

    The value is written as a quoted TOML string: key = "value"
    Existing file content outside [section] is preserved.
    Only one key=value line per key is kept (idempotent).
    """
    if not filepath.exists():
        # Create a minimal file
        filepath.parent.mkdir(parents=True, exist_ok=True)
        filepath.write_text(f'[{section}]\n{key} = "{value}"\n')
        return

    text = filepath.read_text()
    lines = text.splitlines(keepends=True)

    section_header = f"[{section}]"
    key_pattern = re.compile(rf'^(\s*){re.escape(key)}\s*=.*$')

    # Find the section
    section_start = None
    section_end = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == section_header:
            section_start = i
        elif section_start is not None and stripped.startswith("[") and stripped.endswith("]") and stripped != section_header:
            section_end = i
            break

    new_key_line = f'{key} = "{value}"\n'

    if section_start is None:
        # Section not found — append it at the end
        if not text.endswith("\n"):
            lines.append("\n")
        lines.append(f"\n{section_header}\n")
        lines.append(new_key_line)
        filepath.write_text("".join(lines))
        return

    # Section found — look for existing key within the section
    # Key lives between section_start+1 and section_end (or EOF)
    end = section_end if section_end is not None else len(lines)
    key_found = False
    for i in range(section_start + 1, end):
        if key_pattern.match(lines[i]):
            lines[i] = new_key_line
            key_found = True
            break

    if not key_found:
        # Insert after section header
        lines.insert(section_start + 1, new_key_line)

    filepath.write_text("".join(lines))


def main() -> None:
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <file> <section> <key> <value>", file=sys.stderr)
        sys.exit(1)

    filepath = Path(sys.argv[1])
    section = sys.argv[2]
    key = sys.argv[3]
    value = sys.argv[4]

    patch_toml_key(filepath, section, key, value)


if __name__ == "__main__":
    main()
