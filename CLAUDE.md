# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`7r45hc4n` (TrashCan) is a permanent, ownerless token sink — a `/dev/null` for ETH, ERC20, ERC721, and ERC1155. No owner, no withdrawal, no upgradability.

Implementation: `src/7r45hc4n.sol` (Solidity, Foundry project).

## Commands

```bash
forge build
forge test
forge test -v              # verbose, shows gas per test
forge test --match-test <name>
```

## Compiler version

Solidity: `0.8.28` (pinned in pragma).

## Interface

| Function | Mutability | Purpose |
|---|---|---|
| `receive` / `fallback` | payable | Accept ETH; emit only if `value > 0` |
| `burn()` | payable | Explicit ETH burn; always emits |
| `burnERC20(token, amount)` | nonpayable | Pull ERC20 via `transferFrom` (needs prior approval) |
| `onERC721Received(...)` | nonpayable | ERC721 `safeTransferFrom` hook |
| `onERC1155Received(...)` | nonpayable | ERC1155 single transfer hook |
| `onERC1155BatchReceived(...)` | nonpayable | ERC1155 batch transfer hook |
| `supportsInterface(id)` | pure/view | ERC165: `0x01ffc9a7`, `0x150b7a02`, `0x4e2312e0` |
| `is7r45hc4n()`, `name()`, `warning()` | pure/view | Informational |

## Deployment size

| | Solidity |
|---|---|
| Runtime bytecode | ~2,099 bytes |
| Est. deploy gas | ~66,000 |
