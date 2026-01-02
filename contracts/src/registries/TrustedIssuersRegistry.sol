// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {ITrustedIssuersRegistry, IClaimIssuer} from "../interfaces/ITrustedIssuersRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TrustedIssuersRegistry
 * @dev Implementation of Trusted Issuers Registry
 * @notice Maintains a list of authorized claim issuers and their permitted claim topics
 */
contract TrustedIssuersRegistry is ITrustedIssuersRegistry, Ownable {
    /// @dev Array of trusted issuers
    IClaimIssuer[] private trustedIssuers;

    /// @dev Mapping to check if issuer exists
    mapping(address => bool) private issuerExists;

    /// @dev Mapping issuer address to index in array
    mapping(address => uint256) private issuerIndex;

    /// @dev Mapping issuer to their claim topics
    mapping(address => uint256[]) private issuerClaimTopics;

    /// @dev Mapping to check if issuer has specific topic
    mapping(address => mapping(uint256 => bool)) private issuerHasTopic;

    /**
     * @dev Custom errors for gas efficiency
     */
    error IssuerAlreadyExists();
    error IssuerDoesNotExist();
    error InvalidIssuer();
    error EmptyClaimTopics();

    /**
     * @dev Constructor sets deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a trusted issuer to the registry
     * @param trustedIssuer The ClaimIssuer contract address
     * @param claimTopics Array of claim topics the issuer can issue
     */
    function addTrustedIssuer(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics) external override onlyOwner {
        if (address(trustedIssuer) == address(0)) revert InvalidIssuer();
        if (issuerExists[address(trustedIssuer)]) revert IssuerAlreadyExists();
        if (claimTopics.length == 0) revert EmptyClaimTopics();

        trustedIssuers.push(trustedIssuer);
        issuerExists[address(trustedIssuer)] = true;
        issuerIndex[address(trustedIssuer)] = trustedIssuers.length - 1;

        // Store claim topics
        for (uint256 i = 0; i < claimTopics.length; i++) {
            issuerClaimTopics[address(trustedIssuer)].push(claimTopics[i]);
            issuerHasTopic[address(trustedIssuer)][claimTopics[i]] = true;
        }

        emit TrustedIssuerAdded(trustedIssuer, claimTopics);
    }

    /**
     * @notice Remove a trusted issuer from the registry
     * @param trustedIssuer The ClaimIssuer contract address to remove
     */
    function removeTrustedIssuer(IClaimIssuer trustedIssuer) external override onlyOwner {
        if (!issuerExists[address(trustedIssuer)]) revert IssuerDoesNotExist();

        uint256 index = issuerIndex[address(trustedIssuer)];
        uint256 lastIndex = trustedIssuers.length - 1;

        // Move last element to deleted position
        if (index != lastIndex) {
            IClaimIssuer lastIssuer = trustedIssuers[lastIndex];
            trustedIssuers[index] = lastIssuer;
            issuerIndex[address(lastIssuer)] = index;
        }

        // Remove last element
        trustedIssuers.pop();

        // Clear claim topics
        uint256[] memory topics = issuerClaimTopics[address(trustedIssuer)];
        for (uint256 i = 0; i < topics.length; i++) {
            issuerHasTopic[address(trustedIssuer)][topics[i]] = false;
        }
        delete issuerClaimTopics[address(trustedIssuer)];

        // Clear mappings
        delete issuerExists[address(trustedIssuer)];
        delete issuerIndex[address(trustedIssuer)];

        emit TrustedIssuerRemoved(trustedIssuer);
    }

    /**
     * @dev Update the claim topics an issuer can issue
     * @param trustedIssuer The ClaimIssuer contract address
     * @param claimTopics New array of claim topics
     */
    function updateIssuerClaimTopics(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics)
        external
        override
        onlyOwner
    {
        if (!issuerExists[address(trustedIssuer)]) revert IssuerDoesNotExist();
        if (claimTopics.length == 0) revert EmptyClaimTopics();

        // Clear existing topics
        uint256[] memory oldTopics = issuerClaimTopics[address(trustedIssuer)];
        for (uint256 i = 0; i < oldTopics.length; i++) {
            issuerHasTopic[address(trustedIssuer)][oldTopics[i]] = false;
        }
        delete issuerClaimTopics[address(trustedIssuer)];

        // Set new topics
        for (uint256 i = 0; i < claimTopics.length; i++) {
            issuerClaimTopics[address(trustedIssuer)].push(claimTopics[i]);
            issuerHasTopic[address(trustedIssuer)][claimTopics[i]] = true;
        }

        emit ClaimTopicsUpdated(trustedIssuer, claimTopics);
    }

    /**
     * @dev Get all trusted issuers
     * @return Array of all trusted issuer addresses
     */
    function getTrustedIssuers() external view override returns (IClaimIssuer[] memory) {
        return trustedIssuers;
    }

    /**
     * @dev Check if an address is a trusted issuer
     * @param issuer The address to check
     * @return True if the address is a trusted issuer
     */
    function isTrustedIssuer(address issuer) external view override returns (bool) {
        return issuerExists[issuer];
    }

    /**
     * @dev Get claim topics that an issuer can issue
     * @param trustedIssuer The ClaimIssuer contract address
     * @return Array of claim topics
     */
    function getTrustedIssuerClaimTopics(IClaimIssuer trustedIssuer) external view override returns (uint256[] memory) {
        return issuerClaimTopics[address(trustedIssuer)];
    }

    /**
     * @dev Check if issuer has a specific claim topic
     * @param issuer The ClaimIssuer contract address
     * @param claimTopic The claim topic to check
     * @return True if issuer can issue this claim topic
     */
    function hasClaimTopic(address issuer, uint256 claimTopic) external view override returns (bool) {
        return issuerHasTopic[issuer][claimTopic];
    }
}
