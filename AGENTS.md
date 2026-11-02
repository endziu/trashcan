# Repository Guidelines

## Project Structure & Module Organization

- `src/7r45hc4n.sol` contains `TrashCan`, an ownerless, permanent sink for ETH, ERC20, ERC721, and ERC1155 assets.
- `test/7r45hc4n.t.sol` contains token mocks, unit tests, fuzz tests, and the invariant handler and suite.
- `script/Deploy.s.sol` deploys through the canonical CREATE2 factory using a fixed salt.
- `docs/` holds design notes and historical audit and static-analysis reports. Check historical claims against current code.
- `lib/` contains Foundry dependencies, including `forge-std`. Generated artifacts belong in ignored `out/`, `cache/`, and `broadcast/` directories.

## Build, Test, and Development Commands

Run commands from the repository root:

- `forge build`: compile contracts and report lint warnings.
- `forge test`: run unit, fuzz, and invariant suites.
- `forge test --match-test testFuzz_burnERC20 -vv`: run focused ERC20 fuzz tests with verbose output.
- `forge coverage`: inspect exercised code paths; no minimum coverage percentage is configured.
- `forge fmt --check`: check Foundry formatting; use `forge fmt <path>` to format selected files.
- `anvil`: start a local development node. The deployment script requires the CREATE2 factory to exist on its target chain.

## Coding Style & Naming Conventions

Use four-space indentation, SPDX license headers, and NatSpec for public behavior and security assumptions. Follow existing `PascalCase` contract names, `camelCase` functions, and descriptive event names. Keep Solidity and EVM settings aligned with `foundry.toml`; preserve Paris compatibility. Explain narrowly scoped lint suppressions beside the affected statement.

## Testing Guidelines

Use `forge-std/Test.sol`. Name examples `test_<behavior>`, fuzz tests `testFuzz_<behavior>`, and invariants `invariant_<property>`. Cover event amounts, failure paths, token return-value quirks, fees, and callbacks. For bug fixes, demonstrate a failing regression before applying the fix. Run the full suite before submission and inspect invariant call/revert counts.

## Commit & Pull Request Guidelines

History uses prefixes such as `docs:` and `fix(AUDIT-4):`. Write concise, imperative subjects with an issue scope when relevant. Keep commits focused. PR descriptions should explain behavior changes, link relevant issues, and report validation commands and results. Flag bytecode changes and update the README’s predicted CREATE2 address and initcode hash.

## Security & Onchain Work

Before writing Solidity or shipping onchain, read [ETHSKILLS](https://ethskills.com/SKILL.md) and its relevant topic guides. Preserve the ownerless, non-withdrawable, immutable design. Keep private keys and RPC credentials out of Git. Verify target-chain addresses before broadcasting transactions.
