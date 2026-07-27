# 7r45hc4n

A permanent, ownerless token sink for the EVM. Send ETH, ERC20, ERC721, or ERC1155 tokens to the contract address and they are gone forever.

> **WARNING:** All tokens sent here are **PERMANENTLY DESTROYED** and cannot be recovered. There is no owner, no withdrawal function, and no upgrade path.

## Why

A standard burn address (e.g. `0x0...dEaD`) is an EOA with no code. It accepts ETH and any token transfer that does not require a receiver hook, but:

- It will not emit events for what was burned, so off-chain indexers cannot reliably track burn activity.
- It cannot accept ERC721 / ERC1155 transfers via `safeTransferFrom`, since those require the recipient to implement the receiver hook and return the correct selector.

`7r45hc4n` is a contract that emits an event for burns performed through its explicit helpers and implements every standard receiver hook, while still being fully ownerless and unrecoverable. Burns via direct `token.transfer()` or force-sent ETH still destroy assets but produce no TrashCan event.

## Interface

| Function | Mutability | Purpose |
|---|---|---|
| `receive` / `fallback` | payable | Accept ETH transfers; emits `ETHDeposited` if `value > 0` |
| `burn()` | payable | Explicit ETH burn; always emits, even for zero value |
| `burnERC20(token, amount)` | nonpayable | Pull ERC20 via `transferFrom` (caller must approve first) |
| `onERC721Received(...)` | nonpayable | ERC721 `safeTransferFrom` receiver hook |
| `onERC1155Received(...)` | nonpayable | ERC1155 single-transfer receiver hook |
| `onERC1155BatchReceived(...)` | nonpayable | ERC1155 batch-transfer receiver hook |
| `supportsInterface(id)` | view | ERC165 detection (`0x01ffc9a7`, `0x150b7a02`, `0x4e2312e0`) |
| `is7r45hc4n()` / `name()` / `warning()` | view | Informational |

## Events

```solidity
event ETHDeposited(address indexed sender, uint256 indexed amount);
event ERC20Deposited(address indexed token, address indexed sender, uint256 indexed amount);
event ERC721Deposited(address indexed token, address indexed sender, uint256 indexed tokenId);
event ERC1155SingleDeposited(address indexed token, address indexed sender, uint256 indexed tokenId, uint256 amount);
event ERC1155BatchDeposited(address indexed token, address indexed sender);
```

## Usage

### Burn ETH

Send ETH to the contract address, or call `burn()` (with or without value).

### Burn ERC20

```solidity
IERC20(token).approve(trashcan, amount);
TrashCan(trashcan).burnERC20(token, amount);
```

### Burn ERC721 / ERC1155

Call `safeTransferFrom` on the token contract with the TrashCan address as the recipient. The receiver hook fires and emits the corresponding deposit event.

## Build and test

This is a [Foundry](https://book.getfoundry.sh/) project.

```bash
forge build
forge test
forge test -v              # show gas per test
forge test --match-test <name>
```

Test suite includes unit tests, fuzz tests, and an invariant test on the ETH balance.

## Deployment

The contract has no constructor and no initialization. Deploy bytecode and it is ready.

Deploy with `script/Deploy.s.sol`:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

`--verify` submits the source to Etherscan automatically. Omit it for chains where verification is handled separately.

Before broadcasting, do a dry run (drop `--broadcast`) and check the `to` field is `null` (contract creation) and the bytecode matches `forge inspect TrashCan bytecode`.

| | Value |
|---|---|
| Runtime bytecode | 3,834 bytes |
| Est. deploy gas | ~851,000 |
| Compiler | Solidity 0.8.36 (pinned in `foundry.toml`) |
| EVM version | paris (pinned in `foundry.toml`) |
| Optimizer runs | 1,000,000 |

## Caveats

- **Fee-on-transfer ERC20s:** `burnERC20` emits the amount actually received (contract balance delta), not the amount requested. For standard tokens these are equal; for fee-on-transfer tokens the emitted amount will be less than what the caller approved.
- **ERC777 tokens:** the contract is not registered with ERC-1820, so ERC777 transfers that enforce the recipient hook on the `transferFrom` path will revert.
- **Reentrant tokens:** `burnERC20` is guarded. A token whose transfer hook calls back into `burnERC20` reverts rather than emitting an inflated amount — the balance-delta accounting would otherwise count the inner burn twice. Reentry into `burn()` (ETH) is unaffected.
- **Receiver hook events are unauthenticated:** the ERC721 / ERC1155 hooks are public functions. Anyone can call them directly and cause `*Deposited` events to be emitted without an actual token transfer occurring. Off-chain consumers that care about real transfers should cross-reference the corresponding `Transfer` event on the token contract.
- **`onERC1155BatchReceived` does not include token IDs or amounts** in its event, only the token contract and sender. Recover the contents from the corresponding ERC1155 `TransferBatch` event on the token contract.
- **Direct `token.transfer()` produces no `ERC20Deposited` event.** Only `burnERC20` guarantees an event; a plain transfer to the contract address destroys tokens silently from TrashCan's perspective.
- **Force-sent ETH produces no `ETHDeposited` event.** ETH delivered via `SELFDESTRUCT` bypasses `receive`/`fallback`. The contract balance can exceed the sum of all `ETHDeposited` amounts.

## License

MIT
