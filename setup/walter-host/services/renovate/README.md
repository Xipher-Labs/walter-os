# Renovate self-hosted profile

Optional dependency-update runner for Walter-OS and related repositories. It is
disabled by default: nothing runs unless the operator explicitly invokes this
directory's compose profile or installs the commented cron example.

## Files

| File | Purpose |
|---|---|
| `compose.yml` | One-shot Renovate container, pinned image, no exposed ports. |
| `config.js` | Bot/admin self-hosted config. Repository config stays in each repo's onboarding PR. |
| `.env.template` | Non-secret mode and discovery settings only. |
| `run.sh` | Small host wrapper for manual and cron invocations. |
| `cron.example` | Commented weekly schedule example, disabled by default. |

## Secrets

The bot credential must be stored in Infisical as `RENOVATE_TOKEN` and loaded
through the Walter-OS runtime secrets flow:

```bash
walter_secrets_load
cd setup/walter-host/services/renovate
./run.sh dry-run
```

Do not write the token to `.env`, `.env.template`, compose files, cron files, or
repository config. The compose service fails closed when `RENOVATE_TOKEN` is not
present in the process environment.

## GitHub mode

Use `RENOVATE_PLATFORM=github`. For GitHub.com, leave `RENOVATE_ENDPOINT` empty.
For GitHub Enterprise Server, set `RENOVATE_ENDPOINT` to the API base URL, for
example `https://github-enterprise.example.com/api/v3/`.

Token guidance:

- Prefer a dedicated bot account or GitHub App installation token.
- Classic PAT: `repo`; add `workflow` only if Renovate may update GitHub Actions.
- Fine-grained PAT: read/write Contents, Pull requests, Issues, Commit statuses,
  and Workflows; read-only Members and Dependabot alerts when available.
- Scope the token to explicit repositories during rollout.

## Forgejo mode

Use `RENOVATE_PLATFORM=forgejo` and set `RENOVATE_ENDPOINT` to the Forgejo API
base URL, for example `https://git.${WALTER_DOMAIN}/api/v1/`.

Forgejo bot requirements:

- Bot user has a full name and email configured.
- PAT has repository read/write and issue read/write for selected repositories.
- Add organization read only when repository discovery needs org labels/teams.
- Use specific repository access where possible.

## Repository Discovery

The first rollout should use an explicit comma-separated repository list:

```bash
export RENOVATE_REPOSITORIES=your-org/Walter-OS
```

Autodiscover is disabled by default because Renovate otherwise considers every
repository the bot can access. If discovery is required, enable it only with a
restrictive filter or namespace:

```bash
export RENOVATE_AUTODISCOVER=true
export RENOVATE_AUTODISCOVER_FILTER='your-org/Walter-*'
```

Forgejo also supports namespace filtering:

```bash
export RENOVATE_AUTODISCOVER=true
export RENOVATE_AUTODISCOVER_NAMESPACES='walter'
```

## Onboarding PR Behavior

`config.js` sets `onboarding=true` and `requireConfig=required`. When a target
repo has no Renovate config, Renovate opens an onboarding PR instead of applying
updates immediately. If that onboarding PR is closed without merging and the
repo still has no config, future runs skip the repo.

Expected onboarding PR example:

```text
Title: [CHORE] -TECHNICAL- configure Renovate
Branch: renovate/configure
File: renovate.json
Behavior: conservative defaults, dependency dashboard, no automerge,
minimumReleaseAge 7 days, strict internal checks.
```

## Conservative Defaults

- No automerge.
- Minimum release age: 7 days.
- Strict internal checks before branch/PR creation.
- PR rate limits: 2/hour, 5 concurrent.
- Major updates require dependency-dashboard approval and stay ungrouped.
- Patch/digest updates may be grouped to reduce noise.

## Security Notes

- `allowedCommands` is empty, so repository `postUpgradeTasks` cannot execute.
- `allowShellExecutorForPostUpgradeCommands=false`; do not enable it for shared
  or untrusted repositories.
- `allowedUnsafeExecutions` is empty; implicit risky package-manager executions
  such as wrapper-generated commands are blocked unless explicitly reviewed.
- `allowScripts=false` and `ignoreScripts=true`; package install lifecycle
  scripts are not allowed during update artifact generation.
- Keep `RENOVATE_DRY_RUN=full` for the first run against every new repo.
- Never enable automerge in this profile. That is a separate policy decision.

## Verification

Dry-run against a test repository:

```bash
walter_secrets_load
cd setup/walter-host/services/renovate
cp .env.template .env
$EDITOR .env
export RENOVATE_REPOSITORIES=your-org/renovate-smoke-test
RENOVATE_DRY_RUN=full ./run.sh dry-run
```

Expected result:

```text
INFO: Repository started
INFO: DRY-RUN: Would ensure onboarding PR
INFO: Repository finished
```

After the dry-run is clean, run once without dry-run:

```bash
unset RENOVATE_DRY_RUN
./run.sh run
```

Confirm the test repository receives only the onboarding PR. Merge that PR only
after reviewing the generated `renovate.json`.
