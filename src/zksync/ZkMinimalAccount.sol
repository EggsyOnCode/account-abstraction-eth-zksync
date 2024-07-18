// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@zkAA/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "@zkAA/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "@zkAA/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "@zkAA/contracts/Constants.sol";
import {INonceHolder} from "@zkAA/contracts/interfaces/INonceHolder.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZkMinimalAccount__InsufficientBalanceForTx();
    error ZkMinimalAccount__UnAuthhorizedMsgSender();
    error ZkMinimalAccount__NotFromBootloader();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice we must increase the nonce and  valide the tx (we can use cutoms validation logic here but for now; we jsut msg.sender = owner)
     * @dev will be called by the Bootloader contract
     * @dev will also have to check if the account has enough funds to pay for the transaction (since we are not using paymastser)
     */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
        returns (bytes4 magic)
    {
        // 1. Call NonceHolder System Contract to increase the nonce
        // We can't just use the address of the deployed contract here, we need to make a sys call to the kernel of zksync
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, _transaction.nonce)
        );

        // 2. Check for fee to pay
        uint256 mustHaveBalance = _transaction.totalRequiredBalance();
        if (mustHaveBalance > address(this).balance) {
            revert ZkMinimalAccount__InsufficientBalanceForTx();
        }

        // 3. check signature
        bytes32 ethSignedMsgHash = _transaction.encodeHash();
        address signer = ECDSA.recover(ethSignedMsgHash, _transaction.signature);
        if (signer != owner()) {
            revert ZkMinimalAccount__UnAuthhorizedMsgSender();
            magic = bytes4(0);
        }

        magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;

        // return magic number
        // what is the purpose of the magic number?
        return magic;
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
