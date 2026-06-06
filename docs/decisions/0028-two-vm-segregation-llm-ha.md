# ADR-0028: Two-VM segregation + duplicated LLM path

**Status**: Proposed
**Date**: 2026-06-06
**Deciders**: Operator
**Relates**: ADR-0027 (AI-stack resilience), walter-os #342 epic, #351 (resource limits), #353 / config-personal #15 (critical-path split)

## Context

walter-vm ran ~30 containers on one 16 vCPU / 30 GiB box. On 2026-06-06,
live: **load average 98 on 16 cores (6× oversubscribed), swap 100% full**,
with `posthog-worker` at 224% CPU competing with `litellm` (175%) and
`gemini-sub-router` (205%). Under that contention **cloudflared itself was
CPU-starved → the Argo tunnel deregistered → the box "stopped responding"**,
taking the customer-facing LLM gateway down with the homelab (and removing the
SSH recovery path, which rides the same tunnel). This was reproduced live —
SSH dropped mid-session under load 98.

Root cause is two-layered (see ADR-0027 for the config/resilience half). The
half this ADR addresses: **the production-critical LLM path shares one box, with
no resource isolation, with ~30 non-critical homelab services** — so any one of
them (posthog above all) can starve the product into an outage.

## Decision

Move to **two VMs with service segregation, and duplicate the entire LLM path
(active on both)** so the customer AI gateway never shares fate with the
homelab. Every service gets a hard cgroup cap so no single one can starve a VM.

- **vm-core** — production-critical path (LLM **primary**) + light infra
  (infisical, observability server, headscale/wireguard, backups). Nothing
  heavy lands here.
- **vm-aux** — heavy / non-critical homelab (posthog, plane, n8n, metabase,
  synapse, penpot, postiz, forgejo, …) + the LLM **secondary** replica.
- **Duplicated (both VMs):** `litellm`, `litellm-db`, the 3 sub-routers
  (`chatgpt-codex`/`claude-sub`/`gemini-sub`), `llm-proxies`, plus each VM's own
  `cloudflared` + observability agents.
- **Single instance (vm-aux only):** `posthog` (the CPU hog) and the rest of
  the homelab.

### IaC — "easily identifiable" (operator requirement)

The single source of truth is **`ansible/service-placement.yml`**: a flat map of
`service → vms[] + duplicated + cpus + mem_limit + profile`. To move a service
or change a cap, edit one line there. `ansible/inventory.yml` declares the two
hosts (`vm_core`, `vm_aux` under `walter_vms`). The playbook iterates the map
and deploys each service only on its assigned host(s) with its caps. No service
placement is implicit or hand-managed on the box.

### LLM HA strategy

Active-active behind `llm.${WALTER_DOMAIN}`: both VMs run a full litellm stack;
the public ingress balances / fails over between `vm-core:4000` and
`vm-aux:4000` (cloudflared load-balancing, or a tiny Caddy/HAProxy in front).
Either VM dying leaves the AI pipeline serving from the other. `litellm-db` is
per-VM (each replica owns its own spend/key DB); the virtual-key definitions are
identical because both load the same `config.yaml`.

## Migration runbook (operator executes the money/provisioning steps)

The agent **cannot** provision (Hetzner = money + no hcloud token available).
Order:

1. **Operator — provision vm-aux** (Hetzner). The $50–80 dedicated/CPX option
   the operator floated fits here. Either restore the current VM's **snapshot**
   onto it (fast bootstrap — gets all services, then prune to vm-aux's set) or
   bootstrap clean via `setup/walter-host/bootstrap-vm.sh` + Ansible.
2. **Operator — wire cloudflared SSH** for vm-aux (`ssh-aux.${WALTER_DOMAIN}`)
   and set its `ansible_host` in `inventory.yml`.
3. **Agent — apply placement** via Ansible: `ansible-playbook walter-vm.yml`
   targets each host with only its assigned services + caps from the manifest.
   On vm-core this means **removing** the heavy services now living on vm-aux.
4. **Operator — point the LLM ingress** at both replicas (CF load-balancer or
   front proxy). Verify failover: stop litellm on one VM → gateway still serves.
5. Resource caps (#351) land in the same pass — `posthog` hard-capped so it can
   never reproduce the load-98 starvation.

## Consequences

- The product LLM path survives any homelab service (or whole vm-aux) dying.
- No single container can starve a VM → no more "stops responding".
- Cost: +1 VM (~$50–80/mo). Justified — the current single-box fate-sharing has
  already caused customer-facing outages.
- More surface to manage, but it's all declared in one manifest + Ansible.

## Open questions

- **litellm-db replication.** Stateless gateway use needs none (each replica
  self-contained). If per-key spend accounting must be unified, add logical
  replication or point both at one managed Postgres — decide before relying on
  cross-replica spend totals.
- **Ingress LB choice.** cloudflared load-balancing (no extra component) vs a
  Caddy/HAProxy front (more control, more to run). Pick at step 4.
- **vm-aux sizing.** posthog + plane + synapse are heavy; size vm-aux for them,
  not for the (light) secondary LLM replica.
