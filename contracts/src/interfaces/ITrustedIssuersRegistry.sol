// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IClaimIssuer.sol";

/**
 * @title ITrustedIssuersRegistry
 * @dev Interface for Trusted Issuers Registry
 * @notice Maintains list of authorized claim issuers and their permitted claim topics
 */
interface ITrustedIssuersRegistry {
    /**
     * @dev Emitted when a trusted issuer is added
     * @param trustedIssuer The address of the trusted issuer
     * @param claimTopics The claim topics the issuer can issue
     */
    event TrustedIssuerAdded(IClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    /**
     * @dev Emitted when a trusted issuer is removed
     * @param trustedIssuer The address of the trusted issuer
     */
    event TrustedIssuerRemoved(IClaimIssuer indexed trustedIssuer);

    /**
     * @dev Emitted when issuer claim topics are updated
     * @param trustedIssuer The address of the trusted issuer
     * @param claimTopics The new claim topics
     */
    event ClaimTopicsUpdated(IClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    /**
     * @dev Add a trusted issuer to the registry
     * @param trustedIssuer The ClaimIssuer contract address
     * @param claimTopics Array of claim topics the issuer can issue
     */
    function addTrustedIssuer(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics) external;

    /**
     * @dev Remove a trusted issuer from the registry
     * @param trustedIssuer The ClaimIssuer contract address to remove
     */
    function removeTrustedIssuer(IClaimIssuer trustedIssuer) external;

    /**
     * @dev Update the claim topics an issuer can issue
     * @param trustedIssuer The ClaimIssuer contract address
     * @param claimTopics New array of claim topics
     */
    function updateIssuerClaimTopics(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics) external;

    /**
     * @dev Get all trusted issuers
     * @return Array of all trusted issuer addresses
     */
    function getTrustedIssuers() external view returns (IClaimIssuer[] memory);

    /**
     * @dev Check if an address is a trusted issuer
     * @param issuer The address to check
     * @return True if the address is a trusted issuer
     */
    function isTrustedIssuer(address issuer) external view returns (bool);

    /**
     * @dev Get claim topics that an issuer can issue
     * @param trustedIssuer The ClaimIssuer contract address
     * @return Array of claim topics
     */
    function getTrustedIssuerClaimTopics(IClaimIssuer trustedIssuer) external view returns (uint256[] memory);

    /**
     * @dev Check if issuer has a specific claim topic
     * @param issuer The ClaimIssuer contract address
     * @param claimTopic The claim topic to check
     * @return True if issuer can issue this claim topic
     */
    function hasClaimTopic(address issuer, uint256 claimTopic) external view returns (bool);
}
