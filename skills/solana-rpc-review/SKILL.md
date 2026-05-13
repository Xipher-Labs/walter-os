---
name: solana-rpc-review
description: Specialized review for Solana RPC infrastructure code — Yellowstone gRPC streaming plugins, Geyser plugins, Old Faithful (historical access), Dragon's Mouth subscriptions, RPC method handlers. Use this skill on any PR or diff that touches RPC handlers, gRPC streaming code, Geyser plugin code, account/transaction streaming, or anything in [Company]'s hot path. Catches concurrency bugs, allocation in hot paths, missing backpressure, account-size mistakes, compute budget violations, and stake-weighted QoS misconfiguration.
---

# Solana RPC Review

Review skill for the specific class of code [Company] ships: RPC infrastructure
serving 100k+ msg/sec to trading firms, indexers, and oracles. Different
review priorities than typical web code — latency at p99 matters more than
features, and a 2ms regression in the hot path is a blocker.

## Hot path discipline

Any code in the request/message handling path is "hot". For these paths:

### Allocations

- **Zero allocations per message** is the goal in steady state. Reuse
  buffers, use object pools, prefer `&[u8]` over `Vec<u8>` when not consumed.
- Look for: `format!`, `to_string()`, `clone()`, `Vec::new()` inside loops,
  `Box::new()`, lazy `String` concatenation. All suspect.
- Profile with `dhat`, `heaptrack`, or `cargo flamegraph` before claiming
  perf is fine.
- Strings: prefer `&str` over `String`, `Cow<'_, str>` when sometimes-owned.
- Numbers in messages: use `Bytes` from `bytes` crate for zero-copy slicing.

### Locks and contention

- `Mutex`/`RwLock` in the hot path = stop and justify. Use `parking_lot`
  variants (faster) or `arc-swap`/`atomic` types for read-heavy state.
- `tokio::sync::Mutex` is async-aware but slower than `parking_lot::Mutex`
  for short critical sections. Use the right one.
- Sharded locks (`DashMap`) often beat `Arc<RwLock<HashMap>>` when contention
  is real. But profile, don't guess.
- Check for accidental serialization: futures awaiting a global resource
  serialize concurrent requests.

### Async correctness

- **Never block the runtime**. `std::fs::*`, `std::sync::Mutex`,
  `std::thread::sleep`, blocking C library calls — all bad on tokio.
- Use `tokio::task::spawn_blocking` for unavoidable blocking work.
- Channels: `tokio::sync::mpsc` for async senders, `crossbeam` for sync.
  Bounded by default — unbounded channels eat memory under backpressure.
- `select!` macro: cancellation-safe branches only. If a future isn't
  cancellation-safe and gets dropped mid-work, you'll lose state.
- `Stream` adapters: `buffered(N)`/`buffer_unordered(N)` for parallelism,
  but cap N — unbounded parallelism collapses under load.

### Backpressure

- Every channel is bounded. Document the bound and the failure mode (drop
  oldest, drop newest, block sender, return error to client).
- gRPC streaming: server-side, when client is slow, what happens? You
  should see `tonic` flow control engaging or explicit `try_send` with
  drop-on-full. Never silently buffer 10GB.
- Yellowstone subscribers may be slow. Code should detect lag (track
  send/ack lag in metrics) and either drop messages with a "lagged"
  signal or disconnect the consumer.

## Geyser plugin specifics

Geyser plugins run inside the validator. Plugin crashes are validator-level
events. Therefore:

- **Panic boundaries**: every plugin entry point (`update_account`,
  `notify_transaction`, etc.) wraps work in `catch_unwind`. Panics get
  logged with full context and the plugin returns gracefully — never
  unwinding into validator code.
- **No long blocking work in callbacks**. The validator calls these on its
  hot path. Hand off to a background task and acknowledge fast.
- **Bounded queues** between plugin callbacks and async workers. If the
  worker can't keep up, drop with metrics rather than blocking the
  validator.
- **No `unsafe` code without a SAFETY comment**. Solana validator codebase
  has been bitten by plugin UB before.
- **Memory budget**: plugins share the validator's process memory. A leak
  in your plugin OOMs the validator. Track plugin RSS in metrics.

## RPC method handlers

For new RPC methods or changes to existing ones:

- **Compute budget per method**: every account read, every PDA derivation,
  every signature check has a CU cost. Document the worst-case CU footprint
  in the spec.
- **Account discriminator validation**: before deserializing an Anchor
  account, check the 8-byte discriminator. Without it, you can deserialize
  the wrong account type and either crash or, worse, return wrong data.
- **Owner checks**: any account read must verify it's owned by the program
  you expect. Missing owner check = type confusion attack vector.
- **Rate limiting**: per-method, per-API-key. Methods that can fan out into
  multiple validator queries (`getProgramAccounts`, `getMultipleAccounts`)
  get tighter limits.
- **Pagination**: any method that can return >100 items must paginate.
  Maximums explicit, not "as much as fits".
- **Timeouts**: every downstream call (DB, validator, external service) has
  a per-call timeout. The handler has a total timeout. Document both.

## Dragon's Mouth gRPC subscriptions

Subscription code review priorities:

- **Filter validation**: subscription filters can be arbitrarily complex.
  Reject filters that would match >X% of slot traffic without a paid tier.
- **Per-subscriber buffer**: each gRPC stream has its own bounded outbound
  buffer. Slow subscriber = its own buffer fills = drop or disconnect.
  Never let one slow subscriber affect others.
- **Authentication**: subscription endpoints behind auth. Anonymous = rate
  limited to demo levels. Document the tiers in the spec.
- **Heartbeat / keepalive**: gRPC TCP connections die silently behind
  NAT/firewalls. Server-side keepalive enabled, client-side heartbeat
  expected.

## Solana-specific gotchas

- **Lamports vs SOL**: integer lamports in code, formatted SOL in user-
  facing output. Mixing causes off-by-1e9 errors.
- **Slot vs block height**: not the same thing. Skipped slots have no block.
  Code that assumes `slot == block_height` is wrong.
- **Epoch boundaries**: stake activations, leader schedule changes, and
  fee updates happen at epoch boundaries. State that depends on epoch must
  refresh.
- **Versioned vs legacy transactions**: handle both. Legacy is going away
  but slowly.
- **TX size**: 1232 bytes for legacy, slightly different for v0. Code that
  builds transactions checks size before submission.

## Output format

Use the `pr-review` skill's blocking/warn/nit format. Add a "perf risk"
dimension specific to this skill:

```
**[BLOCKING] [PERF] <one-liner>**

Where: `path/to/file.rs:42-58`
Hot path: yes / no
Cost estimate: <allocations per call / locks held / CU budget>
Why blocking: <impact on p99 latency or validator stability>
Fix: <specific change>
Profile: <attach flamegraph or `cargo bench` output>
```

## Tools

- `cargo flamegraph --bench <name>` for hot-path profiling
- `tokio-console` for runtime introspection
- `dhat` for allocation profiling
- `cargo bench` with criterion for microbenchmarks
- `tracing` with `RUST_LOG=info` for structured logs
- `loom` for concurrency model checking

## What this skill does NOT cover

- Solana program (on-chain) code. Use `solana-program-review` instead.
- Customer SDK ergonomics. That's the SDK team's review.
- Infrastructure/Ansible. Out of scope here.
- DevRel content. Different skills.
