// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ComplianceModuleRegistry
 * @dev Registry for managing approved compliance modules
 * @notice Enables discovery and validation of available compliance modules
 */
contract ComplianceModuleRegistry is Ownable {
    /// @dev Module metadata structure
    struct ModuleInfo {
        string name;
        string version;
        string description;
        bool isActive;
    }

    /// @dev Mapping from module address to metadata
    mapping(address => ModuleInfo) private _modules;

    /// @dev Array of registered module addresses
    address[] private _moduleAddresses;

    /// @dev Mapping to track registered modules
    mapping(address => bool) private _registered;

    /// @dev Custom errors
    error InvalidAddress();
    error ModuleAlreadyRegistered();
    error ModuleNotRegistered();
    error EmptyName();
    error EmptyVersion();

    /// @dev Events
    event ModuleRegistered(address indexed module, string name, string version, string description);
    event ModuleDeregistered(address indexed module);
    event ModuleMetadataUpdated(address indexed module);

    /**
     * @dev Constructor sets deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new compliance module
     * @param module Addres of the module
     * @param name Name of the module
     * @param version Version of the module
     * @param description Description of the module
     */
    function registerModule(address module, string calldata name, string calldata version, string calldata description)
        external
        onlyOwner
    {
        if (module == address(0)) revert InvalidAddress();
        if (_registered[module]) revert ModuleAlreadyRegistered();
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(version).length == 0) revert EmptyVersion();

        _modules[module] = ModuleInfo({name: name, version: version, description: description, isActive: true});

        _moduleAddresses.push(module);
        _registered[module] = true;

        emit ModuleRegistered(module, name, version, description);
    }

    /**
     * @notice Deregister a compliance module
     * @param module Address of the module to deregister
     */
    function deregisterModule(address module) external onlyOwner {
        if (!_registered[module]) revert ModuleNotRegistered();

        // Remove from array
        uint256 length = _moduleAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            if (_moduleAddresses[i] == module) {
                _moduleAddresses[i] = _moduleAddresses[length - 1];
                _moduleAddresses.pop();
                break;
            }
        }

        // Mark as inactive and unregistered
        _modules[module].isActive = false;
        _registered[module] = false;

        emit ModuleDeregistered(module);
    }

    /**
     * @notice Update module metadata
     * @param module Address of the module
     * @param name New name of the module
     * @param version New version of the module
     * @param description New description of the module
     */
    function updateModuleMetadata(
        address module,
        string calldata name,
        string calldata version,
        string calldata description
    ) external onlyOwner {
        if (!_registered[module]) revert ModuleNotRegistered();

        _modules[module].name = name;
        _modules[module].version = version;
        _modules[module].description = description;

        emit ModuleMetadataUpdated(module);
    }

    /**
     * @notice Get module information
     * @param module Address of the module
     * @return name Name of the module
     * @return version Version of the module
     * @return description Description of the module
     * @return isActive Whether the module is active
     */
    function getModuleInfo(address module)
        external
        view
        returns (string memory name, string memory version, string memory description, bool isActive)
    {
        if (!_registered[module]) revert ModuleNotRegistered();

        ModuleInfo memory info = _modules[module];
        return (info.name, info.version, info.description, info.isActive);
    }

    /**
     * @notice Check if a module is registered
     * @param module Address of the module
     * @return True if module is registered
     */
    function isRegistered(address module) external view returns (bool) {
        return _registered[module];
    }

    /**
     * @notice Check if a module is approved (registered and active)
     * @param module Address of the module
     * @return True if module is approved
     */
    function isApprovedModule(address module) external view returns (bool) {
        return _registered[module] && _modules[module].isActive;
    }

    /**
     * @notice Get all registered module addresses
     * @return Array of module addresses
     */
    function getAllModules() external view returns (address[] memory) {
        return _moduleAddresses;
    }
}
