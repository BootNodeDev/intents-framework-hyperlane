// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { GasRouter } from "@hyperlane-xyz/client/GasRouter.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract EnrollRouter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("OWNER_PK");

        address localRouter = vm.envAddress("ROUTER");
        address[] memory routers = vm.envAddress("REMOTE_ROUTERS", ",");
        uint256[] memory domains = vm.envUint("ENROLL_CHAINS", ",");
        uint256[] memory gasDomains = vm.envUint("GAS_BY_DOMAIN", ",");

        assert(routers.length == domains.length && domains.length == gasDomains.length);
        uint32[] memory _domains = new uint32[](domains.length);
        bytes32[] memory _routers = new bytes32[](domains.length);
        GasRouter.GasRouterConfig[] memory gasConfigs = new GasRouter.GasRouterConfig[](domains.length);

        for (uint i = 0; i < domains.length; i++) {
          _routers[i] = TypeCasts.addressToBytes32(routers[i]);
          _domains[i] = uint32(domains[i]);
          gasConfigs[i] = GasRouter.GasRouterConfig(_domains[i], gasDomains[i]);
        }

        vm.startBroadcast(deployerPrivateKey);

        Hyperlane7683(localRouter).enrollRemoteRouters(_domains, _routers);

        Hyperlane7683(localRouter).setDestinationGas(gasConfigs);

        vm.stopBroadcast();
    }
}
