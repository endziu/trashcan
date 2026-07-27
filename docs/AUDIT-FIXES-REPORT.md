# Audit Fixes Report

**Source:** `AUDIT-REPORT.md` (2026-07-24), `STATIC-ANALYSIS.md` (2026-07-24), `TODO.md`.
**Date:** 2026-07-27
**Scope:** `src/7r45hc4n.sol`, `script/Deploy.s.sol`, `foundry.toml`, `test/7r45hc4n.t.sol`, `README.md`, `DESIGN.md`.

All 9 numbered audit findings and the actionable informational items are fixed, committed one-by-one directly to `main`, and verified by the full test suite (43 tests passing) after each change. Static analysis findings required no code changes (see `STATIC-ANALYSIS.md`) and are unaffected by this work except where noted.

## High priority

### AUDIT-1 — Cancun opcode dependency (bricked `burnERC20`/`name`/`warning` on pre-Cancun chains)

`bool transient _entered` replaced with plain `bool _entered` storage; `foundry.toml` `evm_version` changed from `cancun` to `paris`. Verified the deployed bytecode contains zero `TLOAD`/`TSTORE`/`MCOPY`/`PUSH0` opcodes by walking the compiled `deployedBytecode` instruction-by-instruction.

### AUDIT-2 — Unauthenticated `burnERC20` balance-delta window

Added `if (received > _amount) received = _amount;` after the balance-delta calculation. A token hook or rebase/reflection mechanic that inflates the contract's balance during the `transferFrom` window can no longer inflate the emitted `ERC20Deposited` amount past what the caller actually authorized.

## Medium priority

### AUDIT-3 — Re-verify zero pre-Shanghai/pre-Cancun opcodes

Re-verified as part of the AUDIT-1 fix: 0 `TLOAD`, 0 `TSTORE`, 0 `MCOPY`, 0 `PUSH0` in the deployed bytecode.

### AUDIT-4 — Nonce-based `CREATE`, no canonical cross-chain address

`script/Deploy.s.sol` rewritten to deploy through the canonical CREATE2 factory (`0x4e59b44847b379578588920cA78FbF26c0B4956C`, already live on 100+ chains) with a fixed `salt = bytes32(0)`, instead of a bare `new TrashCan()`. This gives TrashCan the same address on every chain the factory exists on, with no per-chain nonce bookkeeping and no address-squatting risk from nonce desync.

Verified end-to-end on a local anvil node:
- Deploy succeeded through the factory.
- The resulting address (`0xC669D215e704a33420f295FFd240aa1E9Cc82d69`) was independently recomputed from `keccak256(0xff ++ factory ++ salt ++ initcodeHash)` and matched exactly.
- Initcode hash: `0x009f864742bc6b903a2c1e9cbbb8d643f1c551fc5ccae68a3336021c1577e700`.

Salt, initcode hash, and deployed address are published in `README.md`, with a note that `solc_version`/`evm_version`/`optimizer_runs` must stay frozen or the address changes.

## Low priority

### AUDIT-5 — Negative-rebase tokens underflow-panic

`balanceAfter - balanceBefore` replaced with a saturating form: `balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0`. A token that shrinks the contract's existing balance during the call now hits the existing `require(received > 0, "nothing received")` instead of a bare `0x11` arithmetic-panic.

### AUDIT-6 — Contract-wide `nonReentrant` over-blocks legitimate nesting

Removed the `nonReentrant` modifier and the `_entered` flag entirely. AUDIT-2's clamp and AUDIT-5's saturation already bound every call's `received` to `[0, _amount]` regardless of nesting, so the guard was redundant — and it had been blocking legitimate same-tx nested burns of distinct tokens while masking the real revert reason as `"ERC20 transfer failed"`.

The test that previously asserted a revert on nested reentrant burns (`test_burnERC20_revertsOnReentrantBurnERC20`) was replaced with `test_burnERC20_nestedReentrantBurnDoesNotInflate`, which asserts the nested call completes and the sum of emitted `ERC20Deposited` amounts equals the actual total balance increase (no inflation).

### AUDIT-7 — Return-value check rejects valid tokens, decodes before its own `require`

