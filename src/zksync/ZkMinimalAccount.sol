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
import {Utils} from "@zkAA/contracts/libraries/Utils.sol";

/**
 * Lifecycle of a type 113 (0x71) transaction
 * msg.sender is the bootloader system contract
 *
 * Phase 1 Validation
 * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
 * 2. The zkSync API client checks to see the the nonce is unique by querying the NonceHolder system contract
 * 3. The zkSync API client calls validateTransaction, which MUST update the nonce
 * 4. The zkSync API client checks the nonce is updated
 * 5. The zkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction
 * 6. The zkSync API client verifies that the bootloader gets paid
 *
 * Phase 2 Execution
 * 7. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are the same)
 * 8. The main node calls executeTransaction
 * 9. If a paymaster was used, the postTransaction is called
 */

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZkMinimalAccount__InsufficientBalanceForTx();
    error ZkMinimalAccount__TxValidationFailed();
    error ZkMinimalAccount__NotFromBootloader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__FailedToPay();

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
        return _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
        requireFromBootloader
    {
        _executeTransaction(_transaction);
    }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkMinimalAccount__TxValidationFailed();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
    {
        bool suc = _transaction.payToTheBootloader();
        if (!suc) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
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
            magic = bytes4(0);
        } else {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        }
        // return magic number
        // what is the purpose of the magic number?
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
