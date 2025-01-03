// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPermit2, ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction,
    IOriginSettler,
    IDestinationSettler
} from "./ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "./libs/OrderEncoder.sol";

abstract contract Base7683 is IOriginSettler, IDestinationSettler {
    // ============ Libraries ============
    using SafeERC20 for IERC20;

    // ============ Constants ============

    enum OrderStatus {
        UNFILLED,
        OPENED,
        FILLED,
        SETTLED,
        REFUNDED
    }

    IPermit2 public immutable PERMIT2;

    bytes32 public constant GASLESS_CROSS_CHAIN_ORDER_TYPEHASH = keccak256(
        "GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint64 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType,bytes orderData)"
    );

    string public constant witnessTypeString =
        "GaslessCrossChainOrder witness)GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint64 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType,bytes orderData)TokenPermissions(address token,uint256 amount)";

    // ============ Public Storage ============

    mapping(address sender => uint256 nonce) public senderNonce;

    mapping(bytes32 orderId => OrderData orderData) public orders;

    mapping(bytes32 orderId => bytes fillerData) public orderFillerData;

    mapping(bytes32 orderId => OrderStatus status) public orderStatus;

    // ============ Upgrade Gap ============

    uint256[47] private __GAP;

    // ============ Events ============

    event Filled(bytes32 orderId, bytes originData, bytes fillerData);
    event Settle(bytes32[] orderIds, bytes[] ordersFillerData);
    event Refund(bytes32[] orderIds);
    event Settled(bytes32 orderId, address receiver);
    event Refunded(bytes32 orderId, address receiver);

    // ============ Errors ============

    error OrderOpenExpired();
    error InvalidOrderType(bytes32 orderType);
    error InvalidSenderNonc();
    error InvalidOriginDomain(uint32 originDomain);
    error InvalidOrderId();
    error OrderFillExpired();
    error InvalidOrderDomain();
    error InvalidOrderStatus();
    error InvalidSenderNonce();
    error OrderFillNotExpired();
    error InvalidDomain();
    error InvalidSender();
    error InvalidAmount();

    // ============ Constructor ============

    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
    }

    // ============ Initializers ============

    // ============ External Functions ============

    /// @notice Opens a gasless cross-chain order on behalf of a user.
    /// @dev To be called by the filler.
    /// @dev This method must emit the Open event
    /// @param order The GaslessCrossChainOrder definition
    /// @param signature The user's signature over the order
    /// NOT USED originFillerData Any filler-defined data required by the settler
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata
    )
        external
    {
        if (block.timestamp > order.openDeadline) revert OrderOpenExpired();

        (ResolvedCrossChainOrder memory resolvedOrder, OrderData memory orderData) =
            _resolvedOrder(order.orderDataType, order.user, order.orderData, order.openDeadline, order.fillDeadline);

        bytes32 orderId = _getOrderId(orderData);

        orders[orderId] = orderData;
        orderStatus[orderId] = OrderStatus.OPENED;
        senderNonce[order.user] += 1;

        _permitTransferFrom(order, signature, address(this));

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Opens a cross-chain order
    /// @dev To be called by the user
    /// @dev This method must emit the Open event
    /// @param order The OnchainCrossChainOrder definition
    function open(OnchainCrossChainOrder calldata order) external payable {
        (ResolvedCrossChainOrder memory resolvedOrder, OrderData memory orderData) = _resolvedOrder(
            order.orderDataType,
            msg.sender,
            order.orderData,
            type(uint32).max, // there is no open deadline for onchain orders since the user is opening it the order
            order.fillDeadline
        );

        bytes32 orderId = _getOrderId(orderData);

        orders[orderId] = orderData;
        orderStatus[orderId] = OrderStatus.OPENED;
        senderNonce[msg.sender] += 1;

        if (orderData.inputToken != TypeCasts.addressToBytes32(address(0))) {
            IERC20(TypeCasts.bytes32ToAddress(orderData.inputToken)).safeTransferFrom(
                msg.sender, address(this), orderData.amountIn
            );
        } else {
            if (msg.value != orderData.amountIn) revert InvalidAmount();
        }

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param order The GaslessCrossChainOrder definition
    /// NOT USED originFillerData Any filler-defined data required by the settler
    /// @return resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata
    )
        public
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder)
    {
        (resolvedOrder,) =
            _resolvedOrder(order.orderDataType, order.user, order.orderData, order.openDeadline, order.fillDeadline);
    }

    /// @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param order The OnchainCrossChainOrder definition
    /// @return resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
    function resolve(OnchainCrossChainOrder calldata order)
        public
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder)
    {
        (resolvedOrder,) = _resolvedOrder(
            order.orderDataType,
            msg.sender,
            order.orderData,
            type(uint32).max, // there is no open deadline for onchain orders since the user is opening it the order
            order.fillDeadline
        );
    }

    /// @notice Fills a single leg of a particular order on the destination chain
    /// @param _orderId Unique order identifier for this order
    /// @param _originData Data emitted on the origin to parameterize the fill
    /// @param _fillerData Data provided by the filler to inform the fill or express their preferences. It should
    /// contain the bytes32 encoded address of the receiver which is the used at settlement time
    function fill(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) external payable virtual {
        OrderData memory orderData = OrderEncoder.decode(_originData);

        if (_orderId != _getOrderId(orderData)) revert InvalidOrderId();
        if (block.timestamp > orderData.fillDeadline) revert OrderFillExpired();
        if (orderData.destinationDomain != _localDomain()) revert InvalidOrderDomain();
        _mustHaveRemoteCounterpart(orderData.originDomain);
        if (orderStatus[_orderId] != OrderStatus.UNFILLED) revert InvalidOrderStatus();

        orders[_orderId] = orderData;
        orderStatus[_orderId] = OrderStatus.FILLED;
        orderFillerData[_orderId] = _fillerData;

        emit Filled(_orderId, _originData, _fillerData);

        if (orderData.outputToken != TypeCasts.addressToBytes32(address(0))) {
            IERC20(TypeCasts.bytes32ToAddress(orderData.outputToken)).safeTransferFrom(
                msg.sender, TypeCasts.bytes32ToAddress(orderData.recipient), orderData.amountOut
            );
        } else {
            if (msg.value != orderData.amountOut) revert InvalidAmount();
            Address.sendValue(payable(TypeCasts.bytes32ToAddress(orderData.recipient)), orderData.amountOut);
        }
    }

    function settle(bytes32[] calldata _orderIds) external payable {
        bytes[] memory ordersFillerData = new bytes[](_orderIds.length);
        for (uint256 i = 0; i < _orderIds.length; i += 1) {
            if (orderStatus[_orderIds[i]] != OrderStatus.FILLED) revert InvalidOrderStatus();

            // not necessary to check the localDomain and counterpart since the fill function already did it

            orderStatus[_orderIds[i]] = OrderStatus.SETTLED;
            ordersFillerData[i] = orderFillerData[_orderIds[i]];
        }

        _handleSettlement(_orderIds, ordersFillerData);

        emit Settle(_orderIds, ordersFillerData);
    }
    function refund(OrderData[] memory _ordersData) external payable {
        bytes32[] memory orderIds = new bytes32[](_ordersData.length);
        for (uint256 i = 0; i < _ordersData.length; i += 1) {
            bytes32 orderId = _getOrderId(_ordersData[i]);

            if (orderStatus[orderId] != OrderStatus.UNFILLED) revert InvalidOrderStatus();
            if (block.timestamp <= _ordersData[i].fillDeadline) revert OrderFillNotExpired();

            // we need to check the domain and counterpart here since the fill function was not called
            if (_ordersData[i].destinationDomain != _localDomain()) revert InvalidOrderDomain();
            _mustHaveRemoteCounterpart(_ordersData[i].originDomain);

            orders[orderId] = _ordersData[i];
            orderStatus[orderId] = OrderStatus.REFUNDED;
            orderIds[i] = orderId;
        }

        _handleRefund(orderIds);

        emit Refund(orderIds);
    }

    // ============ Public Functions ============

    function witnessHash(GaslessCrossChainOrder calldata order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GASLESS_CROSS_CHAIN_ORDER_TYPEHASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                order.orderData
            )
        );
    }

    // ============ Internal Functions ============

    function _getOrderId(OrderData memory orderData) internal pure returns (bytes32) {
        return OrderEncoder.id(orderData);
    }

    function _resolvedOrder(
        bytes32 _orderType,
        address _sender,
        bytes memory _orderData,
        uint32 _openDeadline,
        uint32 _fillDeadline
    )
        internal
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder, OrderData memory orderData)
    {
        if (_orderType != OrderEncoder.orderDataType()) revert InvalidOrderType(_orderType);

        orderData = OrderEncoder.decode(_orderData);

        if (orderData.originDomain != _localDomain()) revert InvalidOriginDomain(orderData.originDomain);
        if (orderData.sender != TypeCasts.addressToBytes32(_sender)) revert InvalidSender();
        if (orderData.senderNonce != senderNonce[_sender]) revert InvalidSenderNonce();
        bytes32 destinationSettler = _mustHaveRemoteCounterpart(orderData.destinationDomain);

        // enforce fillDeadline into orderData
        orderData.fillDeadline = _fillDeadline;

        // this can be used by the filler to approve the tokens to be spent on destination
        Output[] memory maxSpent = new Output[](1);
        maxSpent[0] = Output({
            token: orderData.outputToken,
            amount: orderData.amountOut,
            recipient: destinationSettler,
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
            destinationSettler: destinationSettler,
            originData: OrderEncoder.encode(orderData)
        });

        resolvedOrder = ResolvedCrossChainOrder({
            user: _sender,
            originChainId: _localDomain(),
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });
    }

    function _permitTransferFrom(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        address receiver
    )
        internal
    {
        OrderData memory orderData = OrderEncoder.decode(order.orderData);

        PERMIT2.permitWitnessTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: TypeCasts.bytes32ToAddress(orderData.inputToken),
                    amount: orderData.amountIn
                }),
                nonce: order.nonce,
                deadline: order.openDeadline
            }),
            ISignatureTransfer.SignatureTransferDetails({ to: receiver, requestedAmount: orderData.amountIn }),
            order.user,
            witnessHash(order),
            witnessTypeString,
            signature
        );
    }

    /**
     * @dev This function is meant to be called by the inheriting contract when receiving a settle cross-chain message
     * from a remote domain counterpart
    */
    function _settleOrder(bytes32 _orderId, bytes32 _receiver, uint32 _settlingDomain) internal {
        OrderData memory orderData = orders[_orderId];

        if (orderData.destinationDomain != _settlingDomain) revert InvalidDomain();
        if (orderStatus[_orderId] != OrderStatus.OPENED) revert InvalidOrderStatus();

        orderStatus[_orderId] = OrderStatus.SETTLED;

        address receiver = TypeCasts.bytes32ToAddress(_receiver);

        emit Settled(_orderId, receiver);

        if (orderData.inputToken != TypeCasts.addressToBytes32(address(0))) {
            IERC20(TypeCasts.bytes32ToAddress(orderData.inputToken)).safeTransfer(
                receiver, orderData.amountIn
            );
        } else {
            Address.sendValue(payable(receiver), orderData.amountIn);
        }
    }

    /**
     * @dev This function is meant to be called by the inheriting contract when receiving a refund cross-chain message
     * from a remote domain counterpart
    */
    function _refundOrder(bytes32 _orderId, uint32 _refundingDomain) internal {
        OrderData memory orderData = orders[_orderId];

        if (orderData.destinationDomain != _refundingDomain) revert InvalidDomain();
        if (orderStatus[_orderId] != OrderStatus.OPENED) revert InvalidOrderStatus();

        orderStatus[_orderId] = OrderStatus.REFUNDED;

        address orderSender = TypeCasts.bytes32ToAddress(orderData.sender);

        emit Refunded(_orderId, orderSender);

        if (orderData.inputToken != TypeCasts.addressToBytes32(address(0))) {
            IERC20(TypeCasts.bytes32ToAddress(orderData.inputToken)).safeTransfer(
                orderSender, orderData.amountIn
            );
        } else {
            Address.sendValue(payable(orderSender), orderData.amountIn);
        }
    }

    /**
     * @dev This function is called during `settle` to handle the settlement of the orders, it is meant to be
     * implemented by the inheriting contract with specific settlement logic. i.e. sending a cross-chain message
    */
    function _handleSettlement(bytes32[] memory _orderIds, bytes[] memory _ordersFillerData) internal virtual;

    /**
     * @dev This function is called during `refund` to handle the refund of the orders, it is meant to be
     * implemented by the inheriting contract with specific refund logic. i.e. sending a cross-chain message
    */
    function _handleRefund(bytes32[] memory _orderIds) internal virtual;

    /**
     * @dev To be implemented by the inheriting contract with specific logic, the address of its remote counterpart and
     * revert if it does not exist
    */
    function _mustHaveRemoteCounterpart(uint32 _domain) internal view virtual returns (bytes32);

    /**
     * @dev To be implemented by the inheriting contract with specific logic, should return the local domain
    */
    function _localDomain() internal view virtual returns (uint32);
}
