// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";

import { BaseTest } from "./BaseTest.sol";

import { Base7683 } from "../src/Base7683.sol";
import { BasicSwap7683 } from "../src/BasicSwap7683.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Settled(bytes32 orderId, address receiver);

event Refunded(bytes32 orderId, address receiver);

contract BasicSwap7683ForTest is BasicSwap7683 {
    constructor(address permitt2) BasicSwap7683(permitt2) { }

    uint32 public dispatchedOriginDomain;
    bytes32[] public dispatchedOrderIds;
    bytes[] public dispatchedOrdersFillerData;

    function fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _empty) public payable {
        _fillOrder(_orderId, _originData, _empty);
    }

    function settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory ordersOriginData,
        bytes[] memory ordersFillerData
    )
        public
    {
        _settleOrders(_orderIds, ordersOriginData, ordersFillerData);
    }

    function refundOrders(OnchainCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) public {
        _refundOrders(_orders, _orderIds);
    }

    function refundOrders(GaslessCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) public {
        _refundOrders(_orders, _orderIds);
    }

    function resolveOrder(GaslessCrossChainOrder memory order, bytes calldata _dummy)
        public
        view
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolveOrder(order, _dummy);
    }

    function resolveOrder(OnchainCrossChainOrder memory order)
        public
        view
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolveOrder(order);
    }

    function resolvedOrder(
        bytes32 _orderType,
        address _sender,
        uint32 _openDeadline,
        uint32 _fillDeadline,
        bytes memory _orderData
    )
        public
        view
        returns (ResolvedCrossChainOrder memory rOrder)
    {
        (rOrder,,) = _resolvedOrder(_orderType, _sender, _openDeadline, _fillDeadline, _orderData);
    }

    function handleSettleOrder(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId,
        bytes32 _receiver
    ) public {
        _handleSettleOrder(
            _messageOrigin,
            _messageSender,
            _orderId,
            _receiver
        );
    }

    function handleRefundOrder(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId
    ) public {
        _handleRefundOrder(
            _messageOrigin,
            _messageSender,
            _orderId
        );
    }

    function setOrderOpened(bytes32 _orderId, OrderData memory orderData) public {
        openOrders[_orderId] = abi.encode(OrderEncoder.orderDataType(), OrderEncoder.encode(orderData));
        orderStatus[_orderId] = OPENED;
    }

    function getOrderId(GaslessCrossChainOrder memory _order) public pure returns (bytes32) {
        return _getOrderId(_order);
    }

    function getOrderId(OnchainCrossChainOrder memory _order) public pure returns (bytes32) {
        return _getOrderId(_order);
    }

    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        internal
        override
    {
        dispatchedOriginDomain = _originDomain;
        dispatchedOrderIds = _orderIds;
        dispatchedOrdersFillerData = _ordersFillerData;
    }

    function _dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) internal override {
        dispatchedOriginDomain = _originDomain;
        dispatchedOrderIds = _orderIds;
    }

    function _localDomain() internal pure override returns (uint32) {
        return 1;
    }
}

