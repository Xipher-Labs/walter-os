# PLAN: Agent-install tier completion

**Spec:** `docs/specs/agent-install-tier-completion.md`
**ADR:** `docs/decisions/0014-walter-os-cli-symlink-path.md`
**Branch:** `feature/agent-install-tier-completion`
**Total tasks:** 13 (10 implementation + 3 verification).
**Estimated effort:** 90 minutes assuming Bats + bash familiarity.

Each task follows RED-GREEN-REFACTOR. Skip RED is a violation of
`test-driven-development` (superpowers).

---

## Phase A — Test scaffolding (RED for everything that comes after)

### A1. Create new bats test files (empty shells, headers only)

**Files:**
- `tests/install/cli-symlink.bats` (will cover AC1–AC3)
- `tests/cli/walter-os-doctor.bats` (will cover AC4, golden-output regression)
- `tests/cli/walter-os-doctor-tier.bats` (will cover AC5, AC6)
- `tests/compose/tier-profile-gates.bats` (will cover AC7, AC8)
- `tests/install/tier-prompts-flag-coverage.bats` (will cover AC9, AC10)
- `tests/skills/tier-prompts-consistency.bats` (will cover AC11)

Each file: shebang + REPO_ROOT discovery + 1 placeholder `@test "TODO"
{ skip; }`. Verify all 6 files are recognized:
```
bats --list tests/install tests/cli tests/compose tests/skills | grep -cE 'tier|symlink|doctor' # expect 6
```

### A2. Write failing tests for AC1–AC3 (CLI symlink)

**File:** `tests/install/cli-symlink.bats`

