// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IComplianceModule} from "../../interfaces/IComplianceModule.sol";

interface IIdentityRegistry {
    function investorCountry(address _userAddress) external view returns (uint16);
}

/**
 * @title CountryRestrictionsModule
 * @dev Compliance module restricting transfers based on investor jurisdiction
 * @notice Uses whitelist and blacklist of country codes to control transfers
 */
contract CountryRestrictionsModule is IComplianceModule, Ownable {
    /// @dev Address of the bound compliance contract
    address private immutable _compliance;

    /// @dev Address of the bound token
    address private _token;

    /// @dev Address of the identity registry
    address private _identityRegistry;

    /// @dev Whitelist of allowed countries (0 == not whitelisted)
    mapping(uint16 => bool) private _whitelistedCountries;

    /// @dev Blacklist of restricted countries
    mapping(uint16 => bool) private _blacklistedCountries;

    /// @dev Track if any country has been whitelisted (to distinguish no whitelist vs empty whitelist)
    bool private _hasWhitelist;

    /// @dev Custom errors
    error OnlyToken();
    error OnlyCompliance();

    /// @dev Events
    event CountryWhitelisted(uint16 indexed countryCode);
    event CountryUnwhitelisted(uint16 indexed countryCode);
    event CountryBlacklisted(uint16 indexed countryCode);
    event CountryUnblacklisted(uint16 indexed countryCode);
    event IdentityRegistrySet(address indexed identityRegistry);

    /**
     * @dev Modifier to restrict access to bound token only
     */
    modifier onlyToken() {
        if (msg.sender != _token) revert OnlyToken();
        _;
    }

    /**
     * @dev Constructor binds to a specific compliance contract
     * @param compliance Address of the compliance contract
     */
    constructor(address compliance) Ownable(msg.sender) {
        _compliance = compliance;
    }

    /**
     * @notice Set the identity registry address
     * @param identityRegistry Address of the identity registry
     */
    function setIdentityRegistry(address identityRegistry) external onlyOwner {
        _identityRegistry = identityRegistry;
        emit IdentityRegistrySet(identityRegistry);
    }

    /**
     * @notice Add a country to the whitelist
     * @param country Country code to whitelist
     */
    function whitelistCountry(uint16 country) external onlyOwner {
        _whitelistedCountries[country] = true;
        _hasWhitelist = true;
        emit CountryWhitelisted(country);
    }

    /**
     * @notice Remove a country from the whitelist
     * @param country Country code to remove from whitelist
     */
    function unwhitelistCountry(uint16 country) external onlyOwner {
        _whitelistedCountries[country] = false;
        emit CountryUnwhitelisted(country);
    }

    /**
     * @notice Add a country to the blacklist
     * @param country Country code to blacklist
     */
    function blacklistCountry(uint16 country) external onlyOwner {
        _blacklistedCountries[country] = true;
        emit CountryBlacklisted(country);
    }

    /**
     * @notice Remove a country from the blacklist
     * @param country Country code to remove from blacklist
     */
    function unblacklistCountry(uint16 country) external onlyOwner {
        _blacklistedCountries[country] = false;
        emit CountryUnblacklisted(country);
    }

    /**
     * @notice Check if a transfer is compliant based on country restrictions
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        // Zero amount transfers are always allowed
        if (_amount == 0) {
            return true;
        }

        // Transfer to self is allowed
        if (_from == _to) {
            return true;
        }

        // Get identity registry
        if (_identityRegistry == address(0)) {
            // No identity registry set, allow transfer
            return true;
        }

        IIdentityRegistry registry = IIdentityRegistry(_identityRegistry);

        // Get country codes
        uint16 fromCountry = _from != address(0) ? registry.investorCountry(_from) : 0;
        uint16 toCountry = _to != address(0) ? registry.investorCountry(_to) : 0;

        // Check blacklist first (takes precedence)
        if (_blacklistedCountries[fromCountry] || _blacklistedCountries[toCountry]) {
            return false;
        }

        // Check whitelist if enabled
        if (_hasWhitelist) {
            // For mints (from zero address), only check recipient
            if (_from == address(0)) {
                return _whitelistedCountries[toCountry];
            }

            // For burns (to zero address), only check sender
            if (_to == address(0)) {
                return _whitelistedCountries[fromCountry];
            }

            // For regular transfers, check both sender and recipient
            return _whitelistedCountries[fromCountry] && _whitelistedCountries[toCountry];
        }

        return true;
    }

    /**
     * @dev Called after a successful transfer
     * @dev This module doesn't track state, so this is a no-op
     */
    function transferred(address _from, address _to, uint256 _amount) external pure override {
        // No state to update
    }

    /**
     * @notice Called when tokens are created (minted)
     * @dev This module doesn't track state, so this is a no-op
     */
    function created(address, uint256) external pure override {
        // No state tracking needed
    }

    /**
     * @notice Called when tokens are destroyed (burned)
     * @dev This module doesn't track state, so this is a no-op
     */
    function destroyed(address, uint256) external pure override {
        // No state tracking needed
    }

    /**
     * @notice Check if module is compatible with a compliance contract
     * @param compliance Address of the compliance contract
     * @return True if module is bound to this compliance
     */
    function moduleCheck(address compliance) external view override returns (bool) {
        return compliance == _compliance;
    }

    /**
     * @notice Bind this module to a token
     * @dev Called by the token or compliance contract
     * @param token Address of the token to bind
     */
    function bindToken(address token) external {
        if (msg.sender != _compliance && msg.sender != owner()) revert OnlyCompliance();
        _token = token;
    }

    /**
     * @notice Get the identity registry address
     * @return Address of the identity registry
     */
    function identityRegistry() external view returns (address) {
        return _identityRegistry;
    }

    /**
     * @notice Check if a country is whitelisted
     * @param country Country code to check
     * @return True if country is whitelisted
     */
    function isCountryWhitelisted(uint16 country) external view returns (bool) {
        return _whitelistedCountries[country];
    }

    /**
     * @notice Check if a country is blacklisted
     * @param country Country code to check
     * @return True if country is blacklisted
     */
    function isCountryBlacklisted(uint16 country) external view returns (bool) {
        return _blacklistedCountries[country];
    }
}