contract BasicSwap7683Test is BaseTest {
    using TypeCasts for address;

    BasicSwap7683ForTest internal baseSwap;

    uint32 internal wrongMsgOrigin = 678;
    bytes32 internal wrongMsgSender = makeAddr("wrongMsgSender").addressToBytes32();

    function setUp() public override {
        super.setUp();

        baseSwap = new BasicSwap7683ForTest(permit2);

        balanceId[address(baseSwap)] = 4;
        users.push(address(baseSwap));
    }

    receive() external payable { }

    function prepareOrderData() internal view returns (OrderData memory) {
        return OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(karpincho),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            amountOut: amount,
            senderNonce: 1,
            originDomain: origin,
            destinationDomain: destination,
            destinationSettler: counterpart.addressToBytes32(),
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
        });
    }

    function _prepareGaslessOrder(
        bytes memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline
    )
        internal
        view
        returns (GaslessCrossChainOrder memory)
    {
        return _prepareGaslessOrder(
            address(baseSwap),
            kakaroto,
            uint64(origin),
            orderData,
            permitNonce,
            openDeadline,
            fillDeadline,
            OrderEncoder.orderDataType()
        );
    }

    function test__settleOrders_works() public {
        OrderData memory orderData1 = prepareOrderData();
        OrderData memory orderData2 = prepareOrderData();
        orderData2.originDomain = destination;

        bytes32[] memory _orderIds = new bytes32[](2);
        _orderIds[0] = bytes32("order1");
        _orderIds[1] = bytes32("order2");
        bytes[] memory ordersOriginData = new bytes[](2);
        ordersOriginData[0] = OrderEncoder.encode(orderData1);
        ordersOriginData[1] = OrderEncoder.encode(orderData2);
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = abi.encode("some filler data1");
        ordersFillerData[1] = abi.encode("some filler data2");

        baseSwap.settleOrders(_orderIds, ordersOriginData, ordersFillerData);
        assertEq(baseSwap.dispatchedOriginDomain(), origin);
        assertEq(baseSwap.dispatchedOrderIds(0), _orderIds[0]);
        assertEq(baseSwap.dispatchedOrderIds(1), _orderIds[1]);
        assertEq(baseSwap.dispatchedOrdersFillerData(0), abi.encode("some filler data1"));
        assertEq(baseSwap.dispatchedOrdersFillerData(1), abi.encode("some filler data2"));
    }

    function test__refundOrders_onChain_works() public {
        OrderData memory orderData1 = prepareOrderData();
        OrderData memory orderData2 = prepareOrderData();
        orderData2.originDomain = destination;

        OnchainCrossChainOrder memory order1 =
            _prepareOnchainOrder(OrderEncoder.encode(orderData1), orderData1.fillDeadline, OrderEncoder.orderDataType());
        OnchainCrossChainOrder memory order2 =
            _prepareOnchainOrder(OrderEncoder.encode(orderData2), orderData2.fillDeadline, OrderEncoder.orderDataType());

        bytes32[] memory _orderIds = new bytes32[](2);
        _orderIds[0] = bytes32("order1");
        _orderIds[1] = bytes32("order2");

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](2);
        orders[0] = order1;
        orders[1] = order2;

        baseSwap.refundOrders(orders, _orderIds);

        assertEq(baseSwap.dispatchedOriginDomain(), origin);
        assertEq(baseSwap.dispatchedOrderIds(0), _orderIds[0]);
        assertEq(baseSwap.dispatchedOrderIds(1), _orderIds[1]);
    }

    function test__refundOrders_gasless_works() public {
        uint256 permitNonce = 0;
        OrderData memory orderData1 = prepareOrderData();
        OrderData memory orderData2 = prepareOrderData();
        orderData2.originDomain = destination;

        GaslessCrossChainOrder memory order1 = _prepareGaslessOrder(OrderEncoder.encode(orderData1), permitNonce, 0, 0);
        GaslessCrossChainOrder memory order2 = _prepareGaslessOrder(OrderEncoder.encode(orderData2), permitNonce, 0, 0);

        bytes32[] memory _orderIds = new bytes32[](2);
        _orderIds[0] = bytes32("order1");
        _orderIds[1] = bytes32("order2");

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](2);
        orders[0] = order1;
        orders[1] = order2;

        baseSwap.refundOrders(orders, _orderIds);

        baseSwap.refundOrders(orders, _orderIds);

        assertEq(baseSwap.dispatchedOriginDomain(), origin);
        assertEq(baseSwap.dispatchedOrderIds(0), _orderIds[0]);
        assertEq(baseSwap.dispatchedOrderIds(1), _orderIds[1]);
    }

    function test__handleSettleOrder_works() public {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = bytes32("order1");

        // set the order as opened
        baseSwap.setOrderOpened(orderId, orderData);

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, karpincho);

        baseSwap.handleSettleOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId,
            TypeCasts.addressToBytes32(karpincho)
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.SETTLED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);
    }

    function test__handleSettleOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        bytes32 orderId = bytes32("order1");

        // set the order as opened
        baseSwap.setOrderOpened(orderId, orderData);

        deal(address(baseSwap), 1_000_000);

        uint256[] memory balancesBefore = _balances();

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, karpincho);

        baseSwap.handleSettleOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId,
            TypeCasts.addressToBytes32(karpincho)
        );

        uint256[] memory balancesAfter = _balances();

        assertEq(baseSwap.orderStatus(orderId), baseSwap.SETTLED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);
    }

    function test__handleSettleOrder_not_OPENED() public {
        bytes32 orderId = bytes32("order1");
        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleSettleOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId,
            TypeCasts.addressToBytes32(karpincho)
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__handleSettleOrder_wrong_mssgOrigin() public {
        bytes32 orderId = bytes32("order1");
        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleSettleOrder(
            wrongMsgOrigin,
            counterpart.addressToBytes32(),
            orderId,
            TypeCasts.addressToBytes32(karpincho)
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__handleSettleOrder_wrong_mssgSender() public {
        bytes32 orderId = bytes32("order1");
        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleSettleOrder(
            destination,
            wrongMsgSender,
            orderId,
            TypeCasts.addressToBytes32(karpincho)
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__handleRefundOrder_works() public {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = bytes32("order1");

        // set the order as opened
        baseSwap.setOrderOpened(orderId, orderData);

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        baseSwap.handleRefundOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.REFUNDED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] + amount);
    }

    function test__handleRefundOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        bytes32 orderId = bytes32("order1");

        // set the order as opened
        baseSwap.setOrderOpened(orderId, orderData);

        deal(address(baseSwap), 1_000_000);

        uint256[] memory balancesBefore = _balances();

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        baseSwap.handleRefundOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId
        );

        uint256[] memory balancesAfter = _balances();

        assertEq(baseSwap.orderStatus(orderId), baseSwap.REFUNDED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] + amount);
    }

    function test__handleRefundOrder_not_OPENED() public {
        bytes32 orderId = bytes32("order1");

        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleRefundOrder(
            destination,
            counterpart.addressToBytes32(),
            orderId
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__handleRefundOrder_wrong_mssgOrigin() public {
        bytes32 orderId = bytes32("order1");

        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleRefundOrder(
            wrongMsgOrigin,
            counterpart.addressToBytes32(),
            orderId
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__handleRefundOrder_wrong_mssgSender() public {
        bytes32 orderId = bytes32("order1");

        // don't set the order as opened

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = _balances(inputToken);

        baseSwap.handleRefundOrder(
            destination,
            wrongMsgSender,
            orderId
        );

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.UNKNOWN());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]]);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]]);
    }

    function test__resolveOrder_onChain_works() public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        (ResolvedCrossChainOrder memory rOrder,,) = baseSwap.resolveOrder(order);

        _assertResolvedOrder(
            rOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            counterpart.addressToBytes32(),
            counterpart.addressToBytes32(),
            1,
            address(inputToken),
            address(outputToken)
        );
    }

    function test__resolveOrder_gasless_works() public view {
        uint256 permitNonce = 0;
        OrderData memory orderData = prepareOrderData();
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(
            OrderEncoder.encode(orderData), permitNonce, uint32(block.timestamp + 10), orderData.fillDeadline
        );

        (ResolvedCrossChainOrder memory rOrder,,) = baseSwap.resolveOrder(order, new bytes(0));

        _assertResolvedOrder(
            rOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            uint32(block.timestamp + 10),
            counterpart.addressToBytes32(),
            counterpart.addressToBytes32(),
            1,
            address(inputToken),
            address(outputToken)
        );
    }

    function test__resolveOrder_InvalidOrderType() public {
        bytes32 wrongOrderType = bytes32("wrongOrderType");
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, wrongOrderType);

        vm.expectRevert(abi.encodeWithSelector(BasicSwap7683.InvalidOrderType.selector, wrongOrderType));
        baseSwap.resolveOrder(order);
    }

    function test__resolveOrder_InvalidOriginDomain() public {
        OrderData memory orderData = prepareOrderData();
        orderData.originDomain = 0;
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.expectRevert(abi.encodeWithSelector(BasicSwap7683.InvalidOriginDomain.selector, orderData.originDomain));
        baseSwap.resolveOrder(order);
    }

    function test__getOrderId_gasless_works() public view {
        OrderData memory orderData = prepareOrderData();

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        assertEq(baseSwap.getOrderId(order), OrderEncoder.id(orderData));
    }

    function test__getOrderId_onchain_works() public view {
        OrderData memory orderData = prepareOrderData();

        GaslessCrossChainOrder memory order = _prepareGaslessOrder(OrderEncoder.encode(orderData), 0, 0, 0);

        assertEq(baseSwap.getOrderId(order), OrderEncoder.id(orderData));
    }

    function test__getOrderId_onchain_InvalidOrderType() public {
        bytes32 wrongOrderType = bytes32("wrongOrderType");

        OrderData memory orderData = prepareOrderData();

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, wrongOrderType);

        vm.expectRevert(abi.encodeWithSelector(BasicSwap7683.InvalidOrderType.selector, wrongOrderType));
        baseSwap.getOrderId(order);
    }

    function test__fillOrder_ERC20_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.destinationDomain = origin;
        bytes32 orderId = OrderEncoder.id(orderData);
        bytes memory originData = OrderEncoder.encode(orderData);

        uint256[] memory balancesBefore = _balances(outputToken);

        vm.startPrank(kakaroto);

        outputToken.approve(address(baseSwap), amount);

        baseSwap.fillOrder(orderId, originData, new bytes(0));

        uint256[] memory balancesAfter = _balances(outputToken);

        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);

        vm.stopPrank();
    }

    function test__fillOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        orderData.destinationDomain = origin;
        bytes32 orderId = OrderEncoder.id(orderData);
        bytes memory originData = OrderEncoder.encode(orderData);

        uint256[] memory balancesBefore = _balances();

        vm.startPrank(kakaroto);

        baseSwap.fillOrder{ value: amount }(orderId, originData, new bytes(0));

        uint256[] memory balancesAfter = _balances();

        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);

        vm.stopPrank();
    }

    function test__fillOrder_native_InvalidNativeAmount() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        orderData.destinationDomain = origin;
        bytes32 orderId = OrderEncoder.id(orderData);
        bytes memory originData = OrderEncoder.encode(orderData);

        vm.startPrank(kakaroto);

        vm.expectRevert(Base7683.InvalidNativeAmount.selector);
        baseSwap.fillOrder{ value: amount - 1 }(orderId, originData, new bytes(0));

        vm.stopPrank();
    }

    function test__fillOrder_InvalidOrderId() public {
        OrderData memory orderData = prepareOrderData();
        orderData.destinationDomain = origin;
        bytes32 orderId = bytes32("wrongId");
        bytes memory originData = OrderEncoder.encode(orderData);

        vm.startPrank(kakaroto);

        vm.expectRevert(BasicSwap7683.InvalidOrderId.selector);
        baseSwap.fillOrder(orderId, originData, new bytes(0));

        vm.stopPrank();
    }

    function test__fillOrder_OrderFillExpired() public {
        OrderData memory orderData = prepareOrderData();
        orderData.fillDeadline = uint32(block.timestamp - 1);
        orderData.destinationDomain = origin;
        bytes32 orderId = OrderEncoder.id(orderData);
        bytes memory originData = OrderEncoder.encode(orderData);

        vm.startPrank(kakaroto);

        vm.expectRevert(BasicSwap7683.OrderFillExpired.selector);
        baseSwap.fillOrder(orderId, originData, new bytes(0));

        vm.stopPrank();
    }

    function test__fillOrder_InvalidOrderDomain() public {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = OrderEncoder.id(orderData);
        bytes memory originData = OrderEncoder.encode(orderData);

        vm.startPrank(kakaroto);

        vm.expectRevert(BasicSwap7683.InvalidOrderDomain.selector);
        baseSwap.fillOrder(orderId, originData, new bytes(0));

        vm.stopPrank();
    }
}
