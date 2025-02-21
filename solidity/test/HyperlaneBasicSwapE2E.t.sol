// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { StandardHookMetadata } from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import { MockMailbox } from "@hyperlane-xyz/mock/MockMailbox.sol";
import { MockHyperlaneEnvironment } from "@hyperlane-xyz/mock/MockHyperlaneEnvironment.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPostDispatchHook } from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";

import { BaseTest, TestInterchainGasPaymaster } from "./BaseTest.sol";
import { Base7683 } from "../src/Base7683.sol";
import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { Hyperlane7683Message } from "../src/libs/Hyperlane7683Message.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";
import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Refunded(bytes32 orderId, address receiver);

contract HyperlaneBasicSwapE2E is BaseTest {
    using TypeCasts for address;

    using TypeCasts for address;

    MockHyperlaneEnvironment internal environment;

    TestInterchainGasPaymaster internal igp;

    Hyperlane7683 internal originRouter;
    Hyperlane7683 internal destinationRouter;

    bytes32 internal originRouterB32;
    bytes32 internal destinationRouterB32;
    bytes32 internal destinationRouterOverrideB32;

    uint256 gasPaymentQuote;
    uint256 gasPaymentQuoteOverride;
    uint256 internal constant GAS_LIMIT = 60_000;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");

    function _deployProxiedRouter(MockMailbox _mailbox, address _owner) internal returns (Hyperlane7683) {
        Hyperlane7683 implementation = new Hyperlane7683(address(_mailbox), permit2);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(Hyperlane7683.initialize.selector, address(0), address(0), _owner)
        );

        return Hyperlane7683(address(proxy));
    }

    function setUp() public override {
        super.setUp();

        environment = new MockHyperlaneEnvironment(origin, destination);

        igp = new TestInterchainGasPaymaster();

        gasPaymentQuote = igp.quoteGasPayment(destination, GAS_LIMIT);

        originRouter = _deployProxiedRouter(environment.mailboxes(origin), owner);

        _base7683 = Base7683(address(originRouter));

        destinationRouter = _deployProxiedRouter(environment.mailboxes(destination), owner);

        environment.mailboxes(origin).setDefaultHook(address(igp));
        environment.mailboxes(destination).setDefaultHook(address(igp));

        originRouterB32 = TypeCasts.addressToBytes32(address(originRouter));
        destinationRouterB32 = TypeCasts.addressToBytes32(address(destinationRouter));

        balanceId[address(originRouter)] = 4;
        balanceId[address(destinationRouter)] = 5;
        balanceId[address(igp)] = 6;

        users.push(address(originRouter));
        users.push(address(destinationRouter));
        users.push(address(igp));

        vm.startPrank(owner);
        originRouter.enrollRemoteRouter(destination, destinationRouterB32);
        originRouter.setDestinationGas(destination, GAS_LIMIT);

        destinationRouter.enrollRemoteRouter(origin, originRouterB32);
        destinationRouter.setDestinationGas(origin, GAS_LIMIT);

        vm.stopPrank();
    }

    receive() external payable { }

    function _prepareOrderData() internal view returns (OrderData memory) {
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
            destinationSettler: address(destinationRouter).addressToBytes32(),
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
            address(originRouter),
            kakaroto,
            uint64(origin),
            orderData,
            permitNonce,
            openDeadline,
            fillDeadline,
            OrderEncoder.orderDataType()
        );
    }

    function test_open_fill_settle() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        uint256[] memory balancesBeforeOpen = _balances(inputToken);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // fill
        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        uint256[] memory balancesBeforeFill = _balances(outputToken);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Filled(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        destinationRouter.fill(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = destinationRouter.filledOrders(orderId);

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances(outputToken);

        assertEq(balancesAfterFill[balanceId[vegeta]], balancesBeforeFill[balanceId[vegeta]] - amount);
        assertEq(balancesAfterFill[balanceId[karpincho]], balancesBeforeFill[balanceId[karpincho]] + amount);

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterSettle = _balances(inputToken);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(balancesAfterSettle[balanceId[vegeta]], balancesBeforeSettle[balanceId[vegeta]] + amount);
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount
        );
    }

    function test_native_open_fill_settle() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.open{ value: amount }(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(0),
            address(0)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto, true);

        // fill
        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeFill = _balances();

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Filled(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        destinationRouter.fill{ value: amount }(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = destinationRouter.filledOrders(orderId);

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances();

        assertEq(balancesAfterFill[balanceId[vegeta]], balancesBeforeFill[balanceId[vegeta]] - amount);
        assertEq(balancesAfterFill[balanceId[karpincho]], balancesBeforeFill[balanceId[karpincho]] + amount);

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances();

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterSettle = _balances();

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(balancesAfterSettle[balanceId[vegeta]], balancesBeforeSettle[balanceId[vegeta]] + amount);
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount
        );
    }

    function test_openFor_fill_settle() public {
        // open
        uint256 permitNonce = 0;
        OrderData memory orderData = _prepareOrderData();

        uint32 openDeadline = uint32(block.timestamp + 10);

        GaslessCrossChainOrder memory order =
            _prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, openDeadline, orderData.fillDeadline);

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        bytes32 witness = originRouter.witnessHash(originRouter.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(originRouter), witness, address(inputToken), permitNonce, amount, openDeadline, kakarotoPK
        );

        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            openDeadline,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // fill
        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        uint256[] memory balancesBeforeFill = _balances(outputToken);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Filled(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        destinationRouter.fill(orderId, resolvedOrder.fillInstructions[0].originData, fillerData);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = destinationRouter.filledOrders(orderId);

        assertEq(_originData, resolvedOrder.fillInstructions[0].originData);
        assertEq(_fillerData, fillerData);

        uint256[] memory balancesAfterFill = _balances(outputToken);

        assertEq(balancesAfterFill[balanceId[vegeta]], balancesBeforeFill[balanceId[vegeta]] - amount);
        assertEq(balancesAfterFill[balanceId[karpincho]], balancesBeforeFill[balanceId[karpincho]] + amount);

        // settle
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.stopPrank();

        uint256[] memory balancesBeforeSettle = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterSettle = _balances(inputToken);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.FILLED());
        assertEq(balancesAfterSettle[balanceId[vegeta]], balancesBeforeSettle[balanceId[vegeta]] + amount);
        assertEq(
            balancesAfterSettle[balanceId[address(originRouter)]],
            balancesBeforeSettle[balanceId[address(originRouter)]] - amount
        );
    }

    function test_open_refund() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        uint256[] memory balancesBeforeOpen = _balances(inputToken);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }

    function test_open_refund_wrong_mssgOrigin() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.destinationDomain = 678;

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = _getOrderIDFromLogs();

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.OPENED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]]
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]]);
    }

    function test_open_refund_wrong_mssgSender() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.destinationSettler = makeAddr("someSettler").addressToBytes32();

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = _getOrderIDFromLogs();

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.OPENED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]]
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]]);
    }

    function test_native_open_refund() public {
        // open
        OrderData memory orderData = _prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.open{ value: amount }(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            type(uint32).max,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(0),
            address(0)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto, true);

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances();

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterRefund = _balances();

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }

    function test_openFor_refund() public {
        // open
        uint256 permitNonce = 0;
        OrderData memory orderData = _prepareOrderData();

        uint32 openDeadline = uint32(block.timestamp + 10);

        GaslessCrossChainOrder memory order =
            _prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, openDeadline, orderData.fillDeadline);

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        bytes32 witness = originRouter.witnessHash(originRouter.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(originRouter), witness, address(inputToken), permitNonce, amount, openDeadline, kakarotoPK
        );

        vm.startPrank(vegeta);

        uint256[] memory balancesBeforeOpen = _balances();

        vm.recordLogs();
        originRouter.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            order.orderData,
            kakaroto,
            orderData.fillDeadline,
            openDeadline,
            address(destinationRouter).addressToBytes32(),
            address(destinationRouter).addressToBytes32(),
            origin,
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, order.orderData, balancesBeforeOpen, kakaroto);

        // refund
        vm.warp(orderData.fillDeadline + 1);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        assertEq(destinationRouter.orderStatus(orderId), destinationRouter.UNKNOWN());

        uint256[] memory balancesBeforeRefund = _balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfterRefund = _balances(inputToken);

        assertEq(originRouter.orderStatus(orderId), originRouter.REFUNDED());
        assertEq(
            balancesAfterRefund[balanceId[address(originRouter)]],
            balancesBeforeRefund[balanceId[address(originRouter)]] - amount
        );
        assertEq(balancesAfterRefund[balanceId[kakaroto]], balancesBeforeRefund[balanceId[kakaroto]] + amount);
    }
}
