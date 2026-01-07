// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

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
            purposes: 1, // MANAGEMENT_KEY
            keyType: 1, // ECDSA
            key: ownerKey
        });
        keysByPurpose[1].push(ownerKey);

        emit KeyAdded(ownerKey, 1, 1);
    }

    /**
     * @dev Modifier to check if caller has management key
     */
    modifier onlyManagement() {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));
        if (!keyHasPurpose(senderKey, 1)) revert NotAuthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         KEY MANAGEMENT ERC-734
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get key data
     */
    function getKey(bytes32 _key) external view override returns (uint256 purpose, uint256 keyType, bytes32 key) {
        Key storage k = keys[_key];
        return (k.purposes, k.keyType, k.key);
    }

    /**
     * @dev Check if key has specific purpose
     */
    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool exists) {
        Key storage key = keys[_key];
        return (key.purposes & _purpose) != 0;
    }

    /**
     * @dev Get all keys for a specific purpose
     */
    function getKeysByPurpose(uint256 _purpose) external view override returns (bytes32[] memory _keys) {
        return keysByPurpose[_purpose];
    }

    /**
     * @dev Add a key to the identity
     */
    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType)
        external
        override
        onlyManagement
        returns (bool success)
    {
        if (_key == bytes32(0)) revert InvalidKey();

        Key storage key = keys[_key];
        if (key.key != bytes32(0)) revert KeyAlreadyExists();

        keys[_key] = Key({purposes: _purpose, keyType: _keyType, key: _key});

        keysByPurpose[_purpose].push(_key);

        emit KeyAdded(_key, _purpose, _keyType);
        return true;
    }

    /**
     * @dev Remove a key from the identity
     */
    function removeKey(bytes32 _key, uint256 _purpose) external override onlyManagement returns (bool success) {
        Key storage key = keys[_key];
        if (key.key == bytes32(0)) revert KeyDoesNotExist();

        uint256 purposes = key.purposes;
        uint256 keyType = key.keyType;

        // Remove purpose from key
        key.purposes = purposes & ~_purpose;

        // If no purposes left, delete key
        if (key.purposes == 0) {
            delete keys[_key];
        }

        // Remove from purpose array
        _removeKeyFromPurposeArray(_key, _purpose);

        emit KeyRemoved(_key, _purpose, keyType);
        return true;
    }

    /**
     * @dev Execute an action from the identity
     */
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        payable
        override
        onlyManagement
        returns (uint256 executionId)
    {
        executionId = executionNonce++;

        emit ExecutionRequested(executionId, _to, _value, _data);

        (bool success,) = _to.call{value: _value}(_data);

        if (success) {
            executions[executionId] = true;
            emit Executed(executionId, _to, _value, _data);
        } else {
            emit ExecutionFailed(executionId, _to, _value, _data);
        }

        return executionId;
    }

    /**
     * @dev Approve an execution (placeholder for multi-sig)
     */
    function approve(uint256 _id, bool _approve) external override onlyManagement returns (bool success) {
        emit Approved(_id, _approve);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM MANAGEMENT ERC-735
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get claim by ID
     */
    function getClaim(bytes32 _claimId)
        external
        view
        override
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        )
    {
        Claim storage claim = claims[_claimId];
        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }

    /**
     * @dev Get all claim IDs by topic
     */
    function getClaimIdsByTopic(uint256 _topic) external view override returns (bytes32[] memory claimIds) {
        return claimsByTopic[_topic];
    }

    /**
     * @dev Add a claim to the identity
     */
    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external override returns (bytes32 claimRequestId) {
        // Generate claim ID
        claimRequestId = keccak256(abi.encodePacked(_issuer, _topic));

        // Check if claim already exists
        if (claims[claimRequestId].issuer != address(0)) revert ClaimAlreadyExists();

        // Verify signature
        bytes32 dataHash = keccak256(abi.encodePacked(address(this), _topic, _data));
        bytes32 prefixedHash = dataHash.toEthSignedMessageHash();
        address recovered = prefixedHash.recover(_signature);

        if (recovered != _issuer) revert InvalidSignature();

        // Store claim
        claims[claimRequestId] =
            Claim({topic: _topic, scheme: _scheme, issuer: _issuer, signature: _signature, data: _data, uri: _uri});

        claimsByTopic[_topic].push(claimRequestId);

        emit ClaimAdded(claimRequestId, _topic, _scheme, _issuer, _signature, _data, _uri);

        return claimRequestId;
    }

    /**
     * @dev Remove a claim from the identity
     */
    function removeClaim(bytes32 _claimId) external override onlyManagement returns (bool success) {
        Claim storage claim = claims[_claimId];
        if (claim.issuer == address(0)) revert ClaimDoesNotExist();

        uint256 topic = claim.topic;

        // Remove from topic array
        _removeClaimFromTopicArray(_claimId, topic);

        emit ClaimRemoved(_claimId, claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);

        // Delete claim
        delete claims[_claimId];

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Remove key from purpose array
     */
    function _removeKeyFromPurposeArray(bytes32 _key, uint256 _purpose) private {
        bytes32[] storage purposeKeys = keysByPurpose[_purpose];
        for (uint256 i = 0; i < purposeKeys.length; i++) {
            if (purposeKeys[i] == _key) {
                purposeKeys[i] = purposeKeys[purposeKeys.length - 1];
                purposeKeys.pop();
                break;
            }
        }
    }

    /**
     * @dev Remove claim from topic array
     */
    function _removeClaimFromTopicArray(bytes32 _claimId, uint256 _topic) private {
        bytes32[] storage topicClaims = claimsByTopic[_topic];
        for (uint256 i = 0; i < topicClaims.length; i++) {
            if (topicClaims[i] == _claimId) {
                topicClaims[i] = topicClaims[topicClaims.length - 1];
                topicClaims.pop();
                break;
            }
        }
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}
