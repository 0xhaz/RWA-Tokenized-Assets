// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, Vm, console} from "forge-std/Test.sol";
import {ComplianceEventLogger} from "../../src/compliance/ComplianceEventLogger.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MaxHoldersModule} from "../../src/compliance/modules/MaxHoldersModule.sol";

contract ComplianceEventLoggerTest is Test {
    ComplianceEventLogger public logger;
    ModularCompliance public compliance;
    MaxHoldersModule public maxHoldersModule;

    address public token;
    address public owner;
    address public user1;
    address public user2;

    event ComplianceCheckPassed(
        address indexed from, address indexed to, uint256 amount, uint256 timestamp, string context
    );

    event ComplianceCheckFailed(
        address indexed from,
        address indexed to,
        uint256 amount,
        ComplianceEventLogger.ErrorCode errorCode,
        string reason,
        uint256 timestamp
    );

    event ComplianceModuleTriggered(
        address indexed module, address indexed from, address indexed to, uint256 amount, bool passed, uint256 timestamp
    );

    event TransferCompleted(address indexed from, address indexed to, uint256 amount, uint256 timestamp);

    event TokensCreated(address indexed to, uint256 amount, uint256 timestamp);

    event TokensDestroyed(address indexed from, uint256 amount, uint256 timestamp);

    event LoggingStatusChanged(bool enabled);

    function setUp() public {
        owner = address(this);
        token = makeAddr("token");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy compliance and bind token
        compliance = new ModularCompliance();
        compliance.bindToken(token);

        // Deploy module referencing compliance
        maxHoldersModule = new MaxHoldersModule(address(compliance));
        maxHoldersModule.setHolderLimit(100);
        maxHoldersModule.bindToken(token);

        // Add module to compliance
        compliance.addModule(address(maxHoldersModule));

        // Deploy logger wrapping compliance
        logger = new ComplianceEventLogger(address(compliance));
    }

    function test_Deployment() public {
        assertEq(address(logger.compliance()), address(compliance));
        assertEq(logger.loggingEnabled(), true);
    }

    function test_CanTransfer() public {
        bool result = logger.canTransfer(user1, user2, 50);
        assertEq(result, true);
    }

    function test_CheckAndLog_Pass() public {
        vm.expectEmit(true, true, false, true);
        emit ComplianceCheckPassed(user1, user2, 50, block.timestamp, "Test Context");

        bool result = logger.checkAndLog(user1, user2, 50, "Test Context");
        assertEq(result, true);
    }

    function test_CheckAndLog_Fail() public {
        // Set holder limit to 1 and register a holder to exceed limit
        maxHoldersModule.setHolderLimit(1);

        // Register user1 as a holder
        vm.prank(address(compliance));
        maxHoldersModule.created(user1, 100);

        vm.expectEmit(true, true, false, true);
        emit ComplianceCheckFailed(
            user1,
            user2,
            100,
            ComplianceEventLogger.ErrorCode.MODULE_REJECTION,
            "Transfer not compliant",
            block.timestamp
        );

        bool result = logger.checkAndLog(user1, user2, 100, "Test Context");
        assertEq(result, false);
    }

    function test_LogFailure() public {
        vm.expectEmit(true, true, false, true);
        emit ComplianceCheckFailed(
            user1,
            user2,
            100,
            ComplianceEventLogger.ErrorCode.IDENTITY_NOT_VERIFIED,
            "Identity not verified",
            block.timestamp
        );

        logger.logFailure(
            user1, user2, 100, ComplianceEventLogger.ErrorCode.IDENTITY_NOT_VERIFIED, "Identity not verified"
        );
    }

    function test_LogModuleCheck() public {
        vm.expectEmit(true, true, true, true);
        emit ComplianceModuleTriggered(address(maxHoldersModule), user1, user2, 50, true, block.timestamp);

        logger.logModuleCheck(address(maxHoldersModule), user1, user2, 50, true);
    }

    function test_Transferred() public {
        vm.expectEmit(true, true, false, true);
        emit TransferCompleted(user1, user2, 75, block.timestamp);

        vm.prank(token);
        logger.transferred(user1, user2, 75);
    }

    function test_Created() public {
        vm.expectEmit(true, false, false, true);
        emit TokensCreated(user1, 200, block.timestamp);

        vm.prank(token);
        logger.created(user1, 200);
    }

    function test_Destroyed() public {
        vm.expectEmit(true, false, false, true);
        emit TokensDestroyed(user2, 100 ether, block.timestamp);

        vm.prank(token);
        logger.destroyed(user2, 100 ether);
    }

    function test_SetLoggingEnabled() public {
        vm.expectEmit(false, false, false, true);
        emit LoggingStatusChanged(false);

        logger.setLoggingEnabled(false);
        assertFalse(logger.loggingEnabled());

        vm.expectEmit(false, false, false, true);
        emit LoggingStatusChanged(true);

        logger.setLoggingEnabled(true);
        assertTrue(logger.loggingEnabled());
    }

    function test_LoggingDisabled_NoEvents() public {
        logger.setLoggingEnabled(false);

        // Should not emit event when logging disabled
        vm.recordLogs();
        logger.checkAndLog(user1, user2, 100 ether, "test");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Only LoggingStatusChanged event should be present
        assertEq(entries.length, 0);
    }

    function test_LogFailure_RevertsWhenLoggingDisabled() public {
        logger.setLoggingEnabled(false);

        vm.expectRevert(ComplianceEventLogger.LoggingDisabled.selector);
        logger.logFailure(user1, user2, 100 ether, ComplianceEventLogger.ErrorCode.IDENTITY_NOT_VERIFIED, "test");
    }

    function test_SetLoggingEnabled_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        logger.setLoggingEnabled(false);
    }

    function test_GasBenchmark_WithLogging() public {
        uint256 gasBefore = gasleft();
        logger.checkAndLog(user1, user2, 100 ether, "test");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas with logging enabled", gasUsed);
    }

    function test_GasBenchmark_WithoutLogging() public {
        logger.setLoggingEnabled(false);

        uint256 gasBefore = gasleft();
        logger.checkAndLog(user1, user2, 100 ether, "test");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas with logging disabled", gasUsed);
    }
}
