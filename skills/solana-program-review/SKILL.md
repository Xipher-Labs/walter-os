---
name: solana-program-review
description: Specialized review for Solana on-chain programs — Anchor framework, raw BPF, account constraints, signer/owner checks, CPI safety, PDA derivation, compute budget. Use this skill on any PR touching `programs/*` directories, `*.rs` files declaring `#[program]` or `entrypoint!`, Anchor account structs, or smart contracts handling funds. Critical for [Project B] and [Project A] where on-chain logic governs medical/procurement records.
---

# Solana Program Review

On-chain Solana code review. Different threat model than RPC code: bugs
ship to immutable contracts (or upgradeable but with auditable history),
exploits drain real funds, and you can't patch in production without
governance overhead.

## The big seven (most-exploited bug classes)

Every PR is reviewed against these. Any miss is BLOCKING.

### 1. Missing signer check

**The bug**: an instruction trusts that an account is signed without
asserting it. Attacker passes a different (unsigned) account; the program
treats it as authorized.

```rust
// BAD
pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
    // No check that ctx.accounts.authority is a signer!
    transfer_lamports(&ctx.accounts.vault, &ctx.accounts.recipient, amount)
}

// GOOD - Anchor
#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub vault: Account<'info, Vault>,
    pub authority: Signer<'info>,  // <-- Anchor enforces is_signer
    pub recipient: SystemAccount<'info>,
}
```

For raw BPF: explicit `if !account.is_signer { return Err(...); }`.

### 2. Missing owner check

**The bug**: program reads an account's data without checking that the
program owns it. Attacker passes an arbitrary account; deserialization
succeeds with attacker-controlled data.

```rust
// BAD - raw BPF
let vault = Vault::try_from_slice(&account.data.borrow())?;
// Account data could be ANYTHING the attacker put there.

// GOOD - Anchor handles via #[account(owner = crate::ID)]
#[derive(Accounts)]
pub struct UseVault<'info> {
    #[account(owner = crate::ID)]
    pub vault: Account<'info, Vault>,
}
```

### 3. Account discriminator skip (Anchor only)

**The bug**: deserializing as the wrong account type. Anchor's 8-byte
discriminator catches this — IF you use `Account<'info, T>` and not raw
`AccountInfo`. Manual deserialization without checking the discriminator
is a vulnerability.

### 4. Arithmetic overflow/underflow

**The bug**: `lamports + amount` overflows; balance check passes; funds
get drained or duplicated.

Solana programs don't panic on integer overflow by default in release
builds. Use `checked_add`, `checked_sub`, `checked_mul`, `checked_div`
everywhere money is involved.

```rust
// BAD
account.balance = account.balance + amount;

// GOOD
account.balance = account.balance
    .checked_add(amount)
    .ok_or(ErrorCode::Overflow)?;
```

Or in Cargo.toml:

```toml
[profile.release]
overflow-checks = true  # protects against this even with raw +/-
```

But still prefer explicit `checked_*` in financial code — the intent is
clearer.

### 5. PDA seeds collision

**The bug**: two different logical accounts derive to the same PDA address
because seed inputs aren't tightly constrained. Account substitution
becomes possible.

- Seeds always include a discriminator byte or string when there could be
  ambiguity (`b"vault"`, `b"escrow"`, etc.).
- User-controlled seed components (pubkeys, IDs) come AFTER the
  discriminator, not before.
- Document the seed schema in a comment above the PDA derivation.

### 6. Reentrancy via CPI

**The bug**: program A calls program B, which re-calls program A in a
state where invariants don't hold. Solana's runtime catches direct
reentrancy (program calling itself) but not indirect (A → B → A via a
shared dependency).

- Check program invariants are re-validated on entry, not just at
  initialization.
- Update state BEFORE making CPI calls (CEI pattern: Checks, Effects,
  Interactions).
- For sensitive instructions, document the trusted CPI targets.

### 7. Compute budget DoS

**The bug**: an instruction can be made to consume so much CU that it
fails. Attacker sends transactions that legit users can never get
processed.

- Bound iteration: any loop over a user-supplied list has a max length.
- Pagination for instructions that process bulk data.
- For user-supplied account lists in `remaining_accounts`, cap the
  count per instruction.
- Document worst-case CU per instruction in the spec.

## Anchor-specific

### Account constraints

Use Anchor's constraint attributes liberally:

