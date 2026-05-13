# SPEC: Walter homelab topology — 4-node architecture + LiteLLM routing

**Status:** Draft (2026-05-06).
**Scope:** Optional advanced homelab profile for adding local GPU/LLM backends
and syncing them with the hosted Walter-VM control plane.
**Related:** `docs/specs/archive/local-llm-node.md` (standby homelab node role), `docs/specs/multi-agent-autonomy.md` §6 (subscription pool on M2), `docs/specs/secrets-runtime-architecture.md` (cross-device secrets).

---

## 1. The four nodes — what each one is for

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  WALTER-VM    Hetzner CX53 · public-internet hub                │
│  ──────────                                                      │
│  Plane · Forgejo · Infisical · LiteLLM (router) · Synapse ·     │
│  Headscale · Syncthing · OpenClaw · 6 agent workers             │
│  → cloud, static IP, CF Tunnel, always-up                       │
│                                                                  │
└──────────┬──────────────────────────────────────────────────────┘
           │  Tailscale via Headscale (mesh, encrypted)
           │  Home site ↔ cloud region: latency varies
           ▼
═══════════════════ HOME LAN (sub-millisecond) ════════════════════
   ┌─────────────────────┐                ┌─────────────────────┐
   │  M2 STUDIO (32 GB)  │                │  standby homelab node (256 GB)      │
   │  macOS Apple Silicon│                │  Linux + Proxmox VE │
   │                     │                │                     │
   │  • 7× CCR proxies   │                │  • HomeAssistant    │
   │    (subscription    │                │  • Jarvis (HA Conv) │
   │    pool — Pro/Plus) │                │  • Whisper / Piper  │
   │  • Small Ollama     │                │  • Restic primary   │
   │    (7-13B models    │                │  • Syncthing client │
   │    when laptop on)  │                │  • Dev VMs / LXCs   │
   │  • Mac-side coder   │                │  • Ollama (CPU,     │
   │    agent (worktrees)│                │    24/7 light load) │
   │                     │                │                     │
   │  ~30 W idle         │                │  ~150-200 W idle    │
   └─────────┬───────────┘                └────────┬────────────┘
             │                                     │
             └──────────── home switch ────────────┘
                              │
                              ▼
             ┌────────────────────────────────────────┐
             │  Z440 (workstation, GPU box)           │
             │  Linux + Ubuntu/Debian + vLLM          │
             │                                        │
             │  • 2× RTX 3090 (48 GB VRAM total)      │
             │  • vLLM with tensor parallelism        │
             │  • Heavy LLM inference (Llama-70B-4bit │
             │    real-time, embeddings, Qwen-Coder)  │
             │  • SDXL / Stable Diffusion (vision)    │
             │  • on-demand: spin up for workloads    │
             │                                        │
             │  ~150 W idle (GPUs sleep) → 700 W load │
             └────────────────────────────────────────┘