Tests (use a temp $HOME to avoid touching the operator's machine):
- `@test "AC1: --upgrade creates ~/.local/bin/walter-os symlink"`
- `@test "AC1: symlink target is ${WALTER_OS_HOME}/bin/walter-os"`
- `@test "AC2: invoking ~/.local/bin/walter-os --version exits 0"`
- `@test "AC3: re-running --upgrade does not error or duplicate"`

Verify: `bats tests/install/cli-symlink.bats` → 4 FAIL (symlink code not written yet).

### A3. Write failing tests for AC4 (doctor regression)

**File:** `tests/cli/walter-os-doctor.bats`

Golden-output test: capture current `walter-os doctor` output to a
fixture (`tests/cli/fixtures/doctor-baseline.txt`), assert future runs
match the structure (✓/✗ count, section headers). Loose match — exact
line-by-line is too brittle.

Verify: PASS today (no behavior change yet); will catch regressions.

### A4. Write failing tests for AC5, AC6 (doctor --tier N)

**File:** `tests/cli/walter-os-doctor-tier.bats`

- `@test "AC5: --tier 1 runs only tier-1 subset"` (stub all check
  functions to return 0, count printed lines, assert N1)
- `@test "AC5: --tier 2 runs tier-1 + tier-2 subsets"` (assert N2 > N1)
- `@test "AC5: --tier 3 runs tier-1 + 2 + 3"` (assert N3 > N2)
- `@test "AC5: --tier 4 runs all four tiers"` (assert N4 > N3)
- `@test "AC6: --tier 99 exits non-zero with 'invalid tier'"`

Verify: 5 FAIL (flag not implemented yet).

### A5. Write failing tests for AC7, AC8 (compose profile gates)

**File:** `tests/compose/tier-profile-gates.bats`

- `@test "AC7: --profile core config does NOT list control-tower"`
  (uses `docker compose --profile core config --services` → grep -v control-tower)
- `@test "AC7: default config (no profile) does NOT list control-tower"`
- `@test "AC8: --profile tier4 config DOES list control-tower"`

Skip these tests if `docker compose` is not installed (CI may not have
it on every job; gate with `command -v docker`).

Verify: 3 FAIL (compose still has no profile).

### A6. Write failing tests for AC9, AC10 (prompts ↔ reality)

**File:** `tests/install/tier-prompts-flag-coverage.bats`

- `@test "AC9: every install.sh flag in prompts exists in install.sh"`
  (grep `install\.sh --[a-z-]+` from all four prompts, assert each is
  in the case statement in install.sh)
- `@test "AC10: every walter-os subcommand in prompts exists in bin/walter-os"`
  (grep `walter-os [a-z-]+`, assert each in the case statement in bin/walter-os)

Verify: FAIL (prompts have inventado flags like `--skills` that don't
exist yet — failing test == the drift we're closing).

### A7. Write failing tests for AC11 (Plane naming consistency)

**File:** `tests/skills/tier-prompts-consistency.bats`

- `@test "AC11: tier-4.md uses 'projects-personal' not 'personal-projects'"`
  (positive assert on canonical form, negative assert on incorrect form)

Verify: FAIL today (tier-4.md uses `personal-projects`).

---

## Phase B — Compose profile gate (smallest, lowest risk)

### B1. Add `profiles: [tier4]` to compose.yml control-tower

**File:** `compose.yml`

Inside the `control-tower:` service block, add:
```yaml
    profiles: [tier4]
```

Verify:
```
docker compose --profile core config --services | grep -v control-tower    # expect: no output for control-tower
docker compose --profile tier4 config --services | grep control-tower      # expect: control-tower
```
Then re-run AC7, AC8 bats → both PASS.

### B2. Document the gate in CHANGELOG

**File:** `CHANGELOG.md` — add to Unreleased section:
```
### Changed
- compose.yml: `control-tower` is now gated behind `--profile tier4`.
  Operators who relied on default-on control-tower must add `tier4` to
  `COMPOSE_PROFILES` or pass `--profile tier4` explicitly.
```

---

## Phase C — CLI symlink in install.sh

### C1. Add the symlink line inside `install.sh --upgrade` step 0

**File:** `install.sh`

Inside the existing "STEP-0" block (~line 1583), after the existing
`PATH` export, add:
```bash
local cli_symlink="${HOME}/.local/bin/walter-os"
mkdir -p "${HOME}/.local/bin"
ln -sf "${WALTER_OS_HOME}/bin/walter-os" "${cli_symlink}"
if ! command -v walter-os >/dev/null 2>&1; then
  warn "  ~/.local/bin/ is not in your \$PATH. Add it to your shell rc:"
  warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
```

Verify: AC1, AC2, AC3 bats → all PASS.

### C2. Document in install.sh `--help` output

Update the `--help` text inside `install.sh` so the `--upgrade`
description mentions the symlink behavior.

---

## Phase D — walter-os doctor --tier N

### D1. Tag existing checks with tier numbers

**File:** `bin/walter-os` (in `cmd_doctor()` around line 1086).

Refactor: introduce a `_tier_filter` shell variable. Each `check`
invocation gains a tier number suffix passed through a wrapper:

```bash
tier_check() {
  local tier_n="$1"; shift
  if [[ -z "${_tier_filter:-}" ]] || [[ "${_tier_filter}" -ge "${tier_n}" ]]; then
    check "$@"
  fi
}
```

Then existing `check` calls become `tier_check 1 "..."` or `tier_check 2 "..."` per the spec §4.2 mapping.

### D2. Add `--tier N` flag parsing

At the top of `cmd_doctor()`:
```bash
local _tier_filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      _tier_filter="$2"
      shift 2
      ;;
    --tier=*)
      _tier_filter="${1#--tier=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${_tier_filter}" ]] && [[ ! "${_tier_filter}" =~ ^[1-4]$ ]]; then
  echo "Error: --tier must be 1, 2, 3, or 4 (got: ${_tier_filter})" >&2
  return 1
fi
```

Verify: AC5 partial pass (tier 1 + 2 work because existing checks cover them).

### D3. Add new tier 3 + 4 checks

Append to `cmd_doctor()` after existing checks:

```bash
# Tier 3: VM-side credential checks
tier_check 3 "HCLOUD_TOKEN env set" test -n "${HCLOUD_TOKEN:-}"
tier_check 3 "WALTER_DOMAIN env set" test -n "${WALTER_DOMAIN:-}"

# Tier 4: Council prerequisites
tier_check 4 "trust-tiers.yml present" test -f "${WALTER_CONFIG}/trust-tiers.yml"
tier_check 4 "Plane API token present in Infisical" \
  bash -c "test -n \"\$(walter-os secrets-pull plane/PLANE_API_TOKEN 2>/dev/null)\""
```

Verify: AC5 full pass (tier 3 and tier 4 add their extras).

### D4. Add invalid tier handling test

Already covered by AC6 test from A4. Verify it PASSes after D2.

---

## Phase E — Prompts rewrite

### E1. tier-1.md alignment

- Remove enumerated hook list; replace with link to `hooks/` directory and "the install.sh --upgrade step installs everything in that directory".
- Update CLI path verification: replace `~/.local/bin/walter-os` with `walter-os` (use `which walter-os` to confirm, the symlink resolves correctly).
- Verify step: `walter-os doctor --tier 1`.

### E2. tier-2.md alignment

- Drop references to `install.sh --skills`, `--mcp-default`, `--mcp-high-risk`, `--commands`, `--approval-gate`, `--daily-audit-hook`. Replace the whole block with one `install.sh --upgrade` call and prose explaining what it installs.
- Update precheck: `command -v walter-os` (the symlink is on $PATH after install).
- Verify step: `walter-os doctor --tier 2`.

### E3. tier-3.md alignment

- Add explicit `--profile core` (+ chosen optional profiles) to all `docker compose up -d` invocations. The "control-tower NOT started" claim is now enforced by the profile gate from Phase B.
- Verify step: `walter-os doctor --tier 3`.

### E4. tier-4.md alignment

- Replace `personal-projects` with `projects-personal` (matches canonical name in `docs/specs/multi-agent-autonomy.md`).
- Add `--profile tier4` to the `docker compose up -d` command for control-tower.
- Verify step: `walter-os doctor --tier 4`.

After E1–E4: re-run AC9, AC10, AC11 bats → all PASS.

---

## Phase F — Verification

### F1. Run full hook + new test suite

```bash
bats tests/install/cli-symlink.bats
bats tests/cli/walter-os-doctor.bats
bats tests/cli/walter-os-doctor-tier.bats
bats tests/compose/tier-profile-gates.bats
bats tests/install/tier-prompts-flag-coverage.bats
bats tests/skills/tier-prompts-consistency.bats
```

Expected: 100% PASS (AC1–AC11).

### F2. Run existing test suite (regression check)

```bash
bats tests/
```

Expected: same pass count as on `main` pre-change. AC12 covered.

### F3. DoD validator

```bash
walter-os skills run definition-of-done-validator \
  --spec docs/specs/agent-install-tier-completion.md
```

Expected: 11/11 acceptance criteria mapped to tests. Print AC matrix.

### F4. Manual smoke test (operator action)

After PR opens, the operator (or reviewer) clones the branch into a
fresh `$HOME` (or container), runs `./install.sh --upgrade`, and
manually pastes `tier-1.md`'s prompt block into Claude Code in a
scratch directory. The agent should walk Section 1 → Step 6 without
any "command not found" or "flag unknown" errors.

This is the real DoD — the prompts have to copy-paste-execute.

---

## Out-of-plan items (require operator approval to add later)

- Address the 16 low-confidence Copilot suggestions on PR #103 (F1 in spec).
- `walter-os install-tier <N>` meta-command (F2 in spec).
- Profile-gate other Tier IV services as they land (F3 in spec).
- CI agent-in-the-loop smoke test (F4 in spec).

---

## Commit strategy

One commit per task (A1, A2, …, F3). Conventional commits:

```
test: scaffold bats tests for agent-install tier completion (A1)
test: failing tests for CLI symlink (A2)
feat: gate compose.yml control-tower behind tier4 profile (B1)
docs: changelog entry for control-tower profile gate (B2)
feat: install.sh --upgrade adds ~/.local/bin/walter-os symlink (C1)
docs: install.sh --help mentions CLI symlink (C2)
refactor: tag walter-os doctor checks by tier (D1)
feat: walter-os doctor --tier N (D2)
feat: walter-os doctor tier 3 + 4 checks (D3)
docs: tier-1.md aligned to install.sh + walter-os reality (E1)
docs: tier-2.md drops invented install.sh flags (E2)
docs: tier-3.md adds explicit --profile flags (E3)
docs: tier-4.md fixes Plane project naming + adds tier4 profile (E4)
```

PR title: `[FEAT] -OPERATIONS- agent-install tier completion (supersedes #103)`
(matches `hooks/pr-title-validator.sh` convention).
