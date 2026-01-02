// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IIdentity} from "../interfaces/IIdentity.sol";

/**
 * @title Identity
 * @dev Implementation of ONCHAINID identity contract based on ERC-734 and ERC-735
 * @notice This contract combines key management (ERC-734) and claim management (ERC-735)
 */
contract Identity is IIdentity {
    /// @dev Nonce for claim ID generation
    uint256 private claimNonce;

    /// @dev Nonce for execution ID generation
    uint256 private executionNonce;

    /// @dev Mapping claim ID to claim data
    mapping(bytes32 => Claim) private claims;

    /// @dev Mapping topic to array of claim IDs
    mapping(uint256 => bytes32[]) private claimsByTopic;

    /// @dev Mapping claim ID to index in topic array
    mapping(bytes32 => uint256) private claimIndexInTopic;

    /// @dev Mapping key hash to key data
    mapping(bytes32 => Key) private keys;

    /// @dev Mapping purpose to array of key hashes
    mapping(uint256 => bytes32[]) private keysByPurpose;

    /// @dev Mapping key hash to index in purpose array
    mapping(bytes32 => mapping(uint256 => uint256)) private keyPurposeIndex;

    /// @dev Mapping key hash to its purposes (bitfield)
    mapping(bytes32 => uint256) private keyPurposes;

    /// @dev Custom errors for gas efficiency
    error KeyAlreadyExists();
    error KeyDoesNotExist();
    error NotAuthorized();
    error InvalidKey();
    error ClaimNotFound();

    /**
     * @dev Constructor - initializes identity with owner's management key
     * @param _owner Address of the identity owner
     */
    constructor(address _owner) {
        bytes32 ownerKey = keccak256(abi.encodePacked(_owner));

        keys[ownerKey] = Key({
            purposes: 1, // MANAGEMENT
            keyType: 1, // ECDSA
            key: ownerKey
        });

        keysByPurpose[1].push(ownerKey);
        keyPurposes[ownerKey] = 1;
        keyPurposeIndex[ownerKey][1] = 0;

        emit KeyAdded(ownerKey, 1, 1);
    }

    /**
     * @dev Modifier to check if caller has a specific key purpose
     * @param _purpose The purpose to check
     */
    modifier onlyKeyPurpose(uint256 _purpose) {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));
        if (!keyHasPurpose(senderKey, _purpose)) revert NotAuthorized();
        _;
    }

    /**
     * @dev Modifier to check if caller has management key
     */
    modifier onlyManagement() {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));
        if (!keyHasPurpose(senderKey, 1)) {
            // 1 = MANAGEMENT KEY
            revert NotAuthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-734 KEY MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdentity
     */
    function getKey(bytes32 _key) external view override returns (uint256 purposes, uint256 keyType, bytes32 key) {
        Key memory k = keys[_key];
        return (k.purposes, k.keyType, k.key);
    }

    /**
     * @inheritdoc IIdentity
     */
    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool exists) {
        return (keyPurposes[_key] & _purpose) != 0;
    }

    /**
     * @inheritdoc IIdentity
     */
    function getKeysByPurpose(uint256 _purpose) external view override returns (bytes32[] memory _keys) {
        return keysByPurpose[_purpose];
    }

    /**
     * @inheritdoc IIdentity
     */
    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType)
        external
        override
        onlyManagement
        returns (bool success)
    {
        if (_key == bytes32(0)) revert InvalidKey();

        // Check if key already has this purpose
        if (keyHasPurpose(_key, _purpose)) return true; // Key already has this purpose

        // If key doesn't exist at all, create it
        if (keys[_key].key == bytes32(0)) {
            keys[_key] = Key({purposes: _purpose, keyType: _keyType, key: _key});
        } else {
            // Key exists, add new purpose
            keys[_key].purposes |= _purpose;
        }

        // Add to purpose array
        keysByPurpose[_purpose].push(_key);
        keyPurposeIndex[_key][_purpose] = keysByPurpose[_purpose].length - 1;

        // Update purposes bitfield
        keyPurposes[_key] |= _purpose;

        emit KeyAdded(_key, _purpose, _keyType);
        return true;
    }

    /**
     * @inheritdoc IIdentity
     */
    function removeKey(bytes32 _key, uint256 _purpose) external override onlyManagement returns (bool success) {
        if (!keyHasPurpose(_key, _purpose)) revert KeyDoesNotExist();

        // Get key type before removal
        uint256 keyType = keys[_key].keyType;

        // Remove purpose from key
        uint256 index = keyPurposeIndex[_key][_purpose];
        uint256 lastIndex = keysByPurpose[_purpose].length - 1;

        if (index != lastIndex) {
            bytes32 lastKey = keysByPurpose[_purpose][lastIndex];
            keysByPurpose[_purpose][index] = lastKey;
            keyPurposeIndex[lastKey][_purpose] = index;
        }

        keysByPurpose[_purpose].pop();
        delete keyPurposeIndex[_key][_purpose];

        // Update purposes bitfield
        keyPurposes[_key] &= ~_purpose;
        keys[_key].purposes &= ~_purpose;

        // If key has no more purposes, remove it entirely
        if (keys[_key].purposes == 0) {
            delete keys[_key];
        }

        emit KeyRemoved(_key, _purpose, keyType);
        return true;
    }

    /**
     * @inheritdoc IIdentity
     */
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        payable
        override
        returns (uint256 executionId)
    {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));

        // Check if sender has ACTION_KEY (2) or MANAGEMENT_KEY (1)
        if (!keyHasPurpose(senderKey, 2) && !keyHasPurpose(senderKey, 1)) {
            revert NotAuthorized();
        }

        executionNonce++;
        executionId = executionNonce;

        emit ExecutionRequested(executionId, _to, _value, _data);

        // Execute the call
        (bool success,) = _to.call{value: _value}(_data);

        if (success) {
            emit Executed(executionId, _to, _value, _data);
        } else {
            emit ExecutionFailed(executionId, _to, _value, _data);
        }

        return executionId;
    }

    /**
     * @inheritdoc IIdentity
     */
    function approve(uint256 _id, bool _approve) external override onlyManagement returns (bool success) {
        emit Approved(_id, _approve);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-735 CLAIM MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IIdentity
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
        Claim memory claim = claims[_claimId];

        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }

    /**
     * @inheritdoc IIdentity
     */
    function getClaimIdsByTopic(uint256 _topic) external view override returns (bytes32[] memory claimIds) {
        return claimsByTopic[_topic];
    }

    /**
     * @inheritdoc IIdentity
     */
    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external override returns (bytes32 claimRequestId) {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));

        // Check if sendeer has CLAIM_KEY (3) or MANAGEMENT_KEY (1)
        if (!keyHasPurpose(senderKey, 3) && !keyHasPurpose(senderKey, 1)) {
            revert NotAuthorized();
        }

        // Generate claim ID
        claimNonce++;
        claimRequestId = keccak256(abi.encodePacked(address(this), _topic, _scheme, _issuer, _data, claimNonce));

        // Store claim
        claims[claimRequestId] =
            Claim({topic: _topic, scheme: _scheme, issuer: _issuer, signature: _signature, data: _data, uri: _uri});

        // Index by topic
        claimsByTopic[_topic].push(claimRequestId);
        claimIndexInTopic[claimRequestId] = claimsByTopic[_topic].length - 1;

        emit ClaimAdded(claimRequestId, _topic, _scheme, _issuer, _signature, _data, _uri);

        return claimRequestId;
    }

    /**
     * @inheritdoc IIdentity
     */
    function removeClaim(bytes32 _claimId) external override returns (bool success) {
        bytes32 senderKey = keccak256(abi.encodePacked(msg.sender));

        // Check if sender has CLAIM_KEY (3) or MANAGEMENT_KEY (1)
        if (!keyHasPurpose(senderKey, 3) && !keyHasPurpose(senderKey, 1)) {
            revert NotAuthorized();
        }

        Claim memory claim = claims[_claimId];

        if (claim.topic == 0) {
            revert ClaimNotFound();
        }

        // Remove from topic index
        uint256 index = claimIndexInTopic[_claimId];
        uint256 lastIndex = claimsByTopic[claim.topic].length - 1;

        if (index != lastIndex) {
            bytes32 lastClaimId = claimsByTopic[claim.topic][lastIndex];
            claimsByTopic[claim.topic][index] = lastClaimId;
            claimIndexInTopic[lastClaimId] = index;
        }

        claimsByTopic[claim.topic].pop();
        delete claimIndexInTopic[_claimId];

        emit ClaimRemoved(_claimId, claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);

        delete claims[_claimId];
        return true;
    }

    /**
     * @dev Fallback function to accept ETH
     */
    receive() external payable {}
}
