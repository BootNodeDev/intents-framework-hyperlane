// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { GasRouter } from "@hyperlane-xyz/client/GasRouter.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";

import { ICreateX } from "./utils/ICreateX.sol";

contract OwnableProxyAdmin is ProxyAdmin {
    constructor(address _owner) {
        _transferOwnership(_owner);
    }
}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeploySimple is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");

        address owner = vm.envAddress("ROUTER_OWNER");

        uint256[] memory domains = vm.envUint("DOMAINS", ",");
        address[] memory routers = vm.envAddress("ROUTERS", ",");
        assert(routers.length == domains.length);
        uint32[] memory _domains = new uint32[](domains.length);
        bytes32[] memory _routers = new bytes32[](domains.length);
        GasRouter.GasRouterConfig[] memory gasConfigs = new GasRouter.GasRouterConfig[](domains.length);

        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = deployProxyAdmin();
        address routerImpl = deployImplementation();
        TransparentUpgradeableProxy proxy = deployProxy(routerImpl, address(proxyAdmin));

        for (uint i = 0; i < domains.length; i++) {
          _routers[i] = TypeCasts.addressToBytes32(routers[i]);
          _domains[i] = uint32(domains[i]);
          // TODO - amount is based on gas report from tests multiply 2
          gasConfigs[i] = GasRouter.GasRouterConfig(_domains[i], 1070688);
        }

        Hyperlane7683(address(proxy)).enrollRemoteRouters(_domains, _routers);

        Hyperlane7683(address(proxy)).setDestinationGas(gasConfigs);

        Hyperlane7683(address(proxy)).transferOwnership(owner);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("Router Proxy:", address(proxy));
        console2.log("Implementation:", routerImpl);
        console2.log("ProxyAdmin:", address(proxyAdmin));
    }

    function deployProxyAdmin() internal returns (ProxyAdmin proxyAdmin) {
        string memory ROUTER_SALT = vm.envString("HYPERLANE7683_SALT");
        address proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");

        proxyAdmin = new OwnableProxyAdmin(proxyAdminOwner);
    }

    function deployImplementation() internal returns (address routerImpl) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        string memory ROUTER_SALT = vm.envString("HYPERLANE7683_SALT");
        address mailbox = vm.envAddress("MAILBOX");
        address permit2 = vm.envAddress("PERMIT2");

        return address(new Hyperlane7683(mailbox, permit2));
    }

    function deployProxy(address routerImpl, address proxyAdmin) internal returns (TransparentUpgradeableProxy proxy) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        string memory ROUTER_SALT = vm.envString("HYPERLANE7683_SALT");
        address initialOwner = vm.addr(deployerPrivateKey);

        proxy = new TransparentUpgradeableProxy(
          routerImpl,
          proxyAdmin,
          abi.encodeWithSelector(Hyperlane7683.initialize.selector, address(0), address(0), initialOwner)
        );
    }
}
