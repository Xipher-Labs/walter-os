# Langfuse optional profile

Langfuse is an opt-in LLM observability stack for traces, prompt runs, datasets, and evals. It is useful when Walter-OS agents or product experiments need durable visibility into model calls: what prompt ran, which model answered, token and latency shape, tool behavior, and whether eval scores are improving or regressing.

This profile is disabled by default. Start it only when you need LLM tracing or evaluation workflows:

```bash
cd setup/walter-host/services/langfuse
cp .env.template .env
$EDITOR .env
docker compose --profile langfuse up -d
```

The intended public route is:

```text
https://langfuse.${WALTER_DOMAIN}
```

Do not publish the datastore ports. Caddy should proxy the route to `langfuse-web:3000` on the Docker network; the compose file exposes no public host ports.

## Why optional

Langfuse is valuable for startup and small-team AI work because it gives a shared place to inspect traces, compare prompt versions, run evals, and debug regressions without reconstructing behavior from ad hoc logs. It helps answer practical questions: which agent path failed, which prompt change improved task quality, which model route is too expensive, and which customer workflow needs a stronger eval.

It is also a real storage and operations burden. The v3 self-host stack includes the Langfuse web app, a worker, Postgres, ClickHouse, Redis, and S3-compatible object storage. Traces can grow quickly, ClickHouse needs explicit backup planning, object storage retains event and media payloads, and Redis/Postgres credentials become part of the host secret set. For operators who only need the core Walter-OS services, keeping Langfuse off avoids unnecessary data retention, backup surface, memory use, and upgrade work.

## Data and backups

Back up all named volumes together so trace metadata, event payloads, and eval artifacts stay consistent:

```text
langfuse_postgres_data
langfuse_clickhouse_data
langfuse_clickhouse_logs
langfuse_redis_data
langfuse_minio_data
```

For a serious deployment, define retention before enabling wide tracing. Decide which traces may include customer data, how long eval datasets should live, and whether media uploads or batch exports are enabled. Restoring only Postgres without ClickHouse or object storage can leave the UI with missing trace events or broken attachments.

## Secrets

The compose file fails closed when required secrets are missing:

```text
NEXTAUTH_SECRET
SALT
ENCRYPTION_KEY
LANGFUSE_DB_PASSWORD
CLICKHOUSE_PASSWORD
REDIS_AUTH
MINIO_ROOT_PASSWORD
```

Generate secrets locally and keep them out of git. `ENCRYPTION_KEY` must be a 64-character hex string from `openssl rand -hex 32`; `NEXTAUTH_SECRET` and `SALT` should have at least 256 bits of entropy.
