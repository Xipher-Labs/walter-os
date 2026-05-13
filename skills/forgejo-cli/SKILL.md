---
name: forgejo-cli
description: Manage repos, issues, PRs, and releases on the self-hosted Forgejo (git.${WALTER_DOMAIN}) via the official `tea` CLI. Use this skill whenever the user asks to "create a Forgejo repo", "open an issue on git.${WALTER_DOMAIN}", "list my private repos", "tag a release", or any operation against the self-hosted git. Replaces the dropped community forgejo-mcp.
---

# Forgejo CLI (`tea`)

Forgejo is API-compatible with Gitea, so the official **`tea`** CLI works
1:1. Mature, stable, in apt/brew. Replaces the unmaintained community
forgejo-mcp.

## Setup (one-time, per machine)

```bash
brew install tea               # macOS
# or: apt install gitea-tea    # Ubuntu

# Configure login against Walter-VM Forgejo
tea login add \
  --name walter-vm \
  --url https://git.${WALTER_DOMAIN} \
  --token "$FORGEJO_TOKEN"   # generate at: git.${WALTER_DOMAIN}/user/settings/applications

# Verify
tea login list
tea repos list
```

`FORGEJO_TOKEN` lives in `~/.config/walter-os/secrets.env` (or Infisical
workspace `walter-os`). Scope it to the minimum: `repo:read`, `repo:write`
on a per-repo basis when you can.

## Common operations

### Repos

```bash
tea repos list                              # all repos visible to you
tea repos create --name foo --private       # create private repo
tea repos clone <owner>/<repo>              # clone via SSH
```

### Issues

```bash
tea issues list                             # in current repo
tea issues create --title "Bug X" --body "Steps: ..."
tea issues comment 42 --comment "Fixed in commit abc123"
tea issues close 42
```

### Pull requests

```bash
tea pulls list
tea pulls create --title "Add X" --description "Refs #42"
tea pulls checkout 17                       # check out PR #17 locally
tea pulls merge 17                          # merge (requires approval)
```

### Releases

```bash
tea releases list
tea releases create v0.1.0 --title "v0.1.0" --note "Changelog: ..."
```

## Obsidian sync (this is why we run Forgejo)

The vault syncs to Forgejo via plain git, not via tea. The flow:

```bash
# Inside ~/Obsidian/vault/
git remote add origin git@git.${WALTER_DOMAIN}:operator/obsidian-vault.git
git push -u origin main

# In Obsidian: install the "Git" community plugin → auto-pull/push every N minutes.
```

The agent does NOT touch the Obsidian vault remotely. If it needs to
read/write notes, it does so via the local filesystem MCP on
`~/Obsidian/vault/` and lets the Git plugin sync.

## Hard rules

- **Never push to `main` directly** on shared repos. Use PRs even on
  self-hosted (you might be the only operator, but discipline carries
  to other repos).
- **Never delete a repo via `tea` script**. Repo deletion is interactive
  in the Forgejo web UI.
- **Token rotation**: every 90 days. Set a calendar reminder.
- **Token scope**: never grant `admin` scope to the daily-use token. Mint
  a separate admin token only when you need to create users / install
  apps, then revoke.

## Why CLI instead of MCP

- `tea` is the canonical Gitea/Forgejo CLI, maintained by the Forgejo team.
- Community `forgejo-mcp@1.2.0` had ~community trust score, single
  maintainer, no clear advantage over the CLI.
- All operations scriptable from bash → agent invokes via Bash tool.

## What this skill does NOT cover

- Forgejo admin (user management, runners, etc.) — use the web UI.
- Forgejo Actions runner setup — separate setup script.
- Repo migration from GitHub — use `tea repos migrate` + GitHub PAT.
