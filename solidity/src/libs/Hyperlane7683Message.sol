// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ============ External Imports ============

library Hyperlane7683Message {
    /**
     * @notice Returns formatted Router7683 message
     * @dev This function should only be used in memory message construction.
     * @param _settle Flag to indicate if the message is a settlement or refund
     * @param _orderIds The orderIds to settle or refund
     * @param _ordersFillerData Each element should contain the bytes32 encoded address of the settlement receiver.
     * @return Formatted message body
     */
    function encode(
        bool _settle,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(_settle, _orderIds, _ordersFillerData);
    }

    /**
     * @notice Parses and returns the calls from the provided message
     * @param _message The interchain message
     * @return The array of calls
     */
    function decode(bytes calldata _message) internal pure returns (bool, bytes32[] memory, bytes[] memory) {
        return abi.decode(_message, (bool, bytes32[], bytes[]));
    }

    function encodeSettle(
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        pure
        returns (bytes memory)
    {
        return encode(true, _orderIds, _ordersFillerData);
    }

    function encodeRefund(bytes32[] memory _orderIds) internal pure returns (bytes memory) {
        return encode(false, _orderIds, new bytes[](0));
    }
}
