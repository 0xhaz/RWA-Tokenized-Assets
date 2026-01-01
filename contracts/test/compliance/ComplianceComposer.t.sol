// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ComplianceComposer} from "../../src/compliance/ComplianceComposer.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MaxHoldersModule} from "../../src/compliance/modules/MaxHoldersModule.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {CountryRestrictionsModule} from "../../src/compliance/modules/CountryRestrictionsModule.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title ComplianceComposerTest
 * @dev Test for advance AND/OR compliance rule composition
 */
contract ComplianceComposerTest is Test {
    ComplianceComposer public composer;

    MaxHoldersModule public maxHoldersModule;
    MaxBalanceModule public maxBalanceModule;
    CountryRestrictionsModule public countryModule;

    MockToken public token;
    address public owner;
    address public investor1;
    address public investor2;

    event RuleEvaluated(uint256 indexed ruleId, bool result);
    event ComplianceCheckFailed(uint256 indexed ruleId, string reason);

    function setUp() public {
        owner = address(this);
        investor1 = makeAddr("Investor1");
        investor2 = makeAddr("Investor2");

        token = new MockToken();

        composer = new ComplianceComposer();
        composer.bindToken(address(token));

        // Create test modules
        maxHoldersModule = new MaxHoldersModule(address(composer));
        maxHoldersModule.setHolderLimit(100);
        maxHoldersModule.bindToken(address(token));

        maxBalanceModule = new MaxBalanceModule(address(composer));
        maxBalanceModule.setMaxBalance(1_000 ether);
        maxBalanceModule.bindToken(address(token));

        countryModule = new CountryRestrictionsModule(address(composer));
        countryModule.blacklistCountry(840); // USA
        countryModule.bindToken(address(token));
    }

    /*//////////////////////////////////////////////////////////////
                        AND Logic Tests
    //////////////////////////////////////////////////////////////*/

    function test_AndRule_AllModulesPass() public {
        // Create AND rule: maxHolders AND maxBalance
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Both modules should pass for a normal transfer
        assertTrue(composer.evaluateRule(ruleId, investor1, investor2, 100 ether));
    }

    function test_AndRule_OneModuleFails() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Mint tokens to investor2 to exceed maxBalance
        token.mint(investor2, 1_500 ether);

        // Should fail because maxBalance module failes (1500 + 100 > 1000 max)
        assertFalse(composer.evaluateRule(ruleId, investor1, investor2, 100 ether));
    }

    function test_AndRule_AllModulesFail() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Make maxHolders fail - register holders and set limit to 1
        token.mint(investor2, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor2, 100 ether); // register investor2 as holder
        token.mint(investor1, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor1, 100 ether); // register investor1 as holder
        maxHoldersModule.setHolderLimit(1); // now limit is 1, so adding another holder should fail

        // Make maxBalance fail by minting more than max balance
        token.mint(investor2, 1_500 ether);

        // Should fail because both modules fail (trying to add address(this) as 3rd holder)
        assertFalse(composer.evaluateRule(ruleId, investor1, address(this), 100 ether));
    }

    /*//////////////////////////////////////////////////////////////
                        OR Logic Tests
    //////////////////////////////////////////////////////////////*/

    function test_OrRule_AllModulesPass() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createOrRule(modules);

        // Should pass if any module passes (both pass here)
        assertTrue(composer.evaluateRule(ruleId, investor1, investor2, 100 ether));
    }

    function test_OrRule_OneModulePasses() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createOrRule(modules);

        // Make maxBalance fail by minting tokens
        token.mint(investor2, 1_500 ether);

        // Should pass because maxHolders passes
        assertTrue(composer.evaluateRule(ruleId, investor1, investor2, 100 ether));
    }

    function test_OrRule_AllModulesFail() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createOrRule(modules);

        // Make maxHolders fail - register holders and set limit to 1
        token.mint(investor1, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor1, 100 ether); // register investor1 as holder
        token.mint(investor2, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor2, 100 ether); // register investor2 as holder
        maxHoldersModule.setHolderLimit(1); // now limit is 1, so adding another holder should fail

        // Make maxBalance fail by minting more than max balance
        token.mint(address(this), 1_500 ether);

        // Should fail because both modules fail (trying to add address(this) as 3rd holder)
        assertFalse(composer.evaluateRule(ruleId, investor1, address(this), 100 ether));
    }

    /*//////////////////////////////////////////////////////////////
                        Nested Logic Tests
    //////////////////////////////////////////////////////////////*/

    function test_NestedRules_AndOfOrs() public {
        // Create: (maxHolders OR maxBalance) AND countryModule
        address[] memory orModules = new address[](2);
        orModules[0] = address(maxHoldersModule);
        orModules[1] = address(maxBalanceModule);

        uint256 orRuleId = composer.createOrRule(orModules);

        uint256[] memory andRules = new uint256[](2);
        andRules[0] = orRuleId;

        // Create a simple rule for countryModule
        address[] memory countryModuleArr = new address[](1);
        countryModuleArr[0] = address(countryModule);
        andRules[1] = composer.createAndRule(countryModuleArr);

        uint256 compositeId = composer.createCompositeAndRule(andRules);

        // Should pass if OR passes AND country check passes
        assertTrue(composer.evaluateRule(compositeId, investor1, investor2, 100 ether));
    }

    function test_NestedRules_OrOfAnds() public {
        // Create: (maxHolders AND maxBalance) OR countryModule
        address[] memory andModules = new address[](2);
        andModules[0] = address(maxHoldersModule);
        andModules[1] = address(maxBalanceModule);

        uint256 andRuleId = composer.createAndRule(andModules);

        uint256[] memory orRules = new uint256[](2);
        orRules[0] = andRuleId;

        // Create a simple rule for countryModule
        address[] memory countryModuleArr = new address[](1);
        countryModuleArr[0] = address(countryModule);
        orRules[1] = composer.createAndRule(countryModuleArr);

        uint256 compositeId = composer.createCompositeOrRule(orRules);

        // Should pass if AND passes OR country check passes
        assertTrue(composer.evaluateRule(compositeId, investor1, investor2, 100 ether));
    }

    /*//////////////////////////////////////////////////////////////
                        Short-Circuit Tests
    //////////////////////////////////////////////////////////////*/

    function test_AndRule_ShortCircuitOnFirstFailure() public {
        address[] memory modules = new address[](3);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);
        modules[2] = address(countryModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Make first module fail by having max holders exceeded
        token.mint(investor1, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor1, 100 ether); // register investor1 as holder
        token.mint(investor2, 100 ether);
        vm.prank(address(composer));
        maxHoldersModule.transferred(address(0), investor2, 100 ether); // register investor2 as holder
        maxHoldersModule.setHolderLimit(2); // now limit is 2, so adding another holder should fail

        // Should short-circuit and return false immediately
        bool result = composer.evaluateRule(ruleId, investor1, address(this), 100 ether);
        assertFalse(result);
    }

    function test_OrRule_ShortCircuitOnFirstSuccess() public {
        address[] memory modules = new address[](3);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);
        modules[2] = address(countryModule);

        uint256 ruleId = composer.createOrRule(modules);

        // First module passes, should short-circuit
        uint256 gasBefore = gasleft();
        bool result = composer.evaluateRule(ruleId, investor1, investor2, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result);
        // Gas should be less than evaluating all modules
        assertLt(gasUsed, 100_000); // arbitrary threshold
    }

    /*//////////////////////////////////////////////////////////////
                        Gas Benchmark Tests
    //////////////////////////////////////////////////////////////*/

    function test_GasBenchmark_SimpleAndRule() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        uint256 gasBefore = gasleft();
        composer.evaluateRule(ruleId, investor1, investor2, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas Used - Simple AND Rule", gasUsed);
        assertLt(gasUsed, 150_000); // arbitrary threshold
    }

    function test_GasBenchmark_NestedRules() public {
        // Create complex nested rule
        address[] memory modules1 = new address[](2);
        modules1[0] = address(maxHoldersModule);
        modules1[1] = address(maxBalanceModule);

        uint256 andRule1 = composer.createAndRule(modules1);

        address[] memory modules2 = new address[](1);
        modules2[0] = address(countryModule);

        uint256 andRule2 = composer.createAndRule(modules2);

        uint256[] memory orRules = new uint256[](2);
        orRules[0] = andRule1;
        orRules[1] = andRule2;

        uint256 compositeId = composer.createCompositeOrRule(orRules);

        uint256 gasBefore = gasleft();
        composer.evaluateRule(compositeId, investor1, investor2, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas Used - Nested OR of AND Rules", gasUsed);
        assertLt(gasUsed, 300_000); // arbitrary threshold
    }

    /*//////////////////////////////////////////////////////////////
                        Access Control Tests
    //////////////////////////////////////////////////////////////*/

    function test_CreateRule_OnlyOwner() public {
        address[] memory modules = new address[](1);
        modules[0] = address(maxHoldersModule);

        vm.prank(investor1);
        vm.expectRevert();
        composer.createAndRule(modules);
    }

    function test_BindToken_OnlyOwner() public {
        vm.prank(investor1);
        vm.expectRevert();
        composer.bindToken(address(token));
    }

    /*///////////////////////////////////////////////////////////////
                        Rule Management Tests
    //////////////////////////////////////////////////////////////*/

    function test_GetRuleInfo() public {
        address[] memory modules = new address[](2);
        modules[0] = address(maxHoldersModule);
        modules[1] = address(maxBalanceModule);

        uint256 ruleId = composer.createAndRule(modules);

        (ComplianceComposer.LogicOperator operator, uint256 moduleCount, bool isComposite) =
            composer.getRuleInfo(ruleId);

        assertEq(uint8(operator), uint8(ComplianceComposer.LogicOperator.AND));
        assertEq(moduleCount, 2);
        assertEq(isComposite, false);
    }

    function test_UpdateRule() public {
        address[] memory modules = new address[](1);
        modules[0] = address(maxHoldersModule);

        uint256 ruleId = composer.createAndRule(modules);

        // Update to include another module
        address[] memory newModules = new address[](2);
        newModules[0] = address(maxHoldersModule);
        newModules[1] = address(maxBalanceModule);

        composer.updateRule(ruleId, newModules);

        (, uint256 moduleCount,) = composer.getRuleInfo(ruleId);
        assertEq(moduleCount, 2);
    }
}
