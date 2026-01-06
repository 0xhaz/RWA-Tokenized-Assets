// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IdentityRegistryStorage} from "src/storage/IdentityRegistryStorage.sol";
import {IIdentity} from "src/interfaces/IIdentity.sol";

contract IdentityRegistryStorageTest is Test {
    IdentityRegistryStorage public storage_;

    address public owner;
    address public registry1;
    address public registry2;
    address public user1;
    address public user2;

    IIdentity public identity1;
    IIdentity public identity2;

    uint16 constant US_CODE = 840;
    uint16 constant UK_CODE = 826;
    uint16 constant INVALID_CODE = 999;

    event IdentityStored(address indexed investorAddress, IIdentity indexed identity);
    event IdentityUnstored(address indexed investorAddress, IIdentity indexed identity);
    event IdentityModified(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event CountryModified(address indexed investorAddress, uint16 indexed country);
    event IdentityRegistryBound(address indexed identityRegistry);
    event IdentityRegistryUnbound(address indexed identityRegistry);

    function setUp() public {
        owner = address(this);
        registry1 = makeAddr("registry1");
        registry2 = makeAddr("registry2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        identity1 = IIdentity(makeAddr("identity1"));
        identity2 = IIdentity(makeAddr("identity2"));

        storage_ = new IdentityRegistryStorage();
    }

    /*//////////////////////////////////////////////////////////////
                             BINDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BindIdentityRegistry_Success() public {
        vm.expectEmit(true, false, false, false);
        emit IdentityRegistryBound(registry1);

        storage_.bindIdentityRegistry(registry1);
        assertTrue(storage_.identityRegistries(registry1));
    }

    function test_BindIdentityRegistry_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        storage_.bindIdentityRegistry(registry1);
    }

    function test_BindIdentityRegistry_RevertIf_ZeroAddress() public {
        vm.expectRevert();
        storage_.bindIdentityRegistry(address(0));
    }

    function test_BindIdentityRegistry_RevertIf_AlreadyBound() public {
        storage_.bindIdentityRegistry(registry1);

        vm.expectRevert();
        storage_.bindIdentityRegistry(registry1);
    }

    function test_UnbindIdentityRegistry_Success() public {
        storage_.bindIdentityRegistry(registry1);

        vm.expectEmit(true, false, false, false);
        emit IdentityRegistryUnbound(registry1);

        storage_.unbindIdentityRegistry(registry1);

        assertFalse(storage_.identityRegistries(registry1));
    }

    function test_UnbindIdentityRegistry_RevertIf_NotOwner() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(user1);
        vm.expectRevert();
        storage_.unbindIdentityRegistry(registry1);
    }

    function test_UnbindIdentityRegistry_RevertIf_NotBound() public {
        vm.expectRevert();
        storage_.unbindIdentityRegistry(registry1);
    }

    /*//////////////////////////////////////////////////////////////
                           ADD IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddIdentityToStorage_Success() public {
        storage_.bindIdentityRegistry(registry1);

        vm.expectEmit(true, true, false, false);
        emit IdentityStored(user1, identity1);

        vm.prank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        assertEq(address(storage_.storedIdentity(user1)), address(identity1));
        assertEq(storage_.storedInvestorCountry(user1), US_CODE);
    }

    function test_AddIdentityToStorage_RevertIf_NotBoundRegistry() public {
        vm.prank(registry1);
        vm.expectRevert();
        storage_.addIdentityToStorage(user1, identity1, US_CODE);
    }

    function test_AddIdentityToStorage_RevertIf_ZeroAddress() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        vm.expectRevert();
        storage_.addIdentityToStorage(address(0), identity1, US_CODE);
    }

    function test_AddIdentityToStorage_RevertIf_IdentityExists() public {
        storage_.bindIdentityRegistry(registry1);

        vm.startPrank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        vm.expectRevert();
        storage_.addIdentityToStorage(user1, identity2, UK_CODE);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         REMOVE IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RemoveIdentityFromStorage_Success() public {
        storage_.bindIdentityRegistry(registry1);

        vm.startPrank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        vm.expectEmit(true, true, false, false);
        emit IdentityUnstored(user1, identity1);

        storage_.removeIdentityFromStorage(user1);
        vm.stopPrank();

        assertEq(address(storage_.storedIdentity(user1)), address(0));
        assertEq(storage_.storedInvestorCountry(user1), 0);
    }

    function test_RemoveIdentityFromStorage_RevertIf_NotBoundRegistry() public {
        vm.prank(registry1);
        vm.expectRevert();
        storage_.removeIdentityFromStorage(user1);
    }

    function test_RemoveIdentityFromStorage_RevertIf_IdentityNotFound() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        vm.expectRevert();
        storage_.removeIdentityFromStorage(user1);
    }

    /*//////////////////////////////////////////////////////////////
                         MODIFY IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ModifyStoredIdentity_Success() public {
        storage_.bindIdentityRegistry(registry1);

        vm.startPrank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        vm.expectEmit(true, true, false, false);
        emit IdentityModified(identity1, identity2);

        storage_.modifyStoredIdentity(user1, identity2);
        vm.stopPrank();

        assertEq(address(storage_.storedIdentity(user1)), address(identity2));
    }

    function test_ModifyStoredIdentity_RevertIf_NotBoundRegistry() public {
        vm.prank(registry1);
        vm.expectRevert();
        storage_.modifyStoredIdentity(user1, identity2);
    }

    function test_ModifyStoredIdentity_RevertIf_IdentityNotFound() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        vm.expectRevert();
        storage_.modifyStoredIdentity(user1, identity2);
    }

    /*//////////////////////////////////////////////////////////////
                          MODIFY COUNTRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ModifyStoredInvestorCountry_Success() public {
        storage_.bindIdentityRegistry(registry1);

        vm.startPrank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        vm.expectEmit(true, true, false, false);
        emit CountryModified(user1, UK_CODE);

        storage_.modifyStoredInvestorCountry(user1, UK_CODE);
        vm.stopPrank();

        assertEq(storage_.storedInvestorCountry(user1), UK_CODE);
    }

    function test_ModifyStoredInvestorCountry_RevertIf_NotBoundRegistry() public {
        vm.prank(registry1);
        vm.expectRevert();
        storage_.modifyStoredInvestorCountry(user1, UK_CODE);
    }

    function test_ModifyStoredInvestorCountry_RevertIf_IdentityNotFound() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        vm.expectRevert();
        storage_.modifyStoredInvestorCountry(user1, UK_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                          MULTI-REGISTRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleRegistries_CanAccessSameStorage() public {
        storage_.bindIdentityRegistry(registry1);
        storage_.bindIdentityRegistry(registry2);

        vm.prank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        vm.prank(registry2);
        storage_.modifyStoredInvestorCountry(user1, UK_CODE);

        assertEq(storage_.storedInvestorCountry(user1), UK_CODE);
    }

    function test_UnboundRegistry_CannotAccess() public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        storage_.addIdentityToStorage(user1, identity1, US_CODE);

        storage_.unbindIdentityRegistry(registry1);

        vm.prank(registry1);
        vm.expectRevert();
        storage_.modifyStoredInvestorCountry(user1, UK_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                               EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testFuzz_AddIdentity_DifferentCountries(uint16 countryCode) public {
        storage_.bindIdentityRegistry(registry1);

        vm.prank(registry1);
        storage_.addIdentityToStorage(user1, identity1, countryCode);

        assertEq(storage_.storedInvestorCountry(user1), countryCode);
    }

    function test_StoredIdentity_ReturnsZeroForNonExistent() public view {
        assertEq(address(storage_.storedIdentity(user1)), address(0));
        assertEq(storage_.storedInvestorCountry(user1), 0);
    }
}
