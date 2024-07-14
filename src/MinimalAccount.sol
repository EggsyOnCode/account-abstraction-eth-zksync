// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccount} from "@AA/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@AA/contracts/interfaces/PackedUserOperation.sol";

contract MinimalAccount is IAccount {
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {}
}
