// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/**
 * @title IClaimTopicsRegistry
 * @dev Interface for Claim Topics Registry
 * @notice Defines required claim types for token holders
 */
interface IClaimTopicsRegistry {
    /**
     * @dev Emitted when a claim topic is added
     * @param claimTopic The claim topic that was added
     */
    event ClaimTopicAdded(uint256 indexed claimTopic);

    /**
     * @dev Emitted when a claim topic is removed
     * @param claimTopic The claim topic that was removed
     */
    event ClaimTopicRemoved(uint256 indexed claimTopic);

    /**
     * @dev Add a claim topic to the registry
     * @param claimTopic The claim topic to add
     * @notice Only owner can call this function
     */
    function addClaimTopic(uint256 claimTopic) external;

    /**
     * @dev Remove a claim topic from the registry
     * @param claimTopic The claim topic to remove
     * @notice Only owner can call this function
     */
    function removeClaimTopic(uint256 claimTopic) external;

    /**
     * @dev Get all required claim topics
     * @return Array of all required claim topics
     */
    function getClaimTopics() external view returns (uint256[] memory);
}
