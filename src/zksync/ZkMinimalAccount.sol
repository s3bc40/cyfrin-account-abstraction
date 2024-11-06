// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT} from 
    "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import { INonceHolder } from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";

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
contract ZkMinimalAccount is IAccount {
    /*===============================================
                    External functions          
    ===============================================*/
    /**
     *
     * @notice must increase the nonce
     * @notice must validate the transaction (checked if owner signed the transaction)
     */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
        returns (bytes4 magic)
    {
        // Call nonceholder
        // Make a systems contract call
        // Ex: call(x, y, z) => systemContract call
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolde.incrementMinNonceIfEquals, _transaction.nonce)
        )
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    /*===============================================
                    Internal functions          
    ===============================================*/
}
