# Forgejo Actions runner

Optional self-hosted runner for Forgejo Actions on a Walter host. It is
disabled by default and only starts when the `forgejo-runner` Compose profile is
selected.

## Files

- `compose.yml` starts one pinned Forgejo runner container.
- `compose.docker-socket.yml` is an explicit high-risk overlay for Docker
  executor jobs.
- `.env.template` documents required local values. Copy it to `.env` and keep
  the registration token out of git.
- `config.yml.template` keeps runner state at `/data/.runner` inside the named
  Docker volume.

## Register one runner

1. In Forgejo, open the place where the runner should be allowed to execute
   jobs.
   - Instance runner: site administration, then Actions runners.
   - Organization runner: organization settings, then Actions runners.
   - Repository runner: repository settings, then Actions runners.
2. Create or copy a runner registration token.
3. Copy `.env.template` to `.env` and set:
   - `FORGEJO_INSTANCE_URL`, for example `https://git.${WALTER_DOMAIN}`.
   - `FORGEJO_RUNNER_REGISTRATION_TOKEN`, pasted from Forgejo. This is required
     only while `/data/.runner` is absent.
   - `FORGEJO_RUNNER_NAME`, one stable name for this host.
   - `FORGEJO_RUNNER_LABELS`, if the default label does not fit.
4. Start exactly one runner:

```bash
docker compose --profile forgejo-runner up -d
```

On first start, `forgejo-runner register --no-interactive` registers the runner
and creates `/data/.runner` in the `forgejo-runner-data` named volume. After
that, the container starts `forgejo-runner daemon`. Once `.runner` exists, the
container no longer needs `FORGEJO_RUNNER_REGISTRATION_TOKEN` at Compose
interpolation time or daemon startup.

## Labels

The default label is the official Docker executor form:

```text
docker:docker://node:20-bullseye
```

Use the label name, which is the left side before the colon, in workflow jobs:

```yaml
runs-on: docker
```

Add more labels only when you have a real isolation boundary or separate
runtime need. For a small team, one boring Docker label is easier to reason
about than a fleet of overlapping labels. Docker executor labels require a
Docker daemon. The default `compose.yml` does not mount the host Docker socket;
use the explicit overlay below if you accept that risk.

## State and credentials

Runner registration persists in the named Docker volume
`forgejo-runner-data`. The `.runner` file contains credential material for this
runner. Treat that volume like a secret:

- Do not commit `.runner`.
- Do not publish backups of the volume.
- If the host is compromised, delete the runner in Forgejo and recreate it with
  a fresh registration token.

The registration token in `.env` is only needed until the `.runner` file exists,
but it is still credential material while present. Remove it from `.env` after
the runner is registered if your operational flow allows it.

## Docker socket risk

The default profile does not mount the Docker socket. To opt in, run the
runner with the Docker socket overlay:

```bash
docker compose \
  -f compose.yml \
  -f compose.docker-socket.yml \
  --profile forgejo-runner-docker-socket \
  up -d
```

The overlay explicitly mounts:

```text
/var/run/docker.sock:/var/run/docker.sock
```

That mount is high-risk. A workflow that can access the Docker socket can often
control the host Docker daemon, including starting privileged containers or
mounting host paths. `no-new-privileges:true` is enabled for the runner
container, but it does not sandbox the Docker socket and must not be treated as
a containment boundary.

Small-team guidance:

- Run this only for repositories and contributors you trust.
- Prefer repository or organization runners over broad instance runners when
  you need tighter blast radius.
- Do not run unreviewed pull-request workflows from forks on this runner.
- Keep the runner at `capacity: 1` unless you have a clear queueing need and
  understand the extra host load.
