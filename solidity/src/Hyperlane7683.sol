// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { GasRouter } from "@hyperlane-xyz/client/GasRouter.sol";

import { Hyperlane7683Message } from "./libs/Hyperlane7683Message.sol";
import { BasicSwap7683 } from "./BasicSwap7683.sol";

/**
 * @title Hyperlane7683
 * @author BootNode
 * @notice This contract builds on top of BasicSwap7683 as a messaging layer using Hyperlane.
 * @dev It integrates with the Hyperlane protocol for cross-chain communication.
 */
contract Hyperlane7683 is GasRouter, BasicSwap7683 {
    // ============ Libraries ============

    // ============ Constants ============

    // ============ Public Storage ============

    // ============ Upgrade Gap ============
    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Events ============

    // ============ Errors ============

    // ============ Modifiers ============

    // ============ Constructor ============
    /**
     * @notice Initializes the Hyperlane7683 contract with the specified Mailbox and PERMIT2 address.
     * @param _mailbox The address of the Hyperlane mailbox contract.
     * @param _permit2 The address of the permit2 contract.
     */
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

    // ============ Internal Functions ============

    /**
     * @notice Dispatches a settlement message to the specified domain.
     * @dev Encodes the settle message using Hyperlane7683Message and dispatches it via the GasRouter.
     * @param _originDomain The domain to which the settlement message is sent.
     * @param _orderIds The IDs of the orders to settle.
     * @param _ordersFillerData The filler data for the orders.
     */
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

    /**
     * @notice Dispatches a refund message to the specified domain.
     * @dev Encodes the refund message using Hyperlane7683Message and dispatches it via the GasRouter.
     * @param _originDomain The domain to which the refund message is sent.
     * @param _orderIds The IDs of the orders to refund.
     */
    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        _GasRouter_dispatch(_originDomain, msg.value, Hyperlane7683Message.encodeRefund(_orderIds), address(hook));
    }

    /**
     * @notice Handles incoming messages.
     * @dev Decodes the message and processes settlement or refund operations accordingly.
     * @param _messageOrigin The domain from which the message originates (unused in this implementation).
     * @param _messageSender The address of the sender on the origin domain (unused in this implementation).
     * @param _message The encoded message received via Hyperlane.
     */
    function _handle(uint32 _messageOrigin, bytes32 _messageSender, bytes calldata _message) internal virtual override {
        (bool _settle, bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) =
            Hyperlane7683Message.decode(_message);

        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_settle) {
                _handleSettleOrder(_messageOrigin, _messageSender, _orderIds[i], abi.decode(_ordersFillerData[i], (bytes32)));
            } else {
                _handleRefundOrder(_messageOrigin, _messageSender, _orderIds[i]);
            }
        }
    }

    /**
     * @notice Retrieves the local domain identifier.
     * @dev This function overrides the `_localDomain` function from the parent contract.
     * @return The local domain ID.
     */
    function _localDomain() internal view override returns (uint32) {
        return localDomain;
    }
}
