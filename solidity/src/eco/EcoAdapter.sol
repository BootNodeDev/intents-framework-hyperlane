// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { IInbox } from "./IInbox.sol";

import { console2 } from "forge-std/console2.sol";

contract EcoAdapter is Ownable {
    using TypeCasts for address;
    using SafeERC20 for IERC20;

    IInbox public inbox;

    error InvalidFunctionSelector();

    constructor(address _owner, address _inbox) {
        _transferOwnership(_owner);
        inbox = IInbox(_inbox);
    }

    function fulfillHyperInstant(
          uint256 _sourceChainID,
          address[] calldata _targets,
          bytes[] calldata _data,
          uint256 _expiryTime,
          bytes32 _nonce,
          address _claimant,
          bytes32 _expectedHash,
          address _prover
    ) external onlyOwner payable returns (bytes[] memory) {
        address target = _targets[0];

        if (!isTransfer(_data[0])) revert InvalidFunctionSelector();

        (, uint256 amount) = abi.decode(_data[0][4:], (address, uint256));

        IERC20(target).safeTransferFrom(msg.sender, address(inbox), amount);

        return inbox.fulfillHyperInstant{value: msg.value}(
            _sourceChainID, _targets, _data, _expiryTime, _nonce, _claimant, _expectedHash, _prover
        );
    }

    function isTransfer(bytes calldata _data) public pure returns (bool) {
        bytes4 functionSelector = bytes4(_data[:4]);
        return functionSelector == IERC20.transfer.selector;
    }

    function fetchFee(uint256 _sourceChainID, bytes32[] memory _hashes, address[] memory _claimants, address _prover) public view returns (uint256 fee) {
        bytes memory messageBody = abi.encode(_hashes, _claimants);
        bytes32 _prover32 = _prover.addressToBytes32();
        fee = inbox.fetchFee(_sourceChainID, messageBody, _prover32);
    }
}
