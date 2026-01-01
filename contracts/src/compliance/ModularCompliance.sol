// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IComplianceModule} from "../interfaces/IComplianceModule.sol";

/**
 * @title ModularCompliance
 * @dev Base contract for modular compliance system
 * @notice Orchestrates multiple compliance modules and validates transfers
 */
contract ModularCompliance is Ownable {
    /// @dev Address of the bound token
    address private _tokenBound;

    /**
     * @dev Constructor sets the deployer as the initial owner
     */
    constructor() Ownable(msg.sender) {}

    /// @dev Array of active compliance modules
    address[] private _modules;

    /// @dev Mapping to track if a module is bound
    mapping(address => bool) private _moduleBound;

    /// @dev Custom errors for gas efficiency
    error TokenAlreadyBound();
    error TokenNotBound();
    error InvalidAddress();
    error ModuleAlreadyBound();
    error ModuleNotBound();
    error ModuleCheckFailed();
    error OnlyToken();

    /// @dev Events
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event TokenBound(address indexed token);
    event TokenUnbound(address indexed token);

    /**
     * @dev Modifier to restrict access to bound token only
     */
    modifier onlyToken() {
        if (msg.sender != _tokenBound) revert OnlyToken();
        _;
    }

    /**
     * @dev Bind a token to this compliance contract
     * @param _token Address of the token to bind
     */
    function bindToken(address _token) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();
        if (_tokenBound != address(0)) revert TokenAlreadyBound();

        _tokenBound = _token;
        emit TokenBound(_token);
    }

    /**
     * @notice Unbind the current token
     * @param _token Address of the token to unbind (must match current)
     */
    function unbindToken(address _token) external onlyOwner {
        if (_token != _tokenBound) revert TokenNotBound();

        _tokenBound = address(0);
        emit TokenUnbound(_token);
    }

    /**
     * @notice Add a compliance module
     * @param _module Address of the module to add
     */
    function addModule(address _module) external onlyOwner {
        if (_module == address(0)) revert InvalidAddress();
        if (_moduleBound[_module]) revert ModuleAlreadyBound();

        // Verify module is compatible
        if (!IComplianceModule(_module).moduleCheck(address(this))) {
            revert ModuleCheckFailed();
        }

        _modules.push(_module);
        _moduleBound[_module] = true;

        emit ModuleAdded(_module);
    }

    /**
     * @notice Remove a compliance module
     * @param _module Address of the module to remove
     */
    function removeModule(address _module) external onlyOwner {
        if (!_moduleBound[_module]) revert ModuleNotBound();

        // Remove from array
        for (uint256 i = 0; i < _modules.length; i++) {
            if (_modules[i] == _module) {
                _modules[i] = _modules[_modules.length - 1];
                _modules.pop();
                break;
            }
        }

        _moduleBound[_module] = false;

        emit ModuleRemoved(_module);
    }

    /**
     * @notice Check if a transfer is compliant
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view returns (bool) {
        // If no modules, allow transfer
        if (_modules.length == 0) {
            return true;
        }

        // Check all modules - all must approve
        for (uint256 i = 0; i < _modules.length; i++) {
            if (!IComplianceModule(_modules[i]).canTransfer(_from, _to, _amount)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Called after a successful transfer
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external onlyToken {
        // Notify all modules
        for (uint256 i = 0; i < _modules.length; i++) {
            IComplianceModule(_modules[i]).transferred(_from, _to, _amount);
        }
    }

    /**
     * @notice Called when tokens are created (minted)
     * @param _to Receiver address
     * @param _amount Amount created
     */
    function created(address _to, uint256 _amount) external onlyToken {
        // Notify all modules
        for (uint256 i = 0; i < _modules.length; i++) {
            IComplianceModule(_modules[i]).created(_to, _amount);
        }
    }

    /**
     * @notice Called when tokens are destroyed (burned)
     * @param _from Sender address
     * @param _amount Amount destroyed
     */
    function destroyed(address _from, uint256 _amount) external onlyToken {
        // Notify all modules
        for (uint256 i = 0; i < _modules.length; i++) {
            IComplianceModule(_modules[i]).destroyed(_from, _amount);
        }
    }

    /**
     * @notice Get the bound token address
     * @return Address of the bound token
     */
    function tokenBound() external view returns (address) {
        return _tokenBound;
    }

    /**
     * @notice Check if a module is bound
     * @param _module Address of the module to check
     * @return True if module is bound
     */
    function isModuleBound(address _module) external view returns (bool) {
        return _moduleBound[_module];
    }

    /**
     * @notice Get all bound modules
     * @return Array of module addresses
     */
    function getModules() external view returns (address[] memory) {
        return _modules;
    }
}
