// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IEIP712 } from "@uniswap/permit2/src/interfaces/IEIP712.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import {EcoAdapter} from "../src/eco/EcoAdapter.sol";

contract Adapter is Test {
    EcoAdapter internal adapter;
    address solver = 0x6AC4B73Ae41D40E7e920aB5Ff1a97211DAF67949;
    address prover = 0x39cBD6e1C0E6a30dF33428a54Ac3940cF33B23D6;
    address itt = 0x5f94BC7Fb4A2779fef010F96b496cD36A909E818;
    address inbox = 0xB73fD43C293b250Cb354c4631292A318248FB33E;

    uint256 internal forkId;

    uint256 internal sourceChainId = 11155420;
    uint256 internal destChainId = 84532;
    uint256 internal expiryTime = 4294967295;

    function setUp() public {
        forkId = vm.createSelectFork(vm.envString("BASE_RPC_URL"), 17609373);

        adapter = new EcoAdapter(solver, inbox);
    }

    function encodeHash(
        address[] memory _targets,
        bytes[] memory _data,
        bytes32 _nonce
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                inbox, keccak256(abi.encode(sourceChainId, destChainId, _targets, _data, expiryTime, _nonce))
            )
        );
    }


    function test_works() public {
        vm.startPrank(solver);

        bytes32 _nonce = keccak256(abi.encode(0, sourceChainId));

        // 84532,11155420
        address[] memory _claimants = new address[](1);
        _claimants[0] = solver;

        address[] memory _targets = new address[](1);
        _targets[0] = itt;

        bytes[] memory _data = new bytes[](1);
        _data[0] = abi.encodeWithSelector(ERC20.transfer.selector, inbox, 1000);

        bytes32[] memory _hashes = new bytes32[](1);
         _hashes[0] = encodeHash(_targets, _data, _nonce);

        uint256 testFee = adapter.fetchFee(sourceChainId, _hashes, _claimants, prover);

        ERC20(itt).approve(address(adapter), 1000);

        adapter.fulfillHyperInstant{value: testFee}(
            sourceChainId,
            _targets,
            _data,
            expiryTime,
            bytes32(0xdc00b7d95b0b345824d6c6d24ce88863f97d83d8f9303afca30ccaefb756c5d3),
            solver,
            _hashes[0],
            prover
        );

        vm.stopPrank();
    }
}
