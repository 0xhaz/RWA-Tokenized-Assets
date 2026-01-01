// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IComplianceModule} from "../../interfaces/IComplianceModule.sol";

interface IERC20Token {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title MaxBalanceModule
 * @dev Compliance module enforcing maximum token balance per investor
 * @notice Prevents transfers that would cause recipients to exceed configured limits
 */
contract MaxBalanceModule is IComplianceModule, Ownable {
    /// @dev Address of the bound compliance contract
    address private immutable _compliance;

    /// @dev Address of the bound token
    address private _token;

    /// @dev Maximum absolute balance allowed (0 = no limit)
    uint256 private _maxBalance;

    /// @dev Maximum percentage of total supply (in basis points, 0 = no limit)
    /// @notice 10_000 = 100%, 500 = 5%
    uint256 private _maxPercentage;

    /// @dev Basis points denominator
    uint16 private constant BASIS_POINTS = 10_000;

    /// @dev Custom errors
    error OnlyToken();
    error OnlyCompliance();
    error InvalidPercentage();

    /// @dev Events
    event MaxBalanceSet(uint256 maxBalance);
    event MaxPercentageSet(uint256 maxPercentage);

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
     * @notice Set the maximum absolute balance allowed
     * @param maxBalance Maximum balance (0 = no limit)
     */
    function setMaxBalance(uint256 maxBalance) external onlyOwner {
        _maxBalance = maxBalance;
        emit MaxBalanceSet(maxBalance);
    }

    /**
     * @notice Set the maximum percentage of total supply allowed
     * @param maxPercentage Maximum percentage in basis points (0-10_000, 0 = no limit)
     */
    function setMaxPercentage(uint256 maxPercentage) external onlyOwner {
        if (maxPercentage > BASIS_POINTS) revert InvalidPercentage();
        _maxPercentage = maxPercentage;
        emit MaxPercentageSet(maxPercentage);
    }

    /**
     * @notice Check if a transfer is compliant
     * @param _from Address sending tokens
     * @param _to Address receiving tokens
     * @param _amount Amount of tokens to transfer
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        // Zero amount transfers are always allowed
        if (_amount == 0) {
            return true;
        }

        // Transfer to self doesn't change balance
        if (_from == _to) {
            return true;
        }

        // Burn to zero address is allowed
        if (_to == address(0)) {
            return true;
        }

        // If no limits are set, allow transfer
        if (_maxBalance == 0 && _maxPercentage == 0) {
            return true;
        }

        // Get token interface
        IERC20Token token = IERC20Token(_token);

        // Calculate recipient's balance after transfer
        uint256 recipientBalance = token.balanceOf(_to);
        uint256 newBalance = recipientBalance + _amount;

        // Check absolute balance limit
        if (_maxBalance > 0) {
            if (newBalance > _maxBalance) {
                return false;
            }
        }

        // Check percentage limit
        if (_maxPercentage > 0) {
            uint256 totalSupply = token.totalSupply();

            // If total supply is 0, allow transfer (edge case)
            if (totalSupply > 0) {
                // Calculate max allowed balance based on percentage
                uint256 maxAllowedPercentage = (totalSupply * _maxPercentage) / BASIS_POINTS;

                if (newBalance > maxAllowedPercentage) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice Called after a successful transfer
     * @dev This module doesn't track state, so this is a no-op
     */
    function transferred(address, address, uint256) external pure override {
        // No state tracking needed
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
        if (msg.sender != _compliance && msg.sender != owner()) {
            revert OnlyCompliance();
        }
        _token = token;
    }

    /**
     * @notice Get the current maximum balance limit
     * @return Maximum absolute balance allowed
     */
    function maxBalance() external view returns (uint256) {
        return _maxBalance;
    }

    /**
     * @notice Get the current maximum percentage limit
     * @return Maximum percentage in basis points
     */
    function maxPercentage() external view returns (uint256) {
        return _maxPercentage;
    }
}
