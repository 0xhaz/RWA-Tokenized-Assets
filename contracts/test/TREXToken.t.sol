// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TREXToken} from "../src/token/TREXToken.sol";
import {IdentityRegistry} from "src/registry/IdentityRegistry.sol";
import {ModularCompliance} from "src/compliance/ModularCompliance.sol";
import {Identity} from "src/identity/Identity.sol";
import {IdentityRegistryStorage} from "src/storage/IdentityRegistryStorage.sol";
import {TrustedIssuersRegistry} from "src/registries/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "src/registries/ClaimTopicsRegistry.sol";

contract TREXTokenTest is Test {
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);
    event TokensFrozen(address indexed userAddress, uint256 amount);
    event TokensUnfrozen(address indexed userAddress, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);
    event IdentityRegistryAdded(address indexed identityRegistry);
    event ComplianceAdded(address indexed compliance);

    TREXToken public token;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;

    address public owner;
    address public agent;
    address public user1;
    address public user2;
    address public onchainId;

    Identity public identity1;
    Identity public identity2;

    uint16 constant US_CODE = 840;

    function setUp() public {
        owner = address(this);
        agent = makeAddr("agent");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        onchainId = makeAddr("onchainId");

        // Deploy infrastructure
        TrustedIssuersRegistry trustedIssuers = new TrustedIssuersRegistry();
        ClaimTopicsRegistry claimTopics = new ClaimTopicsRegistry();
        IdentityRegistryStorage identityStorage = new IdentityRegistryStorage();

        identityRegistry = new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        // Bind identity registry to storage
        identityStorage.bindIdentityRegistry(address(identityRegistry));
        compliance = new ModularCompliance();

        // Deploy token
        token = new TREXToken("Security Token", "SEC", 18, address(identityRegistry), address(compliance), onchainId);

        // Bind compliance to token
        compliance.bindToken(address(token));

        // Setup identities
        identity1 = new Identity(user1);
        identity2 = new Identity(user2);

        // Register identities
        identityRegistry.registerIdentity(user1, identity1, US_CODE);
        identityRegistry.registerIdentity(user2, identity2, US_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deploy_Success() public view {
        assertEq(token.name(), "Security Token");
        assertEq(token.symbol(), "SEC");
        assertEq(token.decimals(), 18);
        assertEq(address(token.identityRegistry()), address(identityRegistry));
        assertEq(address(token.compliance()), address(compliance));
        assertEq(token.onchainId(), onchainId);
        assertEq(token.owner(), owner);
    }

    function test_Deploy_InitialSupplyZero() public {
        assertEq(token.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Owner_IsDeployer() public view {
        assertEq(token.owner(), owner);
    }

    function test_TransferOwnership_Success() public {
        vm.prank(owner);
        token.transferOwnership(agent);

        assertEq(token.owner(), agent);
    }

    /*//////////////////////////////////////////////////////////////
                            Agent Tests
    //////////////////////////////////////////////////////////////*/

    function test_AddAgent_Success() public {
        token.addAgent(agent);

        assertTrue(token.isAgent(agent));
    }

    function test_AddAgent_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.addAgent(agent);
    }

    function test_RemoveAgent_Success() public {
        token.addAgent(agent);

        token.removeAgent(agent);

        assertFalse(token.isAgent(agent));
    }

    function test_RemoveAgent_RevertIf_NotOwner() public {
        token.addAgent(agent);

        vm.prank(user1);
        vm.expectRevert();
        token.removeAgent(agent);
    }

    function test_IsAgent_ReturnsFalseForNonAgent() public view {
        assertFalse(token.isAgent(user1));
    }

    /*//////////////////////////////////////////////////////////////
                            Freeze Tests
    //////////////////////////////////////////////////////////////*/

    function test_SetAddressFrozen_Freeze() public {
        token.addAgent(agent);

        vm.prank(agent);
        token.setAddressFrozen(user1, true);

        assertTrue(token.isFrozen(user1));
    }

    function test_SetAddressFrozen_Unfreeze() public {
        token.addAgent(agent);

        vm.expectEmit(true, true, true, false);
        emit AddressFrozen(user1, true, agent);

        vm.prank(agent);
        token.setAddressFrozen(user1, true);

        assertTrue(token.isFrozen(user1));

        vm.expectEmit(true, true, true, false);
        emit AddressFrozen(user1, false, agent);

        vm.prank(agent);
        token.setAddressFrozen(user1, false);

        assertFalse(token.isFrozen(user1));
    }

    function test_SetAddressFrozen_RevertIf_NotAgent() public {
        vm.prank(user1);
        vm.expectRevert();
        token.setAddressFrozen(user2, true);
    }

    function test_FreezePartialTokens_Success() public {
        token.addAgent(agent);
        token.mint(user1, 1000e18);

        vm.expectEmit(true, false, false, true);
        emit TokensFrozen(user1, 500e18);

        vm.prank(agent);
        token.freezePartialTokens(user1, 500e18);

        assertEq(token.getFrozenTokens(user1), 500e18);
    }

    function test_FreezePartialTokens_RevertIf_NotAgent() public {
        vm.prank(user1);
        vm.expectRevert();
        token.freezePartialTokens(user2, 100e18);
    }

    function test_UnfreezePartialTokens_Success() public {
        token.addAgent(agent);
        token.mint(user1, 1000e18);

        vm.prank(agent);
        token.freezePartialTokens(user1, 500e18);

        vm.expectEmit(true, false, false, true);
        emit TokensUnfrozen(user1, 300e18);

        vm.prank(agent);
        token.unfreezePartialTokens(user1, 300e18);

        assertEq(token.getFrozenTokens(user1), 200e18);
    }

    function test_UnfreezePartialTokens_RevertIf_NotAgent() public {
        vm.prank(user1);
        vm.expectRevert();
        token.unfreezePartialTokens(user2, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                            Pause Tests
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Success() public {
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);

        token.pause();

        assertTrue(token.paused());
    }

    function test_Pause_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.pause();
    }

    function test_Unpause_Success() public {
        token.pause();

        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);

        token.unpause();

        assertFalse(token.paused());
    }

    function test_Unpause_RevertIf_NotOwner() public {
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            Burning Tests
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Success() public {
        token.mint(user1, 1000e18);
        token.addAgent(address(this));

        token.burn(user1, 500e18);

        assertEq(token.totalSupply(), 500e18);
        assertEq(token.balanceOf(user1), 500e18);
    }

    function test_Burn_RevertIf_NotAgent() public {
        token.mint(user1, 1000e18);

        vm.prank(user1);
        vm.expectRevert();
        token.burn(user1, 500e18);
    }

    function test_Burn_RevertIf_Paused() public {
        token.mint(user1, 1000e18);
        token.pause();

        vm.expectRevert();
        token.burn(user1, 500e18);
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetIdentityRegistry_Success() public {
        TrustedIssuersRegistry trustedIssuers = new TrustedIssuersRegistry();
        ClaimTopicsRegistry claimTopics = new ClaimTopicsRegistry();
        IdentityRegistryStorage identityStorage = new IdentityRegistryStorage();
        IdentityRegistry newRegistry =
            new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        vm.expectEmit(true, false, false, false);
        emit IdentityRegistryAdded(address(newRegistry));

        token.setIdentityRegistry(address(newRegistry));

        assertEq(address(token.identityRegistry()), address(newRegistry));
    }

    function test_SetIdentityRegistry_RevertIf_NotOwner() public {
        TrustedIssuersRegistry trustedIssuers = new TrustedIssuersRegistry();
        ClaimTopicsRegistry claimTopics = new ClaimTopicsRegistry();
        IdentityRegistryStorage identityStorage = new IdentityRegistryStorage();
        IdentityRegistry newRegistry =
            new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        vm.prank(user1);
        vm.expectRevert();
        token.setIdentityRegistry(address(newRegistry));
    }

    function test_SetCompliance_Success() public {
        ModularCompliance newCompliance = new ModularCompliance();
        newCompliance.bindToken(address(token));

        vm.expectEmit(true, false, false, false);
        emit ComplianceAdded(address(newCompliance));

        token.setCompliance(address(newCompliance));

        assertEq(address(token.compliance()), address(newCompliance));
    }

    function test_SetCompliance_RevertIf_NotOwner() public {
        ModularCompliance newCompliance = new ModularCompliance();

        vm.prank(user1);
        vm.expectRevert();
        token.setCompliance(address(newCompliance));
    }

    function test_SetOnchainID_Success() public {
        address newOnchainID = makeAddr("newOnchainID");

        token.setOnchainID(newOnchainID);

        assertEq(token.onchainId(), newOnchainID);
    }

    function test_SetOnchainID_RevertIf_NotOwner() public {
        address newOnchainID = makeAddr("newOnchainID");

        vm.prank(user1);
        vm.expectRevert();
        token.setOnchainID(newOnchainID);
    }

    function test_SetName_Success() public {
        vm.expectRevert("Name immutable");
        token.setName("New Token Name");
    }

    function test_SetSymbol_Success() public {
        vm.expectRevert("Symbol immutable");
        token.setSymbol("NEW");
    }

    /*//////////////////////////////////////////////////////////////
                          VERSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Version_ReturnsCorrectValue() public view {
        assertEq(token.version(), "1.0.0");
    }
}
