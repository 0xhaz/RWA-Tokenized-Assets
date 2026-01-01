// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IComplianceModule} from "../../interfaces/IComplianceModule.sol";

/**
 * @title TimeRestrictionaModule
 * @dev Compliance module enforcing time-based transfer restrictions including lockups and vesting schedules
 * @notice Supports cliff vesting and gradual token unlocking over time
 */
contract TimeRestrictionsModule is IComplianceModule {
    /// @dev Lockup information for an investor
    struct LockupInfo {
        uint256 lockupEnd; // Timestamp when lockup ends
        uint256 cliffEnd; // Timestamp when cliff ends (for vesting)
        uint256 vestingDuration; // Total vesting duration in seconds
        uint256 vestingStart; // When vesting started (set when lockup is created)
    }

    /// @dev Compliance contract this module is bound to
    address public compliance;

    /// @dev Owner of the module
    address public owner;

    /// @dev Lockup infor per investor
    mapping(address => LockupInfo) public lockupInfo;

    /// @dev Total token balance per investor (for vesting calculations)
    mapping(address => uint256) private balances;

    /// @dev Custom errors
    error NotCompliance();
    error NotOwner();
    error InvalidLockupTime();
    error ZeroAddress();

    /// @dev Events
    event TokensLocked(address indexed investor, uint256 amount, uint256 releaseTime);
    event TokensUnlocked(address indexed investor, uint256 amount);
    event LockupSet(address indexed investor, uint256 lockupEnd, uint256 cliffEnd, uint256 vestingDuration);
    event ComplianceVBound(address indexed compliance);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyCompliance() {
        if (msg.sender != compliance) revert NotCompliance();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Bind this module to a compliance contract
     * @param _compliance Address of the compliance contract
     */
    function bindCompliance(address _compliance) external onlyOwner {
        if (_compliance == address(0)) revert ZeroAddress();
        compliance = _compliance;
        emit ComplianceVBound(_compliance);
    }

    /**
     * @dev Set lockup parameters for an investor
     * @param _investor Address of the investor
     * @param _lockupEnd Timestamp when lockup ends
     * @param _cliffEnd Timestamp when cliff ends (0 if no cliff)
     * @param _vestingDuration Duration of vesting in seconds (0 if no vesting)
     */
    function setLockup(address _investor, uint256 _lockupEnd, uint256 _cliffEnd, uint256 _vestingDuration)
        external
        onlyOwner
    {
        if (_lockupEnd <= block.timestamp) revert InvalidLockupTime();

        lockupInfo[_investor] = LockupInfo({
            lockupEnd: _lockupEnd, cliffEnd: _cliffEnd, vestingDuration: _vestingDuration, vestingStart: block.timestamp
        });

        emit LockupSet(_investor, _lockupEnd, _cliffEnd, _vestingDuration);
    }

    /**
     * @dev Check if a transfer is compliant with time restrictions
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        // Transfer to self is always allowed
        if (_from == _to) return true;

        // Zero amount is always allowed
        if (_amount == 0) return true;

        LockupInfo memory lockup = lockupInfo[_from];

        // No lockup set
        if (lockup.lockupEnd == 0) return true;

        // Check if still in lockup period
        if (block.timestamp < lockup.lockupEnd) {
            // If there's vesting or cliff, check unlocked balance
            if (lockup.vestingDuration > 0 || lockup.cliffEnd > 0) {
                uint256 unlockedBalance = _calculateUnlockedBalance(_from, lockup);
                return _amount <= unlockedBalance;
            }
            // Simple lockup - all tokens locked until lockup end
            return false;
        }
        // Lockup period over, transfer allowed
        return true;
    }

    /**
     * @dev Called after a successful transfer
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external override onlyCompliance {
        if (_from != address(0)) {
            balances[_from] -= _amount;
        }
        if (_to != address(0)) {
            balances[_to] += _amount;
        }
    }

    /**
     * @dev Called when tokens are created (minted)
     * @param _to Receiver address
     * @param _amount Amount minted
     */
    function created(address _to, uint256 _amount) external override onlyCompliance {
        balances[_to] += _amount;
    }

    /**
     * @dev Called when tokens are destroyed (burned)
     * @param _from Sender address
     * @param _amount Amount destroyed
     */
    function destroyed(address _from, uint256 _amount) external override onlyCompliance {
        balances[_from] -= _amount;
    }

    /**
     * @dev Check if module is bound to a compliance contract
     * @param _compliance Address of the compliance contract
     * @return True if module is bound to this compliance
     */
    function moduleCheck(address _compliance) external view override returns (bool) {
        return compliance == _compliance;
    }

    /**
     * @dev Get the unlocked balance for an investor
     * @param _investor Address of the investor
     * @return Amount of unlocked tokens
     */
    function getUnlockedBalance(address _investor) external view returns (uint256) {
        LockupInfo memory lockup = lockupInfo[_investor];
        return _calculateUnlockedBalance(_investor, lockup);
    }

    /**
     * @dev Get the total balance for an investor
     * @param _investor Address of the investor
     * @return Total token balance
     */
    function getTotalBalance(address _investor) external view returns (uint256) {
        return balances[_investor];
    }

    /**
     * @dev Calculate unlocked balance based o nvesting schedule
     * @param _investor Address of the investor
     * @param lockup Lockup information struct
     * @return Amount of unlocked tokens
     *
     * @notice Vesting caalculation logic:
     * - If cliff exists: vesting starts AFTER cliff ends
     * - If no cliff: vesting starts from vestingStart
     * - Tokens unlock linearly over vestingDuration
     * - Cliff gates all access until is passes
     */
    function _calculateUnlockedBalance(address _investor, LockupInfo memory lockup) private view returns (uint256) {
        uint256 totalBalances = balances[_investor];

        // No lockup
        if (lockup.lockupEnd == 0) return totalBalances;

        // After lockup end - everything unlocked
        if (block.timestamp >= lockup.lockupEnd) return totalBalances;

        // Before cliff - nothing unlocked
        if (lockup.cliffEnd > 0 && block.timestamp < lockup.cliffEnd) return 0;

        // No vesting duration means cliff only: after cliff, all tokens unlocked
        if (lockup.vestingDuration == 0) {
            // If we have a cliff and passed it, unlock all
            if (lockup.cliffEnd > 0 && block.timestamp >= lockup.cliffEnd) {
                return totalBalances;
            }
            // No cliff and no vesting - all or nothing based on lockupEnd
            return block.timestamp >= lockup.lockupEnd ? totalBalances : 0;
        }

        // Gradual vesting with two modes based on cliff + vesting relationship
        // Mode 1: If cliff + vesting fits within lockupEnd, vesting starts AFTER cliff
        // Mode 2: Otherwise, vesting accumulates from vestingStart, cliff just gates access

        uint256 vestingStartPoint;
        bool vestingAfterCliff = false;

        if (lockup.cliffEnd > 0) {
            // Check if vesting is designed to start after cliff
            // This happens when cliffEnd + vestingDuration <= lockupEnd
            if (lockup.cliffEnd + lockup.vestingDuration <= lockup.lockupEnd) {
                // Mode 1: Vesting starts after cliff enfs
                vestingStartPoint = lockup.cliffEnd;
                vestingAfterCliff = true;
            } else {
                // Mode 2: Vesting starts from vestingStart, cliff just blocks access
                vestingStartPoint = lockup.vestingStart;
            }
        } else {
            // No cliff, vesting starts from vestingStart
            vestingStartPoint = lockup.vestingStart;
        }

        // Calculate elapsed time since vesting started
        uint256 elapsedTime = block.timestamp - vestingStartPoint;

        // Special handling for cliff boundary in Mode 1:
        // At exactly cliffEnd, treat as 1 second elapsed to ensure non-zero unlock
        if (vestingAfterCliff && elapsedTime == 0 && block.timestamp >= lockup.cliffEnd) {
            elapsedTime = 1;
        }

        // Cap elapsed time at vestingDuration
        if (elapsedTime > lockup.vestingDuration) {
            elapsedTime = lockup.vestingDuration;
        }

        // Linear vesting: (elapsedTime / vestingDuration) * totalBalances
        uint256 unlockedAmount = (totalBalances * elapsedTime) / lockup.vestingDuration;

        // Safety: cap at totalBalances
        return unlockedAmount > totalBalances ? totalBalances : unlockedAmount;
    }
}
