# Security Audit — 7r45hc4n (TrashCan)

**Target:** `src/7r45hc4n.sol` @ `371f36f`
**Method:** 7 parallel specialist agents against the `evm-audit-*` checklists (general, precision-math, erc20, erc721, dos, access-control, chain-specific). Findings verified with scratch Foundry tests and live RPC probes; nothing in this repo was modified during the audit.
**Date:** 2026-07-24

## Verdict

The core design goal holds. The **ownerlessness / immutability / unrecoverability claim is verified true at the bytecode level** — the 3,725-byte runtime contains zero `SELFDESTRUCT`, `DELEGATECALL`, `CALLCODE`, `CREATE`, `CREATE2` or `SSTORE`, including in data regions, and `forge inspect storageLayout` returns an empty layout. There is no privileged path, no value-extraction primitive, and no way for the deployed code to ever change. No Critical findings.

The problems are elsewhere: **chain portability** (1 High) and **event integrity**, which matters unusually much here because events are the contract's only product.

| # | Severity | Finding |
|---|---|---|
| 1 | **High** | Cancun-only opcodes silently brick `burnERC20`, `name()`, `warning()` on pre-Cancun chains |
| 2 | **Medium** | `burnERC20` balance-delta window is unauthenticated — receipts inflatable with third-party tokens |
| 3 | **Medium** | `PUSH0` makes deployment fail outright on pre-Shanghai chains |
| 4 | **Medium** | Nonce-based `CREATE` — no canonical cross-chain address; squattable on undeployed chains |
| 5 | Low | Negative-rebase tokens underflow-panic, permanently bricking that token's burn path |
| 6 | Low | `nonReentrant` is contract-wide, over-blocking legitimate cross-token nesting |
| 7 | Low | Return-value check rejects false-on-success tokens and decodes before its own `require` |
| 8 | Low | ERC1155 batch recovery path documented incorrectly (spec permits `TransferSingle`) |
| 9 | Low | Non-hook NFT paths (`transferFrom`, punks, ERC-223) burn with no receipt, undocumented |
| — | Info | 6 further items, listed at the end |

---

## [1] HIGH — Cancun-only opcodes permanently brick `burnERC20`, `name()` and `warning()` on non-Cancun chains

**Location:** `src/7r45hc4n.sol:26` (`bool transient _entered`), `:179`, `:182-184`; `foundry.toml`
**Status:** CONFIRMED (independently by two agents, and re-verified directly)

The runtime emits `TSTORE`/`TLOAD` (EIP-1153, from the transient reentrancy flag) **and** `MCOPY` (EIP-5656, from the `string memory` return path of `name()`/`warning()` — emitted by the cancun pin regardless of the guard). Verified counts in the current artifact: 3 `TLOAD`, 2 `TSTORE`, 2 `MCOPY`, 120 `PUSH0`.

The failure shape is what makes this High. Pre-EOF EVMs do no deploy-time bytecode validation, and the constructor touches none of these opcodes. So on a pre-Cancun chain:

1. Deployment **succeeds** — status `0x1`, correct 3,725 bytes stored, source verification passes.
2. `receive`, `fallback`, `burn`, all three receiver hooks, `supportsInterface`, `is7r45hc4n` keep working.
3. `burnERC20()`, `name()`, `warning()` revert on **every** call, forever, consuming all supplied gas.

The contract is ownerless and non-upgradeable, so this is unfixable in place. Confirmed live on **Polygon zkEVM (1101), Taiko (167000), Metis (1088)** via `eth_call` opcode probes, each validated against an `INVALID` control so a failure is a real opcode rejection rather than an RPC quirk:

```
Polygon zkEVM: -32000: invalid opcode: TSTORE / invalid opcode: MCOPY
Taiko:         -32003: EVM error: NotActivated
```

End-to-end on `anvil --hardfork shanghai` with the real creation bytecode: deploy `status: 0x1`, then `burnERC20`/`name`/`warning` → `NotActivated`, everything else OK.

This directly negates the contract's stated reason to exist. Per the README, the justification over `0x...dEaD` is that a bare burn address *"will not emit events for what was burned, so off-chain indexers cannot reliably track burn activity."* On those three chains `burnERC20` is the only ERC20 path that emits `ERC20Deposited`; with it dead, ERC20 burning degrades to exactly the silent `0x...dEaD` behaviour.

**The existing test suite cannot catch this.** `forge test --evm-version <X>` gates compilation only, not the executor spec — etched `TSTORE`/`MCOPY` bytecode passes identically under `london`, `paris`, `shanghai` and `cancun`. Only a real pre-Cancun node or `anvil --hardfork` surfaces it.

