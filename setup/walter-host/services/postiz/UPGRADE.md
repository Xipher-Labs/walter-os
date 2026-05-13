# Postiz Upgrade Runbook

> AC-17: Postiz deployed version must be >= v2.21.7

## Check current version

```bash
docker inspect postiz | jq -r '.[0].Config.Image'
# Should output: ghcr.io/gitroomhq/postiz-app:v2.21.7 (or newer)
```

Or via HTTP:
```bash
curl -s http://localhost:5000/api/health | jq .version
```

## Upgrade steps

1. Check latest release: https://github.com/gitroomhq/postiz-app/releases

2. Update image tag in compose.yml:
   ```yaml
   image: ghcr.io/gitroomhq/postiz-app:v<NEW_VERSION>
   ```

3. Pull and restart:
   ```bash
   docker compose pull postiz
   docker compose up -d postiz
   ```

4. Verify:
   ```bash
   docker compose logs postiz --tail 50
   docker inspect postiz | jq -r '.[0].Config.Image'
   ```

5. Smoke test: open https://postiz.${WALTER_DOMAIN} and confirm login + scheduling works.

## Rollback

If upgrade breaks something:
```bash
docker compose down postiz
# Edit compose.yml back to previous version
docker compose up -d postiz
```

Data is persisted in `postiz_pg` volume — safe across upgrades.

## Refs

- Postiz releases: https://github.com/gitroomhq/postiz-app/releases
- Postiz docs: https://docs.postiz.com
- Phase V spec: docs/specs/devrel-analytics-stack.md (AC-17)
