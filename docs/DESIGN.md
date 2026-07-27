# Design Notes

## Rationale

Standard burn addresses (e.g. `0x000...dEaD`) are externally owned accounts with no code. They work for direct token transfers, but:

- They emit no events, so off-chain tracking of burn activity requires parsing raw token Transfer events to a well-known address.
- They reject `safeTransferFrom` for ERC721 and ERC1155 tokens, because those require the recipient to implement a receiver hook and return the correct selector. Tokens sent this way revert.

TrashCan is a contract that addresses both: it emits a dedicated event for burns performed through its explicit helpers (`burn()`, `burnERC20`, and the `safeTransferFrom` receiver hooks) and implements every standard receiver hook, while remaining fully ownerless and non-withdrawable. Burns that bypass these helpers — direct ERC20 `transfer()` calls or force-sent ETH — still destroy the assets but produce no TrashCan event.

## Security model

The contract has no owner, no access control, no state mutations beyond the ETH balance (which is monotonically non-decreasing), and no upgrade path. Once deployed, behaviour is fixed forever.

The threat model is simple: **nothing can leave**. The only way assets can change the ETH balance is upward (receives and burns). ERC20, ERC721, and ERC1155 tokens are accepted but never released. There is no `withdraw`, no `transfer`, and no `delegatecall`. The function set is the complete set of functions that can ever exist on this contract.

No constructor means no initialisation race condition and no risk of a deploy-time front-run that changes ownership before it can be renounced.

## Design decisions

### `burn()` always emits, `receive`/`fallback` only emit on non-zero value

`receive` and `fallback` handle the general case of ETH arriving at the contract. Emitting on zero value would create noise for any address-level zero-value probe. `burn()` is an explicit, caller-initiated act of burning; callers deserve an event receipt regardless of value, so they can use it as a verifiable proof of intent.

### `burnERC20` emits received amount, not requested amount

The event records the contract balance delta (before and after the transfer), not the amount the caller passed. For standard ERC20s these are identical. For fee-on-transfer tokens, the emitted amount is the amount actually destroyed — which is what the event should record. Emitting the requested amount would be a permanent lie for any token that takes a transfer fee.

The approach adds two `balanceOf` calls (~2,500 gas each at warm access). This is the correct trade-off for an immutable contract where events are the canonical record of what was destroyed.

### `onERC1155BatchReceived` omits token IDs and amounts from its event

Including `uint256[] ids` and `uint256[] amounts` in `ERC1155BatchDeposited` would make the event log unbounded in size for large batches. The batch token IDs and amounts are already available from the `TransferBatch` event emitted by the token contract in the same transaction. Off-chain consumers that need the full breakdown should read that event.

### `_safeTransferFrom` uses a low-level call

Standard ABI calls to ERC20's `transferFrom` fail for tokens like USDT that do not return a `bool`. The low-level call accepts both: a `true` bool return, and an empty return (which some tokens produce). This covers the full range of token behaviour observed in production.

## Known limitations

**Receiver hooks are unauthenticated.** The ERC721 and ERC1155 receiver hooks (`onERC721Received`, `onERC1155Received`, `onERC1155BatchReceived`) are public functions. Any address can call them directly without a real token transfer, causing the corresponding `*Deposited` event to be emitted with `msg.sender` as the token address. This is inherent to the ERC721/ERC1155 receiver specification — the hooks cannot require caller authentication without breaking compatibility with compliant token contracts. Off-chain consumers that need to verify a real transfer occurred should cross-reference the corresponding `Transfer` or `TransferBatch` event on the token contract in the same transaction.

**`ERC20Deposited` is forgeable.** Any contract can implement a `balanceOf` that returns whatever it wants, then call `burnERC20` on itself to emit an arbitrary `ERC20Deposited(fakeToken, self, anyAmount)` with nothing real destroyed. This is the same class of caveat as the receiver-hook forgery above, so `burnERC20` should not be treated as an authenticity guarantee — only as a guarantee that *if* the token address is a real, known-good ERC20, the emitted amount reflects an actual balance change.

