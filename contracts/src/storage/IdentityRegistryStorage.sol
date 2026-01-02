// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IIdentity} from "../interfaces/IIdentity.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IdentityRegistryStorage
 * @dev Storage contract for wallet-to-identity mappings
 * @notice Enables multiple identity registry contracts to share a common whitelist
 */
contract IdentityRegistryStorage is Ownable {
    /// @dev Mapping from wallet address to ONCHAINID identity
    mapping(address => IIdentity) private identities;

    /// @dev Mapping from wallet address to country code (ISO-3166)
    mapping(address => uint16) private countries;

    /// @dev Mapping of bound Identity Registry contracts
    mapping(address => bool) public identityRegistries;

    /// @dev Custom errors for gas efficiency
    error ZeroAddress();
    error RegistryAlreadyBound();
    error RegistryNotBound();
    error IdentityAlreadyStored();
    error IdentityNotStored();
    error OnlyBoundRegistry();

    /// @dev Events for state changes
    event IdentityStored(address indexed investorAddress, IIdentity indexed identity);
    event IdentityUnstored(address indexed investorAddress, IIdentity indexed identity);
    event IdentityModified(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event CountryModified(address indexed investorAddress, uint16 indexed country);
    event IdentityRegistryBound(address indexed identityRegistry);
    event IdentityRegistryUnbound(address indexed identityRegistry);

    /**
     * @dev Modifier to check if caller is a bound registry
     */
    modifier onlyBoundRegistry() {
        if (!identityRegistries[msg.sender]) revert OnlyBoundRegistry();
        _;
    }

    /**
     * @dev Constructor sets deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Bind an Identity Registry contract to this storage
     * @param _identityRegistry Address of the Identity Registry contract
     */
    function bindIdentityRegistry(address _identityRegistry) external onlyOwner {
        if (_identityRegistry == address(0)) revert ZeroAddress();
        if (identityRegistries[_identityRegistry]) revert RegistryAlreadyBound();

        identityRegistries[_identityRegistry] = true;

        emit IdentityRegistryBound(_identityRegistry);
    }

    /**
     * @dev Unbind an Identity Registry contract from this storage
     * @param _identityRegistry Address of the Identity Registry contract
     */
    function unbindIdentityRegistry(address _identityRegistry) external onlyOwner {
        if (!identityRegistries[_identityRegistry]) revert RegistryNotBound();

        identityRegistries[_identityRegistry] = false;

        emit IdentityRegistryUnbound(_identityRegistry);
    }

    /**
     * @dev Add an identity to storage
     * @param _userAddress Address of the user
     * @param _identity ONCHAINID Identity contract
     * @param _country Country code (ISO-3166)
     */
    function addIdentityToStorage(address _userAddress, IIdentity _identity, uint16 _country)
        external
        onlyBoundRegistry
    {
        if (_userAddress == address(0)) revert ZeroAddress();
        if (identities[_userAddress] != IIdentity(address(0))) revert IdentityAlreadyStored();

        identities[_userAddress] = _identity;
        countries[_userAddress] = _country;

        emit IdentityStored(_userAddress, _identity);
    }

    /**
     * @dev Remove an identity from storage
     * @param _userAddress Address of the user
     */
    function removeIdentityFromStorage(address _userAddress) external onlyBoundRegistry {
        IIdentity identity = identities[_userAddress];

        if (address(identity) == address(0)) revert IdentityNotStored();

        delete identities[_userAddress];
        delete countries[_userAddress];

        emit IdentityUnstored(_userAddress, identity);
    }

    /**
     * @dev Modify a stored identity
     * @param _userAddress Address of the user
     * @param _identity New ONCHAINID Identity contract
     */
    function modifyStoredIdentity(address _userAddress, IIdentity _identity) external onlyBoundRegistry {
        IIdentity oldIdentity = identities[_userAddress];

        if (address(oldIdentity) == address(0)) revert IdentityNotStored();

        identities[_userAddress] = _identity;

        emit IdentityModified(oldIdentity, _identity);
    }

    /**
     * @dev Modify the stored investor country
     * @param _userAddress Wallet address
     * @param _country New country code
     */
    function modifyStoredInvestorCountry(address _userAddress, uint16 _country) external onlyBoundRegistry {
        if (address(identities[_userAddress]) == address(0)) {
            revert IdentityNotStored();
        }

        countries[_userAddress] = _country;

        emit CountryModified(_userAddress, _country);
    }

    /**
     * @dev Get the stored identity for a wallet
     * @param _userAddress Wallet address
     * @return The ONCHAINID identity contract
     */
    function storedIdentity(address _userAddress) external view returns (IIdentity) {
        return identities[_userAddress];
    }

    /**
     * @dev Get the stored country for a wallet
     * @param _userAddress Wallet address
     * @return The country code
     */
    function storedInvestorCountry(address _userAddress) external view returns (uint16) {
        return countries[_userAddress];
    }
}
