# SPEC: Walter-OS one-command upgrade flow

## Problem

Installed operators currently update Walter-OS through scattered commands:
`git pull`, `./install.sh --upgrade`, `walter-os audit`, and optional
`walter deploy <service>` calls for Walter-VM services. That works for the
maintainer, but it is too easy for adopters to miss a step or confuse local
framework updates with VM service updates.

Related issue: #267.

## Decision

Add `walter-os upgrade` as the operator-facing entry point for routine
upgrades. Keep `walter-os sync` as the legacy local fast-forward helper, but
document `upgrade` as the clearer product workflow.

## CLI

```bash
walter-os upgrade [--local|--vm|--all] [--dry-run]
                  [--target <git-ref>] [--snapshot]
                  [--service <name>]... [--skip-audit] [--skip-doctor]
```

- Default mode is `--local`.
- `--local` fast-forwards the Walter-OS checkout or checks out `--target`,
  then runs `install.sh --upgrade`, `walter-os audit`, and `walter-os doctor`.
- `--vm` updates the Walter-VM Walter-OS checkout/config via SSH. It does not
  roll out Docker services by default.
- `--all` runs local first, then VM.
- `--dry-run` prints the planned commands without mutating local or remote
  state.
- `--snapshot` takes a VM snapshot before VM updates. It is opt-in and requires
  `--yes` outside dry-run mode because VM snapshots can cost money.
- `--target` applies only to the local checkout; using it with `--vm` alone is
  invalid.
- `--service <name>` explicitly rolls out one Docker service through the
  existing `walter deploy <service>` path after the VM checkout update.

## Safety Invariants

- Non-dry-run local upgrades refuse a dirty working tree.
- Non-target local upgrades use fast-forward-only pulls.
- Targeted local upgrades fetch tags before checkout.
- Docker service updates never happen implicitly; each service must be named.
- Explicit service updates go through the existing `walter deploy` path,
  preserving service-specific config sync and `.env` exclusions.
- Snapshotting is explicit, never implicit.
- The command is testable without touching the operator's real VM via
  `--dry-run`.

## Acceptance Criteria

- [ ] `walter-os help` lists `upgrade`.
- [ ] `walter-os upgrade --dry-run` shows the local upgrade plan and performs
      no writes.
- [ ] `walter-os upgrade --all --dry-run --snapshot --service n8n` shows local,
      VM checkout, snapshot, and explicit service deploy steps.
- [ ] `walter-os upgrade --vm --target vX.Y.Z` exits non-zero with a clear
      error.
- [ ] Non-dry-run snapshots require `--yes`.
- [ ] README documents routine upgrades through `walter-os upgrade`.
- [ ] Focused Bats tests cover the CLI contract.
