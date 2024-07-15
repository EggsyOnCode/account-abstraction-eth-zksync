// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";

contract DeployMinimal is Script {
    function run() public returns (HelperConfig, MinimalAccount) {
        return deployMinimalAccount();
    }

    function deployMinimalAccount() public returns (HelperConfig helperConfig, MinimalAccount minimalAccount) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory network = helperConfig.getConfig();

        vm.startBroadcast();
        minimalAccount = new MinimalAccount(network.entryPoint);
        minimalAccount.transferOwnership(network.account);
        vm.stopBroadcast();
    }
}
