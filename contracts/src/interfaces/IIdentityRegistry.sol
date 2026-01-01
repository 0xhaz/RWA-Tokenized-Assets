// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IIdentity.sol";
import "./IClaimIssuer.sol";
import "./ITrustedIssuersRegistry.sol";
import "./IClaimTopicsRegistry.sol";

interface IIdentityRegistryStorage {
    function storedIdentity(address _userAddress) external view returns (IIdentity);
    function storedInvestorCountry(address _userAddress) external view returns (uint16);
    function addIdentityToStorage(address _userAddress, IIdentity _identity, uint16 _country) external;
    function removeIdentityFromStorage(address _userAddress) external;
    function modifyStoredIdentity(address _userAddress, IIdentity _identity) external;
    function modifyStoredInvestorCountry(address _userAddress, uint16 _country) external;
}

/**
 * @title IIdentityRegistry
 * @dev Interface for the Identity Registry contract
 * @notice Links wallet addresses to ONCHAINID instances and verifies eligibility
 */
interface IIdentityRegistry {
    // Events
    event ClaimTopicsRegistrySet(address indexed claimTopicsRegistry);
    event IdentityStorageSet(address indexed identityStorage);
    event TrustedIssuersRegistrySet(address indexed trustedIssuersRegistry);
    event IdentityRegistered(address indexed investorAddress, IIdentity indexed identity);
    event IdentityRemoved(address indexed investorAddress, IIdentity indexed identity);
    event IdentityUpdated(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event CountryUpdated(address indexed investorAddress, uint16 indexed country);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    // Getters
    function identityStorage() external view returns (IIdentityRegistryStorage);
    function issuersRegistry() external view returns (ITrustedIssuersRegistry);
    function topicsRegistry() external view returns (IClaimTopicsRegistry);
    function isAgent(address _address) external view returns (bool);

    // Setters
    function setIdentityRegistryStorage(address _identityRegistryStorage) external;
    function setClaimTopicsRegistry(address _claimTopicsRegistry) external;
    function setTrustedIssuersRegistry(address _trustedIssuersRegistry) external;

    // Registry actions
    function registerIdentity(address _userAddress, IIdentity _identity, uint16 _country) external;
    function deleteIdentity(address _userAddress) external;
    function updateCountry(address _userAddress, uint16 _country) external;
    function updateIdentity(address _userAddress, IIdentity _identity) external;
    function batchRegisterIdentity(
        address[] calldata _userAddresses,
        IIdentity[] calldata _identities,
        uint16[] calldata _countries
    ) external;

    // Registry consultation
    function contains(address _userAddress) external view returns (bool);
    function isVerified(address _userAddress) external view returns (bool);
    function identity(address _userAddress) external view returns (IIdentity);
    function investorCountry(address _userAddress) external view returns (uint16);

    // Agent management
    function addAgent(address _agent) external;
    function removeAgent(address _agent) external;
}
