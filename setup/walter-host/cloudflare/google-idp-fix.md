# Fix Google IdP for Cloudflare Access (one-click Google login)

The Google IdP that came pre-configured in this CF account had its OAuth
client deleted in Google Cloud Console (error: `deleted_client`).
Re-create the OAuth client and update CF Access.

## When to do this

Optional. Current setup uses **One-Time PIN to email** which works fine —
CF emails a 6-digit code to `${WALTER_ADMIN_EMAIL}`. Add Google IdP only if you
want one-click "Login with Google" experience.

## One-time setup (15 min)

### 1. Create OAuth 2.0 Client in Google Cloud Console

1. Open https://console.cloud.google.com
2. Pick (or create) a GCP project for `${WALTER_DOMAIN}` admin
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
4. Application type: **Web application**
5. Name: `Cloudflare Access — ${WALTER_DOMAIN}`
6. **Authorized redirect URIs**: add this exact URL:
   ```
   https://<your-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
   ```
   (Find `<your-team-name>` in CF dashboard → Zero Trust → Settings → General → Team domain)
7. Save. Copy the **Client ID** and **Client secret**.

### 2. Update CF Access Google IdP

Two options.

**Option A — via CF Dashboard** (easier):

1. https://one.dash.cloudflare.com → Settings → Authentication
2. Find the existing "Google" IdP (the broken one) → Edit
3. Paste new Client ID + Client secret
4. Save → Test (CF runs a smoke test)

**Option B — via API** (if you prefer):

```bash
source ~/.config/walter-os/secrets.env

curl -sS -X PUT \
  -H "X-Auth-Email: $CF_EMAIL" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/access/identity_providers/$CF_IDP_GOOGLE" \
  -d '{
    "name": "Google",
    "type": "google",
    "config": {
      "client_id": "YOUR_CLIENT_ID",
      "client_secret": "YOUR_CLIENT_SECRET"
    }
  }' | jq
```

### 3. Re-enable Google on Access apps

```bash
source ~/.config/walter-os/secrets.env
cd ~/Projects-Personal/walter-os
bash setup/walter-host/cloudflare/04-create-access.sh ${WALTER_DOMAIN} ${WALTER_DOMAIN} otp+google
```

The script idempotently updates each of the 8 Access apps to allow both
OTP and Google as login methods.

### 4. Test

Open `https://secrets.${WALTER_DOMAIN}` (incognito to avoid stale session).
Should now show two options: "Login with Google" + "Send code to email".

## Troubleshooting

- **"deleted_client" error**: OAuth client got deleted again in GCP.
  Don't auto-delete. Don't change the project owner without notice.
- **"redirect_uri_mismatch"**: the URI in Google Cloud Console doesn't
  match what CF sends. Check team domain hasn't changed.
- **Login works but no access**: Access app policy still requires
  `@${WALTER_DOMAIN}` email — make sure the Google account email matches.
