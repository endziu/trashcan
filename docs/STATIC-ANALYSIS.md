# Static Analysis Report

**Project:** `7r45hc4n`
**Analysis date:** 2026-07-24
**Scope:** `src/7r45hc4n.sol` (85 source lines reported by Aderyn)
**Compiler:** Solidity 0.8.36, EVM Cancun, optimizer enabled with 1,000,000 runs

## Executive summary

No actionable security vulnerability was validated.

The compiler and Forge linter completed without diagnostics. Slither and Aderyn
produced seven detector categories, consolidated below into five findings. The
two alarming results are false positives caused by the contract's deliberate
token-sink design and its transient-storage reentrancy guard. The remaining
results are informational, false-positive, or low-priority maintainability
observations.

| Validated severity | Count |
|---|---:|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| Informational / maintainability | 3 |
| False positive / intended behavior | 3 |

Counts in this table are detector assessments; overlapping detector results are
grouped into five findings below.

## Tools and results

| Tool | Version / detector count | Result |
|---|---|---|
| Solidity compiler | 0.8.36 | Clean; compilation succeeded with warnings denied |
| Forge lint | Foundry 1.7.1 | Clean; all severities ran with notes denied |
| Slither | 0.11.5, 101 detectors | 12 raw results across 4 detector categories |
| Aderyn | 0.6.8, 88 detectors | 3 raw results: 1 high and 2 low |

Commands:

```text
forge build --force --deny warnings
forge lint --force --deny notes
slither . --json /tmp/trashcan-slither.json
aderyn . --output /tmp/trashcan-aderyn.json
```

Slither returned exit code 255 because detector results were present; its JSON
reported `"success": true`. All other commands returned exit code 0.

## Assessed findings

### SA-01: Reentrancy around ERC20 balance accounting

| Field | Value |
|---|---|
| Tool | Slither (`reentrancy-balance`) |
| Raw rating | High impact, medium confidence |
| Location | `src/7r45hc4n.sol:78-87`, external call at lines 92-94 |
| Assessment | False positive |

Slither observes that `balanceBefore` is read before an external token call and
used to calculate `received` afterward. However, `burnERC20` uses the
`nonReentrant` modifier at line 78. The modifier sets the transient `_entered`
flag before the external call and clears it only after the function finishes.
A token callback therefore cannot reenter `burnERC20` and corrupt the outer
balance delta.

The external token is also the asset being measured. A malicious token can
report arbitrary balances regardless of call ordering, but this creates no
privilege escalation or asset-recovery path in an ownerless sink. At worst, its
own `ERC20Deposited` event is untrustworthy, which is inherent when interacting
with an adversarial token contract.

**Recommendation:** No change required. Retain the guard and its regression
tests.

### SA-02: Ether permanently locked

| Field | Value |
|---|---|
| Tools | Slither (`locked-ether`), Aderyn (`contract-locks-ether`) |
| Raw rating | Slither medium; Aderyn high |
| Location | `src/7r45hc4n.sol:17-185` |
| Assessment | Intended behavior |

Both tools correctly detect payable entry points without an Ether withdrawal
function. Permanent, irreversible custody is the contract's defining
requirement. Adding a withdrawal function would violate the specification and
weaken the security model.

**Recommendation:** Do not remediate. Keep the behavior prominent in
documentation and deployment review.

### SA-03: Low-level ERC20 call

| Field | Value |
|---|---|
| Tools | Slither (`low-level-calls`), Aderyn (`unsafe-erc20-operation`) |
| Raw rating | Slither informational; Aderyn low |
| Location | `src/7r45hc4n.sol:91-96` |
| Assessment | Slither: informational; Aderyn: false positive |

`_safeTransferFrom` deliberately uses a low-level call to support both
bool-returning ERC20 contracts and legacy tokens that return no value. It checks
the call status and accepts return data only when it is empty or decodes to
`true`. `burnERC20` additionally verifies a positive balance delta. Aderyn's
unsafe-operation result points at the selector encoded for this checked wrapper,
not at an unchecked direct interface call.

One theoretical edge remains: successful malformed return data can cause
`abi.decode` to revert. That is fail-closed behavior and does not put assets at
risk.

**Recommendation:** No security change required. A standard `SafeERC20` library
could replace the helper for ecosystem familiarity, but would add a dependency
without materially changing this behavior.

### SA-04: Modifier used only once

| Field | Value |
|---|---|
| Tool | Aderyn (`modifier-used-only-once`) |
| Raw rating | Low |
| Location | `src/7r45hc4n.sol:30` |
| Assessment | Informational / maintainability |

The `nonReentrant` modifier currently protects one function. Inlining it could
reduce indirection, while retaining it makes the security boundary conspicuous
and reusable. This is not a vulnerability.

**Recommendation:** Keep it unless project style favors inlining single-use
modifiers.

### SA-05: Parameter naming convention

| Field | Value |
|---|---|
| Tool | Slither (`naming-convention`) |
| Raw rating | Informational, high confidence |
| Locations | Lines 78, 111-112, 129-131, 146, and 163 |
| Assessment | Informational / style |

Slither emitted nine results for underscore-prefixed parameters (`_token`,
`_amount`, `_from`, `_tokenId`, `_id`, `_value`, and `_interfaceId`). The names
are clear and consistently applied, but do not match Slither's configured
mixed-case convention.

**Recommendation:** Optional rename only; there is no security impact.

## Raw-result accounting

Slither's 12 results consist of:

- 1 `reentrancy-balance`
- 1 `locked-ether`
- 1 `low-level-calls`
- 9 `naming-convention`

Aderyn's 3 results consist of:

- 1 `contract-locks-ether`
- 1 `modifier-used-only-once`
- 1 `unsafe-erc20-operation`

Overlapping results were consolidated in SA-02 and SA-03.

## Conclusion

The analyzed source compiles cleanly and has no validated static-analysis
security finding. No code change is recommended from these results. The
permanent asset lock must remain an explicitly accepted design property, and
the ERC20 reentrancy guard should remain covered by tests.

This report covers automated static analysis only. It does not replace manual
review, fuzzing, invariant testing, or deployment-bytecode verification.
