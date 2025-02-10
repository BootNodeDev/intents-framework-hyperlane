// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract EnrollRouter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PK");

        address localRouter = vm.envAddress("ROUTER");
        address remoteRouter = vm.envAddress("REMOTE_ROUTER");
        uint256 chainId = vm.envUint("ENROLL_CHAIN");

        vm.startBroadcast(deployerPrivateKey);

        Hyperlane7683(localRouter).enrollRemoteRouter(uint32(chainId), TypeCasts.addressToBytes32(remoteRouter));

        vm.stopBroadcast();
    }
}
