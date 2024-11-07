// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// zksync Era imports
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";

// OZ imports
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
Lifecycle of a type 113 (0x71) transaction

Phase 1: Validation
The `msg.sender` will always be the bootloader system contract

1. The user sends the transaction to the "zkSync API client" (sort of a "light node").
2. The zkSync API client checks to see that the nonce is unique by querying the `NonceHolder` system contract.
3. The zkSync API client calls `validateTransaction`, which MUST update the nonce.
4. The zkSync API client checks the nonce is updated.
5. The zkSync API client calls `payForTransaction`, or `prepareForPaymaster` & `validateAndPayForPaymasterTransaction`.
6. The zkSync API client verifies that the bootloader gets paid.

Phase 2: Execution

1. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are the same).
2. The main node calls `executeTransaction`.
3. If a paymaster was used, the `postTransaction` is called.

 */
contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /*===============================================
                     Errors          
    ===============================================*/
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__FailedToPay();

    /*===============================================
                     Modifiers          
    ===============================================*/
    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    /*===============================================
                     Functions          
    ===============================================*/
    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    /*===============================================
                    External functions          
    ===============================================*/
    /**
     *
     * @notice must increase the nonce
     * @notice must validate the transaction (checked if owner signed the transaction)
     */
    function validateTransaction(
        bytes32, /*_txHash*/
        bytes32, /*_suggestedSignedHash*/
        Transaction calldata _transaction
    ) external payable requireFromBootLoader returns (bytes4 magic) {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32, /*_txHash*/
        bytes32, /*_suggestedSignedHash*/
        Transaction calldata _transaction
    ) external payable requireFromBootLoaderOrOwner {
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {
        _validateTransaction(_transaction);
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction calldata _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    /*===============================================
                    Internal functions          
    ===============================================*/
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // Call nonceholder
        // Make a systems contract call
        // Ex: call(x, y, z) => systemContract call
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, _transaction.nonce)
        );

        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        // (_transaction.signature, txHash)
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // Return the "magic" number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        // If we need to call a system contract
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
