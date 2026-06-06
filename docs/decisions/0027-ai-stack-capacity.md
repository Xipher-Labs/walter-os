# ADR-0027: AI-stack capacity baseline

**Status**: Accepted
**Date**: 2026-06-06
**Deciders**: Operator
**Part of**: issue #342, issue #350

## Context

The AI-stack resilience investigation had conflicting capacity assumptions:

- `walter-vm-watchdog.sh` treated Walter-VM as an 8 vCPU host and alerted when
  `load1m > 8.0`.
- Grafana alerting already used a 16 vCPU load threshold.
- Hosting guidance mixed core/dev sizing with production/full-stack sizing.

The operator confirmed the live Walter-VM has **16 vCPU / 30 GiB** available
(`nproc=16`). That makes the observed `load ~5` roughly 31% of CPU capacity,
so CPU saturation was not the primary trigger for the recent AI-stack
incidents. The incident focus stays on false-green healthchecks, model-map
drift, and missing recovery paths.

## Decision

Use **16 vCPU** as the production Walter-VM capacity baseline for bundled
alerting:

- `walter-vm-watchdog.sh` alerts when `load1m > 16.0`.
- Grafana's `walter_load_high` rule alerts when `node_load1 > 16`.
- Setup docs recommend CX53-class capacity for the full production stack and
  frame CPX41/CX43-class hosts as core/dev profile options.

No immediate CPU resize is required from the confirmed CPU data. Future resize
decisions should be driven by sustained CPU pressure near the 16-core ceiling,
memory pressure, disk growth, or service split/HA goals rather than the earlier
incorrect 8 vCPU assumption.

## Consequences

- Positive: watchdog and Grafana now agree on the live host's CPU threshold.
- Positive: load around 5 no longer produces misleading "CPU pinned" framing.
- Positive: future investigations have a recorded capacity baseline.
- Trade-off: forks running smaller hosts must intentionally adjust thresholds
  and capacity docs for their own deployment.

## Alternatives Considered

### Keep the 8 vCPU watchdog threshold

Rejected. It contradicts the confirmed live host and creates false CPU
saturation signals.

### Resize immediately

Rejected. The confirmed CPU capacity does not justify a CPU-driven resize.
Capacity work remains useful for resource limits and optional service splits,
but not as an emergency CPU fix.

### Make thresholds fully dynamic

Deferred. Dynamic threshold discovery is attractive, but Grafana provisioning
and shell watchdog behavior need a consistent, documented default first. A
future PR can add operator-configurable thresholds once #351 standardizes
resource limits across services.