```

**Non-substitution principle**: each node does something the others **can't**:

| Node | What it can do that no other can |
|---|---|
| Walter-VM | Internet-facing static IP. CF Access. Cross-device hub. Survives local-site power outage. |
| M2 Studio | Anthropic Pro / ChatGPT Plus auth (locked to macOS binary + Keychain). |
| standby homelab node | 24/7 light-compute Linux, ZFS, IoT integration via HA, easy LXC sandboxing. |
| Z440 | 48 GB VRAM, real-time 70B inference, vision/multimodal at speed. |

Lose any one → degraded slice, not total failure.

---

## 2. The "load balancer" question — already solved

> **You don't need a separate load balancer. LiteLLM already does this.**

LiteLLM (deployed on walter-vm at `llm.${WALTER_DOMAIN}`) is a model gateway with built-in:

- Multi-backend routing (round-robin, weighted, priority, latency-based).
- Per-model fallback chains (when backend X fails, try Y, then Z).
- Per-virtual-key budget caps + per-key allowed-models scoping.
- Health checks (auto-removes unhealthy backends from rotation).
- Request retries with exponential backoff.
- Token accounting + spend telemetry.
- Optional Redis cache for response deduplication.

For our 4-node setup, the LiteLLM `model_list` becomes a **declarative routing policy**:

```yaml
# Conceptual — actual config in setup/vm/services/litellm/config.yaml
model_list:

  # ====================================================
  # SUBSCRIPTION pools (M2 Studio — auth-locked there)
  # ====================================================
  - model_name: anthropic-pool
    litellm_params:
      model: openai/anthropic
      api_base: http://m2-studio.tailnet.ts.net:3461  # ccr-1
      api_key: ${CCR_INTERNAL_APIKEY}
  - model_name: anthropic-pool        # round-robin sibling
    litellm_params:
      api_base: http://m2-studio.tailnet.ts.net:3462  # ccr-2
      ...

  - model_name: gpt-pool
    litellm_params:
      api_base: http://m2-studio.tailnet.ts.net:3471
    # ... ccr-4, ccr-5, ccr-6

  # ====================================================
  # LOCAL GPU pool (Z440 — fast inference, on-demand)
  # ====================================================
  - model_name: local-fast
    litellm_params:
      model: ollama_chat/llama3.3:70b   # served by vLLM OpenAI-compat endpoint
      api_base: http://z440.tailnet.ts.net:8000
      timeout: 30      # 70B is 5-10 tok/s, requests respond in <30s for typical chat

  - model_name: local-coder
    litellm_params:
      model: ollama_chat/qwen2.5-coder:32b
      api_base: http://z440.tailnet.ts.net:8000

  # ====================================================
  # LOCAL CPU pool (standby homelab node — always-on, light loads)
  # ====================================================
  - model_name: local-bg
    litellm_params:
      model: ollama_chat/llama3.2:3b    # tiny, CPU is fine
      api_base: http://standby-node.tailnet.ts.net:11434

  - model_name: local-embed
    litellm_params:
      model: ollama_chat/nomic-embed-text
      api_base: http://standby-node.tailnet.ts.net:11434

  # ====================================================
  # API FALLBACK (Anthropic / OpenAI direct — paid)
  # ====================================================
  - model_name: api-fallback
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: ${ANTHROPIC_API_KEY}

  # ====================================================
  # ROUTED ALIASES — what agents actually request
  # ====================================================
  # Agents call "sonnet" → LiteLLM tries pools in order:
  #   1. anthropic-pool (subscription, free)
  #   2. local-fast     (Z440, no quota)
  #   3. api-fallback   (capped budget)

router_settings:
  routing_strategy: simple-shuffle  # or: latency-based-routing
  fallbacks:
    - sonnet:    [anthropic-pool, local-fast, api-fallback]
    - coder:     [local-coder, anthropic-pool, api-fallback]
    - embed:     [local-embed, api-fallback]
    - cheap:     [local-bg, anthropic-pool]    # never use API for cheap

  num_retries: 2
  timeout: 60
  cooldown_time: 60   # don't hammer a failed backend for 60s
  cache:
    type: redis
    host: redis.walter-vm.local
    port: 6379
    ttl: 3600   # cache identical prompts for 1h
