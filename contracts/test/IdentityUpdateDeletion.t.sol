// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IdentityRegistry} from "src/registry/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "src/storage/IdentityRegistryStorage.sol";
import {TrustedIssuersRegistry} from "src/registries/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "src/registries/ClaimTopicsRegistry.sol";
import {Identity, IIdentity} from "src/identity/Identity.sol";
import {TREXToken} from "src/token/TREXToken.sol";
import {ModularCompliance} from "src/compliance/ModularCompliance.sol";

/**
 * @title IdentityUpdateDeletionTest
 * @dev Tests for identity update and deletion operations
 */
contract IdentityUpdateDeletionTest is Test {
    IdentityRegistry public identityRegistry;
    IdentityRegistryStorage public identityStorage;
    TrustedIssuersRegistry public trustedIssuers;
    ClaimTopicsRegistry public claimTopics;
    TREXToken public token;
    ModularCompliance public compliance;

    address public owner;
    address public user1;
    address public user2;
    address public attacker;
    IIdentity public identity1;
    IIdentity public identity2;

    uint16 public constant US_CODE = 840; // USA
    uint16 public constant FR_CODE = 250; // France

    event IdentityUpdated(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event IdentityRemoved(address indexed investorAddress, IIdentity indexed identity);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");

        // Deploy infrastructure contracts
        trustedIssuers = new TrustedIssuersRegistry();
        claimTopics = new ClaimTopicsRegistry();
        identityStorage = new IdentityRegistryStorage();

        identityRegistry = new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        // Bind registry to storage
        identityStorage.bindIdentityRegistry(address(identityRegistry));

        // Deploy compliance and token
        compliance = new ModularCompliance();
        token = new TREXToken("Security Token", "SEC", 18, address(identityRegistry), address(compliance), address(0));

        compliance.bindToken(address(token));

        // Setup identities
        identity1 = new Identity(user1);
        identity2 = new Identity(user2);

        // Register identities
        identityRegistry.registerIdentity(user1, identity1, US_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                         UPDATE IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateIdentity_Success() public {
        Identity newIdentity = new Identity(user1);

        vm.expectEmit(true, true, false, false);
        emit IdentityUpdated(identity1, newIdentity);

        identityRegistry.updateIdentity(user1, newIdentity);

        // Verify update
        assertEq(address(identityRegistry.identity(user1)), address(newIdentity));
        assertEq(identityRegistry.investorCountry(user1), US_CODE); // Country should remain unchanged
        assertTrue(identityRegistry.contains(user1));
    }

    function test_UpdateIdentity_PreservesCountry() public {
        Identity newIdentity = new Identity(user1);
        identityRegistry.updateCountry(user1, FR_CODE);

        identityRegistry.updateIdentity(user1, newIdentity);

        // Country should remain France after identity update
        assertEq(identityRegistry.investorCountry(user1), FR_CODE);
    }

    function test_UpdateIdentity_ByAgent() public {
        address agent = makeAddr("agent");
        identityRegistry.addAgent(agent);
        Identity newIdentity = new Identity(user1);

        vm.prank(agent);
        identityRegistry.updateIdentity(user1, newIdentity);

        assertEq(address(identityRegistry.identity(user1)), address(newIdentity));
    }

    function test_UpdateIdentity_RevertIf_NotRegistered() public {
        address unregistered = makeAddr("unregistered");
        Identity newIdentity = new Identity(unregistered);

        vm.expectRevert();
        identityRegistry.updateIdentity(unregistered, newIdentity);
    }

    function test_UpdateIdentity_RevertIf_ZeroAddress() public {
        vm.expectRevert();
        identityRegistry.updateIdentity(user1, IIdentity(address(0)));
    }

    function test_UpdateIdentity_RevertIf_NotOwnerOrAgent() public {
        Identity newIdentity = new Identity(user1);

        vm.prank(attacker);
        vm.expectRevert();
        identityRegistry.updateIdentity(user1, newIdentity);
    }

    /*//////////////////////////////////////////////////////////////
                         DELETE IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeleteIdentity_Success() public {
        vm.expectEmit(true, true, false, false);
        emit IdentityRemoved(user1, identity1);

        identityRegistry.deleteIdentity(user1);

        // Verify deletion
        assertEq(address(identityRegistry.identity(user1)), address(0));
        assertEq(identityRegistry.investorCountry(user1), 0);
        assertFalse(identityRegistry.contains(user1));
    }

    function test_DeleteIdentity_ByAgent() public {
        address agent = makeAddr("agent");
        identityRegistry.addAgent(agent);

        vm.prank(agent);
        identityRegistry.deleteIdentity(user1);

        assertFalse(identityRegistry.contains(user1));
    }

    function test_DeleteIdentity_RevertIf_NotRegistered() public {
        address unregistered = makeAddr("unregistered");

        vm.expectRevert();
        identityRegistry.deleteIdentity(unregistered);
    }

    function test_DeleteIdentity_RevertIf_NotOwnerOrAgent() public {
        vm.prank(attacker);
        vm.expectRevert();
        identityRegistry.deleteIdentity(user1);
    }

    // Note: Checking token balance in deleteIdentity would require circular dependency
    // between IdentityRegistry and TREXToken. This check should be handled at the
    // application layer before calling deleteIdentity.

    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_UpdateThenDelete() public {
        Identity newIdentity = new Identity(user1);

        // Update
        identityRegistry.updateIdentity(user1, newIdentity);
        assertEq(address(identityRegistry.identity(user1)), address(newIdentity));

        // Delete
        identityRegistry.deleteIdentity(user1);
        assertFalse(identityRegistry.contains(user1));
    }

    function test_Integration_DeleteAndReregister() public {
        // Delete
        identityRegistry.deleteIdentity(user1);
        assertFalse(identityRegistry.contains(user1));

        // Re-register with new identity
        Identity newIdentity = new Identity(user1);
        identityRegistry.registerIdentity(user1, newIdentity, FR_CODE);

        assertEq(address(identityRegistry.identity(user1)), address(newIdentity));
        assertEq(identityRegistry.investorCountry(user1), FR_CODE);
    }

    function test_Integration_MultipleUpdates() public {
        Identity id2 = new Identity(user1);
        Identity id3 = new Identity(user1);

        // First update
        identityRegistry.updateIdentity(user1, id2);
        assertEq(address(identityRegistry.identity(user1)), address(id2));

        // Second update
        identityRegistry.updateIdentity(user1, id3);
        assertEq(address(identityRegistry.identity(user1)), address(id3));

        // Country should still be preserved
        assertEq(identityRegistry.investorCountry(user1), US_CODE);
    }

    function test_Integration_UpdateDoesNotAffectTokens() public {
        // Mint tokens
        token.addAgent(address(this));
        token.mint(user1, 1000e18);

        uint256 balanceBefore = token.balanceOf(user1);

        // Update identity
        Identity newIdentity = new Identity(user1);
        identityRegistry.updateIdentity(user1, newIdentity);

        // Balance should be unchanged
        assertEq(token.balanceOf(user1), balanceBefore);
    }
}
