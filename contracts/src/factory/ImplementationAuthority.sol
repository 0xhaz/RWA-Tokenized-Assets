// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ImplementationAuthority
 * @dev Manages upgradeable contract implementations with owner-controlled authority
 */
contract ImplementationAuthority is Ownable {
    /// @dev Mapping of contract name hash to implementation address
    mapping(bytes32 => address) public implementation;

    /// @dev Mapping of contract name hash to version number
    mapping(bytes32 => uint256) public versions;

    /// @dev Events
    event ImplementationUpdated(bytes32 indexed name, address indexed implementation, uint256 version);

    /// @dev Custom errors
    error InvalidImplementation();
    error InvalidName();

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Sets implementation for a contract type
     * @param _name Contract name hash
     * @param _implementation Address of the new implementation
     */
    function setImplementation(bytes32 _name, address _implementation) external onlyOwner {
        if (_name == bytes32(0)) revert InvalidName();
        if (_implementation == address(0)) revert InvalidImplementation();

        versions[_name]++;
        implementation[_name] = _implementation;

        emit ImplementationUpdated(_name, _implementation, versions[_name]);
    }

    /**
     * @dev Gets implementation address for a contract type
     * @param _name Contract name hash
     * @return Address of the implementation
     */
    function getImplementation(bytes32 _name) external view returns (address) {
        return implementation[_name];
    }

    /**
     * @dev Gets version number for a contract type
     * @param _name Contract name hash
     * @return Version number
     */
    function getVersion(bytes32 _name) external view returns (uint256) {
        return versions[_name];
    }
}

