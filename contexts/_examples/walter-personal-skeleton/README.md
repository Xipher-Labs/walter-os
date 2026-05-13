# walter-personal

This directory is the skeleton for your private `walter-personal` git repository.
It contains template configuration files for Walter-OS, the open-source
operator automation framework.

## What is walter-personal?

Walter-OS is a public framework. Your personal configuration — your domain, your
company context, your life-admin preferences — lives here, in a *private* repo that
you own and control.

## When to use this pattern

- You use Walter-OS on more than one machine and want config changes to sync via git
  (rather than Syncthing alone).
- You want revision history and rollback for your personal context files.
- You want to back up your overlay to a private remote (GitHub, Forgejo, Gitea, etc.).

If you only ever use one machine and don't need history, the plain overlay at
`~/.config/walter-os/overlay/` (without git) is sufficient.

## Security caveats

**Never commit raw secrets to this repo, even if it is private.**

This skeleton's `.gitignore` excludes `.env*` (except `.env.template` and
`.env.example`) and `secrets/`. Use these patterns to keep credentials out:

- Store API keys in Infisical (self-hosted) and reference them by project ID.
- Store passwords in Vaultwarden and reference them by secret path.
- If you must commit a value, store only the Infisical/Vaultwarden reference path,
  not the secret itself.

See `docs/operational/universal-vs-personal-config.md` in the Walter-OS repo for
full secrets guidance.

## Backup considerations

Even with a private remote, consider encrypting the repo at rest if it contains
sensitive context files (your health notes, financial context, etc.). Options:

- `git-crypt` — encrypt specific files transparently.
- `age` — encrypt entire files before committing.
- Full-disk encryption on the machine hosting the bare clone (recommended baseline).

## Structure

```
walter-personal/
├── README.md                          # this file
├── INSTALL.md                         # 6-step onboarding
├── .gitignore                         # pre-configured for secrets hygiene
├── personal.env.template              # → rename to personal.env and fill in values
└── contexts/
    ├── work/
    │   └── AGENTS.md.template         # → rename to AGENTS.md and fill in
    ├── projects-personal/
    │   └── AGENTS.md.template         # → rename to AGENTS.md and fill in
    └── personal/
        └── AGENTS.md.template         # → rename to AGENTS.md and fill in
```
