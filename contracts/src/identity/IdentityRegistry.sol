// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IIdentityRegistry, IIdentityRegistryStorage} from "../interfaces/IIdentityRegistry.sol";
import {IdentityRegistryStorage, IIdentity} from "../storage/IdentityRegistryStorage.sol";
import {ClaimTopicsRegistry} from "../registries/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../registries/TrustedIssuersRegistry.sol";
import {IClaimTopicsRegistry} from "../interfaces/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "../interfaces/ITrustedIssuersRegistry.sol";

/**
 * @title IdentityRegistry
 * @dev Min registry managing investor identities and verification
 */
contract IdentityRegistry is IIdentityRegistry, Ownable {
    IIdentityRegistryStorage public override identityStorage;
    IClaimTopicsRegistry public override topicsRegistry;
    ITrustedIssuersRegistry public override issuersRegistry;

    mapping(address => bool) private _agents;

    /**
     * @dev Constructor sets deployer as owner
     */
    constructor(address _identityRegistryStorage, address _claimTopicsRegistry, address _trustedIssuersRegistry)
        Ownable(msg.sender)
    {
        require(_trustedIssuersRegistry != address(0), "Invalid issuers registry");
        require(_claimTopicsRegistry != address(0), "Invalid topics registry");
        require(_identityRegistryStorage != address(0), "Invalid storage");

        topicsRegistry = IClaimTopicsRegistry(_claimTopicsRegistry);
        issuersRegistry = ITrustedIssuersRegistry(_trustedIssuersRegistry);
        identityStorage = IIdentityRegistryStorage(_identityRegistryStorage);
    }

    /**
     * @notice Register a new identity
     * @param _userAddress Address of the user
     * @param _identity ONCHAINID identity contract
     * @param _country Country code (ISO-3166)
     */
    function registerIdentity(address _userAddress, IIdentity _identity, uint16 _country) external override onlyOwner {
        identityStorage.addIdentityToStorage(_userAddress, _identity, _country);

        emit IdentityRegistered(_userAddress, _identity);
    }

    /**
     * @notice Update an existing identity
     * @param _userAddress Address of the user
     * @param _identity New ONCHAINID identity contract
     */
    function updateIdentity(address _userAddress, IIdentity _identity) external override onlyOwner {
        IIdentity oldId = identityStorage.storedIdentity(_userAddress);

        identityStorage.modifyStoredIdentity(_userAddress, _identity);

        emit IdentityUpdated(oldId, _identity);
    }

    /**
     * @notice Update the country of an existing identity
     * @param _userAddress Address of the user
     * @param _country New country code (ISO-3166)
     */
    function updateCountry(address _userAddress, uint16 _country) external override onlyOwner {
        identityStorage.modifyStoredInvestorCountry(_userAddress, _country);

        emit CountryUpdated(_userAddress, _country);
    }

    /**
     * @notice Delete an identity
     * @param _userAddress Address of the user
     */
    function deleteIdentity(address _userAddress) external override onlyOwner {
        IIdentity identityAddr = identityStorage.storedIdentity(_userAddress);
        identityStorage.removeIdentityFromStorage(_userAddress);

        emit IdentityRemoved(_userAddress, identityAddr);
    }

    /**
     * @notice Set the identity registry storage contract
     * @param _identityRegistryStorage Address of the identity registry storage contract
     */
    function setIdentityRegistryStorage(address _identityRegistryStorage) external override onlyOwner {
        identityStorage = IIdentityRegistryStorage(_identityRegistryStorage);

        emit IdentityStorageSet(_identityRegistryStorage);
    }

    /**
     * @notice Set the claim topics registry contract
     * @param _claimTopicsRegistry Address of the claim topics registry contract
     */
    function setClaimTopicsRegistry(address _claimTopicsRegistry) external override onlyOwner {
        topicsRegistry = IClaimTopicsRegistry(_claimTopicsRegistry);

        emit ClaimTopicsRegistrySet(_claimTopicsRegistry);
    }

    /**
     * @notice Set the trusted issuers registry contract
     * @param _trustedIssuersRegistry Address of the trusted issuers registry contract
     */
    function setTrustedIssuersRegistry(address _trustedIssuersRegistry) external override onlyOwner {
        issuersRegistry = ITrustedIssuersRegistry(_trustedIssuersRegistry);

        emit TrustedIssuersRegistrySet(_trustedIssuersRegistry);
    }

    /**
     * @notice Check if an investor is verified
     * @param _userAddress Address of the user
     * @return bool True if verified, false otherwise
     */
    function isVerified(address _userAddress) external view override returns (bool) {
        if (address(identityStorage.storedIdentity(_userAddress)) == address(0)) {
            return false;
        }

        IIdentity identityContract = identityStorage.storedIdentity(_userAddress);
        uint256[] memory requiredTopics = topicsRegistry.getClaimTopics();

        if (requiredTopics.length == 0) {
            return true;
        }

        for (uint256 i = 0; i < requiredTopics.length; i++) {
            bytes32[] memory claimIds = identityContract.getClaimIdsByTopic(requiredTopics[i]);

            if (claimIds.length == 0) {
                return false;
            }

            bool hasValidClaim = false;
            for (uint256 j = 0; j < claimIds.length; j++) {
                (uint256 topic,, address issuer,,,) = identityContract.getClaim(claimIds[j]);

                if (
                    topic == requiredTopics[i] && issuersRegistry.isTrustedIssuer(issuer)
                        && issuersRegistry.hasClaimTopic(issuer, requiredTopics[i])
                ) {
                    hasValidClaim = true;
                    break;
                }
            }

            if (!hasValidClaim) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Get the identity of a user
     * @param _userAddress Investor address
     * @return The ONCHAINID identity contract
     */
    function identity(address _userAddress) external view override returns (IIdentity) {
        return identityStorage.storedIdentity(_userAddress);
    }

    /**
     * @notice Get the country of a user
     * @param _userAddress Investor address
     * @return The country code
     */
    function investorCountry(address _userAddress) external view override returns (uint16) {
        return identityStorage.storedInvestorCountry(_userAddress);
    }

    /**
     * @notice Check if an identity is stored
     * @param _userAddress Address of the user
     * @return bool True if stored, false otherwise
     */
    function contains(address _userAddress) external view override returns (bool) {
        return address(identityStorage.storedIdentity(_userAddress)) != address(0);
    }

    /**
     * @notice Batch register identities
     * @param _userAddresses Addresses of the users
     * @param _identities ONCHAINID identity contracts
     * @param _countries Country codes (ISO-3166)
     */
    function batchRegisterIdentity(
        address[] calldata _userAddresses,
        IIdentity[] calldata _identities,
        uint16[] calldata _countries
    ) external override onlyOwner {
        require(
            _userAddresses.length == _identities.length && _userAddresses.length == _countries.length,
            "Input array lengths must match"
        );

        for (uint256 i = 0; i < _userAddresses.length; i++) {
            identityStorage.addIdentityToStorage(_userAddresses[i], _identities[i], _countries[i]);
            emit IdentityRegistered(_userAddresses[i], _identities[i]);
        }
    }

    function isAgent(address _agent) external view override returns (bool) {
        return _agents[_agent];
    }

    function addAgent(address _agent) external override onlyOwner {
        require(_agent != address(0), "Invalid agent address");
        require(!_agents[_agent], "Agent already added");
        _agents[_agent] = true;

        emit AgentAdded(_agent);
    }

    function removeAgent(address _agent) external override onlyOwner {
        require(_agents[_agent], "Agent does not exist");
        _agents[_agent] = false;

        emit AgentRemoved(_agent);
    }
}
