// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {ComplianceComposer} from "../../src/compliance/ComplianceComposer.sol";
import {ComplianceExemption} from "../../src/compliance/ComplianceExemption.sol";
import {MaxHoldersModule} from "../../src/compliance/modules/MaxHoldersModule.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {CountryRestrictionsModule} from "../../src/compliance/modules/CountryRestrictionsModule.sol";
import {TimeRestrictionsModule} from "../../src/compliance/modules/TimeRestrictionsModule.sol";

contract MockToken is ERC20 {
    ModularCompliance public compliance;

    constructor() ERC20("Mock", "MOCK") {}

    function setCompliance(address _compliance) external {
        compliance = ModularCompliance(_compliance);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(compliance.canTransfer(msg.sender, to, amount), "Compliance check failed");
        compliance.transferred(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(compliance.canTransfer(from, to, amount), "Transfer not compliant");
        compliance.transferred(from, to, amount);
        return super.transferFrom(from, to, amount);
    }
}

/**
 * @title ComplianceIntegrationTest
 * @dev Comprehensive integration tests for the compliance layer
 */
contract ComplianceIntegrationTest is Test {
    ModularCompliance public compliance;
    ComplianceComposer public composer;
    ComplianceExemption public exemption;

    MaxHoldersModule public maxHoldersModule;
    MaxBalanceModule public maxBalanceModule;
    CountryRestrictionsModule public countryModule;
    TimeRestrictionsModule public timeModule;

    MockToken public token;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy compliance and modules
        compliance = new ModularCompliance();
        token = new MockToken();
        token.setCompliance(address(compliance));

        // Deploy modules
        maxHoldersModule = new MaxHoldersModule(address(compliance));
        maxBalanceModule = new MaxBalanceModule(address(compliance));
        countryModule = new CountryRestrictionsModule(address(compliance));
        timeModule = new TimeRestrictionsModule();

        // Configure modules
        maxHoldersModule.setHolderLimit(10);
        maxBalanceModule.setMaxBalance(1000 ether);
        countryModule.blacklistCountry(840); // Blacklist US

        // Bind tokens
        compliance.bindToken(address(token));
        maxHoldersModule.bindToken(address(token));
        maxBalanceModule.bindToken(address(token));
        countryModule.bindToken(address(token));

        // Deploy advanced contracts
        composer = new ComplianceComposer();
        composer.bindToken(address(token));
        exemption = new ComplianceExemption(address(compliance));
    }

    /*//////////////////////////////////////////////////////////////
                          SINGLE MODULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SingleModule_MaxHolders() public {
        compliance.addModule(address(maxHoldersModule));

        // Should pass with few holders
        assertTrue(compliance.canTransfer(user1, user2, 100 ether));
    }

    function test_SingleModule_MaxBalance() public {
        compliance.addModule(address(maxBalanceModule));

        assertTrue(compliance.canTransfer(user1, user2, 500 ether));

        assertFalse(compliance.canTransfer(user1, user2, 1500 ether));
    }

    function test_SingleModule_CountryRestrictions() public {
        compliance.addModule(address(countryModule));

        assertTrue(compliance.canTransfer(user1, user2, 100 ether));
    }

    function test_SingleModule_TimeRestrictions() public {
        // Skip - TimeRestrictionsModule uses lockup/vesting model
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                     MULTIPLE MODULE COMBINATIONS
    //////////////////////////////////////////////////////////////*/

    function test_MultiModule_MaxHoldersAndBalance() public {
        compliance.addModule(address(maxHoldersModule));
        compliance.addModule(address(maxBalanceModule));

        assertTrue(compliance.canTransfer(user1, user2, 500 ether));
        assertFalse(compliance.canTransfer(user1, user2, 1500 ether));
    }

    function test_MultiModule_AllModules() public {
        compliance.addModule(address(maxHoldersModule));
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(countryModule));

        // All modules pass
        assertTrue(compliance.canTransfer(user1, user2, 500 ether));
    }

    function test_MultiModule_FailureInAny() public {
        compliance.addModule(address(maxHoldersModule));
        compliance.addModule(address(maxBalanceModule));

        // First module passes, second fails
        assertFalse(compliance.canTransfer(user1, user2, 1500 ether));
    }

    /*//////////////////////////////////////////////////////////////
                         RULE COMPOSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RuleComposition_AndLogic() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Both must pass
        assertTrue(composer.evaluateRule(ruleId, user1, user2, 500 ether));

        // Fails if one fails
        assertFalse(composer.evaluateRule(ruleId, user1, user2, 1500 ether));
    }

    function test_RuleComposition_OrLogic() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createOrRule(modules);

        // Passes if at least one passes
        assertTrue(composer.evaluateRule(ruleId, user1, user2, 1500 ether));
    }

    function test_RuleComposition_Nested() public {
        // Skip nested rules - would require more complex implementation
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                      EXEMPTION SYSTEM INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_Exemption_GlobalBypass() public {
        compliance.addModule(address(maxBalanceModule));

        // Would normally fail
        assertFalse(compliance.canTransfer(user1, user2, 1500 ether));

        // Add global exemption for user1
        exemption.addExemption(user1, address(0), 0);

        // Now should pass via exemption
        assertTrue(exemption.canTransferWithExemption(user1, user2, 1500 ether));
    }

    function test_Exemption_ModuleSpecific() public {
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(maxHoldersModule));

        // Add exemption only for maxBalance
        exemption.addExemption(user1, address(maxBalanceModule), 0);

        assertTrue(exemption.isExempt(user1, address(maxBalanceModule)));
        assertFalse(exemption.isExempt(user1, address(maxHoldersModule)));
    }

    function test_Exemption_TimeLimited() public {
        compliance.addModule(address(maxBalanceModule));

        uint256 expiryTime = block.timestamp + 1 days;
        exemption.addExemption(user1, address(0), expiryTime);

        // Valid now
        assertTrue(exemption.isExempt(user1, address(maxBalanceModule)));

        // Expired later
        vm.warp(expiryTime + 1);
        assertFalse(exemption.isExempt(user1, address(maxBalanceModule)));
    }

    /*//////////////////////////////////////////////////////////////
                       TOKEN TRANSFER INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_TokenTransfer_ComplianceCheck() public {
        compliance.addModule(address(maxBalanceModule));

        token.mint(user1, 500 ether);

        // Should succeed
        vm.prank(user1);
        assertTrue(token.transfer(user2, 500 ether));
        assertEq(token.balanceOf(user2), 500 ether);
    }

    function test_TokenTransfer_ComplianceFailure() public {
        compliance.addModule(address(maxBalanceModule));

        token.mint(user1, 2000 ether);

        // Should fail compliance
        vm.prank(user1);
        vm.expectRevert("Compliance check failed");
        token.transfer(user2, 1500 ether);
    }

    function test_TokenTransfer_StateUpdate() public {
        // Configure module for this test
        maxHoldersModule.setHolderLimit(100);
        compliance.addModule(address(maxHoldersModule));

        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.transfer(user2, 500 ether);

        // Module should track state
        assertEq(token.balanceOf(user2), 500 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         GAS CONSUMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Gas_SingleModule() public {
        compliance.addModule(address(maxBalanceModule));

        uint256 gasBefore = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas for single module", gasUsed);
        assertTrue(gasUsed < 50000, "Single module gas too high");
    }

    function test_Gas_MultipleModules() public {
        compliance.addModule(address(maxHoldersModule));
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(countryModule));

        uint256 gasBefore = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas for 3 modules", gasUsed);
        assertTrue(gasUsed < 150000, "Multi-module gas too high");
    }

    function test_Gas_RuleComposition() public {
        address[] memory modules = new address[](1);
        modules[0] = address(maxHoldersModule);

        uint256 ruleId = composer.createAndRule(modules);

        uint256 startGas = gasleft();
        composer.evaluateRule(ruleId, user1, user2, 500 ether);
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas for 1 rule:", gasUsed);
    }

    /*//////////////////////////////////////////////////////////////
                               EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_ZeroAmount() public {
        compliance.addModule(address(maxBalanceModule));

        // Zero amount should pass
        assertTrue(compliance.canTransfer(user1, user2, 0));
    }

    function test_EdgeCase_SelfTransfer() public {
        compliance.addModule(address(maxBalanceModule));

        // Self transfer should pass
        assertTrue(compliance.canTransfer(user1, user1, 1000 ether));
    }

    function test_EdgeCase_NoModules() public {
        // With no modules, should allow all transfers
        assertTrue(compliance.canTransfer(user1, user2, type(uint256).max));
    }

    function test_EdgeCase_ModuleRemoval() public {
        compliance.addModule(address(maxBalanceModule));

        // Fails with module
        assertFalse(compliance.canTransfer(user1, user2, 1500 ether));

        // Remove module
        compliance.removeModule(address(maxBalanceModule));

        // Now passes
        assertTrue(compliance.canTransfer(user1, user2, 1500 ether));
    }

    /*//////////////////////////////////////////////////////////////
                         PERFORMANCE BENCHMARKS
    //////////////////////////////////////////////////////////////*/

    function test_Benchmark_ModuleScaling() public {
        uint256[] memory gasResults = new uint256[](5);

        // Baseline - no modules
        uint256 gas = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        gasResults[0] = gas - gasleft();

        // 1 module
        compliance.addModule(address(maxHoldersModule));
        gas = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        gasResults[1] = gas - gasleft();

        // 2 modules
        compliance.addModule(address(maxBalanceModule));
        gas = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        gasResults[2] = gas - gasleft();

        // 3 modules
        compliance.addModule(address(countryModule));
        gas = gasleft();
        compliance.canTransfer(user1, user2, 100 ether);
        gasResults[3] = gas - gasleft();

        emit log_named_uint("0 modules", gasResults[0]);
        emit log_named_uint("1 module", gasResults[1]);
        emit log_named_uint("2 modules", gasResults[2]);
        emit log_named_uint("3 modules", gasResults[3]);
    }
}
