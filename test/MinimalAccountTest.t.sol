// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "@AA/contracts/interfaces/IEntryPoint.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {SendPackedUserOp, PackedUserOperation} from "../script/SendPackedUserOp.s.sol";
import {PackedUserOperation} from "@AA/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig public helperConfig;
    MinimalAccount public minimalAccount;
    SendPackedUserOp public sendPackedUserOp;
    ERC20Mock public usdc;
    uint256 public AMT = 1000;
    address public randomUser = makeAddr("randomuser");

    function setUp() external {
        DeployMinimal deployMinimal = new DeployMinimal();
        sendPackedUserOp = new SendPackedUserOp();
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

    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMT);
        // Act
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__OnlyFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function test_recoverECDSArecover() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dst = address(usdc);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", address(minimalAccount), AMT);
        bytes memory callData = abi.encodeWithSelector(MinimalAccount.execute.selector, dst, value, data);
        PackedUserOperation memory userOp =
            sendPackedUserOp.signedPackedUserOp(callData, address(minimalAccount), helperConfig.getConfig());

        // Act
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(userOp);
        address actualSigner = ECDSA.recover(userOpHash.toEthSignedMessageHash(), userOp.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    // 1. Sign user ops
    // 2. Call validate userops
    // 3. Assert the return is correct
    function testValidationOfUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.signedPackedUserOp(executeCallData, address(minimalAccount), helperConfig.getConfig());
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        uint256 missingAccountFunds = 1e18;

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dst = address(usdc);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", address(minimalAccount), AMT);
        bytes memory callData = abi.encodeWithSelector(MinimalAccount.execute.selector, dst, value, data);
        PackedUserOperation memory userOp =
            sendPackedUserOp.signedPackedUserOp(callData, address(minimalAccount), helperConfig.getConfig());
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.deal(address(minimalAccount), 1e18);
        emit log_address(minimalAccount.owner());

        //Act

        /// @dev the random user is mimicking the Alt Mempool which is responsible for sending our tx
        /// the actual msg (userOp) has been signed by the owner (i.e the deployer of the contract) {anvil}
        /// this signed userOp is then submitted to the alt mempool which submits it to the entry point; which
        /// then calls the validateUserOp function on the minimal account; once validation is confirmed by the minimal account
        /// the entry point prompts the minimal account to execute the command
        vm.startPrank(randomUser);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(userOps, payable(randomUser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMT);
    }
}
