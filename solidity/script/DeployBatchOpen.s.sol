// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";

import {
    OnchainCrossChainOrder
} from "../src/ERC7683/IERC7683.sol";

contract BatchOpen  {
    Hyperlane7683 public router;
    constructor(address _router) {
        router = Hyperlane7683(_router);
    }

    function openOrders(OnchainCrossChainOrder[] memory orders, address token, uint256 total) external {
        ERC20(token).transferFrom(msg.sender, address(this), total);
        ERC20(token).approve(address(router), total);
        for (uint256 i = 0; i < orders.length; i++) {
            router.open(orders[i]);
        }
    }
}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployBatchOpen is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address router = vm.envAddress("ROUTER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        new BatchOpen(router);

        vm.stopBroadcast();
    }
}
