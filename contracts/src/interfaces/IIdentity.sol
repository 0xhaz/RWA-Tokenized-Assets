// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/**
 * @title IIdentity
 * @dev Interface for ONCHAINID identity contract based on ERC-734 and ERC-735
 * @notice This interface combines key management (ERC-734) and claim management (ERC-735)
 */
interface IIdentity {
    /// @dev Key purposes from ERC-734
    /// MANAGEMENT: 1, ACTION: 2, CLAIM: 3, ENCRYPTION: 4
    /**
     * @dev Claim structure following ERC-735
     * @param topic Claim topic (type of claim, e.g. KYC=1, Accreditation=2)
     * @param scheme Signature scheme (e.g. ECDSA=1, RSA=2)
     * @param issuer Address of the claim issuer
     * @param signature Signature of the claim
     * @param data Data of the claim
     * @param uri URI for additional claim information
     */
    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    /**
     * @dev Key structure following ERC-734
     * @param purposes Purposes of the key (bitfield)
     * @param keyType Type of key (ECDSA, RSA, etc)
     * @param key The actual key data
     */
    struct Key {
        uint256 purposes;
        uint256 keyType;
        bytes32 key;
    }

    // Events for ERC-734 (Key Management)
    event KeyAdded(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event KeyRemoved(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event ExecutionRequested(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event Executed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event ExecutionFailed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event Approved(uint256 indexed executionId, bool approved);

    // Events for ERC-735 (Claim Management)
    event ClaimRequested(
        uint256 indexed claimRequestId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRemoved(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimChanged(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    // ERC-734 Key Management Functions
    function getKey(bytes32 _key) external view returns (uint256 purposes, uint256 keyType, bytes32 key);
    function keyHasPurpose(bytes32 _key, uint256 _purpose) external view returns (bool exists);
    function getKeysByPurpose(uint256 _purpose) external view returns (bytes32[] memory keys);
    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) external returns (bool success);
    function removeKey(bytes32 _key, uint256 _purpose) external returns (bool success);
    function execute(address _to, uint256 _value, bytes calldata _data) external payable returns (uint256 executionId);
    function approve(uint256 _id, bool _approve) external returns (bool success);

    // ERC-735 Claim Management Functions
    function getClaim(bytes32 _claimId)
        external
        view
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        );

    function getClaimIdsByTopic(uint256 _topic) external view returns (bytes32[] memory claimIds);

    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external returns (bytes32 claimRequestId);

    function removeClaim(bytes32 _claimId) external returns (bool success);
}
