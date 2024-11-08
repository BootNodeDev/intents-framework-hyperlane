// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { EcoAdapter } from "../src/eco/EcoAdapter.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployEcoAdapter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address owner = vm.envAddress("ADAPTER_OWNER");
        address inbox = vm.envAddress("ECO_INBOX");

        vm.startBroadcast(deployerPrivateKey);

        EcoAdapter adapter = new EcoAdapter{salt: keccak256(abi.encode("EcoAdapter.0.0.2"))}(owner, inbox);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("adapter:", address(adapter));
    }
}
