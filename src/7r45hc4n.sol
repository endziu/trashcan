// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 7r45hc4n (TrashCan): irreversible sink for ETH, ERC20, ERC721, and ERC1155 tokens.
// WARNING: All tokens sent here are PERMANENTLY DESTROYED and cannot be recovered.

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract TrashCan {
    event ETHDeposited(address indexed sender, uint256 amount);
    event ERC20Deposited(address indexed token, address indexed sender, uint256 amount);
    event ERC721Deposited(address indexed token, address indexed sender, uint256 tokenId);
    event ERC1155SingleDeposited(address indexed token, address indexed sender, uint256 tokenId, uint256 amount);
    event ERC1155BatchDeposited(address indexed token, address indexed sender);

    // ============================================================================
    // ETH ACCEPTANCE
    // ============================================================================

    receive() external payable {
        if (msg.value > 0) emit ETHDeposited(msg.sender, msg.value);
    }

    fallback() external payable {
        if (msg.value > 0) emit ETHDeposited(msg.sender, msg.value);
    }

    function burn() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    // ============================================================================
    // ERC20 SUPPORT
    // ============================================================================

    function burnERC20(address _token, uint256 _amount) external {
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        require(success, "ERC20 transfer failed");
        emit ERC20Deposited(_token, msg.sender, _amount);
    }

    // ============================================================================
    // ERC721 SUPPORT
    // ============================================================================

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

    function is7r45hc4n() external pure returns (bool) { return true; }

    function name() external pure returns (string memory) { return "7r45hc4n"; }

    function warning() external pure returns (string memory) {
        return "ALL TOKENS SENT HERE ARE PERMANENTLY DESTROYED";
    }
}
