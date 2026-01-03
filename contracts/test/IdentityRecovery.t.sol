// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IdentityRegistry} from "src/registry/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "src/storage/IdentityRegistryStorage.sol";
import {TrustedIssuersRegistry} from "src/registries/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "src/registries/ClaimTopicsRegistry.sol";
import {Identity, IIdentity} from "src/identity/Identity.sol";

/**
 * @title IdentityRecoveryTest
 * @dev Test suite for Identity Recovery functionality
 */
contract IdentityRecoveryTest is Test {
    IdentityRegistry public identityRegistry;
    IdentityRegistryStorage public identityStorage;
    TrustedIssuersRegistry public trustedIssuers;
    ClaimTopicsRegistry public claimTopics;

    address public owner;
    address public user1;
    address public newWallet;
    address public attacker;
    Identity public identity1;

    uint16 constant US_CODE = 840;

    event IdentityRecovered(address indexed oldWallet, address indexed newWallet, IIdentity indexed identity);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        newWallet = makeAddr("newWallet");
        attacker = makeAddr("attacker");

        // Deploy registries
        trustedIssuers = new TrustedIssuersRegistry();
        claimTopics = new ClaimTopicsRegistry();

        // Deploy identity storage
        identityStorage = new IdentityRegistryStorage();

        // Deploy identity registry
        identityRegistry = new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        // Bind registries in storage
        identityStorage.bindIdentityRegistry(address(identityRegistry));

        // Create identity for user1
        identity1 = new Identity(user1);
        identityRegistry.registerIdentity(user1, identity1, US_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                         RECOVERY SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecoverIdentity_Success() public {
        vm.expectEmit(true, true, true, false);
        emit IdentityRecovered(user1, newWallet, identity1);

        identityRegistry.recoverIdentity(user1, newWallet);

        // Old wallet should no longer have an identity
        assertEq(address(identityRegistry.identity(user1)), address(0));
        assertEq(identityRegistry.investorCountry(user1), 0);
        assertFalse(identityRegistry.contains(user1));

        // New wallet should have the identity
        assertEq(address(identityRegistry.identity(newWallet)), address(identity1));
        assertEq(identityRegistry.investorCountry(newWallet), US_CODE);
        assertTrue(identityRegistry.contains(newWallet));
    }

    function test_RecoverIdentity_ByAgent() public {
        address agent = makeAddr("agent");
        identityRegistry.addAgent(agent);

        vm.prank(agent);
        identityRegistry.recoverIdentity(user1, newWallet);

        // Verify recovery
        assertEq(address(identityRegistry.identity(newWallet)), address(identity1));
        assertFalse(identityRegistry.contains(user1));
    }

    /*//////////////////////////////////////////////////////////////
                         RECOVERY FAILURE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecoverIdentity_RevertIf_OldWalletNotRegistered() public {
        address unregistered = makeAddr("unregistered");

        vm.expectRevert();
        identityRegistry.recoverIdentity(unregistered, newWallet);
    }

    function test_RecoverIdentity_RevertIf_NewWalletAlreadyRegistered() public {
        address user2 = makeAddr("user2");
        Identity identity2 = new Identity(user2);
        identityRegistry.registerIdentity(user2, identity2, US_CODE);

        vm.expectRevert();
        identityRegistry.recoverIdentity(user1, user2);
    }

    function test_RecoverIdentity_RevertIf_NewWalletIsZero() public {
        vm.expectRevert();
        identityRegistry.recoverIdentity(user1, address(0));
    }

    function test_RecoverIdentity_RevertIf_NotOwnerOrAgent() public {
        vm.prank(attacker);
        vm.expectRevert();
        identityRegistry.recoverIdentity(user1, newWallet);
    }

    function test_RecoverIdentity_RevertIf_SameAddress() public {
        vm.expectRevert();
        identityRegistry.recoverIdentity(user1, user1);
    }

    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_RecoverAndRegisterAgain() public {
        // Recover to new wallet
        identityRegistry.recoverIdentity(user1, newWallet);

        // Old wallet should be free to register a new identity
        Identity newIdentity = new Identity(user1);
        identityRegistry.registerIdentity(user1, newIdentity, US_CODE);

        // Both should have different identities
        assertEq(address(identityRegistry.identity(user1)), address(newIdentity));
        assertEq(address(identityRegistry.identity(newWallet)), address(identity1));
    }

    function test_Integration_MultipleRecoveries() public {
        address wallet2 = makeAddr("wallet2");
        address wallet3 = makeAddr("wallet3");

        // First recovery
        identityRegistry.recoverIdentity(user1, newWallet);
        assertEq(address(identityRegistry.identity(newWallet)), address(identity1));

        // Second recovery from the recovered wallet
        identityRegistry.recoverIdentity(newWallet, wallet2);
        assertEq(address(identityRegistry.identity(wallet2)), address(identity1));
        assertFalse(identityRegistry.contains(newWallet));

        // Third recovery
        identityRegistry.recoverIdentity(wallet2, wallet3);
        assertEq(address(identityRegistry.identity(wallet3)), address(identity1));
        assertFalse(identityRegistry.contains(wallet2));
    }

    function test_Integration_RecoveryPreservesCountry() public {
        uint16 newCountry = 250; // France
        identityRegistry.updateCountry(user1, newCountry);

        identityRegistry.recoverIdentity(user1, newWallet);

        // Country should be preserved
        assertEq(identityRegistry.investorCountry(newWallet), newCountry);
    }
}

