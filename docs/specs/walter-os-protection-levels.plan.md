# Implementation Plan: walter-os-protection-levels

Ordered tasks. Each is 2–5 minutes of focused work for an implementer subagent.
TDD discipline: write the failing test first (RED), then the minimum code to pass
(GREEN), then clean up (REFACTOR), then commit. Shell tests use bats; Python tests
use pytest.

---

## Task 1: Protection-levels bundle definition [AC-8]

- File: `skills/daily-supply-chain-audit/protection-levels.toml` (new)
- Change: Create the single source of truth for the four bundle definitions.
  Structure:

  ```toml
  [experimental]
  minReleaseAge = "0d"
  pinStrategy   = "any"
  auditGate     = "info"
  review        = "self"

  [sandbox]
  minReleaseAge = "7d"
  pinStrategy   = "minor"
  auditGate     = "warn"
  review        = "self"

  [staging]
  minReleaseAge = "14d"
  pinStrategy   = "exact"
  auditGate     = "high"
  review        = "reviewer"

  [production]
  minReleaseAge = "21d"
  pinStrategy   = "exact"
  auditGate     = "high+drift"
  review        = "reviewer+security-auditor"
  ```

  Also document auto-assignment rules in a `[_auto_assign]` comment block.
- Verify: `cat skills/daily-supply-chain-audit/protection-levels.toml` renders
  all four levels; Python `tomllib.loads()` parses it without error (quick
  smoke test in the REPL or a one-liner assert in the next task's test file).

---

## Task 2: Manifest parser helper [AC-1, AC-2]

- File: `scripts/parse-manifest.py` (new)
- Change: Python 3 script that:
  1. Accepts `--repo-dir <path>` (default: cwd) and `--bundles-file <path>`
     (default: `<WALTER_OS_HOME>/skills/daily-supply-chain-audit/protection-levels.toml`).
  2. Reads `<repo-dir>/walter-os.toml` using `tomllib` (Python 3.11+) or
     `tomli` fallback, then `configparser` as last resort.
  3. Falls back to auto-assignment rules (based on `repo-dir` path) when the
     file is missing; emits `{"warning": "no manifest, using auto-assigned level"}`
     on stderr and proceeds.
  4. On malformed TOML: emits `{"warning": "malformed walter-os.toml, using defaults"}` on stderr, uses `staging` as safe default, exits 0 (not 1).
  5. Merges `[walter.overrides]` on top of the bundle.
  6. Emits the resolved configuration as JSON to stdout:
     ```json
     {"level": "production", "minReleaseAge": "21d", "minReleaseAgeDays": 21,
      "pinStrategy": "exact", "auditGate": "high+drift",
      "review": "reviewer+security-auditor", "source": "manifest"}
     ```
- File: `tests/unit/parse-manifest.bats` (new) — bats tests covering:
  - Missing manifest → auto-assigns by path, exit 0
  - Manifest with `production` → resolves correctly
  - Manifest with `[walter.overrides] minReleaseAge = "3d"` → override applied
  - Malformed TOML → warning on stderr, staging default, exit 0
  - `experimental` level → `minReleaseAgeDays: 0`
- Verify: `bats tests/unit/parse-manifest.bats` passes all 5 cases.

---

## Task 3: `walter-os protection` subcommand [AC-2]

- File: `bin/walter-os` (modify)
- Change: Add `cmd_protection()` function and register it in the dispatch table.
  The function:
  1. Calls `python3 "${WALTER_OS_HOME}/scripts/parse-manifest.py" --repo-dir "$(pwd)"`.
  2. Uses `jq` to pretty-print the resolved level and key fields.
  3. Accepts `--json` flag to emit raw JSON.
  4. Adds the subcommand to the leading-comment help block.
  
  Example output:
  ```
  Protection level: production
    minReleaseAge : 21d
    pinStrategy   : exact
    auditGate     : high+drift
    review        : reviewer+security-auditor
    source        : manifest (./walter-os.toml)
  ```
- File: `tests/unit/walter-os-protection.bats` (new) — tests covering:
  - No manifest in temp dir → prints auto-assigned level, exit 0
  - Manifest with `sandbox` → prints `sandbox`
  - `--json` flag → output is valid JSON
- Verify: `bats tests/unit/walter-os-protection.bats` passes; `walter-os protection --json` in the repo root emits valid JSON.

---

## Task 4: Release-date lookup helper [AC-4, AC-5]

- File: `skills/daily-supply-chain-audit/scripts/check-release-age.py` (new)
- Change: Python 3 script invoked by the audit shell script. Interface:

  ```
  check-release-age.py <pkg>@<ver> [<pkg>@<ver> ...]
    --ecosystem npm|pypi   (default: npm)
    --min-age-days <N>
    --cache-file <path>    (default: ~/.config/walter-os/release-date-cache.json)
    --justify-log <path>   (default: ~/.config/walter-os/justify-log.jsonl)
  ```

  Exit codes: 0 = all packages meet the age requirement or are justified;
  1 = one or more packages are too young and not justified.

  Output: JSON array of findings to stdout:
  ```json
  [{"pkg": "foo@1.2.3", "published": "2026-04-20", "age_days": 22,
    "min_age_days": 21, "ok": true, "justified": false},
   {"pkg": "bar@0.9.0", "published": "2026-05-10", "age_days": 2,
    "min_age_days": 21, "ok": false, "justified": false}]
  ```

  Cache logic:
  - On hit (entry exists, `fetched_at` < 24 h ago): use cached value.
  - On miss: query registry API, write to cache, proceed.
  - On network error (any exception from urllib): emit `{"network_error": true}`
    in the finding object, do NOT increment fail count, log to stderr.

  npm API call: `https://registry.npmjs.org/<pkg>/<ver>` — parse `.time.<ver>`
  PyPI API call: `https://pypi.org/pypi/<pkg>/<ver>/json` — parse `.urls[0].upload_time`

  Justify log: read all entries, discard where `expires < now` (ISO8601 compare).
  Any `{pkg, version}` match with a live entry → `ok: true, justified: true`.

- File: `tests/unit/test_check_release_age.py` (new) — pytest tests with
  `responses` or `unittest.mock` covering:
  - Cache hit (no network call made)
  - Cache miss → network call → cache populated
  - Network error → `network_error: true`, exit 0 (not 1)
  - Package age < `min_age_days` → `ok: false`, exit 1
  - Package age >= `min_age_days` → `ok: true`, exit 0
  - Non-expired justify entry → `ok: true, justified: true`, exit 0
  - Expired justify entry → not exempted, `ok: false`
  - PyPI ecosystem path
- Verify: `python3 -m pytest tests/unit/test_check_release_age.py -v` passes all 8 cases.

---

## Task 5: `check_min_release_age()` wired into `audit.sh` [AC-4, AC-5]

- File: `skills/daily-supply-chain-audit/scripts/audit.sh` (modify)
- Change: Add `check_min_release_age()` function between `check_pinning` and
  `check_skill_scripts` in the `main()` call sequence.

  The function:
  1. Calls `parse-manifest.py` to resolve `minReleaseAgeDays` and `auditGate`
     for the current working directory (uses `WALTER_AUDIT_REPO_DIR` env var if
     set, else cwd).
  2. If `minReleaseAgeDays == 0` (experimental): skip entirely.
  3. Collects installed npm packages by reading `~/.claude/settings.json`
     `.mcpServers` entries where command is `npx` and extracts `pkg@ver` from
     args. Also reads any `.mcp.json` in scope.
  4. Calls `check-release-age.py` with the collected packages and
     `--min-age-days "$min_age_days"`.
  5. Parses the JSON output; for each finding where `ok: false`:
     - If `network_error: true` → `finding info "release-age-network-error-<pkg>"`
     - Else if gate is `info`/`warn` → `finding info "release-age-young-<pkg>"`
     - Else → `finding high "release-age-young-<pkg>"`
  6. Summarizes justified suppressions as info findings.
- Verify: Run `audit.sh` in a temp dir with a mock `settings.json` that includes
  a known-old package (numpy 1.0.0, published 2006) and a too-young mock entry.
  Confirm the old package produces no finding; the too-young mock produces
  `[high] release-age-young-*`. Use `WALTER_AUDIT_REPO_DIR=/tmp/test-repo` with
  a minimal `walter-os.toml` at `production` level.

---

## Task 6: `walter-os justify` subcommand [AC-6, AC-7]

- File: `bin/walter-os` (modify)
- Change: Add `cmd_justify()` and register it in the dispatch table.

  Interface:
  ```
  walter-os justify <pkg>@<ver> --reason="<text>"
  walter-os justify list              # print non-expired entries as table
  walter-os justify revoke <pkg>@<ver>  # adds expiry = now (soft revoke)
  ```

  For the main invocation:
  1. Validate `<pkg>@<ver>` format (alphanumeric + common npm chars + `@`).
  2. Require `--reason` (non-empty). Reject if missing.
  3. Compute `expires` = now + 90 days (ISO8601).
  4. Append JSON object to `~/.config/walter-os/justify-log.jsonl` atomically
     (write to `.tmp`, `mv`).
  5. Print confirmation: `Justified <pkg>@<ver> for 90d. Expires: <date>. Reason logged.`

  Also update the leading-comment help block.

- File: `tests/unit/walter-os-justify.bats` (new) — bats tests covering:
  - Successful justify → file contains new entry, exit 0
  - Missing `--reason` → error message, exit 2, no entry written
  - `list` subcommand → prints non-expired entries
  - Expired entry not shown in list
- Verify: `bats tests/unit/walter-os-justify.bats` passes all 4 cases.

---

## Task 7: PM config writers in `install.sh` [AC-3, AC-10]

- File: `install.sh` (modify)
- File: `scripts/patch-toml-key.py` (new) — minimal Python script that sets
  a single dotted key in a TOML file without destroying the rest of the file.
  Uses `tomllib` + `tomli_w` (or manual string patching under a `[section]`
  marker if `tomli_w` is unavailable). Limited to the known flat shapes of
  `~/.bunfig.toml`.
- Change to `install.sh`: add `write_pm_release_age()` function called from
  `main()`. It:
  1. Calls `parse-manifest.py --repo-dir "$REPO_ROOT"` to get `minReleaseAgeDays`.
  2. Computes Bun seconds = `minReleaseAgeDays * 86400`.
  3. Computes pnpm minutes = `minReleaseAgeDays * 1440`.
  4. Writes `[install] minimumReleaseAge = "<seconds>s"` to `~/.bunfig.toml`
     using `scripts/patch-toml-key.py`. Creates the file if absent.
  5. Writes `minimum-release-age=<minutes>` to `~/.config/pnpm/rc`.
     Uses `awk` to replace an existing line or appends if absent.
  6. If `minReleaseAgeDays == 0` (experimental): removes the keys / sets to 0.
  7. Respects `DRY_RUN` and `--upgrade` flags already in `install.sh`.
  8. Logs a warning for npm/cargo/uvx: "no native minimumReleaseAge support".
  9. Adds a `write_pm_release_age` check to `cmd_doctor` in `bin/walter-os`
     (reads the written value back and compares to expected).
- File: `tests/unit/install-pm-config.bats` (new) — bats tests in a temp
  `$HOME` override covering:
  - Fresh install → `~/.bunfig.toml` contains correct seconds value
  - Idempotent re-run → value not duplicated
  - `--dry-run` → no file written
  - `experimental` level → value is `0s`
- Verify: `bats tests/unit/install-pm-config.bats` passes all 4 cases.
  Manually confirm `cat ~/.bunfig.toml` and `cat ~/.config/pnpm/rc` after
  `./install.sh --upgrade` shows correct values.

---

## Task 8: `walter-os doctor` extension [AC-10]

- File: `bin/walter-os` (modify, `cmd_doctor()` function)
- Change: Add two checks to the "Walter-OS config" section:
  1. `check "bunfig.toml minimumReleaseAge present" ...` — reads `~/.bunfig.toml`,
     verifies the key exists and is non-zero for non-experimental levels.
  2. `check "pnpm rc minimum-release-age present" ...` — reads
     `~/.config/pnpm/rc`, verifies the key exists.
  Both checks soft-pass (info, not error) when PM is not installed.
- Verify: `walter-os doctor` output includes both new check lines in the
  "Walter-OS config" section. In a clean install the checks pass. Manually
  delete the key from `~/.bunfig.toml` and confirm the check fails.

---

## Task 9: Integration smoke test [AC-1 through AC-10]

- File: `tests/integration/protection-levels.bats` (new)
- Change: End-to-end bats test that:
  1. Creates a temp repo dir with `walter-os.toml` set to `production`.
  2. Sets `WALTER_AUDIT_REPO_DIR` and `HOME` overrides to temp paths.
  3. Runs `walter-os protection --json` and asserts output contains
     `"level":"production"` and `"minReleaseAgeDays":21`.
  4. Runs `walter-os justify "test-pkg@1.0.0" --reason="integration test"` and
     asserts the justify log contains the entry.
  5. Runs `audit.sh` with the temp settings (mock MCP with a package that has
     a mocked-old release date via `WA_SKIP_NETWORK=1` env passthrough). Asserts
     exit code 0 (no findings) since the mock is within age.
  6. Changes the mock to a too-young date, re-runs audit, asserts exit code 2
     (`high` severity) when no justify entry exists, then asserts exit code 0
     after adding a valid justify entry.
- Verify: `bats tests/integration/protection-levels.bats` passes all 6 assertions.

---

## Task 10: Documentation + SKILL.md update [AC-8]

- File: `skills/daily-supply-chain-audit/SKILL.md` (modify)
- Change: Add a "Protection levels" section after "What it checks" that:
  - Lists the four levels and their thresholds (reference the table from the spec).
  - Documents the `walter-os.toml` manifest shape.
  - Documents the `--justify` flow and the 90-day expiry.
  - Mentions the offline degraded-mode behavior.
  - Notes the known gaps (cargo, uvx, npm native support).
- File: `skills/daily-supply-chain-audit/SKILL.md` — also add
  `check_min_release_age` to the "What it checks" numbered list as item 10.
- Verify: `cat skills/daily-supply-chain-audit/SKILL.md` shows the new section;
  `tests/lint-cross-references.sh` (existing) passes.

---

## Commit sequence

Each task is one atomic commit following the convention:

```
feat(protection-levels): <imperative subject ≤ 72 chars>

<why — what problem this task solves>

Refs: docs/specs/walter-os-protection-levels.md
```

Tasks 1–8 can be committed individually. Tasks 9 and 10 may be squashed into
the commit for whichever task they close out, or committed separately.
