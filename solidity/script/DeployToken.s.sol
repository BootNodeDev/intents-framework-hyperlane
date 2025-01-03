// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IntentTestToken is ERC20 {
    constructor(address receiver) ERC20("IntentTestToken", "ITT") {
        _mint(receiver, 1_000_000 * 10 ** decimals());
    }
}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployToken is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address owner = vm.envAddress("ROUTER_OWNER");

        vm.startBroadcast(deployerPrivateKey);

        IntentTestToken itt = new IntentTestToken{ salt: keccak256(abi.encode("IntentTestToken.0.0.1")) }(owner);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("ITT:", address(itt));
    }
}
