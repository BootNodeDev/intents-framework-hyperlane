// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";

import { BasicSwap7683 } from "../src/BasicSwap7683.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";

event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Settled(bytes32 orderId, address receiver);

event Refunded(bytes32 orderId, address receiver);

contract BasicSwap7683ForTest is BasicSwap7683 {
    constructor(address permitt2) BasicSwap7683(permitt2) { }

    uint32 public dispatchedOriginDomain;
    bytes32[] public dispatchedOrderIds;
    bytes[] public dispatchedOrdersFillerData;

    function settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory ordersOriginData,
        bytes[] memory ordersFillerData
    )
        public
    {
        _settleOrders(_orderIds,ordersOriginData,ordersFillerData);
    }

    function refundOrders(OnchainCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) public {
        _refundOrders(_orders, _orderIds);
    }

    function refundOrders(GaslessCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) public {
        _refundOrders(_orders, _orderIds);
    }

    function resolveOrder(GaslessCrossChainOrder memory order)
        public
        view
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolveOrder(order);
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

    function handleSettleOrder(bytes32 _orderId, bytes32 _receiver) public {
        _handleSettleOrder(_orderId, _receiver);
    }

    function handleRefundOrder(bytes32 _orderId) public {
        _handleRefundOrder(_orderId);
    }

    function setOrder(bytes32 _orderId, ResolvedCrossChainOrder memory rOrder) public {
        orders[_orderId] = abi.encode(rOrder);
        orderStatus[_orderId] = OPENED;
    }

    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    ) internal override {
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

contract BasicSwap7683BaseTest is Test, DeployPermit2 {
    using TypeCasts for address;

    address permit2;

    uint32 internal origin = 1;
    uint32 internal destination = 2;

    BasicSwap7683ForTest internal baseSwap;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");

    ERC20 internal inputToken;
    ERC20 internal outputToken;

    address internal kakaroto;
    uint256 internal kakarotoPK;
    address internal karpincho;
    uint256 internal karpinchoPK;
    address internal vegeta;
    uint256 internal vegetaPK;
    address internal counterpart = makeAddr("counterpart");

    uint256 internal amount = 100;

    mapping(address => uint256) internal balanceId;

    function setUp() public virtual {
        permit2 = deployPermit2();

        baseSwap = new BasicSwap7683ForTest(permit2);

        (kakaroto, kakarotoPK) = makeAddrAndKey("kakaroto");
        (karpincho, karpinchoPK) = makeAddrAndKey("karpincho");
        (vegeta, vegetaPK) = makeAddrAndKey("vegeta");

        inputToken = new ERC20("Input Token", "IN");
        outputToken = new ERC20("Output Token", "OUT");

        deal(address(inputToken), kakaroto, 1_000_000, true);
        deal(address(inputToken), karpincho, 1_000_000, true);
        deal(address(inputToken), vegeta, 1_000_000, true);
        deal(address(outputToken), kakaroto, 1_000_000, true);
        deal(address(outputToken), karpincho, 1_000_000, true);
        deal(address(outputToken), vegeta, 1_000_000, true);

        balanceId[kakaroto] = 0;
        balanceId[karpincho] = 1;
        balanceId[vegeta] = 2;
        balanceId[counterpart] = 3;
        balanceId[address(baseSwap)] = 4;
    }

    receive() external payable { }
}

contract BasicSwap7683Test is BasicSwap7683BaseTest {
    using TypeCasts for address;

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
            destinationSettler: bytes32("somedest"),
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
        });
    }

    function prepareOnchainOrder(
        OrderData memory orderData,
        uint32 fillDeadline,
        bytes32 orderDataType
    )
        internal
        pure
        returns (OnchainCrossChainOrder memory)
    {
        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: OrderEncoder.encode(orderData)
        });
    }

    function prepareGaslessOrder(
        bytes memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline
    )
        internal
        view
        returns (GaslessCrossChainOrder memory)
    {
        return GaslessCrossChainOrder({
            originSettler: address(baseSwap),
            user: kakaroto,
            nonce: permitNonce,
            originChainId: uint64(origin),
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderDataType: OrderEncoder.orderDataType(),
            orderData: orderData
        });
    }

    function balances(ERC20 token) internal view returns (uint256[] memory) {
        uint256[] memory _balances = new uint256[](7);
        _balances[0] = token.balanceOf(kakaroto);
        _balances[1] = token.balanceOf(karpincho);
        _balances[2] = token.balanceOf(vegeta);
        _balances[3] = token.balanceOf(counterpart);
        _balances[4] = token.balanceOf(address(baseSwap));

        return _balances;
    }

    function balances() internal view returns (uint256[] memory) {
        uint256[] memory _balances = new uint256[](7);
        _balances[0] = kakaroto.balance;
        _balances[1] = karpincho.balance;
        _balances[2] = vegeta.balance;
        _balances[3] = counterpart.balance;
        _balances[4] = address(baseSwap).balance;

        return _balances;
    }

    function assertResolvedOrder(
        ResolvedCrossChainOrder memory resolvedOrder,
        bytes memory orderData,
        address _user,
        uint32 _fillDeadline,
        uint32 _openDeadline
    )
        internal
        view
    {
        assertEq(resolvedOrder.maxSpent.length, 1);
        assertEq(resolvedOrder.maxSpent[0].token, TypeCasts.addressToBytes32(address(outputToken)));
        assertEq(resolvedOrder.maxSpent[0].amount, amount);
        assertEq(resolvedOrder.maxSpent[0].recipient, bytes32("somedest"));
        assertEq(resolvedOrder.maxSpent[0].chainId, destination);

        assertEq(resolvedOrder.minReceived.length, 1);
        assertEq(resolvedOrder.minReceived[0].token, TypeCasts.addressToBytes32(address(inputToken)));
        assertEq(resolvedOrder.minReceived[0].amount, amount);
        assertEq(resolvedOrder.minReceived[0].recipient, bytes32(0));
        assertEq(resolvedOrder.minReceived[0].chainId, origin);

        assertEq(resolvedOrder.fillInstructions.length, 1);
        assertEq(resolvedOrder.fillInstructions[0].destinationChainId, destination);
        assertEq(resolvedOrder.fillInstructions[0].destinationSettler, bytes32("somedest"));

        assertEq(resolvedOrder.fillInstructions[0].originData, orderData);

        assertEq(resolvedOrder.user, _user);
        assertEq(resolvedOrder.originChainId, 1);
        assertEq(resolvedOrder.openDeadline, _openDeadline);
        assertEq(resolvedOrder.fillDeadline, _fillDeadline);
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
            prepareOnchainOrder(orderData1, orderData1.fillDeadline, OrderEncoder.orderDataType());
        OnchainCrossChainOrder memory order2 =
            prepareOnchainOrder(orderData2, orderData2.fillDeadline, OrderEncoder.orderDataType());

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

        GaslessCrossChainOrder memory order1 = prepareGaslessOrder(OrderEncoder.encode(orderData1), permitNonce, 0, 0);
        GaslessCrossChainOrder memory order2 = prepareGaslessOrder(OrderEncoder.encode(orderData2), permitNonce, 0, 0);

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
        ResolvedCrossChainOrder memory rOrder = baseSwap.resolvedOrder(OrderEncoder.orderDataType(), kakaroto, 0, 0, OrderEncoder.encode(orderData));
        baseSwap.setOrder(orderId, rOrder);

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, karpincho);

        baseSwap.handleSettleOrder(orderId, TypeCasts.addressToBytes32(karpincho));

        uint256[] memory balancesAfter = balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.SETTLED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);
    }

    function test__handleSettleOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        bytes32 orderId = bytes32("order1");
        ResolvedCrossChainOrder memory rOrder = baseSwap.resolvedOrder(OrderEncoder.orderDataType(), kakaroto, 0, 0, OrderEncoder.encode(orderData));
        baseSwap.setOrder(orderId, rOrder);

        deal(address(baseSwap), 1_000_000);

        uint256[] memory balancesBefore = balances();

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, karpincho);

        baseSwap.handleSettleOrder(orderId, TypeCasts.addressToBytes32(karpincho));

        uint256[] memory balancesAfter = balances();

        assertEq(baseSwap.orderStatus(orderId), baseSwap.SETTLED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[karpincho]], balancesBefore[balanceId[karpincho]] + amount);
    }

    function test__handleRefundOrder_works() public {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = bytes32("order1");
        ResolvedCrossChainOrder memory rOrder = baseSwap.resolvedOrder(OrderEncoder.orderDataType(), kakaroto, 0, 0, OrderEncoder.encode(orderData));
        baseSwap.setOrder(orderId, rOrder);

        deal(address(inputToken), address(baseSwap), 1_000_000, true);

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        baseSwap.handleRefundOrder(orderId);

        uint256[] memory balancesAfter = balances(inputToken);

        assertEq(baseSwap.orderStatus(orderId), baseSwap.REFUNDED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] + amount);
    }

    function test__handleRefundOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        bytes32 orderId = bytes32("order1");
        ResolvedCrossChainOrder memory rOrder = baseSwap.resolvedOrder(OrderEncoder.orderDataType(), kakaroto, 0, 0, OrderEncoder.encode(orderData));
        baseSwap.setOrder(orderId, rOrder);

        deal(address(baseSwap), 1_000_000);

        uint256[] memory balancesBefore = balances();

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        baseSwap.handleRefundOrder(orderId);

        uint256[] memory balancesAfter = balances();

        assertEq(baseSwap.orderStatus(orderId), baseSwap.REFUNDED());
        assertEq(balancesAfter[balanceId[address(baseSwap)]], balancesBefore[balanceId[address(baseSwap)]] - amount);
        assertEq(balancesAfter[balanceId[kakaroto]], balancesBefore[balanceId[kakaroto]] + amount);
    }

    function test__resolveOrder_onChain_works() public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order = prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        (ResolvedCrossChainOrder memory rOrder,,) = baseSwap.resolveOrder(order);

        assertResolvedOrder(rOrder, order.orderData, kakaroto, orderData.fillDeadline, type(uint32).max);
    }

    function test__resolveOrder_gasless_works() public view {
        uint256 permitNonce = 0;
        OrderData memory orderData = prepareOrderData();
        GaslessCrossChainOrder memory order = prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, uint32(block.timestamp + 10), orderData.fillDeadline);

        (ResolvedCrossChainOrder memory rOrder, , ) = baseSwap.resolveOrder(order);

        assertResolvedOrder(rOrder, order.orderData, kakaroto, orderData.fillDeadline, uint32(block.timestamp + 10));
    }




    // TODO test_refund_gasless_work
    // TODO tests refund reverts

    // TODO test_resolve_onchain

    // TODO test_resolve_gassless
}
