# walter-personal — Onboarding (6 steps)

## Step 1: Copy the skeleton

From your Walter-OS repo:

```bash
cp -r contexts/_examples/walter-personal-skeleton ~/walter-personal
cd ~/walter-personal
```

Or use the helper flag (does the same thing, puts it directly in the overlay):

```bash
./setup/personal-overlay-init.sh --from-skeleton
```

If using `--from-skeleton`, the overlay is immediately live at
`~/.config/walter-os/overlay/`. Skip to Step 3.

## Step 2: Initialize a git repo

```bash
cd ~/walter-personal    # or wherever you copied the skeleton
git init
git add .
git commit -m "chore: initial walter-personal skeleton"
```

## Step 3: Fill in your values

Rename and edit the template files:

```bash
mv personal.env.template personal.env
# Edit personal.env — fill in WALTER_DOMAIN, GITHUB_USER, etc.

mv contexts/work/AGENTS.md.template contexts/work/AGENTS.md
# Edit to describe your company stack and workflow rules.

mv contexts/projects-personal/AGENTS.md.template contexts/projects-personal/AGENTS.md
# Edit to list your active personal projects.

mv contexts/personal/AGENTS.md.template contexts/personal/AGENTS.md
# Edit to add your locale, tax context, health notes policy.
```

Commit your changes:

```bash
git add .
git commit -m "chore: fill in personal values"
```

## Step 4: Push to a private remote

```bash
# GitHub (using gh CLI):
gh repo create YOUR_GITHUB_USER/walter-personal --private --source=. --push

# Forgejo / Gitea (self-hosted):
git remote add origin git@your-forgejo.example.com:YOUR_USER/walter-personal.git
git push -u origin main
```

## Step 5: Wire the overlay

If you used `--from-skeleton`, the overlay is already at `~/.config/walter-os/overlay/`.
If you initialized manually, symlink or clone it:

```bash
# Option A: clone directly as the overlay
./setup/personal-overlay-init.sh --git-clone git@github.com:YOUR_USER/walter-personal.git

# Option B: symlink (if the repo lives elsewhere)
ln -s ~/walter-personal ~/.config/walter-os/overlay
```

## Step 6: Clone on a second machine

On the new machine, after cloning Walter-OS:

```bash
./setup/personal-overlay-init.sh --git-clone git@github.com:YOUR_USER/walter-personal.git
```

This clones your private repo directly to `~/.config/walter-os/overlay/`.
The overlay is immediately active — no further steps required.

---

## Keeping in sync

On each machine, pull changes before starting a session:

```bash
cd ~/.config/walter-os/overlay && git pull
```

After editing context files, commit and push:

```bash
cd ~/.config/walter-os/overlay
git add -p
git commit -m "chore: update work context — new project"
git push
```

For fully automatic sync without git discipline, see the Syncthing alternative
in `docs/operational/multi-device-sync.md`.
