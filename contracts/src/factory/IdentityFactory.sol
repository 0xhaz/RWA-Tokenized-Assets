// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Identity} from "../identity/Identity.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IdentityFactory
 * @notice Factory contract for creating ONCHAINID Identity contracts
 * @dev Deploys minimal proxy clones of the Identity contract
 */
contract IdentityFactory is Ownable {
    /// @dev Events
    event IdentityCreated(address indexed identity, address indexed owner, bytes32 indexed salt);

    /// @dev Custom errors
    error IdentityCreationFailed();
    error InvalidOwner();

    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Creates a new identity contract for the specified owner
     * @param _owner Address of the identity owner
     * @param _salt Unique salt for deterministic deployment
     * @return identityAddress of the newly created identity contract
     */
    function createIdentity(address _owner, bytes32 _salt) external returns (address identityAddress) {
        if (_owner == address(0)) revert InvalidOwner();

        // Deploy a new Identity contract
        Identity identity = new Identity{salt: _salt}(_owner);
        identityAddress = address(identity);

        if (identityAddress == address(0)) revert IdentityCreationFailed();

        emit IdentityCreated(identityAddress, _owner, _salt);

        return identityAddress;
    }

    /**
     * @notice Predicts the address of an identity before deployment
     * @param _owner Address of the identity owner
     * @param _salt Unique salt for deterministic deployment
     * @return predicted The predicted address of the identity contract
     */
    function predictIdentityAddress(address _owner, bytes32 _salt) external view returns (address predicted) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(abi.encodePacked(type(Identity).creationCode, abi.encode(_owner)))
            )
        );

        return address(uint160(uint256(hash)));
    }
}
