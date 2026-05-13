# SPEC: Local LLM Node (Archived)

**Status:** Draft (2026-05-06).
**Archive note:** retained as a generic worked example for an optional local
LLM / homelab node. The public core does not require this hardware.
**Related:**
- `docs/specs/homelab-topology.md` — **read this FIRST** for the 4-node big picture (standby homelab node + GPU inference node + M2 + walter-vm + LiteLLM routing)
- `docs/specs/multi-agent-autonomy.md` §6 (subscription pool — M2-only)
- existing `setup/local-llm-node.md` (now superseded by this spec)

---

## 1. Hardware profile

| Spec | Value | Notes |
|---|---|---|
| Chassis | rack or tower server | Mature used enterprise hardware is fine |
| CPU | multi-core x86_64 | Enough cores for background inference and utility VMs |
| RAM | 128-256 GB ECC | Headroom for LLM + VM workload |
| Storage | SSD pool | Size for local models, backups, and snapshots |
| Power | dual PSU (typical standby homelab node) | UPS recommended |
| Idle draw | ~150-200 W | ~€280-380/yr at AR rates |
| Load draw | ~400-600 W | LLM batches push toward upper end |
| Noise | 45-55 dB at idle (server fans) | put it in a closet/utility room with airflow |
| Thermal | ~2000 BTU/h at load | room may need ventilation |
| GPU | none documented | CPU-only LLM inference. Add GPU later if local voice assistant needs faster Whisper / vision. |

**ZFS layout recommendation** (4× 2 TB SSD):

| Layout | Usable | Failure tolerance | Recommendation |
|---|---|---|---|
| Stripe | 8 TB | 0 disks | ❌ never |
| Mirror (2× 2-disk) | 4 TB | 1 disk per mirror | OK if budget-tight |
| RAIDZ1 | 6 TB | 1 disk | OK |
| **RAIDZ2** | **4 TB** | **2 disks** | **✅ recommended** — SSD failures cluster temporally; 2-disk tolerance is the right safety margin |

---

## 2. Why three nodes (Walter-VM + M2 Studio + standby homelab node)

Each plays a non-substitutable role:

| Node | Role | Why it specifically |
|---|---|---|
| **Walter-VM** (Hetzner CX53, cloud) | Internet-facing services hub: Plane, Forgejo, Infisical, LiteLLM, Synapse, Headscale, Syncthing, OpenClaw, etc. | Static public IP via CF Tunnel. Always-up. Outside-in DNS. Independent of local-site power/network. |
| **macOS subscription host** (local, ARM) | Subscription pool: 7 CCR-style proxies, one per Anthropic/ChatGPT subscription | Native `claude` / `codex` binaries with macOS Keychain OAuth. **Cannot be replaced by Linux** — Anthropic Pro auth is locked to the macOS binary. |
| **standby homelab node** (local site, Linux, x86) | Heavy compute: HomeAssistant, local voice assistant, Ollama, Whisper, restic local target, dev VMs | 256 GB RAM (M2 maxes at 192 GB), 28 cores, easy GPU upgrade path, ZFS at the OS level, runs Linux containers natively. |

**Failure isolation**: each node going down degrades a slice of capability, not the whole stack:

- Walter-VM down → operator loses public Plane/Forgejo/etc, but local dev + M2 + standby homelab node keep working.
- M2 Studio down → subscription pool unavailable, agents fall back to API keys (capped budget).
- standby homelab node down → no local voice assistant, no HomeAssistant; everything else unaffected.

---

## 3. OS + virtualization choice

Three viable bases:

| Choice | Pros | Cons | Recommendation |
|---|---|---|---|
| **Proxmox VE 8** | Mature, free, web UI, full KVM + LXC, easy snapshots, ZFS first-class, runs HomeAssistant OS as a VM officially | Yet another OS to maintain; Debian-based but with custom kernel | ✅ **default** — best fit for "homelab with mixed services" |
| **Plain Debian + docker compose** | Simplest mental model; matches walter-vm pattern | No native VM story; HomeAssistant in docker is officially "supervised" mode = degraded | only if the operator prefers minimal-magic |
| **Talos Linux + k8s** | Proper k8s, immutable, GitOps-friendly | Steep learning curve; HomeAssistant doesn't fit cleanly; overkill for a single homelab node | ❌ not for v1 |

