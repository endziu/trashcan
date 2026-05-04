// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TrashCan} from "../src/7r45hc4n.sol";

contract Deploy is Script {
    function run() external returns (TrashCan trash) {
        vm.startBroadcast();
        trash = new TrashCan();
        vm.stopBroadcast();
        console.log("TrashCan deployed at:", address(trash));
    }
}
