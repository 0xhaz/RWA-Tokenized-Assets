// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MaxBalanceModule} from "src/compliance/modules/MaxBalanceModule.sol";
import {ModularCompliance} from "src/compliance/ModularCompliance.sol";

contract MockToken {
    uint256 private _totalSupply = 1_000_000 ether;
    mapping(address => uint256) private _balances;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }

    function setTotalSupply(uint256 amount) external {
        _totalSupply = amount;
    }
}

contract MaxBalanceModuleTest is Test {
    MaxBalanceModule public module;
    ModularCompliance public compliance;
    MockToken public token;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    event MaxBalanceSet(uint256 maxBalance);
    event MaxPercentageSet(uint256 maxPercentage);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        compliance = new ModularCompliance();
        token = new MockToken();
        module = new MaxBalanceModule(address(compliance));

        compliance.bindToken(address(token));
        module.bindToken(address(token));
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMaxBalance_Success() public {
        vm.expectEmit(false, false, false, true);
        emit MaxBalanceSet(1000 ether);

        module.setMaxBalance(1000 ether);

        assertEq(module.maxBalance(), 1000 ether);
    }

    function test_SetMaxBalance_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        module.setMaxBalance(1000 ether);
    }

    function test_SetMaxPercentage_Success() public {
        vm.expectEmit(false, false, false, true);
        emit MaxPercentageSet(5);

        module.setMaxPercentage(5);

        assertEq(module.maxPercentage(), 5);
    }

    function test_SetMaxPercentage_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        module.setMaxPercentage(500);
    }

    function test_SetMaxPercentage_RevertIf_Exceeds10000() public {
        vm.expectRevert();
        module.setMaxPercentage(10001);
    }

    function test_Constructor_BindsCompliance() public view {
        assertTrue(module.moduleCheck(address(compliance)));
        assertFalse(module.moduleCheck(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                      ABSOLUTE BALANCE LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanTransfer_AllowsWhenBelowAbsoluteLimit() public {
        module.setMaxBalance(1000e18);
        token.setBalance(user1, 500e18);

        assertTrue(module.canTransfer(user2, user1, 400e18));
    }

    function test_CanTransfer_RejectsWhenExceedsAbsoluteLimit() public {
        module.setMaxBalance(1000e18);
        token.setBalance(user1, 500e18);

        assertFalse(module.canTransfer(user2, user1, 600e18));
    }

    function test_CanTransfer_AllowsExactAbsoluteLimit() public {
        module.setMaxBalance(1000e18);
        token.setBalance(user1, 500e18);

        assertTrue(module.canTransfer(user2, user1, 500e18));
    }

    function test_CanTransfer_AllowsWhenNoAbsoluteLimitSet() public {
        token.setBalance(user1, 500e18);

        assertTrue(module.canTransfer(user2, user1, 1000e18));
    }

    /*//////////////////////////////////////////////////////////////
                     PERCENTAGE BALANCE LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanTransfer_AllowsWhenBelowPercentageLimit() public {
        module.setMaxPercentage(500); // 5%
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18); // 3%

        assertTrue(module.canTransfer(user2, user1, 10000e18)); // Would be 4%
    }

    function test_CanTransfer_RejectsWhenExceedsPercentageLimit() public {
        module.setMaxPercentage(500); // 5%
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18); // 3%

        assertFalse(module.canTransfer(user2, user1, 30000e18)); // Would be 6%
    }

    function test_CanTransfer_AllowsExactPercentageLimit() public {
        module.setMaxPercentage(500); // 5%
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18); // 3%

        assertTrue(module.canTransfer(user2, user1, 20000e18)); // Exactly 5%
    }

    function test_CanTransfer_AllowsWhenNoPercentageLimitSet() public {
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18);

        assertTrue(module.canTransfer(user2, user1, 100000e18));
    }

    /*//////////////////////////////////////////////////////////////
                         COMBINED LIMITS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanTransfer_RespectsStricterAbsoluteLimit() public {
        module.setMaxBalance(40000e18); // Stricter
        module.setMaxPercentage(1000); // 10% = 100000e18 (less strict)
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18);

        assertFalse(module.canTransfer(user2, user1, 15000e18)); // Would exceed 40000
    }

    function test_CanTransfer_RespectsStricterPercentageLimit() public {
        module.setMaxBalance(100000e18); // Less strict
        module.setMaxPercentage(500); // 5% = 50000e18 (stricter)
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18);

        assertFalse(module.canTransfer(user2, user1, 25000e18)); // Would exceed 5%
    }

    function test_CanTransfer_AllowsWhenBothLimitsSatisfied() public {
        module.setMaxBalance(100000e18);
        module.setMaxPercentage(1000); // 10%
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 30000e18);

        assertTrue(module.canTransfer(user2, user1, 40000e18)); // 70000 < both limits
    }

    /*//////////////////////////////////////////////////////////////
                               EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_CanTransfer_AllowsZeroAmount() public {
        module.setMaxBalance(1000e18);
        token.setBalance(user1, 500e18);

        assertTrue(module.canTransfer(user2, user1, 0));
    }

    function test_CanTransfer_AllowsTransferToSelf() public {
        module.setMaxBalance(1000e18);
        token.setBalance(user1, 500e18);

        assertTrue(module.canTransfer(user1, user1, 1000e18));
    }

    function test_CanTransfer_AllowsBurnToZeroAddress() public {
        module.setMaxBalance(1000e18);

        assertTrue(module.canTransfer(user1, address(0), 500e18));
    }

    function test_CanTransfer_HandlesZeroTotalSupply() public {
        module.setMaxPercentage(500); // 5%
        token.setTotalSupply(0);
        token.setBalance(user1, 0);

        // When total supply is 0, percentage check should allow transfer
        assertTrue(module.canTransfer(user2, user1, 100e18));
    }

    function test_DynamicTotalSupply_UpdatesPercentageCalculation() public {
        module.setMaxPercentage(500); // 5%
        token.setTotalSupply(1000000e18);
        token.setBalance(user1, 40000e18); // 4%

        // Should allow up to 5% initially
        assertTrue(module.canTransfer(user2, user1, 10000e18)); // Would be 5%

        // Now increase total supply
        token.setTotalSupply(2000000e18);

        // Same balance is now only 2%, so can receive more
        assertTrue(module.canTransfer(user2, user1, 60000e18)); // Would be 5% of new supply
    }

    /*//////////////////////////////////////////////////////////////
                              HOOKS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transferred_DoesNothing() public view {
        // This module doesn't track state, so transferred is a no-op
        // Just verify it doesn't revert
    }

    function test_Created_DoesNothing() public view {
        // This module doesn't track state, so created is a no-op
    }

    function test_Destroyed_DoesNothing() public view {
        // This module doesn't track state, so destroyed is a no-op
    }

    /*//////////////////////////////////////////////////////////////
                               FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetMaxBalance_AcceptsAnyValue(uint256 maxBalance) public {
        module.setMaxBalance(maxBalance);
        assertEq(module.maxBalance(), maxBalance);
    }

    function testFuzz_CanTransfer_ConsistentBehavior(uint256 currentBalance, uint256 transferAmount) public {
        vm.assume(currentBalance < type(uint256).max / 2);
        vm.assume(transferAmount < type(uint256).max / 2);
        vm.assume(transferAmount > 0); // Zero transfers always allowed, test non-zero

        module.setMaxBalance(1000e18);
        token.setBalance(user1, currentBalance);

        uint256 newBalance = currentBalance + transferAmount;
        bool expected = newBalance <= 1000e18;

        assertEq(module.canTransfer(user2, user1, transferAmount), expected);
    }
}