```rust
#[derive(Accounts)]
pub struct ClaimReward<'info> {
    #[account(
        mut,
        seeds = [b"reward", user.key().as_ref()],
        bump = reward.bump,                    // bump stored & verified
        constraint = reward.user == user.key(),  // explicit pubkey match
        constraint = !reward.claimed @ ErrorCode::AlreadyClaimed,
    )]
    pub reward: Account<'info, Reward>,

    #[account(mut)]
    pub user: Signer<'info>,
}
```

Every constraint here prevents a specific attack. The reviewer checks each
account struct field has constraints sufficient for the threat model.

### `init` vs `init_if_needed`

- `init`: account must not exist. Use when uniqueness matters.
- `init_if_needed`: idempotent; risky if the existing account could be in
  a state the new init wouldn't initialize. Audit each use.

### `realloc`

Anchor `realloc` constraint changes account size. Check:
- Reallocation funded properly (lamports sufficient for new size).
- Existing data isn't truncated unexpectedly.
- Caller is authorized (it's a state-changing op).

### Errors

- Use `#[error_code]` enums. Custom error codes ≥ 6000 (Anchor reserves
  below).
- Every constraint that can fail has an `@ErrorCode::Specific` annotation.
- Generic "InvalidArgument" is a smell — be specific.

## Funds-handling code

For any code that moves SOL or SPL tokens:

- **Source authorization**: who must sign for this transfer? Documented
  and enforced.
- **Destination validation**: is there a check the destination is
  expected? Free-form recipient = potential drain.
- **Amount bounds**: zero allowed? Negative not possible (unsigned), but
  zero often is — is it intended?
- **Token mint checks**: SPL transfers, the mint is verified. Otherwise
  attacker can substitute a worthless token.
- **ATA derivation**: associated token accounts derive deterministically.
  Use `get_associated_token_address` consistently.
- **Token-2022 vs SPL Token**: different programs, different account
  layouts, different transfer semantics (transfer fees, hooks). Code that
  handles "tokens" generally must handle both or refuse one.

## Upgrade authority

For upgradeable programs:

- Document who has upgrade authority and the process to upgrade.
- Plan for upgrade authority revocation. Mainnet contracts holding real
  value should burn upgrade authority eventually OR move it to a multisig
  with public governance.
- For [Project B]: medical record contracts should have governance-style
  upgrades, not solo-key authority.

## [Project B]-specific (medical data on-chain)

Hard rules, no exceptions:

- **No raw PHI on-chain ever**. Hashes only. The on-chain contract stores
  Merkle roots, IPFS CIDs, encrypted blob references — not data.
- **Patient consent encoded on-chain**: explicit opt-in actions, with
  revocation path. Smart contract enforces revocation can't be silently
  ignored.
- **Encryption keys**: never on-chain. Key shares (Shamir, threshold
  encryption) may be referenced by hash but never stored.
- **Audit log**: every read of a patient record emits an event with the
  reader's pubkey. Patients can audit who accessed their records.
- **Argentine ley 26.529 alignment**: patient is the data owner. Contract
  enforces this even against the platform operator.

## [Project A]-specific (procurement on-chain)

- **Tender lifecycle as state machine**: clear states (draft, open,
  closed, awarded, cancelled) with allowed transitions. No "back to
  draft from awarded" type bugs.
- **Bid sealing**: bids are commitments (hash) until tender close, then
  reveal. Prevents price collusion.
- **Award immutability**: once awarded, an audit log is permanent. No
  "let me edit this entry".
- **Time as a constraint**: tender close times use slot, not Unix time.
  Slot drift is real but bounded; off-chain clock manipulation is not a
  concern with slot-based timing.

## Tooling

- `cargo build-sbf` to confirm compilation
- `solana-test-validator` + integration tests
- `anchor test` for end-to-end with TypeScript client
- `solana-program-test` for unit-test-style program tests
- Audit tools: `sec3`, `kudelski`, `OtterSec` reports — read for patterns
  even when not using their service

## What this skill does NOT cover

- Off-chain RPC client code. Use `solana-rpc-review`.
- Token economics design (use a separate economics-review skill or human
  expert).
- Frontend / wallet integration code. Standard web review applies.

## References

- Solana Cookbook security section
- Anchor book chapter on security
- Sealevel attacks list (community-maintained)
- Past audit reports from sec3, OtterSec, Kudelski for patterns
