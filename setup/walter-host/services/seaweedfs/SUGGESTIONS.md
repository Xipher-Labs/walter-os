# SeaweedFS — Operator Customization Guide

## What ships by default

Single-node SeaweedFS 4.03 in `server` mode with S3 API enabled.
- `server -s3 -s3.port=8333 -dir=/data` — master + volume + filer + S3 in one process.
- Exposed on localhost only: S3 (8333), master (9333).
- No authentication by default (any access key / secret key pair accepted).

**Note on Caddy vhost**: SeaweedFS currently has no Caddy vhost on the
operator VM — it is accessed only from within the Docker network by PostHog.
To expose externally, add a Caddyfile block:
```
s3.${WALTER_DOMAIN} {
  reverse_proxy localhost:8333
}
```
Consider whether public S3 exposure is desirable before doing this.
<!-- TODO: add Caddy vhost when exposing externally; currently internal-only -->

## RAM / disk baseline

| Resource | Baseline | Notes |
|---|---|---|
| RAM (idle) | 300-500 MB | Master + volume server + filer |
| RAM (under load) | 500 MB - 1 GB | Depends on concurrent S3 ops |
| Disk (data) | grows with stored objects | Session recordings are the main driver |

## Common customizations

- **Enable S3 authentication** (recommended for external exposure):
  Create an IAM config JSON and pass it to the server:
  ```yaml
  command: server -s3 -s3.port=8333 -dir=/data -s3.config=/etc/weed/s3.json
  ```
  See: https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API

- **Separate master and volume servers** (for multi-node):
  Replace `server` mode with separate `master` and `volume` processes.
  For single-node hobby deploys, `server` mode is simpler.

- **Replication**: SeaweedFS supports volume replication for fault tolerance.
  In single-node, replication only protects against volume corruption, not
  host failure. For HA, use a dedicated backup strategy (restic or equivalent).

- **Bucket pre-provisioning**: PostHog expects a `posthog` bucket.
  The healthcheck (`s3.bucket.list | grep -q posthog`) enforces this.
  To pre-create: `echo 'volume.grow count=1' | weed shell` before starting PostHog.

## When to override

- **Storage > 200 GB**: Consider sharding into multiple volumes by adding
  a dedicated `volume` server. Or switch to external S3 (AWS, Hetzner Object Storage).
- **External access needed**: Add Caddy vhost + IAM config before exposing S3 publicly.
- **Replace with MinIO**: If you need S3 API compatibility + web UI + multi-bucket
  management, MinIO is a drop-in replacement. Update the `OBJECT_STORAGE_ENDPOINT`
  and `SESSION_RECORDING_V2_S3_ENDPOINT` env vars in PostHog's compose.

## Tradeoffs

- **SeaweedFS vs MinIO**: SeaweedFS is more storage-efficient (erasure coding).
  MinIO has a better web UI and is more widely deployed. For PostHog hobby, either
  works — the PostHog team tested both.
- **Single-node limitations**: SeaweedFS single-node has no automatic failover.
  A backup strategy (volume snapshots, restic) is essential.

## References

- SeaweedFS wiki: https://github.com/seaweedfs/seaweedfs/wiki
- PostHog session recording storage: https://posthog.com/docs/self-host/configure/recordings
- SeaweedFS S3 API: https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API
