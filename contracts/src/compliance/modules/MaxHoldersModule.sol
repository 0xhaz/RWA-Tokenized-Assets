// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IComplianceModule} from "../../interfaces/IComplianceModule.sol";

/**
 * @title MaxHoldersModule
 * @dev Compliance module enforcing maximum number of token holders
 * @notice Prevents transfers that would exceed the configured holder limit
 */
contract MaxHoldersModule is IComplianceModule, Ownable {
    /// @dev Address of the bound compliance contract
    address private immutable _compliance;

    /// @dev Address of the bound token (retrieved from compliance)
    address private _token;

    /// @dev Maximum number of holders allowed
    uint256 private _holderLimit;

    /// @dev Current number of holders
    uint256 private _holderCount;

    /// @dev Mapping to track if an address is a holder
    mapping(address => bool) private _holders;

    /// @dev Custom errors
    error OnlyToken();
    error OnlyCompliance();

    /// @dev Events
    event HolderLimitSet(uint256 limit);
    event HolderAdded(address indexed holder);
    event HolderRemoved(address indexed holder);

    /**
     * @dev Modifier to restrict access to bound compliance only
     */
    modifier onlyCompliance() {
        if (msg.sender != _compliance) revert OnlyCompliance();
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
     * @notice Set the maximum number of holders
     * @param limit Maximum holder count (0 = no limit)
     */
    function setHolderLimit(uint256 limit) external onlyOwner {
        _holderLimit = limit;
        emit HolderLimitSet(limit);
    }

    /**
     * @notice Check if a transfer is compliant
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     * return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        // If no limit set, allow all transfers
        if (_holderCount == 0) {
            return true;
        }

        // Zero amount transfers are always allowed
        if (_amount == 0) {
            return true;
        }

        // Transfer to self doesn't change holder count
        if (_from == _to) {
            return true;
        }

        // If recipient is already a holder, transfer is allowed
        if (_holders[_to]) {
            return true;
        }

        // If recipient is zero address (burn), transfer is allowed
        if (_to == address(0)) {
            return true;
        }

        // Check if adding a new holder would exceed the limit
        return _holderCount < _holderLimit;
    }

    /**
     * @notice Called after a successful transfer
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external override onlyCompliance {
        _amount; // Silence unused parameter warning

        // Add recipient as holder if not already tracked and not zero address
        if (!_holders[_to] && _to != address(0)) {
            _holders[_to] = true;
            _holderCount++;
            emit HolderAdded(_to);
        }
    }

    /**
     * @notice Called when tokens are created (minted)
     * @param _to Receiver adddress
     * @param _amount Amount created
     */
    function created(address _to, uint256 _amount) external override onlyCompliance {
        _amount; // Silence unused parameter warning

        // Add recipient as holder if not already tracked
        if (!_holders[_to]) {
            _holders[_to] = true;
            _holderCount++;
            emit HolderAdded(_to);
        }
    }

    /**
     * @notice Called when tokens are destroyed (burned)
     * @param _from Burner adddress
     * @param _amount Amounts to be burn
     */
    function destroyed(address _from, uint256 _amount) external override onlyCompliance {
        _from; // Silence unused parameter warning
        _amount; // Silence unused parameter warning

        // Note: We don't remove holders on burn because we don't track individual balances
        // The token contract should handle removal when balance reaches zero
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
        if (msg.sender != _compliance && msg.sender != owner()) {
            revert OnlyCompliance();
        }
        _token = token;
    }

    /**
     * @notice Get the current holder limit
     * @return Maximum number of holders allowed
     */
    function holderLimit() external view returns (uint256) {
        return _holderLimit;
    }

    /**
     * @notice Get the current holder count
     * @return Current number of holders
     */
    function holderCount() external view returns (uint256) {
        return _holderCount;
    }

    /**
     * @notice Check if an address is a holder
     * @param holder Address to check
     * @return True if address is a holder
     */
    function isHolder(address holder) external view returns (bool) {
        return _holders[holder];
    }
}