**`operator` is discarded from every receiver hook.** `onERC721Received`, `onERC1155Received`, and `onERC1155BatchReceived` all receive an `operator` parameter (the address that initiated the transfer, which may differ from `from`) but it is not emitted. Marketplace- or operator-initiated burns lose the initiator's identity in the event log; a `_safeMint(trashcan, id)` "provably burned at mint" pattern attributes the burn to `address(0)` rather than the actual minter.

**Blocklist/pause tokens can permanently disable `burnERC20` for themselves.** USDC, USDT, and similar centrally-administered stablecoins can blocklist any address, including TrashCan's. Once blocklisted for a given token, `burnERC20` reverts for that token forever — there is no owner to appeal to and no workaround, since the contract cannot be upgraded or migrated.

**ERC777 tokens.** TrashCan is not registered as an ERC-1820 recipient. ERC777 tokens that enforce the `tokensReceived` hook on the `transferFrom` path (implementation-dependent) will revert when `burnERC20` is called. These tokens cannot be burned through this contract. The contract has no constructor, so ERC-1820 registration is not possible without an external call at deploy time — which would require an owner to perform it, contradicting the ownerless design. ERC777 tokens can still be sent via a direct ERC20 `transfer` call if the token's implementation allows it; they just cannot use `burnERC20`.

**`onERC1155BatchReceived` event does not contain token IDs or amounts.** The `ERC1155BatchDeposited` event records only the token contract address and the sender. The full batch contents (which token IDs, how many of each) must be recovered from the `TransferBatch` event emitted by the token contract in the same transaction.

**`burn()` emits `ETHDeposited(sender, 0)` for zero-value calls.** This is intentional (see design decision above), but indexers that aggregate burn totals by summing `ETHDeposited.amount` will include zero-value events. Consumers that aggregate totals should be aware of this.

**Force-sent ETH produces no event.** ETH sent via `SELFDESTRUCT` (or assigned as a coinbase reward) bypasses `receive` and `fallback` entirely. The contract balance will increase without a corresponding `ETHDeposited` log. Off-chain systems that use `ETHDeposited` events to account for destroyed ETH will undercount if any ETH arrives through this path.

**Direct ERC20 `transfer()` produces no event.** Calling `token.transfer(trashcan, amount)` directly on the token contract destroys the tokens without invoking any TrashCan function, so no `ERC20Deposited` event is emitted. `burnERC20` is the only path that guarantees an event.

**Non-hook NFT transfers produce no event.** Plain ERC721 `transferFrom` (the default in most wallet UIs and explorer "Write" tabs) never calls `onERC721Received`. CryptoPunks-style pre-ERC721 transfers and ERC-223 `tokenReceived` are absorbed by the catch-all `fallback()`, which only emits on non-zero `msg.value`. In all three cases the asset is still destroyed, just without a receipt. Event receipts exist only for the `safeTransferFrom`/`safeBatchTransferFrom` paths, ETH, and `burnERC20` — off-chain consumers should treat the token contract's own `Transfer`/`TransferSingle`/`TransferBatch` events to the TrashCan address as the authoritative record for everything else.

## Deployment

The contract has no constructor and no initialisation. Deploy and it is immediately operational.

The deploy script (`script/Deploy.s.sol`) uses `forge script` with `--broadcast`. Adding `--verify --etherscan-api-key $ETHERSCAN_API_KEY` submits the source to Etherscan in the same run, which enables Etherscan to render NatSpec for every verified interaction.

Before broadcasting, perform a dry run (omit `--broadcast`) and verify:
- The `to` field is `null` (contract creation, not a call).
- The creation bytecode matches `forge inspect TrashCan bytecode`.

Record the deployed address and transaction hash as the canonical deployment record.
