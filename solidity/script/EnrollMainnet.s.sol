// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract EnrollMainnet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PK");

        vm.startBroadcast(deployerPrivateKey);

        Hyperlane7683(0x9245A985d2055CeA7576B293Da8649bb6C5af9D0).enrollRemoteRouter(1, TypeCasts.addressToBytes32(0x5F69f9aeEB44e713fBFBeb136d712b22ce49eb88));

        vm.stopBroadcast();
    }
}
