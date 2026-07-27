// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title 7r45hc4n (TrashCan)
/// @notice Permanent, ownerless token sink. ETH, ERC20, ERC721, and ERC1155
///         tokens sent here are irreversibly destroyed.
/// @dev No owner, no withdrawal function, no upgradability. Deployment is final.
///      Implements ERC721TokenReceiver and ERC1155TokenReceiver so tokens can be
///      sent via safeTransferFrom without reverting.
///      WARNING: ALL TOKENS SENT HERE ARE PERMANENTLY DESTROYED AND CANNOT BE RECOVERED.

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TrashCan {
    event ETHDeposited(address indexed sender, uint256 indexed amount);
    event ERC20Deposited(address indexed token, address indexed sender, uint256 indexed amount);
    event ERC721Deposited(address indexed token, address indexed sender, uint256 indexed tokenId);
    event ERC1155SingleDeposited(address indexed token, address indexed sender, uint256 indexed tokenId, uint256 amount);
    event ERC1155BatchDeposited(address indexed token, address indexed sender);

    /// @dev Reentrancy flag for burnERC20. Plain storage (not transient) to avoid
    ///      a Cancun-only opcode dependency that bricks the contract on older chains.
    bool _entered;

    /// @dev Blocks reentry into burnERC20 via a token transfer hook, which would
    ///      otherwise double-count the balance delta and over-report the burn.
    modifier nonReentrant() {
        require(!_entered, "reentrant");
        _entered = true;
        _;
        _entered = false;
    }

    // ============================================================================
    // ETH ACCEPTANCE
    // ============================================================================

    /// @notice Accepts ETH transfers. Emits ETHDeposited if value is non-zero.
    /// @dev Zero-value calls succeed silently. Use burn() to guarantee an event.
    receive() external payable {
        if (msg.value > 0) emit ETHDeposited(msg.sender, msg.value);
    }

    /// @notice Accepts ETH sent alongside unrecognized calldata. Emits ETHDeposited
    ///         if value is non-zero.
    /// @dev Fires when msg.data is non-empty and no function selector matches.
    ///      Zero-value calls succeed silently.
    fallback() external payable {
        if (msg.value > 0) emit ETHDeposited(msg.sender, msg.value);
    }

    /// @notice Permanently destroys ETH sent by the caller. Always emits
    ///         ETHDeposited, even when msg.value is zero.
    /// @dev Unlike receive/fallback, emits unconditionally. Use this when callers
    ///      need an event receipt for a zero-value call.
    function burn() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    // ============================================================================
    // ERC20 SUPPORT
    // ============================================================================

    /// @notice Permanently destroys ERC20 tokens by pulling them from the caller
    ///         via transferFrom. The caller must approve this contract first.
    /// @dev Emits the amount actually received (contract balance delta), not the
    ///      amount requested. For fee-on-transfer tokens these may differ.
    ///      Reverts if _token is not a deployed contract or if nothing is received (e.g. 100%-fee token).
    ///      ERC777 tokens that enforce ERC-1820 hooks on the transferFrom path may revert.
    ///      Non-reentrant: a token whose transfer hook calls back into burnERC20 reverts
    ///      rather than emitting an inflated amount. Reentry into burn() (ETH) is
    ///      unaffected and remains harmless.
    ///      The received amount is clamped to _amount: a token hook or rebase that
    ///      inflates the balance delta during the transferFrom window cannot inflate
    ///      the emitted receipt beyond what the caller actually authorized.
    ///      Negative-rebase/deflationary tokens that shrink the contract's existing
    ///      balance during the call saturate to zero instead of underflow-panicking.
    /// @param _token ERC20 token contract address.
    /// @param _amount Number of tokens to pull (pre-fee for fee-on-transfer tokens).
    function burnERC20(address _token, uint256 _amount) external nonReentrant {
        require(_token != address(0), "zero address");
        require(_amount > 0, "amount is zero");
        require(_token.code.length > 0, "not a contract");
        uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
        _safeTransferFrom(_token, msg.sender, address(this), _amount);
        uint256 balanceAfter = IERC20(_token).balanceOf(address(this));
        uint256 received = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
        if (received > _amount) received = _amount;
        require(received > 0, "nothing received");
        emit ERC20Deposited(_token, msg.sender, received);
    }

    /// @dev Handles both bool-returning ERC20s and no-return-value tokens (e.g. USDT).
    ///      Reverts with "ERC20 transfer failed" on any failure.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "ERC20 transfer failed");
    }

    // ============================================================================
    // ERC721 SUPPORT
    // ============================================================================

    /// @notice ERC721 safeTransferFrom receiver hook. Always accepts the token and
    ///         emits ERC721Deposited.
    /// @dev This function is public and unauthenticated. Any address can call it
    ///      directly without a real token transfer, producing a spurious ERC721Deposited
    ///      event. Off-chain consumers verifying burns should cross-reference the
    ///      token contract's Transfer event.
    /// @return bytes4 ERC721TokenReceiver magic value (0x150b7a02).
    function onERC721Received(
        address,
        address _from,
        uint256 _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        emit ERC721Deposited(msg.sender, _from, _tokenId);
        return this.onERC721Received.selector;
    }

    // ============================================================================
    // ERC1155 SUPPORT
    // ============================================================================

    /// @notice ERC1155 single-transfer receiver hook. Always accepts; emits
    ///         ERC1155SingleDeposited.
    /// @dev Unauthenticated — see onERC721Received for the forged-event caveat.
    /// @return bytes4 ERC1155 single-transfer magic value (0xf23a6e61).
    function onERC1155Received(
        address,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata
    ) external returns (bytes4) {
        emit ERC1155SingleDeposited(msg.sender, _from, _id, _value);
        return this.onERC1155Received.selector;
    }

    /// @notice ERC1155 batch-transfer receiver hook. Always accepts; emits
    ///         ERC1155BatchDeposited.
    /// @dev Token IDs and amounts are intentionally omitted from the event to save gas.
    ///      Recover the batch contents from the token contract's TransferBatch event.
    ///      Unauthenticated — see onERC721Received for the forged-event caveat.
    /// @return bytes4 ERC1155 batch-transfer magic value (0xbc197c81).
    function onERC1155BatchReceived(
        address,
        address _from,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external returns (bytes4) {
        emit ERC1155BatchDeposited(msg.sender, _from);
        return this.onERC1155BatchReceived.selector;
    }

    // ============================================================================
    // ERC165 INTERFACE DETECTION
    // ============================================================================

    /// @notice Returns true for ERC165 (0x01ffc9a7), ERC721TokenReceiver (0x150b7a02),
    ///         and ERC1155TokenReceiver (0x4e2312e0).
    /// @param _interfaceId Interface selector to query.
    /// @return bool True if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return (
            _interfaceId == 0x01ffc9a7 || // ERC165
            _interfaceId == 0x150b7a02 || // ERC721TokenReceiver
            _interfaceId == 0x4e2312e0    // ERC1155TokenReceiver
        );
    }

    // ============================================================================
    // INFORMATIONAL VIEWS
    // ============================================================================

    /// @notice Returns true. Identifies this contract to off-chain tools.
    function is7r45hc4n() external pure returns (bool) { return true; }

    /// @notice Returns the contract name ("7r45hc4n").
    function name() external pure returns (string memory) { return "7r45hc4n"; }

    /// @notice Returns a warning that all tokens sent here are permanently destroyed.
    function warning() external pure returns (string memory) {
        return "ALL TOKENS SENT HERE ARE PERMANENTLY DESTROYED";
    }
}
