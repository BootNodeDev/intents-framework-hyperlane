// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IIntentSource } from "../src/eco/IIntentSource.sol";

import {
    OnchainCrossChainOrder
} from "../src/ERC7683/IERC7683.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract CreateEcoIntent is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");

        vm.startBroadcast(deployerPrivateKey);

        address intentSource = vm.envAddress("ECO_INTENT_SOURCE");
        uint256 destinationChain = vm.envUint("ECO_DESTINATION_CHAIN");
        address inbox = vm.envAddress("ECO_INBOX");
        address targetToken = vm.envAddress("ECO_TARGET_TOKEN");
        address receiverAddress = vm.envAddress("ECO_RECEIVER_ADDRESS");
        uint256 receiverAmount = vm.envUint("ECO_RECEIVER_AMOUNT");
        address[] memory rewardTokens = vm.envAddress("ECO_REWARD_TOKENS", ",");
        uint256[] memory rewardAmounts = vm.envUint("ECO_RECEIVER_AMOUNT", ",");
        address prover = vm.envAddress("ECO_PROVER");

        for (uint i = 0; i < rewardTokens.length; i++) {
            ERC20(rewardTokens[i]).approve(intentSource, rewardAmounts[i]);
        }

        address[] memory targets = new address[](1);
        targets[0] = targetToken;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(ERC20.transfer.selector, receiverAddress, receiverAmount);

        IIntentSource(intentSource).createIntent(
            destinationChain,
            inbox,
            targets,
            data,
            rewardTokens,
            rewardAmounts,
            type(uint32).max,
            prover
        );

        vm.stopBroadcast();
    }
}
