//SPDX-Licence-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {PiggyBank} from "../src/PiggyBank.sol";

contract DeployPiggyBank is Script {
    function run() external returns (PiggyBank) {
        vm.startBroadcast();
        PiggyBank piggyBank = new PiggyBank();
        vm.stopBroadcast();
        return piggyBank;
    }
}
