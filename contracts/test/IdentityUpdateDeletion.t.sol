// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IdentityRegistry} from "src/registry/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "src/storage/IdentityRegistryStorage.sol";
import {TrustedIssuersRegistry} from "src/registries/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "src/registries/ClaimTopicsRegistry.sol";
import {Identity, IIdentity} from "src/identity/Identity.sol";
