// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

/**
 * @title TREXLib
 * @dev Library for minimal CREATE2 deployment without importing contracts
 */
library TREXLib {
    error DeploymentFailed();

    function deploy2(bytes32 salt, bytes memory bytecode) internal returns (address) {
        address deployed;
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
        return deployed;
    }
}