**Recommendation: Proxmox VE 8.x + ZFS RAIDZ2.**

VM/container layout:

```
Proxmox VE 8 (host)
├── ZFS pool 'tank' (RAIDZ2, 4 TB usable)
│   ├── tank/ha-os         → HomeAssistant OS (VM, 4 vCPU, 8 GB)
│   ├── tank/voice-agent   → voice assistant services (LXC, 16 vCPU, 64 GB)
│   ├── tank/llm           → Ollama / vLLM (LXC, 24 vCPU, 160 GB; rest of RAM)
│   ├── tank/restic-target → Restic local repository (LXC, 2 vCPU, 4 GB)
│   ├── tank/dev-sandbox   → spare LXC for ad-hoc experiments
│   └── tank/snapshots     → daily ZFS snapshots, 7 retained
└── Tailscale (host-level, joined to Headscale mesh)
```

Why LXC vs VM:
- **HomeAssistant** = VM (HA OS is shipped as a virtual appliance; supervised+docker is officially deprecated).
- Everything else = LXC (lower overhead, share kernel).

---

## 4. Service catalog (Phase L1 → L4)

### L1 — Foundation (~half day)

- Install Proxmox VE 8 from USB.
- Configure ZFS RAIDZ2 pool `tank`.
- Join Headscale mesh (Tailscale agent on Proxmox host).
- Enable LDAP/PAM SSH lockdown via `walter-os-style` hardening (steal from `setup/vm/bootstrap-vm.sh`).
- Initial restic-target LXC.

Acceptance: walter-vm can `ssh standby-node.<tailnet>.ts.net` and rsync into /tank/restic-target.

### L2 — HomeAssistant + IoT (~1 day)

