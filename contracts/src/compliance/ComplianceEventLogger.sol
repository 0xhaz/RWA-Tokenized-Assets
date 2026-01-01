// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICompliance} from "../interfaces/ICompliance.sol";

/**
 * @title ComplianceEventLogger
 * @dev Enhanced compliance wrapper with comprehensive event logging for audit trails
 * @notice Wraps any ICompliance implementation to add detailed event logging
 */
contract ComplianceEventLogger is ICompliance, Ownable {
    /// @dev Error codes for compliance failures
    enum ErrorCode {
        NONE,
        IDENTITY_NOT_VERIFIED,
        HOLDER_LIMIT_EXCEEDED,
        BALANCE_LIMIT_EXCEEDED,
        COUNTRY_RESTRICTED,
        TIME_RESTRICTED,
        MODULE_REJECTION,
        PAUSED,
        FROZEN,
        CUSTOM
    }

    /// @dev The underlying compliance contract
    ICompliance public immutable compliance;

    /// @dev Enable/disable event logging
    bool public loggingEnabled;

    /// @dev Events for compliance checks
    event ComplianceCheckPassed(
        address indexed from, address indexed to, uint256 amount, uint256 timestamp, string context
    );

    event ComplianceCheckFailed(
        address indexed from, address indexed to, uint256 amount, ErrorCode errorCode, string reason, uint256 timestamp
    );

    event ComplianceModuleTriggered(
        address indexed module, address indexed from, address indexed to, uint256 amount, bool passed, uint256 timestamp
    );

    event TransferCompleted(address indexed from, address indexed to, uint256 amount, uint256 timestamp);

    event TokensCreated(address indexed to, uint256 amount, uint256 timestamp);

    event TokensDestroyed(address indexed from, uint256 amount, uint256 timestamp);

    event LoggingStatusChanged(bool enabled);

    /// @dev Errors
    error LoggingDisabled();

    /**
     * @dev Constructor
     * @param _compliance Address of the compliance contract to wrap
     */
    constructor(address _compliance) Ownable(msg.sender) {
        compliance = ICompliance(_compliance);
        loggingEnabled = true;
    }

    /**
     * @notice Enable or disable event logging
     * @param enabled True to enable logging, false to disable
     */
    function setLoggingEnabled(bool enabled) external onlyOwner {
        loggingEnabled = enabled;
        emit LoggingStatusChanged(enabled);
    }

    /**
     * @notice Check if a transfer is compliant with logging
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        return compliance.canTransfer(_from, _to, _amount);
    }

    /**
     * @notice Check compliance and emit detailed events
     * @param from Sender address
     * @param to Receiver address
     * @param amount Transfer amount
     * @param context Additional context for the transfer
     * @return True if transfer is compliant
     */
    function checkAndLog(address from, address to, uint256 amount, string calldata context) external returns (bool) {
        bool result = compliance.canTransfer(from, to, amount);

        if (loggingEnabled) {
            if (result) {
                emit ComplianceCheckPassed(from, to, amount, block.timestamp, context);
            } else {
                emit ComplianceCheckFailed(
                    from, to, amount, ErrorCode.MODULE_REJECTION, "Transfer not compliant", block.timestamp
                );
            }
        }
        return result;
    }

    /**
     * @notice Log compliance check failure with specific error code
     * @param from Sender address
     * @param to Receiver address
     * @param amount Transfer amount
     * @param errorCode Specific error code for failure
     * @param reason Human-readable reason for failure
     */
    function logFailure(
        address from,
        address to,
        uint256 amount,
        ErrorCode errorCode,
        string calldata reason
    ) external {
        if (!loggingEnabled) revert LoggingDisabled();

        emit ComplianceCheckFailed(from, to, amount, errorCode, reason, block.timestamp);
    }
    

    /**
     * @notice Log module evaluation
     * @param module Address of the compliance module
     * @param from Sender address
     * @param to Receiver address
     * @param amount Transfer amount
     * @param passed True if module approved the transfer
     */
    function logModuleCheck(address module, address from, address to, uint256 amount, bool passed) external {
        if (!loggingEnabled) revert LoggingDisabled();

        emit ComplianceModuleTriggered(module, from, to, amount, passed, block.timestamp);
    }

    /**
     * @notice Log completed transfer
     * @param _from Sender address
     * @param _to Receiver address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external override {
        if (loggingEnabled) {
            emit TransferCompleted(_from, _to, _amount, block.timestamp);
        }
    }

    /**
     * @notice Called when tokens are created
     * @param _to Receiver address
     * @param _amount Amount created
     */
    function created(address _to, uint256 _amount) external override {
        if (loggingEnabled) {
            emit TokensCreated(_to, _amount, block.timestamp);
        }
    }

    /**
     * @notice Called when tokens are destroyed
     * @param _from Address from which tokens were destroyed
     * @param _amount Amount destroyed
     */
    function destroyed(address _from, uint256 _amount) external override {
        if (loggingEnabled) {
            emit TokensDestroyed(_from, _amount, block.timestamp);
        }
    }

    /**
     * @notice Add a module to the underlying compliance contract
     * @param _module Address of the module to add
     */
    function addModule(address _module) external override onlyOwner {
        compliance.addModule(_module);
    }

    /**
     * @notice Remove a module from the underlying compliance
     * @param _module Module address
     */
    function removeModule(address _module) external override onlyOwner {
        compliance.removeModule(_module);
    }

    /**
     * @notice Unbind the token
     * @param _token Token address
     */
    function unbindToken(address _token) external override onlyOwner {
        compliance.unbindToken(_token);
    }

    /**
     * @notice Bind this compliance to a token
     * @dev This is a passthrough - the underlying compliance must already be bound
     * @param _token Token address
     */
    function bindToken(address _token) external view onlyOwner {
        // Verify underlying compliance is bound
        require(compliance.isTokenBound(_token), "Underlying compliance not bound");
    }

    /**
     * @notice Check if a module is bound
     * @param _module Module address
     * @return True if module is bound
     */
    function isModuleBound(address _module) external view override returns (bool) {
        return compliance.isModuleBound(_module);
    }

    /**
     * @notice Check if a token is bound
     * @param _token Token address
     * @return True if token is bound
     */
    function isTokenBound(address _token) external view override returns (bool) {
        return compliance.isTokenBound(_token);
    }
}