`_safeTransferFrom` no longer decodes the call's return data. It now only checks `require(ok, "ERC20 transfer failed")` and relies on `burnERC20`'s own `received > 0` balance check as evidence of a real transfer — which is strictly stronger than a token's self-reported return value. This fixes hard-reverts (with no reason string) for tokens that return `false` on success (e.g. Tether Gold), a non-canonical 32-byte value, or 1–31 bytes of return data.

Added `MockERC20FalseOnSuccess` and `test_burnERC20_succeedsOnFalseReturnFromRealTransfer` to cover the Tether Gold-style case. Updated `test_burnERC20_revertsOnTransferFailure` to expect `"nothing received"` instead of the old decode-based revert, since a token that never actually moves balance now fails on the balance check rather than the (removed) decode.

### AUDIT-8 — Incorrect ERC1155 batch recovery NatSpec

Corrected the NatSpec on `onERC1155BatchReceived`: EIP-1155 permits `safeBatchTransferFrom` to emit only `TransferSingle` events (no `TransferBatch`), so a fully compliant token can invoke this hook while the "recover from `TransferBatch`" advice finds nothing. Also documented that `ERC1155BatchDeposited`'s fields are all indexed (zero data bytes), so two same-tx batch deposits from the same `(token, from)` pair are distinguishable only by log index.

### AUDIT-9 — Silent non-hook NFT burn paths undocumented

Documented, in both the contract's top-level NatSpec and `DESIGN.md`'s Known Limitations, that event receipts only exist for `burn()`/`receive`/`fallback` (ETH), `burnERC20` (ERC20), and the `safeTransferFrom`/`safeBatchTransferFrom` paths (ERC721/ERC1155). Plain ERC721 `transferFrom`, CryptoPunks-style transfers, and ERC-223 `tokenReceived` all destroy the asset via the catch-all `fallback()` with no corresponding event.

## Informational / docs only

Added to `DESIGN.md`'s Known Limitations and/or `README.md`'s Caveats:

- **`ERC20Deposited` is forgeable** — any contract can implement a custom `balanceOf` and call `burnERC20` on itself to emit an arbitrary receipt with nothing real destroyed. `burnERC20` is not an authenticity guarantee for unknown token addresses.
- **`operator` is discarded from all receiver hooks** — marketplace/operator-initiated burns lose the initiator's identity in the log; a `_safeMint(trashcan, id)` "provably burned at mint" pattern attributes to `address(0)`.
- **Blocklist/pause risk** — USDC/USDT-style tokens can blocklist the TrashCan address, permanently disabling `burnERC20` for that token with no workaround.
- **Blast gas-fee revenue** — on Blast, gas-fee revenue that accrues to the contract by default has no claim path and is permanently stuck, consistent with the non-withdrawable design.

Two informational items were left open (not mechanical fixes):

- **`returndatacopy` cap** — largely mooted by AUDIT-7, which already discards `_safeTransferFrom`'s return data rather than decoding it. Left unchecked in `TODO.md` since a residual bounded copy elsewhere was not independently re-audited.
- **Re-pinning solc to a "more seasoned" release** — no specific target version was identified by the audit; this needs a judgment call at a future date, not a mechanical fix.

## Verification

- Full test suite (`forge test`): 43 tests passing after every commit, including the 1000-run/500k-call invariant test (`invariant_balanceEqualsDeposited`).
- Deployed bytecode scanned instruction-by-instruction for banned opcodes (AUDIT-1/3).
- CREATE2 deployment (AUDIT-4) verified end-to-end on a local anvil node, with the resulting address independently recomputed and cross-checked.

## Commit log

One commit per fix, pushed directly to `main` (no feature branches, per project preference):

1. `fix(AUDIT-1)` — drop Cancun dependency, pin `evm_version=paris`
2. `fix(AUDIT-2)` — clamp `burnERC20` received amount
3. `fix(AUDIT-5)` — saturate balance delta at zero
4. `fix(AUDIT-6)` — remove `nonReentrant` guard
5. `fix(AUDIT-7)` — loosen `_safeTransferFrom` to rely on `ok`, not return data
6. `docs(AUDIT-8)` — fix ERC1155 batch recovery NatSpec
7. `docs(AUDIT-9)` — document receipt-only paths for NFT transfers
8. `fix(AUDIT-4)` — deploy via canonical CREATE2 factory, fixed salt
9. `docs` — informational caveats (forgeability, operator, blocklist, gas-fee)
10. `docs` — check off completed TODO items
