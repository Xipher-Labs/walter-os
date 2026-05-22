# Walter-OS Review Loop — GitHub Action

A composite GitHub Action that implements the **Walter-OS 3-round PR review pattern**: Copilot → Codex → collaborative. The action is usable standalone — you do NOT need to adopt the rest of Walter-OS to call it from your workflow.

## What it does

For every PR your workflow runs it on:

1. **Round 1 — Copilot** — requests Copilot review via the GitHub REST API (the only endpoint that works for the Copilot reviewer bot; `gh pr edit --add-reviewer` variants all fail with `Could not resolve user/team`).
2. **Round 2 — Codex** — runs `codex exec review` against the PR's base branch, if the `codex` CLI is on PATH and an `auth.json` is mounted.
3. **Round 3 — Collaborative** — emitted as a status verdict; the workflow that consumes this action is responsible for the collaborative round when findings remain after Rounds 1+2.

Each round is **graceful-degradation**:
- Copilot unavailable (PR too large, capacity, org policy) → Round 1 skipped with a warning, action continues.
- `codex` CLI missing OR no `auth.json` → Round 2 skipped with a warning, action continues.
- Both rounds skipped → action emits `status=escalate` for the caller to investigate.

## Usage

```yaml
# .github/workflows/pr-review.yml
name: PR review loop

on:
  pull_request:
    branches: [main]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # need full history for the diff
      - uses: Xipher-Labs/walter-os/.github/actions/walter-review-loop@main
        id: review
        with:
          pr-number: ${{ github.event.pull_request.number }}
          base-branch: ${{ github.event.pull_request.base.ref }}
          run-copilot: true
          run-codex: true
      - name: Post status
        if: always()
        run: |
          echo "Rounds: ${{ steps.review.outputs.rounds-completed }}"
          echo "Status: ${{ steps.review.outputs.status }}"
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `pr-number` | yes | — | The PR number to review. |
| `base-branch` | yes | `main` | The base branch for the diff. |
| `severity-gate-config` | no | `''` | Optional path to a severity-gate config (Walter-OS-specific — see [docs/specs/pr-review-severity-gate.md](../../../docs/specs/pr-review-severity-gate.md) in the Walter-OS repo). |
| `run-copilot` | no | `true` | Whether to request Copilot review (Round 1). |
| `run-codex` | no | `true` | Whether to run Codex review (Round 2). |
| `github-token` | no | `${{ github.token }}` | Token used to request Copilot review. |
| `codex-home` | no | `/tmp/codex-minimal` | `CODEX_HOME` path. Set + mount `auth.json` here BEFORE the action to enable Round 2. |

## Outputs

| Output | Description |
|---|---|
| `findings-json` | JSON array of `{round, tool, severity, file, line, message}` objects. Empty in v1 — the calling workflow reads raw outputs from PR comments + `/tmp/codex-review.txt`. Future iterations will parse findings into structured form. |
| `rounds-completed` | JSON array listing which rounds actually ran. Subset of `['copilot-round-1', 'codex-round-2', 'collaborative-round-3']`. |
| `status` | Overall verdict — `clean` / `findings` / `escalate`. v1 emits `escalate` when no rounds ran, `findings` otherwise; future iterations will parse severities and emit `clean` when all findings are MINOR/COSMETIC. |

## Setting up Codex Round 2

The Codex CLI requires an `auth.json` with valid credentials. The action expects it at `${codex-home}/auth.json` (default `/tmp/codex-minimal/auth.json`).

Recommended workflow:

```yaml
- name: Mount Codex auth
  env:
    CODEX_AUTH_JSON: ${{ secrets.CODEX_AUTH_JSON }}
  if: ${{ env.CODEX_AUTH_JSON != '' }}
  run: |
    mkdir -p /tmp/codex-minimal
    printf '%s' "$CODEX_AUTH_JSON" > /tmp/codex-minimal/auth.json
- uses: Xipher-Labs/walter-os/.github/actions/walter-review-loop@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    base-branch: main
```

Without `CODEX_AUTH_JSON`, Round 2 is automatically skipped and the action still runs Round 1.

## License

Apache-2.0 — see [LICENSE-APACHE](../../../LICENSE-APACHE) in the Walter-OS repo. You may copy, adapt, and redistribute this action without restriction beyond attribution.

## Limitations (v1)

- `findings-json` is a placeholder — parsing Copilot review comments + Codex stdout into structured findings is deferred.
- The `status` verdict is coarse (`escalate`/`findings`); it doesn't yet distinguish "clean" from "MINOR-only".
- The collaborative round (Round 3) is the caller's responsibility — this action only handles Rounds 1+2.

Tracking: [Walter-OS issue #149](https://github.com/Xipher-Labs/walter-os/issues/149).
