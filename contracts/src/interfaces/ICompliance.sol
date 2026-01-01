// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IComplianceModule} from "./IComplianceModule.sol";

/**
 * @title ICompliance
 * @dev Interface for modular compliance
 * @notice Orchestrates compliance modules to enforce transfer rules
 */
interface ICompliance {
    /*/////////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////////*/
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event TokenBound(address indexed token);
    event TokenUnbound(address indexed token);

    /**
     * @dev Add a compliance module
     * @param _module Address of the module to add
     */
    function addModule(address _module) external;

    /**
     * @dev Remove a compliance module
     * @param _module Address of the module to remove
     */
    function removeModule(address _module) external;

    /**
     * @dev Bind a token to this compliance contract
     * @param _token Address of the token to bind
     */
    function bindToken(address _token) external;

    /**
     * @dev Unbind a token from this compliance contract
     * @param _token Address of the token to unbind
     */
    function unbindToken(address _token) external;

    /**
     * @dev Check if a module is active
     * @param _module Address of the module
     * @return bool True if the module is active
     */
    function isModuleBound(address _module) external view returns (bool);

    /**
     * @dev Check if a token is bound
     * @param _token Address of the token
     * @return bool True if the token is bound
     */
    function isTokenBound(address _token) external view returns (bool);

    /**
     * @dev Check if a transfer is compliant across all modules
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     * @return bool True if transfer is compliant
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view returns (bool);

    /**
     * @dev Notify modules that a transfer occured
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external;

    /**
     * @dev Notify modules that tokens were minted
     * @param _to Receiver address
     * @param _amount Amount minted
     */
    function created(address _to, uint256 _amount) external;

    /**
     * @dev Notify all modules that tokens were burned
     * @param _from Address from which tokens were burned
     * @param _amount Amount burned
     */
    function destroyed(address _from, uint256 _amount) external;
}
