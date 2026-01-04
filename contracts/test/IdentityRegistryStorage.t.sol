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
}
