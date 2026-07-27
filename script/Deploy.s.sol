// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {TrashCan} from "../src/7r45hc4n.sol";

/// @dev Canonical CREATE2 factory ("Deterministic Deployment Proxy"), already
///      deployed at this address on 100+ chains via a presigned, chain-agnostic
///      transaction. Using it (instead of a bare `new TrashCan()`, which is a
///      nonce-dependent CREATE from the broadcaster's EOA) gives TrashCan the
///      same address on every chain where the factory exists.
address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev Fixed salt for TrashCan's CREATE2 address. The resulting address also
///      depends on the exact creation bytecode: solc_version, evm_version, and
///      optimizer_runs in foundry.toml must stay frozen once an address is
///      published, since any of those three changes the initcode hash.
bytes32 constant SALT = bytes32(uint256(0));

contract Deploy is Script {
    function run() external returns (TrashCan trash) {
        require(CREATE2_FACTORY.code.length > 0, "CREATE2 factory not deployed on this chain");

        bytes memory initCode = type(TrashCan).creationCode;
        bytes memory payload = abi.encodePacked(SALT, initCode);

        vm.startBroadcast();
        (bool ok, bytes memory ret) = CREATE2_FACTORY.call(payload);
        vm.stopBroadcast();

        require(ok && ret.length == 20, "CREATE2 factory deploy failed");
        // forge-lint: disable-next-line(unsafe-typecast)
        address deployed = address(uint160(bytes20(ret)));
        trash = TrashCan(payable(deployed));

        console.log("TrashCan deployed at:", deployed);
        console.log("Salt:");
        console.logBytes32(SALT);
        console.log("Initcode hash:");
        console.logBytes32(keccak256(initCode));
    }
}