- HomeAssistant OS in VM (via Proxmox community helper script).
- Wyoming protocol satellites: Whisper STT + Piper TTS in HA add-ons (HA's official Assist stack).
- Integrate operator's existing IoT (Zigbee dongle, smart plugs, lights, etc.).
- Expose UI through CF Tunnel: `home.${WALTER_DOMAIN}` (already taken by Homepage; consider `ha.${WALTER_DOMAIN}`).

Acceptance: voice command "lights on" via local microphone → HA acts within 1 s. No cloud round-trip.

### L3 — local voice assistant (local LLM agent) (~3 days)

- Ollama in LXC, with at least:
  - `llama3.3:70b` (general)
  - `qwen2.5-coder:32b` (code assist on PHI-tagged example medical app content)
  - `nomic-embed-text` (embeddings for wiki RAG fallback)
- Connect HomeAssistant's "Extended OpenAI Conversation" or "Ollama Conversation" integration → local voice assistant becomes a real voice assistant with tool-use.
- local voice assistant tool palette (custom HA actions):
  - `home.<x>.<action>` (HA-native)
  - `agents.run-once <agent> --issue <id>` → bridges to Walter Council
  - `walter wiki query <terms>` → reads from the operator's wiki via SSH-back-to-walter-vm
  - `infisical secrets get <key>` (read-only operator vault)
- Wake word: HA's local wake word detection (openWakeWord / Wyoming).

Acceptance: operator says "Hey Walter, what is pending in Plane today?" → response within 5 s, citing the actual issues.

### L4 — Pool extension + DR (~2 days)

- Restic primary repo at `/tank/restic-target`. Walter-VM cron sends nightly snapshots over Headscale (LAN-fast, no B2 egress for primary path).
- B2 stays as the offsite (per `docs/specs/walter-vm-ha.md` Tier 1). Two-tier backup: standby homelab node = fast restore, B2 = building-burns-down case.
- Optional: extend the subscription pool from M2 to standby homelab node by hosting **non-subscription** OpenAI-compatible models (Ollama serving OpenAI API) as a fallback when Anthropic + ChatGPT subscription quotas exhaust. Pure compute; no auth dance.

Acceptance: operator can `walter-os agents pause`, kill walter-vm, restore from standby homelab node restic, resume in <30 min.

---

## 5. Walter Council adjustments after standby homelab node lands

`docs/specs/multi-agent-autonomy.md` §6 says all subscription pool runs on M2. With standby homelab node added:

| Concern | Pre-standby homelab node design | Post-standby homelab node design |
|---|---|---|
| Subscription proxies | M2 only (7 containers) | M2 only (UNCHANGED — only macOS has the binaries) |
| Local LLM (Ollama) for PHI / example medical app | M2 (limited RAM, no GPU yet) | **standby homelab node** (256 GB lets you run 70B fp16; M2 can fall back) |
| Whisper STT for voice ingestion | M2 | **standby homelab node** (Wyoming Whisper as HA add-on) |
| Backup target for Restic | B2 only | standby homelab node primary + B2 secondary |
| HomeAssistant | not deployed | **standby homelab node** |
| local voice assistant (HA-driven channel) | not deployed | **standby homelab node** |
| `coder` agent worker | Mac portable | UNCHANGED |
| `researcher`, `triage`, `liaison`, `janitor`, `reviewer` | walter-vm | UNCHANGED |

**No agent code change needed for L1.** L3 introduces the voice-assistant channel feature: HA voice command → Plane issue → walter-vm router → standard Walter Council flow. The local voice assistant is not a new agent; it is a new trigger and a new channel for the existing `liaison` agent's outputs.

---

## 6. Operator action items (sequenced)

| # | Action | Time | Phase |
|---|---|---|---|
| 1 | Buy/source 4× 2 TB SSD (if not already) | – | pre-L1 |
| 2 | Install Proxmox VE 8 from USB; first-boot wizard | 30 min | L1 |
| 3 | Create ZFS RAIDZ2 pool `tank` | 5 min | L1 |
| 4 | Join Headscale mesh: install tailscale on Proxmox host | 10 min | L1 |
| 5 | Apply walter-vm-style bootstrap (UFW, fail2ban, unattended-upgrades, swap) | 30 min | L1 |
| 6 | Provision restic-target LXC | 15 min | L1 |
| 7 | Install HomeAssistant OS VM | 30 min | L2 |
| 8 | Move existing Zigbee/Z-wave dongle to standby homelab node (if migrating) | varies | L2 |
| 9 | Add Whisper / Piper add-ons | 15 min | L2 |
| 10 | Operator-test: voice command works end-to-end | 5 min | L2 |
| 11 | Provision Ollama LXC + pull models | 60 min (model download) | L3 |
| 12 | HA Ollama integration | 20 min | L3 |
| 13 | local voice assistant tool palette (HA scripts → walter-vm endpoints) | 4 h | L3 |
| 14 | Restic primary repo + cron | 30 min | L4 |
| 15 | DR drill: restore walter-vm from standby homelab node → empty CX53 | 60 min | L4 |

---

## 7. Constraints + caveats

- **Power cost is real.** ~€280-380/year at idle. Run the math against cloud equivalents — for the Ollama use case, a year of standby homelab node idle ≈ 6 months of a cloud GPU rental, but you OWN the hardware.
- **Noise.** 45-55 dB. Don't put it in your bedroom. Utility room / basement / garage with ventilation works.
- **Heat.** ~2000 BTU/h sustained. Closed closet WILL overheat. Open shelf or vented enclosure required.
- **No GPU yet.** Ollama on CPU works for 7B-13B fast, 32-70B usable but slow (5-15 tok/s). For real-time voice responses, plan a future GPU (single RTX 4070 / 4080 fits the standby homelab node with adapter cables; A4500 if you're feeling enterprise).
- **macOS-only auth stays on M2.** No way around this — Anthropic Pro / ChatGPT Plus require the official binaries with their respective Keychain/state. standby homelab node doesn't replace M2; it complements.
- **Single point of failure for HA.** When standby homelab node is down, lights stop responding to voice. Mitigation: HA's own offline mode (most automations work without the LLM); operator can fall back to phone app for direct control.
- **PHI rules unchanged.** Even with local Ollama on standby homelab node, example medical app PHI policy says "no external AI APIs". standby homelab node satisfies that — but the wiki/agent-memory must NEVER cross-contaminate (operator-owned vs walter-os-owned content stays separate, per `docs/specs/karpathy-llm-wiki-compliance.md`).

---

## 8. Phase plan summary

| Phase | Cost (operator-time) | Cost (€/mo) | Output |
|---|---|---|---|
| L1 Foundation | ~half day | +€25-30/mo electricity | standby homelab node on mesh, restic target online |
| L2 HomeAssistant + voice | ~1 day | +€0 | "Hey Walter, lights on" works locally |
| L3 local voice assistant (LLM-driven) | ~3 days | +€0 | Voice queries against Plane / wiki / Walter Council |
| L4 Pool ext + DR drill | ~2 days | +€0 | LAN-fast restic + tested DR runbook |

Total: ~6-7 working days, plus initial Proxmox install. Distributed over weekends is fine.

---

## 9. Acceptance criteria

- [ ] **L1**: `ssh standby-node.<tailnet>.ts.net` from operator Mac succeeds. ZFS pool `tank` showing 4 disks ONLINE in RAIDZ2. Restic target LXC reachable from walter-vm.
- [ ] **L2**: Local microphone → "lights on" → smart bulb responds within 1 second. No cloud roundtrip detectable in HA logs.
- [ ] **L3**: "Hey Walter, what is pending in Plane today?" → answer with real Plane issue titles, response in <5 s.
- [ ] **L3**: "Hey Walter, ingest the latest NEJM paper on biomarkers" → creates a Plane issue with `lane:research, context:medical` → researcher agent picks it up overnight → wiki gets the new pages.
- [ ] **L4**: DR drill: `walter-os agents pause`; pretend walter-vm is dead; restore latest snapshot from standby homelab node's restic-target to a fresh CX53; bring services back; resume agents. Total: < 30 min.
- [ ] Power consumption: idle ≤ 200 W, load ≤ 600 W. Annual electricity ≤ €400 measured.
- [ ] No PHI / example medical app content reaches Anthropic or OpenAI. Audit log review at end of L4.

---

## 10. Open questions for operator

1. **GPU now or later?** standby homelab node takes a single double-wide GPU with the right riser. RTX 4070 (~€600) makes Ollama 70B real-time. RTX 4080 (~€1000) for vision (Frigate). A4500 (€1500) for enterprise warranty. Recommend **deferring** until L3 reveals actual perf bottleneck.
2. **Where does the standby homelab node physically live?** Garage, utility room, basement, dedicated closet? Affects networking (PoE? wifi backhaul? wired ethernet to home router?).
3. **Existing HomeAssistant?** If you already run HA elsewhere, migration plan needed (snapshot export → import on Proxmox VM). If not, fresh install is simpler.
4. **Wake word.** Default "Hey Walter"? Operator-specific phrase to avoid the (now too common) "Hey Siri" / "Alexa" collision?
5. **PHI inference**: example medical app medical content gets routed to standby homelab node Ollama. Confirm: any specific Spanish-language medical model needed, or is `qwen2.5-coder:32b` + general-purpose `llama3.3:70b` enough for v1? (Spec says enough for v1; revisit at L3 acceptance.)
6. **Restic primary or both**: today walter-vm backs up to B2. With standby homelab node online, is standby homelab node the primary (faster restore) and B2 a secondary (offsite)? Or stay B2-only and treat standby homelab node as redundant? Recommend **standby homelab node primary, B2 secondary**.

---

## 11. Reference

- Existing draft `setup/local-llm-node.md` is now superseded by this spec. Will be replaced by a thin pointer in a follow-up cleanup PR.
- `docs/specs/multi-agent-autonomy.md` §6 (subscription pool, M2-only, unchanged).
- `docs/specs/walter-vm-ha.md` (Tier 1 backup design — standby homelab node makes Tier 1+ feasible).
- HomeAssistant Wyoming protocol: https://github.com/rhasspy/wyoming
- HA Ollama integration: https://www.home-assistant.io/integrations/ollama/
- Proxmox VE community helper scripts: https://community-scripts.github.io/ProxmoxVE/
