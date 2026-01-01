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
        require(compliance.canTransfer(msg.sender, to, amount), "Transfer not compliant");
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
}
