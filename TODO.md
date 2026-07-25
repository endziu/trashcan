# TODO — audit + static analysis follow-up

Source: AUDIT-REPORT.md (2026-07-24), STATIC-ANALYSIS.md (2026-07-24).
Static analysis validated 0 security findings (all false-positive/intended/style) — no items from it below require action beyond optional style. Audit findings are the real backlog.

## High priority

- [ ] **[AUDIT-1]** Drop Cancun dependency: replace `bool transient _entered` with plain storage (or remove guard per AUDIT-2), set `evm_version = "paris"` in foundry.toml. Fixes deploy-succeeds-but-bricked `burnERC20`/`name`/`warning` on pre-Cancun chains (Polygon zkEVM, Taiko, Metis). Also clears PUSH0 (AUDIT-3).
- [ ] **[AUDIT-2]** Clamp `burnERC20` received amount to `_amount` (`if (received > _amount) received = _amount;`) so hook-injected/rebased third-party balance can't inflate the emitted receipt. Subsumes need for reentrancy guard.

## Medium priority

- [ ] **[AUDIT-3]** Re-verify zero PUSH0/TSTORE/TLOAD/MCOPY in disassembly after AUDIT-1 fix (pre-Shanghai deploy failure otherwise).
- [ ] **[AUDIT-4]** Switch `Deploy.s.sol` to canonical CREATE2 factory (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salt; publish salt + initcode hash + resulting address once solc_version/evm_version/optimizer_runs are frozen.

## Low priority

- [ ] **[AUDIT-5]** Saturate balance delta (`balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0`) so negative-rebase/deflationary tokens revert cleanly instead of underflow-panicking.
- [ ] **[AUDIT-6]** Remove (or scope per-token) the contract-wide `nonReentrant` guard once AUDIT-2's clamp lands — currently blocks legitimate same-tx nested burns of distinct tokens, and masks the real revert reason as "ERC20 transfer failed".
- [ ] **[AUDIT-7]** Loosen `_safeTransferFrom` check to `require(ok, ...)` (rely on `received > 0` instead of decoding return data) so false-on-success tokens (e.g. Tether Gold) and non-canonical/short return data don't hard-revert with no reason string.
- [ ] **[AUDIT-8]** Fix NatSpec on `onERC1155BatchReceived`: recovery via `TransferBatch` is wrong per EIP-1155 (compliant tokens may emit only `TransferSingle`). Also note `ERC1155BatchDeposited` has zero data bytes (fully indexed) — same-tx duplicate logs are only distinguishable by log index.
- [ ] **[AUDIT-9]** Document that receipts only exist for `safeTransferFrom`/`safeBatchTransferFrom`/ETH/`burnERC20` — plain `transferFrom`, CryptoPunks-style transfers, and ERC-223 all burn silently via `fallback`.

## Informational / docs only

- [ ] Note `ERC20Deposited` is forgeable by any contract with a custom `balanceOf` — don't call `burnERC20` an authenticity guarantee.
- [ ] Document `operator` is discarded from all receiver hooks (marketplace/operator-initiated burns lose the initiator; `_safeMint` provably-burned-mint attributes to `address(0)`).
- [ ] Document blocklist/pause risk (USDC/USDT can blocklist the TrashCan address, permanently disabling `burnERC20` for that token).
- [ ] Optional: cap `returndatacopy` in `_safeTransferFrom` against return-bomb griefing (not currently exploitable — self-harm only — but cheap to close).
- [ ] Once AUDIT-1 lands, consider re-pinning solc to a more seasoned release than 0.8.36.
- [ ] One README line: gas-fee revenue accrued to the contract is permanently unclaimable (consistent with design).

## Static analysis — no action needed

- SA-01 reentrancy-balance: false positive, guard covers it (superseded by AUDIT-2/6 plan above).
- SA-02 locked-ether: intended behavior, do not remediate.
- SA-03 low-level-calls: informational, no change required (see AUDIT-7 for the one real edge).
- SA-04 modifier-used-only-once: maintainability only, keep as-is.
- SA-05 naming-convention (`_param` style): optional rename, no security impact.
