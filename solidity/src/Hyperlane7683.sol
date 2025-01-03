// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { GasRouter } from "@hyperlane-xyz/client/GasRouter.sol";

import { Hyperlane7683Message } from "./libs/Hyperlane7683Message.sol";

import { BasicSwap7683 } from "./BasicSwap7683.sol";

contract Hyperlane7683 is GasRouter, BasicSwap7683 {
    // ============ Libraries ============

    // ============ Constants ============

    // ============ Public Storage ============

    // ============ Upgrade Gap ============

    uint256[47] private __GAP;

    // ============ Events ============

    // ============ Errors ============

    // ============ Modifiers ============

    // ============ Constructor ============

    constructor(address _mailbox, address _permit2) GasRouter(_mailbox) BasicSwap7683(_permit2) { }

    // ============ Initializers ============

    /**
     * @notice Initializes the contract with HyperlaneConnectionClient contracts
     * @param _customHook used by the Router to set the hook to override with
     * @param _interchainSecurityModule The address of the local ISM contract
     * @param _owner The address with owner privileges
     */
    function initialize(address _customHook, address _interchainSecurityModule, address _owner) external initializer {
        _MailboxClient_initialize(_customHook, _interchainSecurityModule, _owner);
    }

    // ============ External Functions ============

    // ============ Internal Functions ============

    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        override
    {
        _GasRouter_dispatch(
            _originDomain, msg.value, Hyperlane7683Message.encodeSettle(_orderIds, _ordersFillerData), address(hook)
        );
    }

    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        _GasRouter_dispatch(_originDomain, msg.value, Hyperlane7683Message.encodeRefund(_orderIds), address(hook));
    }

    function _handle(uint32, bytes32, bytes calldata _message) internal virtual override {
        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            Hyperlane7683Message.decode(_message);

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(_orderIds[i], abi.decode(_ordersFillerData[i], (bytes32)));
            } else {
                _handleRefundOrder(_orderIds[i]);
            }
        }
    }

    function _localDomain() internal view override returns (uint32) {
        return localDomain;
    }
}
