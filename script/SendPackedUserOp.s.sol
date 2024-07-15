// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IAccount} from "@AA/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@AA/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@AA/contracts/core/Helpers.sol";
import {IEntryPoint} from "@AA/contracts/interfaces/IEntryPoint.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() external {}

    function signedPackedUserOp(
        bytes memory _callData,
        address _minimalAccount,
        HelperConfig.NetworkConfig memory config
    ) public returns (PackedUserOperation memory) {
        // create a unsigned userOp
        uint256 nonce = vm.getNonce(_minimalAccount) - 1;
        PackedUserOperation memory userOp = _generateUnsignedPackedUserOp(nonce, _callData, _minimalAccount);

        // get the userOp hash using the entry point interface
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // sign it
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else {
            (v, r, s) = vm.sign(config.account, digest);
        }
        userOp.signature = abi.encodePacked(r, s, v); // Note the order
        return userOp;
    }

    function _generateUnsignedPackedUserOp(uint256 _nonce, bytes memory _callData, address _sender)
        internal
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            /// @dev the sender needs to be teh address of the minimalAccount since in EntryPoint contract
            /// we use IAccount(sender).validateUserOp(userOp, userOpHash, missingAccountFunds);
            /// i.e we treat sender as the wallet
            sender: _sender,
            nonce: _nonce,
            initCode: hex"",
            callData: _callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
