# Signing commits — SSH or GPG

GitHub branch protection on `main` requires signed commits. SSH is the
simpler path because the same key you already use to push can sign.

## Option A: SSH signing (recommended)

1. Reuse or generate an Ed25519 key (skip if you already push via SSH):

   ```bash
   ssh-keygen -t ed25519 -C "<your-username>@walter-os" -f ~/.ssh/id_ed25519
   ```

2. Configure git to sign with SSH:

   ```bash
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519.pub
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   ```

3. Add the **same public key** to GitHub as a **Signing Key** (Auth and
   Signing are separate entries even when the key material is identical):

   ```bash
   gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "walter-os signing"
   ```

   Or via the web UI: `Settings → SSH and GPG keys → New SSH key → Key type: Signing Key`.

4. Verify locally:

   ```bash
   git commit --allow-empty -m "test: signing"
   git log --show-signature -1   # expect: Good "ssh" signature for ...
   ```

## Option B: GPG signing

1. Generate a key (skip if you have one):

   ```bash
   gpg --full-generate-key   # RSA 4096 or Ed25519, expiry 2y or none
   gpg --list-secret-keys --keyid-format long   # grab the long key ID
   ```

2. Configure git and upload the public key:

   ```bash
   git config --global user.signingkey <LONG_KEY_ID>
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   gpg --armor --export <LONG_KEY_ID> | gh gpg-key add -
   ```

3. Verify: `git commit --allow-empty -m "test" && git log --show-signature -1`.

## On GitHub

Every PR commit now shows a green **Verified** badge next to the author
name. Branch protection with `required_signatures: true` rejects any
push whose commits lack a verified signature.

If a commit shows "Unverified", check (in order):

- Public key was not added to GitHub.
- The key on disk does not match the one on GitHub.
- `git config --get commit.gpgsign` returns false.
- For SSH: key was added as Authentication-only, not Signing.

## Related

- [branch-protection.md](branch-protection.md) — server-side enforcement
  via the GitHub API (`required_signatures: true`).
