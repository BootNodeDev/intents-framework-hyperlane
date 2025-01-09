// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";

import { OnchainCrossChainOrder } from "../src/ERC7683/IERC7683.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract OpenOrder is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");

        vm.startBroadcast(deployerPrivateKey);

        address localRouter = vm.envAddress("ROUTER_ADDRESS");
        address sender = vm.envAddress("ORDER_SENDER");
        address recipient = vm.envAddress("ORDER_RECIPIENT");
        address inputToken = vm.envAddress("ITT_INPUT");
        address outputToken = vm.envAddress("ITT_OUTPUT");
        uint256 amountIn = vm.envUint("AMOUNT_IN");
        uint256 amountOut = vm.envUint("AMOUNT_OUT");
        uint256 senderNonce = vm.envUint("SENDER_NONCE");
        uint32 originDomain = Hyperlane7683(localRouter).localDomain();
        uint256 destinationDomain = vm.envUint("DESTINATION_DOMAIN");
        uint32 fillDeadline = type(uint32).max;

        ERC20(inputToken).approve(localRouter, amountIn);

        OrderData memory order = OrderData(
            TypeCasts.addressToBytes32(sender),
            TypeCasts.addressToBytes32(recipient),
            TypeCasts.addressToBytes32(inputToken),
            TypeCasts.addressToBytes32(outputToken),
            amountIn,
            amountOut,
            senderNonce,
            originDomain,
            uint32(destinationDomain),
            TypeCasts.addressToBytes32(localRouter),
            fillDeadline,
            new bytes(0)
        );

        OnchainCrossChainOrder memory onchainOrder =
            OnchainCrossChainOrder(fillDeadline, OrderEncoder.orderDataType(), OrderEncoder.encode(order));

        Hyperlane7683(localRouter).open(onchainOrder);

        vm.stopBroadcast();
    }
}
