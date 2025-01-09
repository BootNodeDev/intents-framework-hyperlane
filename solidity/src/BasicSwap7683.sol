// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import { Base7683 } from "./Base7683.sol";
import { OrderData, OrderEncoder } from "./libs/OrderEncoder.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction,
    IOriginSettler,
    IDestinationSettler
} from "./ERC7683/IERC7683.sol";

/**
 * @title BasicSwap7683
 * @author BootNode
 * @notice This contract builds on top of Base7683 as a second layer, implementing logic to handle a specific type of
 * order for swapping a single token.
 * @dev This is an abstract contract intended to be inherited by a third contract that will function as the messaging
 * layer.
 */
abstract contract BasicSwap7683 is Base7683 {
    // ============ Libraries ============
    using SafeERC20 for IERC20;

    // ============ Constants ============
    /// @notice Status constant indicating that an order has been settled.
    bytes32 public constant SETTLED = "SETTLED";
    /// @notice Status constant indicating that an order has been refunded.
    bytes32 public constant REFUNDED = "REFUNDED";

    // ============ Public Storage ============

    // ============ Upgrade Gap ============
    /// @dev Reserved storage slots for upgradeability.
    uint256[47] private __GAP;

    // ============ Events ============
    /**
     * @notice Emitted when an order is settled.
     * @param orderId The ID of the settled order.
     * @param receiver The address of the order's input token receiver.
     */
    event Settled(bytes32 orderId, address receiver);

    /**
     * @notice Emitted when an order is refunded.
     * @param orderId The ID of the refunded order.
     * @param receiver The address of the order's input token receiver.
     */
    event Refunded(bytes32 orderId, address receiver);

    // ============ Errors ============

    error InvalidOrderType(bytes32 orderType);
    error InvalidOriginDomain(uint32 originDomain);
    error InvalidOrderId();
    error OrderFillExpired();
    error InvalidOrderDomain();
    error InvalidDomain();
    error InvalidSender();

    // ============ Modifiers ============

    // ============ Constructor ============
    /**
     * @dev Initializes the contract by calling the constructor of Base7683 with the permit2 address.
     * @param _permit2 The address of the PERMIT2 contract.
     */
    constructor(address _permit2) Base7683(_permit2) { }

    // ============ Initializers ============

    // ============ External Functions ============

    // ============ Internal Functions ============

    /**
     * @dev Settles multiple orders by dispatching the settlement instructions.
     * @param _orderIds The IDs of the orders to settle.
     * @param _ordersOriginData The original data of the orders.
     * @param _ordersFillerData The filler data for the orders.
     */
    function _settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory _ordersOriginData,
        bytes[] memory _ordersFillerData
    )
        internal
        override
    {
        // at this point we are sure all orders are filled, use the first order to get the originDomain
        // if some order differs on the originDomain ir can be re-settle later
        _dispatchSettle(OrderEncoder.decode(_ordersOriginData[0]).originDomain, _orderIds, _ordersFillerData);
    }

    /**
     * @dev Refunds multiple OnchainCrossChain orders by dispatching refund instructions.
     * @param _orders The orders to refund.
     * @param _orderIds The IDs of the orders to refund.
     */
    function _refundOrders(OnchainCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal override {
        // at this point we are sure all orders are filled, use the first order to get the originDomain
        // if some order differs on the originDomain ir can be re-refunded later
        _dispatchRefund(OrderEncoder.decode(_orders[0].orderData).originDomain, _orderIds);
    }

    /**
     * @dev Refunds multiple GaslessCrossChain orders by dispatching refund instructions.
     * @param _orders The orders to refund.
     * @param _orderIds The IDs of the orders to refund.
     */
    function _refundOrders(GaslessCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal override {
        // at this point we are sure all orders are filled, use the first order to get the originDomain
        // if some order differs on the originDomain ir can be re-refunded later
        _dispatchRefund(OrderEncoder.decode(_orders[0].orderData).originDomain, _orderIds);
    }

    /**
     * @dev Handles settling an individual order, should be called by the inheriting contract when receiving a setting
     * instruction from a remote chain.
     * @param _orderId The ID of the order to settle.
     * @param _receiver The receiver address (encoded as bytes32).
     */
    function _handleSettleOrder(bytes32 _orderId, bytes32 _receiver) internal virtual {
        // check if the order is opened to ensure it belongs to this domain, skip otherwise
        if (orderStatus[_orderId] != OPENED) return;

        ResolvedCrossChainOrder memory resolvedOrder = abi.decode(orders[_orderId], (ResolvedCrossChainOrder));

        OrderData memory orderData = OrderEncoder.decode(resolvedOrder.fillInstructions[0].originData);

        orderStatus[_orderId] = SETTLED;

        address receiver = TypeCasts.bytes32ToAddress(_receiver);
        address inputToken = TypeCasts.bytes32ToAddress(orderData.inputToken);

        if (inputToken == address(0)) {
            Address.sendValue(payable(receiver), orderData.amountIn);
        } else {
            IERC20(inputToken).safeTransfer(receiver, orderData.amountIn);
        }

        emit Settled(_orderId, receiver);
    }

    /**
     * @dev Handles refunding an individual order, should be called by the inheriting contract when receiving a
     * refunding instruction from a remote chain.
     * @param _orderId The ID of the order to refund.
     */
    function _handleRefundOrder(bytes32 _orderId) internal virtual {
        // check if the order is opened to ensure it belongs to this domain, skip otherwise
        if (orderStatus[_orderId] != OPENED) return;

        ResolvedCrossChainOrder memory resolvedOrder = abi.decode(orders[_orderId], (ResolvedCrossChainOrder));

        OrderData memory orderData = OrderEncoder.decode(resolvedOrder.fillInstructions[0].originData);

        orderStatus[_orderId] = REFUNDED;

        address orderSender = TypeCasts.bytes32ToAddress(orderData.sender);
        address inputToken = TypeCasts.bytes32ToAddress(orderData.inputToken);

        if (inputToken == address(0)) {
            Address.sendValue(payable(orderSender), orderData.amountIn);
        } else {
            IERC20(inputToken).safeTransfer(orderSender, orderData.amountIn);
        }

        emit Refunded(_orderId, orderSender);
    }

    /**
     * @dev Gets the ID of a GaslessCrossChainOrder.
     * @param _order The GaslessCrossChainOrder to compute the ID for.
     * @return The computed order ID.
     */
    function _getOrderId(GaslessCrossChainOrder memory _order) internal pure override returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /**
     * @dev Gets the ID of an OnchainCrossChainOrder.
     * @param _order The OnchainCrossChainOrder to compute the ID for.
     * @return The computed order ID.
     */
    function _getOrderId(OnchainCrossChainOrder memory _order) internal pure override returns (bytes32) {
        return _getOrderId(_order.orderDataType, _order.orderData);
    }

    /**
     * @dev Computes the ID of an order given its type and data.
     * @param _orderType The type of the order.
     * @param _orderData The data of the order.
     * @return orderId The computed order ID.
     */
    function _getOrderId(bytes32 _orderType, bytes memory _orderData) internal pure returns (bytes32 orderId) {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);
        OrderData memory orderData = OrderEncoder.decode(_orderData);
        orderId = OrderEncoder.id(orderData);
    }

    /**
     * @dev Resolves a GaslessCrossChainOrder.
     * @param _order The GaslessCrossChainOrder to resolve.
     * @return A ResolvedCrossChainOrder structure.
     * @return The order ID.
     * @return The order nonce.
     */
    function _resolveOrder(GaslessCrossChainOrder memory _order)
        internal
        view
        virtual
        override
        returns (ResolvedCrossChainOrder memory, bytes32, uint256)
    {
        return _resolvedOrder(
            _order.orderDataType, _order.user, _order.openDeadline, _order.fillDeadline, _order.orderData
        );
    }

    /**
     * @notice Resolves a OnchainCrossChainOrder.
     * @param _order The OnchainCrossChainOrder to resolve.
     * @return A ResolvedCrossChainOrder structure.
     * @return The order ID.
     * @return The order nonce.
     */
    function _resolveOrder(OnchainCrossChainOrder memory _order)
        internal
        view
        virtual
        override
        returns (ResolvedCrossChainOrder memory, bytes32, uint256)
    {
        return _resolvedOrder(_order.orderDataType, msg.sender, type(uint32).max, _order.fillDeadline, _order.orderData);
    }

    /**
     * @dev Resolves an order into a ResolvedCrossChainOrder structure.
     * @param _orderType The type of the order.
     * @param _sender The sender of the order.
     * @param _openDeadline The open deadline of the order.
     * @param _fillDeadline The fill deadline of the order.
     * @param _orderData The data of the order.
     * @return resolvedOrder A ResolvedCrossChainOrder structure.
     * @return orderId The order ID.
     * @return nonce The order nonce.
     */
    function _resolvedOrder(
        bytes32 _orderType,
        address _sender,
        uint32 _openDeadline,
        uint32 _fillDeadline,
        bytes memory _orderData
    )
        internal
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce)
    {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);

        // IDEA: _orderData should not be directly typed as OrderData, it should contain information that is not
        // present on the type used for open the order. So _fillDeadline and _user should be passed as arguments
        OrderData memory orderData = OrderEncoder.decode(_orderData);

        if (orderData.originDomain != _localDomain()) revert InvalidOriginDomain(orderData.originDomain);

        // bytes32 destinationSettler = _mustHaveRemoteCounterpart(orderData.destinationDomain);

        // enforce fillDeadline into orderData
        orderData.fillDeadline = _fillDeadline;
        // enforce sender into orderData
        orderData.sender = TypeCasts.addressToBytes32(_sender);

        // this can be used by the filler to approve the tokens to be spent on destination
        Output[] memory maxSpent = new Output[](1);
        maxSpent[0] = Output({
            token: orderData.outputToken,
            amount: orderData.amountOut,
            recipient: orderData.destinationSettler,
            chainId: orderData.destinationDomain
        });

        // this can be used by the filler know how much it can expect to receive
        Output[] memory minReceived = new Output[](1);
        minReceived[0] = Output({
            token: orderData.inputToken,
            amount: orderData.amountIn,
            recipient: bytes32(0),
            chainId: orderData.originDomain
        });

        // this can be user by the filler to know how to fill the order
        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        fillInstructions[0] = FillInstruction({
            destinationChainId: orderData.destinationDomain,
            destinationSettler: orderData.destinationSettler,
            originData: OrderEncoder.encode(orderData)
        });

        orderId = OrderEncoder.id(orderData);

        resolvedOrder = ResolvedCrossChainOrder({
            user: _sender,
            originChainId: _localDomain(),
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            orderId: orderId,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });

        nonce = orderData.senderNonce;
    }

    /**
     * @dev Fills an order on the current domain.
     * @param _orderId The ID of the order to fill.
     * @param _originData The origin data of the order.
     * Additional data related to the order (unused).
     */
    function _fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata) internal override {
        OrderData memory orderData = OrderEncoder.decode(_originData);

        if (_orderId != OrderEncoder.id(orderData)) revert InvalidOrderId();
        if (block.timestamp > orderData.fillDeadline) revert OrderFillExpired();
        if (orderData.destinationDomain != _localDomain()) revert InvalidOrderDomain();

        address outputToken = TypeCasts.bytes32ToAddress(orderData.outputToken);
        address recipient = TypeCasts.bytes32ToAddress(orderData.recipient);

        if (outputToken == address(0)) {
            if (orderData.amountOut != msg.value) revert InvalidNativeAmount();
            Address.sendValue(payable(recipient), orderData.amountOut);
        } else {
            IERC20(outputToken).safeTransferFrom(msg.sender, recipient, orderData.amountOut);
        }
    }

    /**
     * @dev Should be implemented by the messaging layer for dispatching a settlement instruction the remote domain
     * where the orders where created.
     * @param _originDomain The origin domain of the orders.
     * @param _orderIds The IDs of the orders to settle.
     * @param _ordersFillerData The filler data for the orders.
     */
    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        virtual;

    /**
     * @dev Should be implemented by the messaging layer for dispatching a refunding instruction the remote domain
     * where the orders where created.
     * @param _originDomain The origin domain of the orders.
     * @param _orderIds The IDs of the orders to refund.
     */
    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal virtual;
}
