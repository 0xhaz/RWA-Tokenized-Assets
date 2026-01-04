// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/registry/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "../../src/storage/IdentityRegistryStorage.sol";
import {TrustedIssuersRegistry} from "../../src/registries/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "../../src/registries/ClaimTopicsRegistry.sol";
import {Identity, IIdentity} from "../../src/identity/Identity.sol";
import {IClaimIssuer} from "../../src/interfaces/IClaimIssuer.sol";

/**
 * @title MockClaimIssuer
 * @dev Simple mock claim issuer for testing - implments minimal IClaimIssuer interface
 */
contract MockClaimIssuer {
    function isClaimValid(IIdentity, uint256, bytes memory, bytes memory) external pure returns (bool) {
        return true;
    }

    function getRecoveredAddress(bytes calldata, bytes calldata) external pure returns (address) {
        return address(0);
    }

    function isClaimIssuer() external pure returns (bool) {
        return true;
    }

    function revokeClaim(bytes32) external pure returns (bool) {
        return true;
    }
}

/**
 * @title IdentityRegistryIntegrationTest
 * @dev Comprehensive integration tests for Identity Layer
 */
contract IdentityRegistryIntegrationTest is Test {
    IdentityRegistry public identityRegistry;
    IdentityRegistryStorage public identityStorage;
    TrustedIssuersRegistry public trustedIssuers;
    ClaimTopicsRegistry public claimTopics;

    MockClaimIssuer public issuer1;
    MockClaimIssuer public issuer2;

    address public owner;
    address public agent;
    address public investor1;
    address public investor2;
    address public investor3;

    Identity public identity1;
    Identity public identity2;
    Identity public identity3;

    uint256 constant CLAIM_TOPIC_KYC = 1;
    uint256 constant CLAIM_TOPIC_AML = 2;

    uint16 constant US_CODE = 840;
    uint16 constant FR_CODE = 250;
    uint16 constant DE_CODE = 276;

    function setUp() public {
        owner = address(this);
        agent = makeAddr("agent");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        investor3 = makeAddr("investor3");

        // Deploy core infrastructure
        trustedIssuers = new TrustedIssuersRegistry();
        claimTopics = new ClaimTopicsRegistry();
        identityStorage = new IdentityRegistryStorage();

        identityRegistry = new IdentityRegistry(address(trustedIssuers), address(claimTopics), address(identityStorage));

        // Bind registries in storage
        identityStorage.bindIdentityRegistry(address(identityRegistry));

        // Deploy claim issuers
        issuer1 = new MockClaimIssuer();
        issuer2 = new MockClaimIssuer();

        // Setup trusted issuers
        uint256[] memory topics1 = new uint256[](1);
        topics1[0] = CLAIM_TOPIC_KYC;
        trustedIssuers.addTrustedIssuer(IClaimIssuer(address(issuer1)), topics1);

        uint256[] memory topics2 = new uint256[](1);
        topics2[0] = CLAIM_TOPIC_AML;
        trustedIssuers.addTrustedIssuer(IClaimIssuer(address(issuer2)), topics2);

        // Setup required claim topics for countries
        claimTopics.addClaimTopic(CLAIM_TOPIC_KYC);
        claimTopics.addClaimTopic(CLAIM_TOPIC_AML);

        // Create identities for investors
        identity1 = new Identity(investor1);
        identity2 = new Identity(investor2);
        identity3 = new Identity(investor3);

        // Add agent
        identityRegistry.addAgent(agent);
    }

    /*//////////////////////////////////////////////////////////////
                   COMPLETE INVESTOR ONBOARDING FLOW
    //////////////////////////////////////////////////////////////*/

    function test_Integration_CompleteOnboardingFlow() public {
        // Step 1: Investor creates identity
        Identity newIdentity = identity1;

        // Step 1.5: Add issuer keys with CLAIM purpose (3)
        vm.prank(investor1);
        newIdentity.addKey(keccak256(abi.encodePacked(address(issuer1))), 3, 1);
        vm.prank(investor1);
        newIdentity.addKey(keccak256(abi.encodePacked(address(issuer2))), 3, 1);

        // Step 2: Issuers add claims to identity
        bytes memory kycData = "KYC_VERIFIED";
        vm.prank(address(issuer1));
        newIdentity.addClaim(
            CLAIM_TOPIC_KYC,
            1, // scheme
            address(issuer1),
            "",
            kycData,
            ""
        );

        bytes memory amlData = "AML_CLEARED";
        vm.prank(address(issuer2));
        newIdentity.addClaim(
            CLAIM_TOPIC_AML,
            1, // scheme
            address(issuer2),
            "",
            amlData,
            ""
        );

        // Step 3: Register identity in registry
        identityRegistry.registerIdentity(investor1, newIdentity, US_CODE);

        // Step 4: Verify registration
        assertTrue(identityRegistry.contains(investor1));
        assertEq(address(identityRegistry.identity(investor1)), address(newIdentity));
        assertEq(identityRegistry.investorCountry(investor1), US_CODE);

        // Step 5: Verify identity has required claims
        assertTrue(identityRegistry.isVerified(investor1));
    }

    function test_Integration_OnboardingFailsWithoutRequiredClaims() public {
        // Register identity without adding claims
        identityRegistry.registerIdentity(investor2, identity2, FR_CODE);

        // Should not be verified
        assertFalse(identityRegistry.isVerified(investor2));
    }

    /*//////////////////////////////////////////////////////////////
                 CLAIM VALIDATION WITH MULTIPLE ISSUERS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_MultipleIssuersValidation() public {
        // Add issuer keys
        vm.prank(investor1);
        identity1.addKey(keccak256(abi.encodePacked(address(issuer1))), 3, 1);
        vm.prank(investor1);
        identity1.addKey(keccak256(abi.encodePacked(address(issuer2))), 3, 1);

        // Add only KYC claim
        bytes memory kycData = "KYC_VERIFIED";
        vm.prank(address(issuer1));
        identity1.addClaim(
            CLAIM_TOPIC_KYC,
            1, // scheme
            address(issuer1),
            "",
            kycData,
            ""
        );

        // Add AML claim from second issuer
        bytes memory amlData = "AML_CLEARED";
        vm.prank(address(issuer2));
        identity1.addClaim(
            CLAIM_TOPIC_AML,
            1, // scheme
            address(issuer2),
            "",
            amlData,
            ""
        );

        // Register identity
        identityRegistry.registerIdentity(investor1, identity1, DE_CODE);

        // Verify identity is verified with claims from multiple issuers
        assertTrue(identityRegistry.isVerified(investor1));
    }

    function test_Integration_RevokedIssuerInvalidatesVerification() public {
        // Setup verified identity
        test_Integration_MultipleIssuersValidation();

        assertTrue(identityRegistry.isVerified(investor1));

        // Remove one of the trusted issuers
        trustedIssuers.removeTrustedIssuer(IClaimIssuer(address(issuer1)));

        // Should no longer be verified
        assertFalse(identityRegistry.isVerified(investor1));
    }

    /*//////////////////////////////////////////////////////////////
                IDENTITY UPDATES AND RECOVERY SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_IdentityUpdatePreservesVerification() public {
        // Setup verified identity
        test_Integration_MultipleIssuersValidation();
        assertTrue(identityRegistry.isVerified(investor1));

        // Create new identity with same claims
        Identity newIdentity = new Identity(investor1);

        // Add issuer keys to new identity
        vm.prank(investor1);
        newIdentity.addKey(keccak256(abi.encodePacked(address(issuer1))), 3, 1);
        vm.prank(investor1);
        newIdentity.addKey(keccak256(abi.encodePacked(address(issuer2))), 3, 1);

        bytes memory kycData = "KYC_VERIFIED";
        vm.prank(address(issuer1));
        newIdentity.addClaim(CLAIM_TOPIC_KYC, 1, address(issuer1), "", kycData, "");

        bytes memory amlData = "AML_CLEARED";
        vm.prank(address(issuer2));
        newIdentity.addClaim(CLAIM_TOPIC_AML, 1, address(issuer2), "", amlData, "");

        // Update identity
        identityRegistry.updateIdentity(investor1, newIdentity);

        // Should still be verified
        assertTrue(identityRegistry.isVerified(investor1));
        assertEq(address(identityRegistry.identity(investor1)), address(newIdentity));
    }

    function test_Integration_RecoveryMaintainsCountryAndVerification() public {
        // Setup verified identity
        test_Integration_MultipleIssuersValidation();

        uint16 originalCountry = identityRegistry.investorCountry(investor1);
        assertTrue(identityRegistry.isVerified(investor1));

        // Recover to new wallet
        address newWallet = makeAddr("newWallet");
        identityRegistry.recoverIdentity(investor1, newWallet);

        // New wallet should have same country and verification status
        assertEq(identityRegistry.investorCountry(newWallet), originalCountry);
        assertTrue(identityRegistry.isVerified(newWallet));

        // Old wallet should no longer exist
        assertFalse(identityRegistry.contains(investor1));
    }

    /*//////////////////////////////////////////////////////////////
             BATCH OPERATIONS WITH MIXED VALID/INVALID DATA
    //////////////////////////////////////////////////////////////*/

    function test_Integration_BatchRegistrationWithMixedData() public {
        address[] memory users = new address[](3);
        users[0] = investor1;
        users[1] = investor2;
        users[2] = investor3;

        IIdentity[] memory identities = new IIdentity[](3);
        identities[0] = identity1;
        identities[1] = identity2;
        identities[2] = identity3;

        uint16[] memory countries = new uint16[](3);
        countries[0] = US_CODE;
        countries[1] = FR_CODE;
        countries[2] = DE_CODE;

        identityRegistry.batchRegisterIdentity(users, identities, countries);

        // Verify all identities registered
        assertTrue(identityRegistry.contains(investor1));
        assertTrue(identityRegistry.contains(investor2));
        assertTrue(identityRegistry.contains(investor3));

        assertEq(identityRegistry.investorCountry(investor1), US_CODE);
        assertEq(identityRegistry.investorCountry(investor2), FR_CODE);
        assertEq(identityRegistry.investorCountry(investor3), DE_CODE);
    }

    function test_Integration_BatchCountryUpdate() public {
        // First batch register
        test_Integration_BatchRegistrationWithMixedData();

        address[] memory users = new address[](2);
        users[0] = investor1;
        users[1] = investor2;

        uint16[] memory newCountries = new uint16[](2);
        newCountries[0] = DE_CODE;
        newCountries[1] = US_CODE;

        identityRegistry.batchUpdateCountry(users, newCountries);

        assertEq(identityRegistry.investorCountry(investor1), DE_CODE);
        assertEq(identityRegistry.investorCountry(investor2), US_CODE);
        assertEq(identityRegistry.investorCountry(investor3), DE_CODE); // Unchanged
    }

    /*//////////////////////////////////////////////////////////////
                       AGENT DELEGATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_AgentCompleteWorkflow() public {
        // Agent registers investor
        vm.prank(agent);
        identityRegistry.registerIdentity(investor1, identity1, US_CODE);

        assertTrue(identityRegistry.contains(investor1));

        // Agent updates country
        vm.prank(agent);
        identityRegistry.updateCountry(investor1, FR_CODE);

        assertEq(identityRegistry.investorCountry(investor1), FR_CODE);

        // Agent creates new identity
        Identity newIdentity = new Identity(investor1);

        // Agent updates identity
        vm.prank(agent);
        identityRegistry.updateIdentity(investor1, newIdentity);

        assertEq(address(identityRegistry.identity(investor1)), address(newIdentity));

        // Agent recovers to new wallet
        address newWallet = makeAddr("newWallet");
        vm.prank(agent);
        identityRegistry.recoverIdentity(investor1, newWallet);

        assertTrue(identityRegistry.contains(newWallet));
        assertFalse(identityRegistry.contains(investor1));
    }

    function test_Integration_RevokedAgentCannotPerformActions() public {
        // Agent registers investor
        vm.prank(agent);
        identityRegistry.registerIdentity(investor1, identity1, US_CODE);

        // Owner removes agent
        identityRegistry.removeAgent(agent);

        // Agent cannot update country
        vm.prank(agent);
        vm.expectRevert();
        identityRegistry.updateCountry(investor1, FR_CODE);

        // Agent cannot delete
        vm.prank(agent);
        vm.expectRevert();
        identityRegistry.deleteIdentity(investor1);
    }

    /*//////////////////////////////////////////////////////////////
                   COUNTRY CODE COMPLIANCE FILTERING
    //////////////////////////////////////////////////////////////*/

    function test_Integration_CountryCodeFiltering() public {
        // Register investors from different countries
        identityRegistry.registerIdentity(investor1, identity1, US_CODE);
        identityRegistry.registerIdentity(investor2, identity2, FR_CODE);
        identityRegistry.registerIdentity(investor3, identity3, DE_CODE);

        // Verify country codes are correct
        assertEq(identityRegistry.investorCountry(investor1), US_CODE);
        assertEq(identityRegistry.investorCountry(investor2), FR_CODE);
        assertEq(identityRegistry.investorCountry(investor3), DE_CODE);

        // Update investor2 to US
        identityRegistry.updateCountry(investor2, US_CODE);

        // Now investor1 and investor2 are from US
        assertEq(identityRegistry.investorCountry(investor1), US_CODE);
        assertEq(identityRegistry.investorCountry(investor2), US_CODE);
        assertEq(identityRegistry.investorCountry(investor3), DE_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                     EDGE CASES AND ERROR SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_CannotRegisterTwice() public {
        identityRegistry.registerIdentity(investor1, identity1, US_CODE);

        Identity newIdentity = new Identity(investor1);
        vm.expectRevert();
        identityRegistry.registerIdentity(investor1, newIdentity, FR_CODE);
    }

    function test_Integration_CanReregisterAfterDeletion() public {
        // Register
        identityRegistry.registerIdentity(investor1, identity1, US_CODE);
        assertTrue(identityRegistry.contains(investor1));

        // Delete
        identityRegistry.deleteIdentity(investor1);
        assertFalse(identityRegistry.contains(investor1));

        // Re-register with different identity and country
        Identity newIdentity = new Identity(investor1);
        identityRegistry.registerIdentity(investor1, newIdentity, FR_CODE);

        assertTrue(identityRegistry.contains(investor1));
        assertEq(address(identityRegistry.identity(investor1)), address(newIdentity));
        assertEq(identityRegistry.investorCountry(investor1), FR_CODE);
    }

    function test_Integration_VerificationUpdatesWhenClaimTopicChanged() public {
        // Setup with KYC and AML claims
        test_Integration_MultipleIssuersValidation();
        assertTrue(identityRegistry.isVerified(investor1));

        // Add new required claim topic
        uint256 NEW_TOPIC = 3;
        claimTopics.addClaimTopic(NEW_TOPIC);

        // Should no longer be verified
        assertFalse(identityRegistry.isVerified(investor1));
    }
}
