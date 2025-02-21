// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import {
    OnchainCrossChainOrder
} from "../src/ERC7683/IERC7683.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { OrderEncoder } from "../src/libs/OrderEncoder.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract RefundOrder is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("USER_PK");

        address router = vm.envAddress("ROUTER");
        uint32 fillDeadline = uint32(vm.envUint("ORDER_FILL_DEADLINE"));
        uint32 orderOrigin = uint32(vm.envUint("ORDER_ORIGIN"));
        bytes memory orderData = vm.envBytes("ORDER_DATA");

        vm.startBroadcast(deployerPrivateKey);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0].fillDeadline = fillDeadline;
        orders[0].orderDataType = OrderEncoder.orderDataType();
        orders[0].orderData = orderData;

        uint256 quote = Hyperlane7683(router).quoteGasPayment(orderOrigin);

        Hyperlane7683(router).refund{value: quote}(orders);

        vm.stopBroadcast();
    }
}
