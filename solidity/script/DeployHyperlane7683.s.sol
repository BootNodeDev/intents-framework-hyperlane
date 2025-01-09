// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { GasRouter } from "@hyperlane-xyz/client/GasRouter.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";

contract OwnableProxyAdmin is ProxyAdmin {
    constructor(address _owner) {
        _transferOwnership(_owner);
    }
}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployHyperlane7683 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");

        string memory ROUTER_SALT = vm.envString("HYPERLANE7683_SALT");
        address mailbox = vm.envAddress("MAILBOX");
        address permit2 = vm.envAddress("PERMIT2");
        address proxyAdminOwner = vm.envOr("PROXY_ADMIN_OWNER", address(0));
        address owner = vm.envAddress("ROUTER_OWNER");
        uint256[] memory domains = vm.envUint("DOMAINS", ",");
        uint32[] memory _domains = new uint32[](domains.length);
        bytes32[] memory routers = new bytes32[](domains.length);
        GasRouter.GasRouterConfig[] memory gasConfigs = new GasRouter.GasRouterConfig[](domains.length);

        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = new OwnableProxyAdmin{ salt: keccak256(abi.encode(ROUTER_SALT)) }(proxyAdminOwner);

        address routerImpl = address(new Hyperlane7683{ salt: keccak256(abi.encode(ROUTER_SALT)) }(mailbox, permit2));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy{ salt: keccak256(abi.encode(ROUTER_SALT)) }(
            routerImpl,
            address(proxyAdmin),
            abi.encodeWithSelector(Hyperlane7683.initialize.selector, address(0), address(0), owner)
        );

        for (uint256 i = 0; i < domains.length; i++) {
            routers[i] = TypeCasts.addressToBytes32(address(proxy));
            _domains[i] = uint32(domains[i]);
            // amount is based on gas report from tests multiply 2
            gasConfigs[i] = GasRouter.GasRouterConfig(_domains[i], 1_070_688);
        }

        Hyperlane7683(address(proxy)).enrollRemoteRouters(_domains, routers);

        Hyperlane7683(address(proxy)).setDestinationGas(gasConfigs);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("Router Proxy:", address(proxy));
        console2.log("Implementation:", routerImpl);
        console2.log("ProxyAdmin:", address(proxyAdmin));
    }
}