```

**Routing policy** (per agent, derived from autonomy spec §6):

| Agent | Default model alias | Why |
|---|---|---|
| triage | `cheap` (local-bg) | classification, tiny |
| liaison | `cheap` | summarization, tiny |
| janitor | `cheap` | lint, audit |
| researcher | `sonnet` | needs reasoning + ingestion quality |
| reviewer | `sonnet` | security/perf judgment |
| coder | `coder` (Z440 first, then Anthropic) | code-completion-grade output |

**On compliance / context**:
- `context:work` → never use subscription pool (enterprise account billing required); routes directly to `api-fallback` with `ANTHROPIC_ENTERPRISE_KEY`.
- `context:medical` (PHI) → **only** routes to `local-*` backends. PHI never leaves the home LAN. LiteLLM enforces via virtual-key allowed-models.
- everything else → standard fallback chain.

---

## 3. Sync question — what to sync, what NOT to sync

### ❌ Don't sync model files

Each node pulls models independently from Ollama / HuggingFace registries. Why:

- Models are big (Llama 70B = 40GB; 405B = 230GB).
- Each node has different storage layout (standby homelab node ZFS, Z440 ext4, M2 APFS).
- Models DON'T change once pulled (immutable artifacts).
- Bandwidth: pulling once per node from registry is cheaper than syncing across nodes.

Exception: if you want a curated "blessed model set" version-pinned, store SHA256 + version in the wiki (`tools/ollama-models.md`) and re-pull on node setup. Don't sync the bytes.

### ✅ Already syncing (Syncthing — works as-is)

| What | Where | Notes |
|---|---|---|
| `agent-memory/` | walter-vm hub ↔ M2 ↔ standby homelab node ↔ laptop | each device has full copy |
| `wiki/` (private) | same | follows operator across devices |
| `Documents/`, `Desktop/`, `Downloads/`, `personal/`, `obsidian-vault/` | same | personal data |

### ✅ GitOps (no sync needed — pull from walter-os repo)

| What | Where | How |
|---|---|---|
| `setup/vm/services/*/compose.yml` | every node | `git pull && docker compose up -d` |
| `hooks/`, `agents/`, `skills/`, `commands/` | every node | symlinked via install.sh |
| LiteLLM `config.yaml` | walter-vm only | versioned in repo |
| local LLM node ansible playbooks | applied from operator workstation via SSH | walter-os repo |

### ✅ Centralized (single source of truth — read on demand)

| What | Where | How accessed |
|---|---|---|
| Operator secrets | Infisical (walter-vm) | `walter_secrets_load` runtime fetch |
| Issue queue / state | Plane (walter-vm) | API |
| LLM response cache | Redis (walter-vm, NEW for §2) | LiteLLM auto |
| Audit log | walter-vm + Syncthing replication | append-only JSONL |

### 🆕 New addition needed: Redis cache on Walter-VM

Today LiteLLM has no shared cache. With 4-node + agent council, requests duplicate. Add Redis as a LiteLLM caching backend:

```yaml
# setup/vm/services/litellm/compose.yml — add a Redis service
services:
  redis-cache:
    image: redis:7-alpine
    container_name: litellm-cache
    restart: unless-stopped
    networks: [litellm_default]
    volumes:
      - redis_cache:/data
```

LiteLLM picks it up via `cache.type: redis` in config. Hits = free repeated answers.

---

## 4. Hardware sizing — Z440 specifics

The standby homelab node spec covers standby homelab node. Adding Z440:

| Spec | Value | Notes |
|---|---|---|
| Chassis | HP Z440 workstation | accepts 1× Xeon E5-2600 v3/v4 |
| CPU | 1× Xeon (operator picks; E5-2680v4 fine, or v3 cheaper) | single-socket |
| RAM | 64-128 GB DDR4 ECC | 64 GB enough; 128 GB if running multiple models concurrent |
| GPU | **2× RTX 3090** (24 GB each = 48 GB total) | NVLink bridge optional |
| PSU | **upgrade to 1200 W** | stock 700 W will brown out under dual-3090 load |
| Storage | 2× 2 TB NVMe (one OS, one model cache) | LLM models 40-200 GB each; SSD speeds matter for cold load |
| OS | Ubuntu 22.04 LTS Server | best NVIDIA driver path; CUDA 12.x |
| Inference engine | **vLLM** (not Ollama) | tensor parallelism across 2 GPUs; Ollama uses 1 GPU per model and is slower |
| Idle power | ~150 W | 3090 sleeps low |
| Load power | ~700 W | both GPUs at full TDP |
| Headscale agent | yes — same mesh as standby homelab node/M2 | LAN to standby homelab node/M2, WAN to walter-vm |

**vLLM > Ollama for Z440** because:
- vLLM serves OpenAI-compatible API natively → drops into LiteLLM config.
- Tensor parallelism across `--tensor-parallel-size 2` actually uses both GPUs for one big model.
- Continuous batching (multiple requests in flight) → higher throughput.
- Quantization (AWQ, GPTQ, INT4) supported natively.
- Ollama is great for "set and forget", but for 2× 3090 + heavy use, vLLM wins on perf.

**What models fit (4-bit quantization, 48 GB VRAM)**:

| Model | Quant | VRAM use | Headroom |
|---|---|---|---|
| Llama 3.3 70B | AWQ-INT4 | ~40 GB | tight; can run with `--max-model-len 8192` |
| Qwen 2.5 72B | INT4 | ~38 GB | OK |
| Qwen 2.5-Coder 32B | FP16 | ~64 GB | NO — use AWQ → ~20 GB ✓ |
| DeepSeek-V3 671B (MoE) | INT4 | ~150 GB | NO — way too big |
| Llama 3.1 405B | INT4 | ~230 GB | NO |
| **Multiple smaller concurrent**: Coder-32B-AWQ + Llama-8B + Whisper + nomic-embed | mixed | ~35 GB | YES — best mode for daily use |

**Recommendation**: run 2 servers concurrent on Z440:
- vLLM tenant 1: `qwen2.5-coder:32b` (AWQ) on GPU 0 — for `coder` agent
- vLLM tenant 2: `llama3.3:70b-instruct` (AWQ, tensor-parallel 2) when needed — but takes BOTH GPUs

Switch dynamically: HA Conv prompts → 70B for general; coder requests → 32B-coder. Operator can manage with systemd unit + LiteLLM health checks.

---

## 5. Network + DNS

Headscale already meshes everything. With 4 nodes:

| Node | Tailnet hostname | Purpose |
|---|---|---|
| Walter-VM | `walter-vm.tailnet.ts.net` | services hub |
| M2 Studio | `m2-studio.tailnet.ts.net` | subscription proxies |
| standby homelab node | `standby-node.tailnet.ts.net` | Proxmox + HA + Ollama-CPU |
| Z440 | `z440.tailnet.ts.net` | vLLM heavy GPU |

LiteLLM config uses these hostnames directly. **No public exposure of M2/standby homelab node/Z440** — they're mesh-internal only.

**LAN vs WAN**:
- Walter-VM → standby homelab node/Z440/M2: WAN (latency depends on home and cloud regions)
- standby homelab node ↔ Z440 ↔ M2: LAN (sub-1ms)

This means:
- Agents running on walter-vm calling Z440 vLLM = 150ms RTT per call. Fine for chat (< 1% of total response time).
- Agent CODER running on operator workstation calling Z440 = LAN fast. Better.
- Voice (Jarvis) on standby homelab node calling Z440 vLLM = LAN. <1ms RTT, <100ms total response.

**Topology decision**: agents don't move. Walter-VM still hosts triage/researcher/reviewer/janitor/liaison; the operator workstation hosts coder. Z440/standby homelab node/M2 are MODEL BACKENDS only. Walter-VM is the orchestration plane.

---

## 6. Phase plan (Z440)

Build on top of standby homelab node phases. Z440 is independent — can be added before, during, or after standby homelab node rollout.

| Phase | Output | Time |
|---|---|---|
| **Z1 Hardware** | Z440 + 2× 3090 + 1200W PSU + 64-128GB RAM + NVMe storage | (operator-driven, depends on parts) |
| **Z2 OS + drivers** | Ubuntu 22.04 LTS + NVIDIA 550+ driver + CUDA 12.4 + Tailscale agent | ~half day |
| **Z3 vLLM + first model** | vLLM serving Qwen-Coder-32B AWQ; OpenAI-compat API on `:8000`; bench: ~80-100 tok/s | ~2 hours |
| **Z4 LiteLLM integration** | walter-vm LiteLLM routes `coder` + `local-fast` to Z440; verified via curl + agent test | ~1 hour |
| **Z5 Multi-tenant** | Two vLLM systemd units (coder-32B + llama-70B-on-demand); LiteLLM uses both | ~2 hours |
| **Z6 Redis cache** | LiteLLM caching backend → repeated agent prompts hit cache | ~30 min |

Total active work: ~1 day after parts arrive. Operator-decision points: which models, which quantization.

---

## 7. Cost tracking (4 nodes)

| Cost type | Walter-VM | M2 Studio | standby homelab node | Z440 | Total |
|---|---|---|---|---|---|
| Hardware (one-time) | n/a | ~€2500 | ~€600-800 used | ~€1500-2500 (chassis + 2× used 3090) | ~€5000 |
| Power /year | n/a | ~€50 | ~€300 | ~€300-450 | ~€650-800 |
| Cloud (Hetzner) | ~€25/mo | n/a | n/a | n/a | ~€300/yr |
| LLM API (subscription baseline) | n/a | ~$80/mo (operator's existing 4 personal subs) | n/a | n/a | already-paid |
| LLM API (fallback when pools exhaust) | est ~$5-20/mo | — | — | — | ~$60-240/yr |

**Annual run rate**: ~€1300-1500/year operational (electricity + Hetzner + API fallback). One-time ~€5000.

**Equivalent cloud GPU rental** for 24/7 access to similar perf: ~$1000-1500/month. Homelab pays for itself in **3-5 months of heavy use**. Plus ownership + privacy + zero egress fees.

---

## 8. Open questions for operator

1. **Z440 PSU**: stock 700W will throttle 2× 3090 under load. Plan to upgrade to 1200W (or 1000W if undervolting GPUs). Decide before parts arrive.
2. **Used vs new 3090**: used 3090s are €700-900 each on local market; new 4090 is €1800. 4090 is 30-50% faster but 2× cost; 3090 NVLink-able. Operator's call (recommend used 3090 — better $/perf).
3. **NVLink bridge**: ~€200-300 used. Helps tensor-parallel inference for very large models. NOT needed for 70B with `--tensor-parallel-size 2` over PCIe (works fine). Skip unless going for 100B+ models.
4. **Z440 always-on or wake-on-demand**: 150W idle × 24/7 = ~€220/yr just to be reachable. Operator can wake-on-LAN from standby homelab node when needed; add ~5s latency. Decide based on usage pattern.
5. **vLLM tenant count**: 1 (one big model) or 2 (smaller concurrent)? Tradeoff: 1 big = better quality on hard tasks; 2 small = better latency on common tasks. Recommend **2** for daily use.
6. **Sync strategy for "blessed model set"**: store list in `wiki/tools/ollama-models.md` + setup script that pulls them. Per-node `ollama pull <list>`. Or skip — pull on demand.

---

## 9. Acceptance criteria

- [ ] 4 nodes visible in Headscale: `walter-vm`, `m2-studio`, `standby-node`, `z440`. All reachable from each other via tailnet hostname.
- [ ] LiteLLM config has all 4 backend categories (subscription pool, local-fast Z440, local-bg standby homelab node, api-fallback) with fallback chains.
- [ ] `curl litellm/v1/chat/completions -d '{"model":"sonnet","messages":[...]}'` succeeds with response from anthropic-pool (M2) when subscriptions have quota; transparently falls back to Z440 when pool exhausts.
- [ ] `coder` agent run-once on a `context:projects-personal` issue uses Z440 (`local-coder`). Latency < 5s for typical 200-token completion.
- [ ] `context:medical` issue routes EXCLUSIVELY to local backends (Z440 + standby homelab node), never reaches Anthropic/OpenAI. Verified via LiteLLM access logs.
- [ ] Redis cache hit-rate > 20% after a week of agent activity (measured via Redis MONITOR + LiteLLM telemetry).
- [ ] DR: kill any one node → degraded but functional system. Documented in DR runbook.
- [ ] Annual electricity cost ≤ €800 measured (4 nodes combined, excluding M2 portable laptop).

---

## 10. What this is NOT

- ❌ Not a replacement for Walter-VM. Cloud node stays — it's the public face + cross-device hub.
- ❌ Not a Kubernetes cluster. Each node is independent. Coordination via LiteLLM (model routing) + Plane (task queue) + Syncthing (data) + GitOps (config).
- ❌ Not a "high availability" setup in the enterprise sense. Single instance per node. Acceptable because: walter-vm = backup-able; M2/standby homelab node/Z440 = local-recoverable; degraded mode is well-defined per node.
- ❌ Not always-on for Z440. Wake-on-LAN saves ~€220/yr if usage is bursty.

---

## 11. Reference

- `docs/specs/archive/local-llm-node.md` — standby homelab node-specific (Phase L1-L4)
- `docs/specs/multi-agent-autonomy.md` §6 — subscription pool design (M2 only)
- vLLM docs: https://docs.vllm.ai/
- LiteLLM router config: https://docs.litellm.ai/docs/proxy/reliability
- Tailscale subnet routing: https://tailscale.com/kb/1019/subnets
