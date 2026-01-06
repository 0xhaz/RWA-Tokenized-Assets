// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IIdentity} from "../interfaces/IIdentity.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title OnchainID
 * @dev Implementation of ONCHAINID contract based on ERC-734 and ERC-735 standards
 * @notice Manages blockchain identities with keys and verifiable claims
 */
contract OnChainID is IIdentity {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Storage for claims
    mapping(bytes32 => Claim) private claims;
    mapping(uint256 => bytes32[]) private claimsByTopic;

    // Storage for keys
    mapping(bytes32 => Key) private keys;
    mapping(uint256 => bytes32[]) private keysByPurpose;

    // Execution tracking
    uint256 private executionNonce;
    mapping(uint256 => bool) private executions;

    // Owner of the identity
    address private owner;

    /**
     * @dev Custom errors for gas efficiency
     */
    error InvalidSignature();
    error InvalidKey();
    error KeyAlreadyExists();
    error KeyDoesNotExist();
    error ClaimAlreadyExists();
    error ClaimDoesNotExist();
    error NotAuthorized();
    error InvalidAddress();

    /**
     * @dev Constructor - initializes with owner as management key
     * @param _owner Address of the identity owner
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidAddress();
        owner = _owner;

        // Add management key for owner
        bytes32 ownerKey = keccak256(abi.encodePacked(_owner));
        keys[ownerKey] = Key({
            purpose: 1, // MANAGEMENT_KEY
            keyType: 1, // ECDSA
            key: ownerKey
        });
        keysByPurpose[1].push(ownerKey);

        emit KeyAdded(ownerKey, 1, 1);
    }
}
