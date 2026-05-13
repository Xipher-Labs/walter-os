# Walter-OS Protection Levels + minimumReleaseAge

**Status**: Draft
**Owner**: Xipher Labs
**Created**: 2026-05-12

## Problem

Walter-OS already enforces exact-version pinning and daily CVE/config-drift auditing
(PR #54). Both checks fire *after* a package has been installed. They do nothing
about the window between a release being published and the community noticing it is
malicious — a window that has shrunk to hours for targeted attacks
(ClawHavoc, npm package-confusion campaigns, compromised maintainer accounts).

The first hours and days of any release are the highest-risk period. A supply-chain
attacker who hijacks a maintainer account can push a poisoned version, have it auto-
installed by anyone running `pnpm install` or `npx @foo/bar@latest`, and extract
tokens before the registry reverts the package. Waiting a minimum number of days
before trusting a new release is the single most cost-effective mitigation that
does not require changing the developer workflow.

Different repos in the Walter-OS ecosystem carry different risk profiles. A
hackathon prototype and the example work org production RPC layer should not share the same
defaults. Today there is no declarative way to express that difference, so the
audit script has to be patched manually per-repo — which means it never actually
happens.

## Proposed Solution

Two complementary additions:

**1. `minimumReleaseAge` enforcement** — a configurable wait period (default 21 days
for production repos) before any package version is considered safe to install.
Enforced at the package-manager layer where the PM supports it (Bun ≥ v1, pnpm ≥
10.16), and at the audit layer for everything else. A `--justify` escape hatch
allows exceptions with mandatory tamper-evident logging.

**2. Protection levels** — a declarative `walter-os.toml` manifest at the repo
root that bundles sensible defaults for `minReleaseAge`, pin strategy, audit-gate
severity threshold, and review requirements. Four levels are defined (`experimental`,
`sandbox`, `staging`, `production`), with auto-assignment by path and full override
capability. `install.sh` writes the package-manager configs when it runs; the daily
audit reads the manifest and applies the corresponding check settings.

## Acceptance Criteria

- [AC-1] A `walter-os.toml` manifest schema is defined and documented. The parser
  accepts the file, falls back to defaults on missing file, and emits a warning but
  does not crash on malformed TOML.
- [AC-2] `walter-os protection` subcommand reads and prints the active protection
  level for the current directory (falling back to auto-assigned level when no
  manifest is present).
- [AC-3] `install.sh` writes correct `minimumReleaseAge` values into `~/.bunfig.toml`
  and `~/.config/pnpm/rc` matching the active level's policy. The write is
  idempotent and does not destroy unrelated user config in those files.
- [AC-4] `check_min_release_age()` in the audit script queries npm and PyPI release
  dates, respects a 24-hour TTL cache at `~/.config/walter-os/release-date-cache.json`,
  and emits a finding at the severity matching the active protection level's audit
  gate when a dependency is younger than `minReleaseAge`.
- [AC-5] Network failure during release-date lookup causes an `info`-severity finding
  (not a block) and falls back to the local cache; the audit continues to completion
  in offline/degraded mode.
- [AC-6] `walter-os justify <pkg>@<version> --reason="<text>"` appends one JSON
  object to `~/.config/walter-os/justify-log.jsonl` (append-only). The justified
  package is exempt from the age check for 90 days from the timestamp.
- [AC-7] The justify log is read by `check_min_release_age()` and non-expired
  entries suppress the finding for the named package+version.
- [AC-8] The four protection level bundles are codified and reachable from a single
  source of truth (`skills/daily-supply-chain-audit/protection-levels.toml`). The
  bundles match the table in the Decisions section below.
- [AC-9] All new shell entry-points have bats unit tests. The Python helper has
  pytest unit tests. Tests cover: cache hit, cache miss, offline path, expired
  justify entry, non-expired justify entry, malformed `walter-os.toml`.
- [AC-10] `walter-os doctor` reports whether the PM-level `minimumReleaseAge`
  config is present and correct for the resolved protection level.

## Decisions

### Protection level bundles (codified in `protection-levels.toml`)

| Level | `minReleaseAge` | Pin strategy | Audit gate | Review |
|---|---|---|---|---|
| `experimental` | 0 d | any | info only | self |
| `sandbox` | 7 d | minor-locked | warn (no block) | self |
| `staging` | 14 d | exact | block CVSS >= 7 | reviewer subagent |
| `production` | 21 d | exact | block CVSS >= 7 + drift | reviewer + security-auditor |

Auto-assignment by path (applied when no manifest is found):

- `~/work/*` or remote matches `${WALTER_WORK_GITHUB_ORG}` → `production`
- `~/Projects/*` → `staging`
- Repo name contains `hackathon` or type is `hackathon` → `sandbox`
- Everything else → `staging` (safe default)

### TOML parser approach

**Python helper** (`scripts/parse-manifest.py`). Bash has no native TOML parser.
The alternatives — `tq`/`yq` (requires an extra binary not in the bootstrap set),
or a bash regex parser (brittle, breaks on multi-line values and quoted strings) —
are worse tradeoffs. Python 3 ships on macOS and is already required by `uvx` and
the devrel-analyst skill. The manifest is kept deliberately flat so the parser
stays under 50 lines with stdlib only (`configparser` fallback if `tomllib` is not
available; `tomllib` is stdlib in Python 3.11+).

The parser is invoked lazily: only when a check actually needs the protection level.
It emits JSON to stdout so callers can use `jq` or read it directly in bash.

### `--justify` interaction with the audit gate

`walter-os justify <pkg>@<ver> --reason="..."` appends to
`~/.config/walter-os/justify-log.jsonl` (append-only JSONL). Each entry:

```json
{"ts": "<ISO8601>", "pkg": "<name>", "version": "<ver>", "level": "<active level>",
 "reason": "<operator text>", "operator": "<$USER>", "expires": "<ISO8601+90d>"}
```

During `check_min_release_age()`, before emitting a finding, the helper reads the
log, discards entries where `expires < now`, and suppresses the finding for any
package+version that has a live entry. The suppression is logged in the audit
report as `[INFO] <pkg>@<ver> age-check suppressed by justify entry (expires: ...)`.

The gate severity for an unjustified too-young package follows the active level:
- `experimental`/`sandbox`: `info` (no block)
- `staging`: `high` (blocks with `ack`)
- `production`: `high` (blocks with `ack`; drift-check also fires as `crit` if the
  package appears in a lock file that was not reviewed post-install)

### Cache design

Cache file: `~/.config/walter-os/release-date-cache.json`
Shape: `{ "<pkg>@<ver>": { "published": "<ISO8601>", "fetched_at": "<ISO8601>" } }`
TTL: 24 hours. Entries older than 24 h are refetched if the network is available.
On network failure: stale cache entries are used as-is (treated as valid); if no
cache entry exists the finding is emitted as `info` (not high), noting the lookup
could not be completed.

### Package-manager config templates

- **Bun** (`~/.bunfig.toml`): `[install]\nminimumReleaseAge = "<seconds>"`. `install.sh`
  uses `python3 scripts/patch-toml-key.py` to set the key without destroying the
  rest of the file. Values: 0s / 604800s / 1209600s / 1814400s for the four levels.
- **pnpm** (`~/.config/pnpm/rc`): `minimum-release-age=<minutes>`. Values:
  0 / 10080 / 20160 / 30240. Written with a simple sed/awk pass since the file is
  a flat `key=value` ini.
- **npm** / **cargo** / **uvx**: no native support. `install.sh` logs a warning
  pointing to the known gap; the audit script checks ages for these ecosystems
  directly.

### Manifest shape (`walter-os.toml`)

```toml
[walter]
protection = "production"   # one of: experimental | sandbox | staging | production
context    = "projects-personal"  # mirrors existing Walter-OS context system

[walter.overrides]
# Any bundle key can be overridden here.
# minReleaseAge = "7d"  # e.g. relax for a specific repo
```

The `[walter.overrides]` section is additive: only specified keys override the
bundle; unspecified keys inherit from the named level.

## Non-goals

- Per-package allowlists (e.g. `@types/*` always OK regardless of age) — followup.
- Bun/pnpm rollout to specific Walter-OS apps (control-tower, etc.) — followup.
- Native `cargo` or `uvx` age enforcement at the PM layer — documented as a known
  gap; covered by the audit script's direct check instead.
- Automated remediation (auto-pin an update, auto-remove a package) — operator-
  driven only.
- Registry mirroring or vendoring — out of scope for v0.1.
- CI/CD enforcement (GitHub Actions gate) — followup once the audit script is stable.

## Open Questions

- **pnpm `minimum-release-age` unit**: the docs say "minutes" but some sources say
  "seconds" for pnpm 10.16+. Implementer must verify against the pnpm 10.16
  changelog before writing the value to `~/.config/pnpm/rc`.
- **Renovate alignment**: `renovate.json` already sets `minimumReleaseAge: "3 days"`
  globally and `"14 days"` for major bumps. Should `install.sh` also update
  `renovate.json` to match the active protection level, or leave Renovate config
  as a separate concern? Recommended: leave it separate (Renovate is committed to
  the repo; `walter-os.toml` is the local enforcement layer). Confirm with operator.
- **Multi-repo installs**: when `install.sh` is run from repo A, it writes
  `~/.bunfig.toml` with repo A's protection level. If repo B has a different level,
  the last `install.sh` run wins at the PM layer. The audit script reads per-repo
  manifests correctly, but the PM config is machine-global. Acceptable for v0.1?
  Recommended mitigation: always use the *highest* level seen across all installed
  repos (i.e. `production` wins). Operator to confirm.
- **`justify` expiry for critical CVE patches**: 90-day default may be too long if a
  package later turns out to be malicious. Should justify entries be revocable? A
  `walter-os justify revoke <pkg>@<ver>` subcommand is trivial to add but was not
  scoped here.

## References

- `skills/daily-supply-chain-audit/SKILL.md` — current audit skill contract
- `skills/daily-supply-chain-audit/scripts/audit.sh` — script being extended
- `.github/renovate.json` — existing `minimumReleaseAge` configuration
- PR #54 — exact-version pinning (base for this work); `check-pinning.py` added there
- Bun install docs: https://bun.sh/docs/runtime/bunfig#install-minimumreleaseage
- pnpm 10.16 changelog: minimum-release-age flag
- npm Registry API: `npm view <pkg>@<ver> time --json`
- PyPI JSON API: `https://pypi.org/pypi/<pkg>/json`
