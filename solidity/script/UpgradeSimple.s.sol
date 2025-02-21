// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract UpgradeSimple is Script {
    function run() public {
        uint256 proxyAdminOwner = vm.envUint("PROXY_ADMIN_OWNER_PK");

        address routerProxy = vm.envAddress("ROUTER");
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");

        vm.startBroadcast(proxyAdminOwner);

        address newRouterImpl = deployImplementation();

        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(routerProxy), newRouterImpl);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("New Implementation:", newRouterImpl);
    }

    function deployImplementation() internal returns (address routerImpl) {
        address mailbox = vm.envAddress("MAILBOX");
        address permit2 = vm.envAddress("PERMIT2");

        return address(new Hyperlane7683(mailbox, permit2));
    }
}
