// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ComplianceExemption} from "../../src/compliance/ComplianceExemption.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MaxHoldersModule} from "../../src/compliance/modules/MaxHoldersModule.sol";

contract ComplianceExemptionTest is Test {
    ComplianceExemption public exemption;
    ModularCompliance public compliance;
    MaxHoldersModule public maxHoldersModule;

    address public owner;
    address public agent;
    address public user1;
    address public user2;
    address public token;

    event ExemptionAdded(address indexed account, address indexed module, uint256 expiryTime);
    event ExemptionRemoved(address indexed account, address indexed module);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    function setUp() public {
        owner = address(this);
        agent = makeAddr("agent");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        token = makeAddr("token");

        // Deploy compliance and bind token
        compliance = new ModularCompliance();
        exemption = new ComplianceExemption(address(compliance));
        maxHoldersModule = new MaxHoldersModule(address(compliance));

        maxHoldersModule.setHolderLimit(1);
        maxHoldersModule.bindToken(token);
        compliance.addModule(address(maxHoldersModule));
        compliance.bindToken(token);
    }

    function test_Deployment() public {
        assertEq(address(exemption.compliance()), address(compliance));
        assertFalse(exemption.isAgent(agent));
    }

    function test_AddAgent() public {
        vm.expectEmit(true, false, false, false);
        emit AgentAdded(agent);

        exemption.addAgent(agent);
        assertTrue(exemption.isAgent(agent));
    }

    function test_RemoveAgent() public {
        exemption.addAgent(agent);
        assertTrue(exemption.isAgent(agent));

        vm.expectEmit(true, false, false, false);
        emit AgentRemoved(agent);

        exemption.removeAgent(agent);
        assertFalse(exemption.isAgent(agent));
    }

    function test_AddAgent_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        exemption.addAgent(agent);
    }

    function test_AddGlobalExemption() public {
        vm.expectEmit(true, true, false, true);
        emit ExemptionAdded(user1, address(0), 0);

        exemption.addExemption(user1, address(0), 0);
        assertTrue(exemption.isExempt(user1, address(0)));
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
    }

    function test_AddModuleSpecificExemption() public {
        vm.expectEmit(true, true, false, true);
        emit ExemptionAdded(user1, address(maxHoldersModule), 0);

        exemption.addExemption(user1, address(maxHoldersModule), 0);
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
        assertFalse(exemption.isExempt(user1, address(0)));
    }

    function test_AddTimeLimitedExemption() public {
        uint256 expiryTime = block.timestamp + 1 days;

        vm.expectEmit(true, true, false, true);
        emit ExemptionAdded(user1, address(0), expiryTime);

        exemption.addExemption(user1, address(0), expiryTime);
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));

        // Fast forward past expiry
        vm.warp(expiryTime + 1);
        assertFalse(exemption.isExempt(user1, address(maxHoldersModule)));
    }

    function test_RemoveExemption() public {
        exemption.addExemption(user1, address(0), 0);

        vm.expectEmit(true, true, false, false);
        emit ExemptionRemoved(user1, address(0));

        exemption.removeExemption(user1, address(0));
        assertFalse(exemption.isExempt(user1, address(maxHoldersModule)));
    }

    function test_AddExemption_AgentAccess() public {
        exemption.addAgent(agent);

        vm.expectEmit(true, true, false, true);
        emit ExemptionAdded(user1, address(0), 0);

        vm.prank(agent);
        exemption.addExemption(user1, address(0), 0);
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
    }

    function test_AddExemption_OnlyOwnerOrAgent() public {
        vm.prank(user1);
        vm.expectRevert();
        exemption.addExemption(user2, address(0), 0);
    }

    function test_RemoveExemption_OnlyOwnerOrAgent() public {
        exemption.addExemption(user1, address(0), 0);

        vm.prank(user2);
        vm.expectRevert();
        exemption.removeExemption(user1, address(0));
    }

    function test_GlobalExemptionOverridesModuleSpecific() public {
        // Add module-specific exemption
        exemption.addExemption(user1, address(maxHoldersModule), 0);

        // Add global exemption
        exemption.addExemption(user1, address(0), 0);

        // Global should override
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
        assertTrue(exemption.isExempt(user1, address(0)));
    }

    function test_MultipleExemptions() public {
        exemption.addExemption(user1, address(0), 0);
        exemption.addExemption(user2, address(maxHoldersModule), 0);

        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
        assertTrue(exemption.isExempt(user2, address(maxHoldersModule)));
        assertFalse(exemption.isExempt(user2, address(0)));
    }

    function test_CanTransferWithExemption() public {
        // Add exemption
        exemption.addExemption(user1, address(0), 0);

        // Verify exemption works
        assertTrue(exemption.isExempt(user1, address(maxHoldersModule)));
        assertTrue(exemption.canTransferWithExemption(user1, user2, 100 ether));
    }

    function test_ExpiryTimeValidation() public {
        // Cannot set expiry at or before current time
        vm.warp(100); // Set timestamp to 100

        vm.expectRevert(ComplianceExemption.InvalidExpiryTime.selector);
        exemption.addExemption(user1, address(0), 99); // Past time

        vm.expectRevert(ComplianceExemption.InvalidExpiryTime.selector);
        exemption.addExemption(user1, address(0), 100); // Current time
    }

    function test_GetExemptionInfo() public {
        uint256 expiryTime = block.timestamp + 1 days;
        exemption.addExemption(user1, address(maxHoldersModule), expiryTime);

        (bool isExempt, uint256 expiry) = exemption.getExemptionInfo(user1, address(maxHoldersModule));
        assertTrue(isExempt);
        assertEq(expiry, expiryTime);
    }
}
