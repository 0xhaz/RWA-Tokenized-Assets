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
}
