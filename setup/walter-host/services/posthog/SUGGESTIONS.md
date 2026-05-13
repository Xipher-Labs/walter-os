# PostHog — Operator Customization Guide

## What ships by default

The hobby stack from `compose.yml` includes:
- PostHog web app + worker + plugin-server + asyncmigrationscheck
- ClickHouse (columnar store for events)
- Kafka + Zookeeper (event streaming)
- Redis 7 (job queue)
- Postgres 15 (session/user metadata)
- MinIO/objectstorage (uploads, feature flag payloads)
- SeaweedFS (session recording V2 storage)
- Temporal (workflow engine for async tasks)
- 8 Rust-based services: capture, recording-api, property-defs-rs, cymbal,
  personhog-replica, personhog-router, feature-flags, hypercache-server

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | 6-8 GB | ClickHouse is the heaviest (~2 GB); Kafka ~1 GB |
| RAM (under load) | 10-12 GB | Add 1-2 GB headroom for burst |
| Disk (event store) | ~10-20 GB/year | At ~1M events/month; ClickHouse compresses ~10:1 |
| Disk (session replay) | ~5-50 GB | Highly variable; disable if not needed |
| Disk (Docker images) | ~4-6 GB | All services pulled fresh |

Minimum host: 16 GB RAM, 160 GB SSD (Hetzner CX53 or equivalent).

## Common customizations

- **Disable session recording** (saves 2-4 GB RAM, significant disk):
  In PostHog project settings → "Session Recording" → disable. Frees
  SeaweedFS from heavy write load.

- **Disable Temporal** (saves ~1 GB RAM if you don't use batch exports):
  Comment out `temporal`, `temporal-admin-tools`, `temporal-ui`,
  `temporal-django-worker` services.

- **Tune ClickHouse memory** (default: uncapped):
  Add to clickhouse service environment:
  ```yaml
  CLICKHOUSE_MAX_SERVER_MEMORY_USAGE_TO_RAM_RATIO: "0.5"
  ```
  This limits ClickHouse to 50% of host RAM.

- **Reduce Kafka retention** (already set to 1 hour in compose.yml):
  For low-traffic installs, 1 hour is fine. For high-traffic, increase to
  24 hours to survive downstream outages.

- **Pin image digests** for reproducible deploys:
  Replace `POSTHOG_APP_TAG=master` with a concrete SHA digest.
  Get the current digest:
  ```bash
  docker pull ghcr.io/posthog/posthog:master
  docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/posthog/posthog
  ```

## When to override

- **>100M events/month**: ClickHouse needs dedicated shard configuration.
  Consider the managed PostHog Cloud at this scale — self-hosting becomes
  a significant ops burden.
- **>50 GB session recordings**: Add a dedicated SeaweedFS volume or switch
  to S3-compatible external storage. Set `SESSION_RECORDING_V2_S3_ENDPOINT`
  to your external store.
- **Multi-node**: PostHog hobby is single-node. Multi-node requires Kubernetes
  (PostHog has sunset Helm support; check their latest docs).
- **ARM host**: Most PostHog images are multi-arch except some Rust services.
  Check before deploying on ARM (e.g., Hetzner CAX series).

## Tradeoffs

- **Self-host vs Cloud**: PostHog Cloud handles infra; self-host gives full
  data sovereignty and no usage caps. At <1M events/month, cloud is often
  cheaper total cost of ownership.
- **Storage**: SeaweedFS is included for free but adds complexity. If you
  already run S3, point `OBJECT_STORAGE_ENDPOINT` there instead.
- **License**: PostHog OSS is MIT; the included features are comprehensive.
  Some features (group analytics, advanced cohorts) require a PostHog Cloud
  subscription or Enterprise license.

## References

- PostHog self-host docs: https://posthog.com/docs/self-host
- PostHog hobby deploy: https://posthog.com/docs/self-host/deploy/hobby
- ClickHouse tuning: https://clickhouse.com/docs/en/operations/server-configuration-parameters/settings
- SeaweedFS session recording: https://posthog.com/docs/self-host/configure/recordings
