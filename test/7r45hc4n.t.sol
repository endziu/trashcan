// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {TrashCan} from "../src/7r45hc4n.sol";

// ============================================================================
// MINIMAL MOCK TOKENS
// ============================================================================

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockERC20Reverting {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

// USDT-style: transferFrom succeeds but returns nothing (no bool).
contract MockERC20NoReturn {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract MockERC721 {
    mapping(uint256 => address) public ownerOf;

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        ownerOf[tokenId] = to;
        uint256 size;
        assembly { size := extcodesize(to) }
        if (size > 0) {
            bytes4 retval = TrashCan(payable(to)).onERC721Received(msg.sender, from, tokenId, data);
            require(retval == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")), "bad receiver");
        }
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }
}

contract MockERC1155 {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    function mint(address to, uint256 id, uint256 amount) external {
        balanceOf[to][id] += amount;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external {
        balanceOf[from][id] -= amount;
        balanceOf[to][id] += amount;
        bytes4 retval = TrashCan(payable(to)).onERC1155Received(msg.sender, from, id, amount, data);
        require(retval == bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")), "bad receiver");
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[from][ids[i]] -= amounts[i];
            balanceOf[to][ids[i]] += amounts[i];
        }
        bytes4 retval = TrashCan(payable(to)).onERC1155BatchReceived(msg.sender, from, ids, amounts, data);
        require(retval == bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)")), "bad receiver");
    }
}

// ============================================================================
// TEST SUITE
// ============================================================================

contract TrashCanTest is Test {
    TrashCan internal trash;
    MockERC20 internal erc20;
    MockERC20Reverting internal erc20Rev;
    MockERC20NoReturn internal erc20NoReturn;
    MockERC721 internal erc721;
    MockERC1155 internal erc1155;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event ETHDeposited(address indexed sender, uint256 indexed amount);
    event ERC20Deposited(address indexed token, address indexed sender, uint256 indexed amount);
    event ERC721Deposited(address indexed token, address indexed sender, uint256 indexed tokenId);
    event ERC1155SingleDeposited(address indexed token, address indexed sender, uint256 indexed tokenId, uint256 amount);
    event ERC1155BatchDeposited(address indexed token, address indexed sender);

    function setUp() public {
        trash = new TrashCan();
        erc20 = new MockERC20();
        erc20Rev = new MockERC20Reverting();
        erc20NoReturn = new MockERC20NoReturn();
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        erc20.mint(alice, 1000e18);
        erc20NoReturn.mint(alice, 1000e18);
        erc721.mint(alice, 1);
        erc721.mint(alice, 2);
        erc1155.mint(alice, 10, 500);
        erc1155.mint(alice, 20, 500);
    }

    // ============================================================================
    // ETH — receive()
    // ============================================================================

    function test_receive_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 1 ether}("");
        assertTrue(ok);
    }

    function test_receive_zeroValue_noEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 0}("");
        assertTrue(ok);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_receive_ethStaysLocked() public {
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 3 ether}("");
        assertTrue(ok);
        assertEq(address(trash).balance, 3 ether);
    }

    function testFuzz_receive(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, amount);
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, amount);
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: amount}("");
        assertTrue(ok);
        assertEq(address(trash).balance, amount);
    }

    // ============================================================================
    // ETH — fallback() (calldata with unrecognized selector + value)
    // ============================================================================

    function test_fallback_withValue_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 1 ether}(hex"deadbeef");
        assertTrue(ok);
    }

    function test_fallback_withValue_zeroNoEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 0}(hex"deadbeef");
        assertTrue(ok);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    // ============================================================================
    // ETH — burn()
    // ============================================================================

    function test_burn_withValue_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, 2 ether);
        vm.prank(alice);
        trash.burn{value: 2 ether}();
        assertEq(address(trash).balance, 2 ether);
    }

    function test_burn_zeroValue_stillEmits() public {
        // burn() emits unconditionally, unlike receive/fallback
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, 0);
        vm.prank(alice);
        trash.burn{value: 0}();
    }

    function testFuzz_burn(uint96 amount) public {
        vm.deal(alice, amount);
        vm.expectEmit(true, true, false, false);
        emit ETHDeposited(alice, amount);
        vm.prank(alice);
        trash.burn{value: amount}();
        assertEq(address(trash).balance, amount);
    }

    // ============================================================================
    // ERC20
    // ============================================================================

    function test_burnERC20_emitsEvent() public {
        vm.startPrank(alice);
        erc20.approve(address(trash), 100e18);
        vm.expectEmit(true, true, true, false);
        emit ERC20Deposited(address(erc20), alice, 100e18);
        trash.burnERC20(address(erc20), 100e18);
        vm.stopPrank();

        assertEq(erc20.balanceOf(alice), 900e18);
        assertEq(erc20.balanceOf(address(trash)), 100e18);
    }

    function test_burnERC20_noReturnValue() public {
        vm.startPrank(alice);
        erc20NoReturn.approve(address(trash), 100e18);
        vm.expectEmit(true, true, true, false);
        emit ERC20Deposited(address(erc20NoReturn), alice, 100e18);
        trash.burnERC20(address(erc20NoReturn), 100e18);
        vm.stopPrank();

        assertEq(erc20NoReturn.balanceOf(alice), 900e18);
        assertEq(erc20NoReturn.balanceOf(address(trash)), 100e18);
    }

    function test_burnERC20_revertsOnTransferFailure() public {
        vm.prank(alice);
        vm.expectRevert("ERC20 transfer failed");
        trash.burnERC20(address(erc20Rev), 1e18);
    }

    function test_burnERC20_revertsWithoutApproval() public {
        vm.prank(alice);
        vm.expectRevert();
        trash.burnERC20(address(erc20), 1e18);
    }

    function test_burnERC20_revertsInsufficientAllowance() public {
        vm.startPrank(alice);
        erc20.approve(address(trash), 50e18);
        vm.expectRevert();
        trash.burnERC20(address(erc20), 100e18);
        vm.stopPrank();
    }

    function testFuzz_burnERC20(uint256 amount) public {
        amount = bound(amount, 1, 1000e18);
        vm.startPrank(alice);
        erc20.approve(address(trash), amount);
        vm.expectEmit(true, true, true, false);
        emit ERC20Deposited(address(erc20), alice, amount);
        trash.burnERC20(address(erc20), amount);
        vm.stopPrank();
        assertEq(erc20.balanceOf(address(trash)), amount);
    }

    // ============================================================================
    // ERC721
    // ============================================================================

    function test_onERC721Received_viaTransfer_emitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit ERC721Deposited(address(erc721), alice, 1);
        vm.prank(alice);
        erc721.safeTransferFrom(alice, address(trash), 1);
        assertEq(erc721.ownerOf(1), address(trash));
    }

    function test_onERC721Received_returnsMagicValue() public {
        bytes4 expected = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        bytes4 ret = trash.onERC721Received(alice, alice, 1, "");
        assertEq(ret, expected);
    }

    function test_onERC721Received_withData() public {
        vm.expectEmit(true, true, true, false);
        emit ERC721Deposited(address(erc721), alice, 2);
        vm.prank(alice);
        erc721.safeTransferFrom(alice, address(trash), 2, "somedata");
    }

    function testFuzz_onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public {
        bytes4 expected = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        vm.expectEmit(true, true, true, false);
        emit ERC721Deposited(address(this), from, tokenId);
        bytes4 ret = trash.onERC721Received(operator, from, tokenId, data);
        assertEq(ret, expected);
    }

    // ============================================================================
    // ERC1155 — single
    // ============================================================================

    function test_onERC1155Received_viaTransfer_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ERC1155SingleDeposited(address(erc1155), alice, 10, 100);
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(trash), 10, 100, "");
        assertEq(erc1155.balanceOf(address(trash), 10), 100);
    }

    function test_onERC1155Received_returnsMagicValue() public {
        bytes4 expected = bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
        bytes4 ret = trash.onERC1155Received(alice, alice, 10, 100, "");
        assertEq(ret, expected);
    }

    function testFuzz_onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public {
        bytes4 expected = bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
        vm.expectEmit(true, true, true, true);
        emit ERC1155SingleDeposited(address(this), from, id, value);
        bytes4 ret = trash.onERC1155Received(operator, from, id, value, data);
        assertEq(ret, expected);
    }

    // ============================================================================
    // ERC1155 — batch
    // ============================================================================

    function test_onERC1155BatchReceived_viaTransfer_emitsEvent() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 10; ids[1] = 20;
        amounts[0] = 50; amounts[1] = 75;

        vm.expectEmit(true, true, false, false);
        emit ERC1155BatchDeposited(address(erc1155), alice);
        vm.prank(alice);
        erc1155.safeBatchTransferFrom(alice, address(trash), ids, amounts, "");

        assertEq(erc1155.balanceOf(address(trash), 10), 50);
        assertEq(erc1155.balanceOf(address(trash), 20), 75);
    }

    function test_onERC1155BatchReceived_returnsMagicValue() public {
        bytes4 expected = bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
        uint256[] memory ids = new uint256[](1);
        uint256[] memory vals = new uint256[](1);
        bytes4 ret = trash.onERC1155BatchReceived(alice, alice, ids, vals, "");
        assertEq(ret, expected);
    }

    function testFuzz_onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory vals,
        bytes memory data
    ) public {
        bytes4 expected = bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
        vm.expectEmit(true, true, false, false);
        emit ERC1155BatchDeposited(address(this), from);
        bytes4 ret = trash.onERC1155BatchReceived(operator, from, ids, vals, data);
        assertEq(ret, expected);
    }

    // ============================================================================
    // ERC165
    // ============================================================================

    function test_supportsInterface_ERC165() public view {
        assertTrue(trash.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_ERC721Receiver() public view {
        assertTrue(trash.supportsInterface(0x150b7a02));
    }

    function test_supportsInterface_ERC1155Receiver() public view {
        assertTrue(trash.supportsInterface(0x4e2312e0));
    }

    function test_supportsInterface_unknownReturnsFalse() public view {
        assertFalse(trash.supportsInterface(0xdeadbeef));
        assertFalse(trash.supportsInterface(0x00000000));
        assertFalse(trash.supportsInterface(0xffffffff));
    }

    function testFuzz_supportsInterface_unknownReturnsFalse(bytes4 id) public view {
        if (id == 0x01ffc9a7 || id == 0x150b7a02 || id == 0x4e2312e0) return;
        assertFalse(trash.supportsInterface(id));
    }

    // ============================================================================
    // INFORMATIONAL VIEWS
    // ============================================================================

    function test_is7r45hc4n() public view {
        assertTrue(trash.is7r45hc4n());
    }

    function test_name() public view {
        assertEq(trash.name(), "7r45hc4n");
    }

    function test_warning() public view {
        assertEq(trash.warning(), "ALL TOKENS SENT HERE ARE PERMANENTLY DESTROYED");
    }

    // ============================================================================
    // NO WITHDRAWAL — contract can hold but never release
    // ============================================================================

    function test_noWithdrawal_ethLockedForever() public {
        vm.prank(alice);
        (bool ok,) = address(trash).call{value: 10 ether}("");
        assertTrue(ok);
        assertEq(address(trash).balance, 10 ether);
        assertEq(alice.balance, 90 ether);
        // No function can release ETH — verified by the absence of any such selector
    }
}
