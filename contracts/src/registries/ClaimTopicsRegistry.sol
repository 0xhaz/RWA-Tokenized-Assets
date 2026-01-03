// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IClaimTopicsRegistry} from "../interfaces/IClaimTopicsRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClaimTopicsRegistry
 * @dev Implementation of Claim Topics Registry
 * @notice Defines required claim types for token holders
 */
contract ClaimTopicsRegistry is IClaimTopicsRegistry, Ownable {
    /// @dev Array of required claim topics
    uint256[] private claimTopics;

    /// @dev Mapping to track if a topic exists
    mapping(uint256 => bool) private topicExists;

    /**
     * @dev Custom errors for gas efficiency
     */
    error TopicAlreadyExists();
    error TopicDoesNotExist();

    /**
     * @dev Constructor sets deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a claim topic to the registry
     * @param claimTopic The claim topic to add
     * @notice Only owner can call this function
     */
    function addClaimTopic(uint256 claimTopic) external override onlyOwner {
        if (topicExists[claimTopic]) revert TopicAlreadyExists();

        claimTopics.push(claimTopic);
        topicExists[claimTopic] = true;

        emit ClaimTopicAdded(claimTopic);
    }

    /**
     * @dev Remove a claim topic from the registry
     * @param claimTopic The claim topic to remove
     * @notice Only owner can call this function
     */
    function removeClaimTopic(uint256 claimTopic) external override onlyOwner {
        if (!topicExists[claimTopic]) revert TopicDoesNotExist();

        // Find and remove the topic
        uint256 length = claimTopics.length;
        for (uint256 i = 0; i < length; i++) {
            if (claimTopics[i] == claimTopic) {
                claimTopics[i] = claimTopics[length - 1];
                claimTopics.pop();
                break;
            }
        }
        topicExists[claimTopic] = false;

        emit ClaimTopicRemoved(claimTopic);
    }

    /**
     * @dev Get all required claim topics
     * @return Array of all required claim topics
     */
    function getClaimTopics() external view override returns (uint256[] memory) {
        return claimTopics;
    }
}
