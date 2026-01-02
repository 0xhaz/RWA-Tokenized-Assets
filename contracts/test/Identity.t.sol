// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Identity} from "../../src/identity/Identity.sol";
import {IIdentity} from "../../src/interfaces/IIdentity.sol";

contract IdentityTest is Test {
    Identity public identity;

    address public owner;
    address public claimIssuer;
    address public user1;
    address public user2;

    // Key purposes
    uint256 constant MANAGEMENT_KEY = 1;
    uint256 constant ACTION_KEY = 2;
    uint256 constant CLAIM_KEY = 3;
    uint256 constant ENCRYPTION_KEY = 4;

    // Key types
    uint256 constant ECDSA = 1;
    uint256 constant RSA = 2;

    // Claim topics
    uint256 constant KYC_TOPIC = 1;
    uint256 constant ACCREDITATION_TOPIC = 2;

    event KeyAdded(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event KeyRemoved(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRemoved(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    function setUp() public {
        owner = address(this);
        claimIssuer = makeAddr("claimIssuer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        identity = new Identity(owner);
    }

    /*//////////////////////////////////////////////////////////////
                          KEY MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsOwnerManagementKey() public {
        bytes32 ownerKey = keccak256(abi.encodePacked(owner));

        (uint256 purposes, uint256 keyType, bytes32 key) = identity.getKey(ownerKey);

        assertEq(purposes, MANAGEMENT_KEY);
        assertEq(keyType, ECDSA);
        assertEq(key, ownerKey);

        assertTrue(identity.keyHasPurpose(ownerKey, MANAGEMENT_KEY));
    }

    function test_AddKey_Success() public {
        bytes32 newKey = keccak256(abi.encodePacked(user1));

        vm.expectEmit(true, true, true, true);
        emit KeyAdded(newKey, ACTION_KEY, ECDSA);

        bool success = identity.addKey(newKey, ACTION_KEY, ECDSA);

        assertTrue(success);
        assertTrue(identity.keyHasPurpose(newKey, ACTION_KEY));

        (uint256 purposes, uint256 keyType, bytes32 key) = identity.getKey(newKey);
        assertEq(purposes, ACTION_KEY);
        assertEq(keyType, ECDSA);
        assertEq(key, newKey);
    }

    function test_AddKey_RevertIf_NotManagementKey() public {
        bytes32 newKey = keccak256(abi.encodePacked(user1));

        vm.prank(user2);
        vm.expectRevert();
        identity.addKey(newKey, ACTION_KEY, ECDSA);
    }

    function test_AddKey_AllowsDuplicatePurposes() public {
        bytes32 newKey = keccak256(abi.encodePacked(user1));

        identity.addKey(newKey, ACTION_KEY, ECDSA);

        // Adding the same key with different purpose should succeed
        bool success = identity.addKey(newKey, CLAIM_KEY, ECDSA);
        assertTrue(success);

        assertTrue(identity.keyHasPurpose(newKey, ACTION_KEY));
        assertTrue(identity.keyHasPurpose(newKey, CLAIM_KEY));
    }

    function test_RemoveKey_Success() public {
        bytes32 newKey = keccak256(abi.encodePacked(user1));

        identity.addKey(newKey, ACTION_KEY, ECDSA);

        vm.expectEmit(true, true, true, true);
        emit KeyRemoved(newKey, ACTION_KEY, ECDSA);

        bool success = identity.removeKey(newKey, ACTION_KEY);

        assertTrue(success);
        assertFalse(identity.keyHasPurpose(newKey, ACTION_KEY));
    }

    function test_RemoveKey_RevertIf_NotManagementKey() public {
        bytes32 newKey = keccak256(abi.encodePacked(user1));
        identity.addKey(newKey, ACTION_KEY, ECDSA);

        vm.prank(user2);
        vm.expectRevert();
        identity.removeKey(newKey, ACTION_KEY);
    }

    function test_GetKeysByPurpose_ReturnsCorrectKeys() public {
        bytes32 key1 = keccak256(abi.encodePacked(user1));
        bytes32 key2 = keccak256(abi.encodePacked(user2));

        identity.addKey(key1, ACTION_KEY, ECDSA);
        identity.addKey(key2, ACTION_KEY, ECDSA);

        bytes32[] memory actionKeys = identity.getKeysByPurpose(ACTION_KEY);

        assertEq(actionKeys.length, 2);
        assertTrue(actionKeys[0] == key1 || actionKeys[0] == key2);
        assertTrue(actionKeys[1] == key1 || actionKeys[1] == key2);
        assertTrue(actionKeys[0] != actionKeys[1]);
    }

    /*//////////////////////////////////////////////////////////////
                         CLAIM MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddClaim_Success() public {
        uint256 topic = KYC_TOPIC;
        uint256 scheme = ECDSA;
        bytes memory signature = "signature";
        bytes memory data = "data";
        string memory uri = "http://example.com/claim";

        vm.expectEmit(false, true, false, true);
        emit ClaimAdded(bytes32(0), topic, scheme, claimIssuer, signature, data, uri);

        bytes32 claimId = identity.addClaim(topic, scheme, claimIssuer, signature, data, uri);

        assertTrue(claimId != bytes32(0));

        (
            uint256 retTopic,
            uint256 retScheme,
            address retIssuer,
            bytes memory retSignature,
            bytes memory retData,
            string memory retUri
        ) = identity.getClaim(claimId);

        assertEq(retTopic, topic);
        assertEq(retScheme, scheme);
        assertEq(retIssuer, claimIssuer);
        assertEq(retSignature, signature);
        assertEq(retData, data);
        assertEq(retUri, uri);
    }

    function test_AddClaim_RevertIf_NotClaimKey() public {
        vm.prank(user2);
        vm.expectRevert();
        identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig", "data", "uri");
    }

    function test_AddClaim_IndexesByTopic() public {
        bytes32 claimId1 = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig1", "data1", "uri1");
        bytes32 claimId2 = identity.addClaim(KYC_TOPIC, ECDSA, user1, "sig2", "data2", "uri2");
        bytes32 claimId3 = identity.addClaim(ACCREDITATION_TOPIC, ECDSA, user2, "sig3", "data3", "uri3");

        bytes32[] memory kycClaims = identity.getClaimIdsByTopic(KYC_TOPIC);
        assertEq(kycClaims.length, 2);
        assertTrue(kycClaims[0] == claimId1 || kycClaims[0] == claimId2);
        assertTrue(kycClaims[1] == claimId1 || kycClaims[1] == claimId2);
        assertTrue(kycClaims[0] != kycClaims[1]);

        bytes32[] memory accreditationClaims = identity.getClaimIdsByTopic(ACCREDITATION_TOPIC);
        assertEq(accreditationClaims.length, 1);
        assertEq(accreditationClaims[0], claimId3);
    }

    function test_RemoveClaim_Success() public {
        bytes32 claimId = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig", "data", "uri");

        vm.expectEmit(false, true, false, true);
        emit ClaimRemoved(claimId, KYC_TOPIC, ECDSA, claimIssuer, "sig", "data", "uri");

        bool success = identity.removeClaim(claimId);

        assertTrue(success);

        // Verify claim is removed
        (uint256 topic,,,,,) = identity.getClaim(claimId);
        assertEq(topic, 0);
    }

    function test_RemoveClaim_RevertIf_NotManagementOrClaimKey() public {
        bytes32 claimId = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig", "data", "uri");

        vm.prank(user2);
        vm.expectRevert();
        identity.removeClaim(claimId);
    }

    function test_GetClaimIdsByTopic_ReturnsEmptyForNonExistent() public {
        bytes32[] memory claims = identity.getClaimIdsByTopic(999);
        assertEq(claims.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             EXECUTION TEST
    //////////////////////////////////////////////////////////////*/

    function test_Execute_Success() public {
        // Add action key for execution
        bytes32 actionKey = keccak256(abi.encodePacked(owner));

        address target = address(new MockTarget());
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        uint256 executionId = identity.execute(target, value, data);

        assertTrue(executionId > 0);
    }

    function test_Execute_RevertIf_NotActionOrManagementKey() public {
        vm.prank(user2);
        vm.expectRevert();
        identity.execute(address(1), 0, "");
    }

    function test_Approve_Success() public {
        address target = address(new MockTarget());
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        uint256 executionId = identity.execute(target, 0, data);

        bool success = identity.approve(executionId, true);
        assertTrue(success);
    }

    /*//////////////////////////////////////////////////////////////
                     EDGE CASES AND SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_AddClaim_DifferentInputs(uint256 topic, bytes memory data) public {
        vm.assume(topic > 0);

        bytes32 claimId = identity.addClaim(topic, ECDSA, claimIssuer, "sig", data, "uri");

        (uint256 retTopic,,,, bytes memory retData,) = identity.getClaim(claimId);

        assertEq(retTopic, topic);
        assertEq(retData, data);
        assertTrue(claimId != bytes32(0));
    }

    function test_ClaimId_IsUnique() public {
        bytes32 claimId1 = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig1", "data1", "uri");
        bytes32 claimId2 = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig2", "data2", "uri");

        assertTrue(claimId1 != claimId2);
    }

    function test_RemoveClaim_UpdatesTopicIndex() public {
        bytes32 claimId1 = identity.addClaim(KYC_TOPIC, ECDSA, claimIssuer, "sig1", "data1", "uri1");
        bytes32 claimId2 = identity.addClaim(KYC_TOPIC, ECDSA, user1, "sig2", "data2", "uri2");

        identity.removeClaim(claimId1);

        bytes32[] memory kycClaims = identity.getClaimIdsByTopic(KYC_TOPIC);
        assertEq(kycClaims.length, 1);
        assertEq(kycClaims[0], claimId2);
    }
}

// Mock contract for execution target
contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external payable {
        value = _value;
    }
}