**Recommendation:** drop the Cancun dependency. Replace `bool transient _entered` with plain storage (or remove the guard entirely — see [2] and [6]) and set `evm_version = "paris"`, which also clears `MCOPY` and `PUSH0`. **Verified:** a scratch build with `bool private _entered` + `evm_version = "paris"` compiles clean with zero `TSTORE`/`TLOAD`/`MCOPY`/`PUSH0`. Additionally: probe the target RPC before broadcasting (the README's current "check `to` is null and bytecode matches" check does not catch this, because deployment genuinely succeeds), and publish a supported-chains table.

## [2] MEDIUM — `burnERC20` balance-delta window is unauthenticated; receipts can be inflated with a third party's tokens

**Location:** `src/7r45hc4n.sol:82-86`
**Status:** CONFIRMED — independently, by three agents

`received = balanceOf(this)_after - balanceOf(this)_before` credits `msg.sender` with *every* token unit arriving at the contract during the `transferFrom` window, not with what `msg.sender` actually parted with. **The `nonReentrant` guard does not close this** — it blocks re-entry through `burnERC20`, but any other inflow landing inside the window is still counted.

Two confirmed vectors:

- **Hook-based injection (the sharp one).** An attacker's ERC777 `tokensToSend` / ERC-1363 callback fires inside `transferFrom` and pushes a victim's tokens into the can using any pre-existing allowance the attacker holds. PoC: attacker burns `1e18` of their own, drags `500e18` of a victim's, and the emitted receipt reads `ERC20Deposited(token, attacker, 501e18)`. A second agent reproduced this at `1000e18`. The victim's tokens are irreversibly destroyed and the attacker is named as the burner.
- **Accrual / reflection.** For aTokens, stETH-style index tokens or reflection tokens, the interaction revalues the can's *entire existing stack* inside the window and attributes the gain to the caller. PoC: can holds 1,000,000 units, Alice burns `100e18`, receipt emits ~100,100 units — a 1000x overstatement. This error scales with everything ever burned, since a sink's balance only grows.

The documented fee-on-transfer caveat covers only `received < requested`; nothing warns it can be arbitrarily *larger*, or that it can include tokens the sender never owned. Any off-chain system ranking or paying out on `ERC20Deposited.amount` is gameable.

**Recommendation:** clamp the credit so it can never exceed what the caller authorized:

```solidity
uint256 received = balanceAfter - balanceBefore;
if (received > _amount) received = _amount;
```

This preserves the fee-on-transfer property (`received <= _amount` always) while making the receipt un-inflatable. Note this **subsumes the reentrancy guard**: with the clamp in place the double-count the guard was added for cannot inflate a receipt either, so the guard — and with it finding [1]'s TSTORE dependency and finding [6] — can be removed.

## [3] MEDIUM — `PUSH0` makes deployment fail outright on pre-Shanghai chains

**Location:** `foundry.toml`; 124 `PUSH0` in creation bytecode, 4 in constructor code
**Status:** CONFIRMED

solc ≥0.8.20 defaults to Shanghai+ and emits `PUSH0`; because 4 land in constructor code, the creation transaction itself aborts. Confirmed against the real creation bytecode on **Kava EVM (2222)**: `invalid opcode: PUSH0`, with a passing control probe.

Materially less dangerous than [1] — it fails loudly at deploy time, leaving no half-working contract. Recorded separately because it sets the true portability floor: fixing [1] via `paris` fixes this too, whereas fixing [1] via `shanghai` would not.

## [4] MEDIUM — Nonce-based `CREATE`: no canonical cross-chain address, squattable on undeployed chains

**Location:** `script/Deploy.s.sol:9`
**Status:** CONFIRMED

`new TrashCan()` compiles to `CREATE`, so the address is `keccak256(rlp(deployerEOA, nonce))`. For a sink meant to be recognisable across many chains:

- The address differs per chain unless the deployer EOA is used exclusively for TrashCan with nonces kept in lockstep — one unrelated tx desynchronises it permanently.
- No counterfactual address: the project cannot publish "TrashCan is at 0xABC on every chain" ahead of deploying, nor let third parties permissionlessly complete the rollout.
- **Address squatting.** Users of a multi-chain sink copy the address across chains — that is the UX. On a chain where TrashCan is *not* deployed, plain ERC20 `transfer` and ETH sends land at a codeless address. If the deployer key is ever compromised over the contract's unbounded lifetime, the attacker replays the nonce there, deploys arbitrary code at the canonical address, and sweeps everything parked there and everything sent after. Docs and muscle memory still point at the "correct" address.

The canonical CREATE2 factory `0x4e59b44847b379578588920cA78FbF26c0B4956C` is already live with identical code on all 16 major chains checked, including zkSync Era and Polygon zkEVM — no new infrastructure needed.

Note: the metadata CBOR encodes `evmVersion`, so **the EVM pin changes the initcode hash and therefore any CREATE2 address** (cancun `c874b47c…` vs prague `f2fd2380…` vs osaka `c93a882f…`). Freeze `solc_version`, `evm_version` and `optimizer_runs` before publishing an address, and treat any change to those three as a new version.

## [5] LOW — Negative-rebase tokens underflow-panic, bricking that token's burn path

**Location:** `src/7r45hc4n.sol:84` · **Status:** CONFIRMED (three agents)

`balanceAfter - balanceBefore` assumes the can's balance never shrinks during the call. For AMPL-style negative rebase, supply-burning deflationary tokens, or reflection tokens diluting the can's share, the shrink of the accumulated stack can exceed the incoming amount and the checked subtraction panics (`0x11`). Because a sink's stack grows monotonically, **the failure gets more likely the longer the contract is used** — a token that burns fine on day one becomes permanently unburnable. Nothing is lost (tx reverts), but the only event-emitting ERC20 path dies for that token, with an opaque panic rather than a readable error.

**Recommendation:** saturate, letting the existing guard produce the documented error:
```solidity
uint256 received = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
require(received > 0, "nothing received");
```
Combined with [2]'s clamp, `received` always lands in `[0, _amount]`.

## [6] LOW — `nonReentrant` is contract-wide, over-blocking legitimate nesting

**Location:** `src/7r45hc4n.sol:26-35`, applied at `:78` · **Status:** CONFIRMED (two agents)

The double-count hazard the guard addresses is strictly **per-token** (`balanceBefore`/`received` are read from `_token`), but the guard is one contract-wide flag rejecting every nested entry regardless of token. Consequences, permanent because the contract cannot be patched:

- A token routing its own fee-burn through `TrashCan.burnERC20` is **entirely unburnable**.
- Nested burns of *distinct* tokens are rejected despite no possible double-count — a router burning a fee token inside a swap callback, or a batch burner whose token-A callback burns token B.

Secondarily, the inner `require(!_entered, "reentrant")` is swallowed by `_safeTransferFrom`'s low-level call and resurfaces as `"ERC20 transfer failed"`, so integrators get a misleading reason — and the repo's own test asserts that masked string.

For the record the guard is otherwise sound: the transient flag clears correctly on revert, an attacker cannot set it to strand a victim, and sequential burns in one tx work.

**Recommendation:** adopt [2]'s clamp and **remove the guard** — the clamp makes it unnecessary for correctness and its removal resolves [1] and [3] as well. If it is kept, scope it per token (`mapping(address => bool) transient _burning`) and bubble the inner revert data.

## [7] LOW — Return-value check rejects valid tokens and decodes before its own `require`

**Location:** `src/7r45hc4n.sol:95` · **Status:** CONFIRMED (two agents)

`require(ok && (data.length == 0 || abi.decode(data, (bool))), "ERC20 transfer failed")` handles bool-returning and USDT-style no-return tokens, but hard-fails three real classes: tokens returning `false` on success (Tether Gold), tokens returning a 32-byte non-canonical bool (e.g. the transferred amount), and tokens returning 1–31 bytes. In the latter two, `abi.decode` reverts *before* the `require` is evaluated, so the failure is a bare `EvmError: Revert` with no reason string rather than the intended message.

This matches OZ SafeERC20 and is normally the right conservative choice, but this contract is unusual: it independently measures the balance delta and already requires `received > 0`, which is strictly stronger evidence than the return flag. The check buys nothing it doesn't already have while adding a permanent DoS.

**Recommendation:** reduce to `require(ok, "ERC20 transfer failed")` and rely on `received > 0` (plus [2]'s clamp); or gate the decode on `data.length >= 32` and document false-on-success tokens as unsupported.

## [8] LOW — ERC1155 batch recovery path is documented incorrectly

**Location:** `src/7r45hc4n.sol:138-153` (NatSpec `:140-141`) · **Status:** CONFIRMED

The batch hook omits `ids`/`amounts` and the NatSpec says to recover them from the token's `TransferBatch` event. EIP-1155 permits `safeBatchTransferFrom` to emit **`TransferSingle` *or* `TransferBatch`** events, so a fully compliant token may emit N `TransferSingle` events, no `TransferBatch`, and still invoke `onERC1155BatchReceived`. An indexer following the documented recipe finds nothing and reports an unresolvable burn. This is not covered by the known gas trade-off — the documented mitigation itself is wrong.

Compounding: `ERC1155BatchDeposited` has both fields indexed and therefore **zero data bytes**, so two batch deposits from the same `(token, from)` in one tx are byte-identical logs separable only by log index.

**Recommendation:** include `ids`/`amounts` as non-indexed data (trivial next to the N balance writes the tx already pays for), or at minimum correct the NatSpec and note the duplicate-log ambiguity.

## [9] LOW — Non-hook NFT paths burn with no receipt, undocumented

**Location:** `src/7r45hc4n.sol:43-53` (`fallback`), contract NatSpec `:4-10` · **Status:** CONFIRMED

Three paths destroy tokens silently: plain **`transferFrom`** (never calls `onERC721Received`, and is the default in most wallet UIs and explorer Write tabs), **CryptoPunks-style** pre-ERC721 transfers, and **ERC-223** `tokenReceived`, which the catch-all `fallback()` absorbs — the transfer succeeds, but `fallback` only emits when `msg.value > 0`. The permissive fallback turns every unknown callback standard into a receipt-free burn, while the NatSpec advertises "ETH, ERC20, ERC721, and ERC1155" without qualifying that NFT receipts exist only on `safe*` paths.

**Recommendation:** document that receipts exist only for `safeTransferFrom`/`safeBatchTransferFrom`/ETH/`burnERC20`, and direct consumers to treat the token's own `Transfer` events to the TrashCan address as authoritative. Optionally add a pull-based `burnERC721` mirroring `burnERC20`.

---

## Informational

- **`ERC20Deposited` is forgeable.** Anyone can deploy a contract whose `balanceOf` returns anything and emit `ERC20Deposited(fake, self, 1e27)` with nothing destroyed. The docs warn about forgery for the NFT hooks but call `burnERC20` "the only path that guarantees an event", which reads as an authenticity guarantee it cannot back. Extend the caveat.
- **`operator` discarded from all hooks.** Marketplace/operator burns lose the initiator; `_safeMint(trashcan, id)` — a real provably-burned-mint pattern — attributes to `address(0)`.
- **Blocklist / pause DoS undocumented.** USDC/USDT can blocklist an address that visibly accumulates and never releases stablecoins. Once blocklisted, `burnERC20` is permanently unusable for that token with no workaround. Absent from DESIGN.md's Known limitations.
- **Return bomb is present but not exploitable.** `_safeTransferFrom` decodes unbounded returndata. Measured cost to produce vs copy is ~1:1 (3.2 MB: 19.8M vs 20.1M gas), and the caller chooses the token, so a griefer only harms their own call. Optional `returndatacopy` cap; defensible as-is.
- **Repo test mocks are hard-typed to `TrashCan`**, so "would a real NFT transfer here?" is answered tautologically — signature drift would drift in the mock too. Declare receiver interfaces locally instead. (Answered externally with independent interfaces: result is clean.)
- **Compiler freshness.** solc 0.8.36 was released 15 days before this audit with an empty `bugs_by_version.json` entry — "nothing found yet", not "nothing there" — on an immutable contract leaning on newer transient-storage codegen. Taking [1]'s fix allows dropping to a seasoned release.
- **Blast:** gas-fee revenue accrues to the contract and is permanently unclaimable. Consistent with a sink's design; one README line.

## Verified clean

Ownerlessness (bytecode-level, above). No `block.*`, `tx.origin`, `selfdestruct`, `delegatecall`, assembly, loops, `unchecked`, hardcoded addresses, or persistent storage anywhere. ERC165 IDs and all three hook magic values correct by derivation (`0x4e2312e0 == 0xf23a6e61 ^ 0xbc197c81`); `supportsInterface(0xffffffff)` correctly false; strict ERC165-probing ERC721 and ERC1155 implementations both transfer in successfully. `receive()`'s LOG2 fits the 2300-gas stipend, so legacy `.transfer()`/`.send()` callers succeed. Precompiles correctly rejected by the `code.length > 0` check. No division, multiplication, casts, decimals assumptions or accumulators — `type(uint256).max` handled safely. Gas-sink tokens cannot silently succeed (EIP-150 63/64 leaves the parent enough to finish). No front-running, block-stuffing, or time-dependence surface. zkSync Era is deployable and address-consistent (EVM Bytecode Interpreter v27 accepts all three opcodes and preserves standard CREATE/CREATE2 derivation).

## Suggested remediation order

One change resolves the High and most of the rest:

1. **Remove the transient guard, clamp and saturate the delta** — fixes [1], [2], [3], [5], [6] together:
   ```solidity
   uint256 balanceAfter = IERC20(_token).balanceOf(address(this));
   uint256 received = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
   if (received > _amount) received = _amount;
   require(received > 0, "nothing received");
   ```
2. Set `evm_version = "paris"`; consider re-pinning solc to a seasoned release. Re-verify the disassembly has zero `0x5c`/`0x5d`/`0x5e`/`0x5f`.
3. Switch `Deploy.s.sol` to the canonical CREATE2 factory with a fixed salt; publish salt, initcode hash and address — fixes [4].
4. Documentation: correct the ERC1155 batch recovery note [8], the silent NFT paths [9], the ERC20 forgeability caveat, and the blocklist/pause limitation.
