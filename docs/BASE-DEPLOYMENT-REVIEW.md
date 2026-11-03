# Security and Base Deployment Readiness Review

**Date:** 2026-11-03  
**Reviewed commit:** `3eb4631`  
**Target:** Base mainnet, chain ID `8453`  
**Method:** ETHSKILLS security, audit, testing, L2, wallet, and CROPS guidance, with independent reviews for general security, precision/math, ERC20, NFTs, chain-specific behavior, CREATE2, and denial of service.

## Verdict

No confirmed exploitable contract vulnerability was found. Resolve the compiler advisory and deployment documentation findings below before production deployment. This review does not constitute deployment approval or prove the absence of vulnerabilities.

The review covered `src/7r45hc4n.sol`, `script/Deploy.s.sol`, `foundry.toml`, the existing test suite, README, and historical design/security documents. It covered the contract and deployment workflow, not a frontend. No tracked files were changed during the review and no transactions were broadcast.

## Findings

### BASE-1 — Low: compiler pin predates an optimizer security fix

**Location:** `foundry.toml:5–9`; Solidity pragmas in source, script, and tests.

The build uses Solidity `0.8.36`, optimization enabled with 1,000,000 runs, the legacy code-generation pipeline (`viaIR: false`), and the Paris EVM target.

The Solidity team's October 22 advisory describes a Yul optimizer bookkeeping bug affecting versions `0.8.19` through `0.8.37`. Legacy code generation has narrower exposure than the IR pipeline, but compiler-generated Yul utility functions can still be affected. The Paris target does not eliminate this risk. **Miscompilation was not demonstrated in TrashCan**; this is a deployment-readiness concern rather than a confirmed contract exploit.

**Recommendation:** follow the advisory's recommendation to use Solidity `0.8.38` or later before deploying with optimization enabled. Update matching pragmas, rerun validation, and regenerate the initcode hash and predicted CREATE2 address. The current published address belongs to the reviewed build and must not be assumed to survive a compiler change.

**Source:** [Solidity optimizer advisory and recommended actions](https://www.soliditylang.org/blog/2026/10/22/yul-optimizer-knowledge-base-stale-bookkeeping-bug/).

### BASE-2 — Low: deployment verification instructions conflict with the script

**Locations:** `README.md:86`; `docs/DESIGN.md:68–70`.

The README asks deployers to compare raw creation bytecode from `forge inspect TrashCan bytecode` with the script's initcode hash. These representations cannot match. The design document also requires the transaction's `to` field to be null, although the current script calls the CREATE2 factory.

These instructions prevent an operator from completing the documented integrity checks correctly.

**Recommendation:** document the factory as the transaction destination; compare the Keccak-256 hash of creation bytecode with the expected initcode hash; independently derive the CREATE2 address; and compare deployed runtime bytecode with the compiled runtime artifact. Confirm chain ID `8453` before broadcasting.

## Validation Results

| Check | Result |
| --- | --- |
| `forge build --sizes` | Passed; runtime 3,786 bytes, initcode 3,817 bytes; only intentional locked-ETH warning |
| `forge test` | 44 passed, zero failed |
| Stateful invariant | 1,000 runs, 500,000 handler calls, zero reverts |
| Targeted reentrancy lint and unused-suppression check | Passed without diagnostics |
| Slither | Completed; findings assessed below |
| Base deployment-script simulation | Succeeded without broadcast |
| Additional pinned Base fork tests | Three passed at block `53437175` |

The additional fork tests ran in an isolated review copy, not as committed repository tests. They exercised:

- Base USDC approval, deposit, balance delta, and receipt fields.
- Base WETH wrapping and two successive deposits, including receipt/balance checks.
- Factory deployment, independently computed CREATE2 address, exact runtime-bytecode equality, and rejection of a repeated deployment.

Token addresses were cross-checked against [Circle's USDC deployment list](https://developers.circle.com/stablecoins/usdc-contract-addresses) and [Base's contract-address documentation](https://docs.base.org/specifications/reference/base-contracts).

### Static-analysis assessment

Slither reported a high-severity `reentrancy-balance` diagnostic. The ERC20 entry guard is engaged before both balance reads and the transfer, and nested ERC20 deposits are rejected. No guard bypass was demonstrated. Rebase/reflection changes can still affect a token's balance during transfer; this is a disclosed receipt limitation, not authority to withdraw assets or spend another holder's allowance.

Slither's medium-severity locked-ETH finding is intentional for this sink. Its low-level-call and naming diagnostics are informational. No confirmed high- or medium-severity contract vulnerability remained after manual assessment.

## Base Deployment Evidence

The RPC reported chain ID `8453`. The canonical factory was present, and the predicted target had no code when checked. The simulation and pinned-fork deployment returned the expected address and runtime.

| Reviewed-build property | Value |
| --- | --- |
| Factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `bytes32(0)` |
| Initcode hash | `0x0ef3d694aa562b7f8e0504e98883250bd85117234987bf1b7fb77972a6958078` |
| Predicted address | `0xF43ba7c5CdD8391732919115E8E16Ea485b23a78` |
| Runtime hash | `0xd145b52a9ac8f051d6a2549f6f91101ef928d85af326340de7f2824423bb3a9e` |

These are point-in-time results for the reviewed build. Recheck the chain, factory, target address, and bytecode immediately before deployment. After deployment, verify source on the explorer and compare live runtime bytecode before publishing the address for use.

The script currently checks factory code presence and return-data length, rather than asserting factory identity, the independently predicted return address, and runtime hash. Adding executable integrity checks would strengthen future deployments. A third party can deploy the identical immutable code first and make a repeated deployment fail; a public salt does not give them ownership or permit different code at this address.

## Remaining Validation Gaps

- Retain the pinned Base fork tests in the repository so future changes can rerun them.
- The stateful invariant checks ETH balance only. ERC20 receipt/custody conservation is not asserted across randomized sequences.
- ERC20 fuzz inputs cover bounded amounts rather than the full `uint256` domain. Explicit positive/negative rebase cases would improve coverage.
- Real quirky-token and NFT integration coverage remains limited. Existing NFT transfer mocks invoke the concrete TrashCan type, rather than an independent receiver interface.

These are validation gaps, not demonstrated vulnerabilities. Passing USDC and WETH tests does not establish compatibility with every token.

## CROPS and Accepted Trust Assumptions

**Chosen architecture:** an ownerless, immutable, directly callable sink. There is no team-controlled withdrawal, upgrade, pause, or recovery path. Source carries MIT licensing; the repository supplies contracts, interfaces, build configuration, and deployment instructions.

**Censorship and availability:** users can switch RPC providers or call directly. Base's sequencer and chain governance remain external dependencies; token issuers can also pause, blocklist, or upgrade their tokens. Base's [risk assessment](https://l2beat.com/layer2s/projects/base) describes chain-level upgrade and availability assumptions. TrashCan's immutability does not remove those dependencies.

**Privacy:** sender addresses, token addresses, amounts, and transaction timing are public. RPC providers can observe requests. This contract provides no privacy mechanism.

**Security and exit:** deposited assets have no exit through TrashCan by design. Users must accept irreversibility before depositing. “Burning” here means locking assets in the sink; it does not invoke an ERC20 supply-reduction function. Token-issuer powers remain outside the sink's control.

**Receipts:** arbitrary tokens and unauthenticated NFT hooks can fabricate logs. Rebases can affect observed ERC20 deltas, and direct transfers or force-sent ETH can produce no TrashCan receipt. Consumers must validate known token contracts and corroborating token events rather than treating every deposit log as proof of an authentic burn.
