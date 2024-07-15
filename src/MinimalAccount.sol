// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccount} from "@AA/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@AA/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@AA/contracts/core/Helpers.sol";
import {IEntryPoint} from "@AA/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, ECDSA, Ownable {
    // Errors
    error MinimalAccount__OnlyFromEntryPoint();

    IEntryPoint private immutable i_entryPoint;

    modifier requireOnlyFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__OnlyFromEntryPoint();
        }
        _;
    }

    constructor(address _entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireOnlyFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateUserOp(userOp, userOpHash);
        // _validateNonce() ==> teh smart contract has to ensure the uniqueness of the nonce; but EntryPoint.sol already handles this for us
        _payPrefund();
    }

    /// @dev validation logic is kept simple for now: if the msg.sender is the owner and has signed the msg; then its valid
    function _validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        pure
        returns (uint256 validationData)
    {
        bytes32 memory ethSignedMsgHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMsgHash, userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED();
        }

        return SIG_VALIDATION_SUCCESS();
    }

    /// @dev the contract (i.e the wallet) has to pay for the gas fees of the user operation to the EntryPoint
    function _payPrefund(uint256 missingAccountFunds) internal returns (bool) {
        if (missingAccountFunds > 0) {
            (bool suc,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            suc;
        }
    }
}
