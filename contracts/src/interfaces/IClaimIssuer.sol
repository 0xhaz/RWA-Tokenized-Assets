// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IIdentity.sol";

/**
 * @title IClaimIssuer
 * @dev Interface for claim issuer contracts based on ONCHAINID
 * @notice Claim issuers are trusted entities that can issue claims about identities
 */
interface IClaimIssuer is IIdentity {
    /**
     * @dev Revoke a claim that was previously issued
     * @param _claimId The ID of the claim to revoke
     * @return success True if the revocation was successful
     */
    function revokeClaim(bytes32 _claimId) external returns (bool success);

    /**
     * @dev Get the public key of the claim issuer for signature verification
     * @param _key The key identifier
     * @return purpose The purpose of the key
     * @return keyType The type of the key
     * @return key The actual key data
     */
    function getKey(bytes32 _key) external view returns (uint256 purpose, uint256 keyType, bytes32 key);

    /**
     * @dev Check if this claim issuer is valid
     * @return bool True if the issuer is a valid claim issuer
     */
    function isClaimIssuer() external view returns (bool);
}
