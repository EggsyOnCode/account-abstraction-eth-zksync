// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MinimalAccountTest is Test {
    HelperConfig public helperConfig;
    MinimalAccount public minimalAccount;
    ERC20Mock public usdc;
    uint256 public AMT = 1000;

    function setUp() external {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.run();
        usdc = new ERC20Mock();
    }

    // USDC Mint
    // msg.sender -> MinimalAccount
    // approve some amount
    // USDC contract
    // come from the entrypoint

    function test_onlyOwnerCanCall() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dst = address(usdc);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", address(minimalAccount), AMT);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dst, value, data);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMT);
    }
}
