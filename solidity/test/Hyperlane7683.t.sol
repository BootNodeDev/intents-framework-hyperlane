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
import { IInterchainSecurityModule } from "@hyperlane-xyz/interfaces/IInterchainSecurityModule.sol";
import { IPostDispatchHook } from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";
import { TestIsm } from "@hyperlane-xyz/test/TestIsm.sol";
import { InterchainGasPaymaster } from "@hyperlane-xyz/hooks/igp/InterchainGasPaymaster.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";

import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { Base7683 } from "../src/Base7683.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder
} from "../src/ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";
import {
    BaseTest
} from "./BaseTest.sol";

event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

event Settled(bytes32 orderId, address receiver);

event Refunded(bytes32 orderId, address receiver);

contract TestInterchainGasPaymaster is InterchainGasPaymaster {
    uint256 public gasPrice = 10;

    constructor() {
        initialize(msg.sender, msg.sender);
    }

    function quoteGasPayment(uint32, uint256 gasAmount) public view override returns (uint256) {
        return gasPrice * gasAmount;
    }

    function setGasPrice(uint256 _gasPrice) public {
        gasPrice = _gasPrice;
    }

    function getDefaultGasUsage() public pure returns (uint256) {
        return DEFAULT_GAS_USAGE;
    }
}

contract Hyperlane7683ForTest is Hyperlane7683 {
    constructor(address _mailbox, address permitt2) Hyperlane7683(_mailbox, permitt2) { }

    function get7383LocalDomain() public view returns (uint32) {
        return _localDomain();
    }
}

contract Hyperlane7683BaseTest is BaseTest {
    using TypeCasts for address;

    MockHyperlaneEnvironment internal environment;

    TestInterchainGasPaymaster internal igp;

    Hyperlane7683ForTest internal originRouter;
    Hyperlane7683ForTest internal destinationRouter;

    TestIsm internal testIsm;
    bytes32 internal testIsmB32;
    bytes32 internal originRouterB32;
    bytes32 internal destinationRouterB32;
    bytes32 internal destinationRouterOverrideB32;

    uint256 gasPaymentQuote;
    uint256 gasPaymentQuoteOverride;
    uint256 internal constant GAS_LIMIT = 60_000;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");


    function deployProxiedRouter(MockMailbox _mailbox, address _owner) public returns (Hyperlane7683ForTest) {
        Hyperlane7683ForTest implementation = new Hyperlane7683ForTest(address(_mailbox), permit2);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(Hyperlane7683.initialize.selector, address(0), address(0), _owner)
        );

        return Hyperlane7683ForTest(address(proxy));
    }

    function setUp() public override {
        super.setUp();

        environment = new MockHyperlaneEnvironment(origin, destination);

        igp = new TestInterchainGasPaymaster();

        gasPaymentQuote = igp.quoteGasPayment(destination, GAS_LIMIT);

        testIsm = new TestIsm();

        originRouter = deployProxiedRouter(environment.mailboxes(origin), owner);

        destinationRouter = deployProxiedRouter(environment.mailboxes(destination), owner);

        environment.mailboxes(origin).setDefaultHook(address(igp));
        environment.mailboxes(destination).setDefaultHook(address(igp));

        originRouterB32 = TypeCasts.addressToBytes32(address(originRouter));
        destinationRouterB32 = TypeCasts.addressToBytes32(address(destinationRouter));
        testIsmB32 = TypeCasts.addressToBytes32(address(testIsm));

        _base7683 = Base7683(address(originRouter));

        balanceId[address(originRouter)] = 4;
        balanceId[address(destinationRouter)] = 5;
        balanceId[address(igp)] = 6;

        users.push(address(originRouter));
        users.push(address(destinationRouter));
        users.push(address(igp));
    }

    receive() external payable { }
}

contract Hyperlane7683Test is Hyperlane7683BaseTest {
    using TypeCasts for address;

    modifier enrollRouters() {
        vm.startPrank(owner);
        originRouter.enrollRemoteRouter(destination, destinationRouterB32);
        originRouter.setDestinationGas(destination, GAS_LIMIT);

        destinationRouter.enrollRemoteRouter(origin, originRouterB32);
        destinationRouter.setDestinationGas(origin, GAS_LIMIT);

        vm.stopPrank();
        _;
    }

    function test_localDomain() public view {
        assertEq(originRouter.get7383LocalDomain(), origin);
        assertEq(destinationRouter.get7383LocalDomain(), destination);
    }

    function testFuzz_enrollRemoteRouters(uint8 count, uint32 domain, bytes32 router) public {
        vm.assume(count > 0 && count < uint256(router) && count < domain);

        // arrange
        // count - # of domains and routers
        uint32[] memory domains = new uint32[](count);
        bytes32[] memory routers = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            domains[i] = domain - uint32(i);
            routers[i] = bytes32(uint256(router) - i);
        }

        // act
        vm.prank(owner);
        originRouter.enrollRemoteRouters(domains, routers);

        // assert
        uint32[] memory actualDomains = originRouter.domains();
        assertEq(actualDomains.length, domains.length);
        assertEq(abi.encode(originRouter.domains()), abi.encode(domains));

        for (uint256 i = 0; i < count; i++) {
            bytes32 actualRouter = originRouter.routers(domains[i]);

            assertEq(actualRouter, routers[i]);
            assertEq(actualDomains[i], domains[i]);
        }
    }

    function assertIgpPayment(uint256 _balanceBefore, uint256 _balanceAfter) private view {
        uint256 expectedGasPayment = GAS_LIMIT * igp.gasPrice();
        assertEq(_balanceBefore - _balanceAfter, expectedGasPayment);
        assertEq(address(igp).balance, expectedGasPayment);
    }

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
            fillDeadline: uint32(block.timestamp + 100),
            data: new bytes(0)
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


    function test_settle_work() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = _getOrderIDFromLogs();

        vm.stopPrank();

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        vm.deal(vegeta, gasPaymentQuote);
        uint256 balanceBefore = address(vegeta).balance;

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Settled(orderId, vegeta);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = _balances(inputToken);

        assertTrue(originRouter.orderStatus(orderId) == originRouter.SETTLED());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.FILLED());

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[vegeta]] + amount, balancesAfter[balanceId[vegeta]]);

        uint256 balanceAfter = address(vegeta).balance;
        assertIgpPayment(balanceBefore, balanceAfter);

        vm.stopPrank();
    }

    function settle_multiple_orders_works() public enrollRouters {
        OrderData memory orderData1 = prepareOrderData();
        OnchainCrossChainOrder memory order1 =
            _prepareOnchainOrder(OrderEncoder.encode(orderData1), orderData1.fillDeadline, OrderEncoder.orderDataType());
        bytes32 orderId1 = OrderEncoder.id(orderData1);

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order1);

        OrderData memory orderData2 = prepareOrderData();
        orderData2.senderNonce += 1;
        OnchainCrossChainOrder memory order2 =
            _prepareOnchainOrder(OrderEncoder.encode(orderData2), orderData2.fillDeadline, OrderEncoder.orderDataType());
        bytes32 orderId2 = OrderEncoder.id(orderData2);

        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order2);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount*2);
        destinationRouter.fill(orderId1, OrderEncoder.encode(orderData1), fillerData);
        destinationRouter.fill(orderId2, OrderEncoder.encode(orderData2), fillerData);

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = fillerData;
        ordersFillerData[1] = fillerData;

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        vm.deal(vegeta, gasPaymentQuote);
        uint256 balanceBefore = address(vegeta).balance;

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Settled(orderId1, vegeta);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Settled(orderId2, vegeta);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = _balances(inputToken);

        assertTrue(originRouter.orderStatus(orderId1) == originRouter.SETTLED());
        assertTrue(originRouter.orderStatus(orderId2) == originRouter.SETTLED());
        assertTrue(destinationRouter.orderStatus(orderId1) == destinationRouter.FILLED());
        assertTrue(destinationRouter.orderStatus(orderId2) == destinationRouter.FILLED());

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount*2, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[vegeta]] + amount*2, balancesAfter[balanceId[vegeta]]);

        uint256 balanceAfter = address(vegeta).balance;
        assertIgpPayment(balanceBefore, balanceAfter);

        vm.stopPrank();
    }

    function test_settle_InvalidOrderOrigin() public enrollRouters {
        bytes32 invalidOrderId = bytes32 ("someInvalidOrderId");

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = invalidOrderId;

        OrderData memory orderData = prepareOrderData();
        orderIds[1] = OrderEncoder.id(orderData);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(OrderEncoder.id(orderData), OrderEncoder.encode(orderData), fillerData);

        vm.deal(vegeta, gasPaymentQuote);

        vm.expectRevert(Hyperlane7683.InvalidOrderOrigin.selector);
        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.stopPrank();
    }

    function test_settle_InvalidOrderStatus() public enrollRouters {
        OrderData memory orderData1 = prepareOrderData();
        bytes32 orderId1 = OrderEncoder.id(orderData1);

        OrderData memory orderData2 = prepareOrderData();
        orderData2.senderNonce += 1;
        bytes32 orderId2 = OrderEncoder.id(orderData2);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(orderId1, OrderEncoder.encode(orderData1), fillerData);

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = fillerData;
        ordersFillerData[1] = fillerData;

        vm.deal(vegeta, gasPaymentQuote);

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.stopPrank();
    }

    function test__handleSettleOrder_should_skip_if_not_opened() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = OrderEncoder.id(orderData);

        // the order is "filled" on destination buy was never opened on origin

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.deal(vegeta, gasPaymentQuote);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        deal(address(inputToken), address(originRouter), 1000, true);
        uint256[] memory balancesBefore = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        assertTrue(originRouter.orderStatus(orderId) == originRouter.UNKNOWN());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.FILLED());

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(
            balancesBefore[balanceId[address(originRouter)]], balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[vegeta]], balancesAfter[balanceId[vegeta]]);

        vm.stopPrank();
    }

    function test_re_try_settle_should_work() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        bytes32 orderId = OrderEncoder.id(orderData);

        // the order is "filled" on destination buy was never opened on origin

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.deal(vegeta, gasPaymentQuote);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        deal(address(inputToken), address(originRouter), 1000, true);
        uint256[] memory balancesBefore = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        assertTrue(originRouter.orderStatus(orderId) == originRouter.UNKNOWN());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.FILLED());

        uint256[] memory balancesAfter = _balances(inputToken);

        assertEq(
            balancesBefore[balanceId[address(originRouter)]], balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[vegeta]], balancesAfter[balanceId[vegeta]]);

        vm.stopPrank();

        // once the order is opened, the filler can retry settling
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        vm.stopPrank();

        vm.deal(vegeta, gasPaymentQuote);

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        deal(address(inputToken), address(originRouter), 1000, true);
        balancesBefore = _balances(inputToken);

        environment.processNextPendingMessageFromDestination();

        assertTrue(originRouter.orderStatus(orderId) == originRouter.SETTLED());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.FILLED());

        balancesAfter = _balances(inputToken);

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[vegeta]] + amount, balancesAfter[balanceId[vegeta]]);

        vm.stopPrank();
    }

    // TODO: this sims to be unreachable
    // function test__handleSettleOrder_InvalidDomain() public enrollRouters {}

    function test_refund_onchain_work() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = _getOrderIDFromLogs();

        vm.warp(orderData.fillDeadline + 1);

        // OrderData[] memory ordersData = new OrderData[](1);
        // ordersData[0] = orderData;

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Refund(orderIds);

        vm.deal(kakaroto, gasPaymentQuote);
        uint256 balanceBefore = address(kakaroto).balance;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = _balances(inputToken);

        assertTrue(originRouter.orderStatus(orderId) == originRouter.REFUNDED());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.REFUNDED());

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[kakaroto]] + amount, balancesAfter[balanceId[kakaroto]]);

        uint256 balanceAfter = address(kakaroto).balance;
        assertIgpPayment(balanceBefore, balanceAfter);

        vm.stopPrank();
    }

    function test_refund_gasless_work(uint32 _fillDeadline, uint32 _openDeadline) public enrollRouters {
        vm.assume(_openDeadline >= block.timestamp);
        vm.assume(_fillDeadline < block.timestamp + 86400);

        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        OrderData memory orderData = prepareOrderData();
        orderData.fillDeadline = _fillDeadline;

        uint256 permitNonce = 0;
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, _openDeadline, _fillDeadline);


        bytes32 witness = originRouter.witnessHash(originRouter.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(originRouter),
            witness,
            address(inputToken),
            permitNonce,
            amount,
            _openDeadline,
            kakarotoPK
        );
        vm.stopPrank();

        vm.recordLogs();
        vm.prank(karpincho);
        originRouter.openFor(order, sig, new bytes(0));

        (bytes32 orderId,) = _getOrderIDFromLogs();

        vm.warp(orderData.fillDeadline + 1);

        OrderData[] memory ordersData = new OrderData[](1);
        ordersData[0] = orderData;

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        uint256[] memory balancesBefore = _balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Refund(orderIds);

        vm.deal(kakaroto, gasPaymentQuote);
        uint256 balanceBefore = address(kakaroto).balance;

        vm.prank(kakaroto);
        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = _balances(inputToken);

        assertTrue(originRouter.orderStatus(orderId) == originRouter.REFUNDED());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.REFUNDED());

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[kakaroto]] + amount, balancesAfter[balanceId[kakaroto]]);

        uint256 balanceAfter = address(kakaroto).balance;
        assertIgpPayment(balanceBefore, balanceAfter);

        vm.stopPrank();
    }

    function test_refund_InvalidOrderStatus() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        orderData.fillDeadline = _fillDeadline;

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(OrderEncoder.id(orderData), OrderEncoder.encode(orderData), fillerData);
        vm.stopPrank();

        vm.warp(orderData.fillDeadline + 1);

        vm.deal(kakaroto, gasPaymentQuote);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.prank(kakaroto);
        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        destinationRouter.refund{ value: gasPaymentQuote }(orders);
    }

    function test_refund_OrderFillNotExpired() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        orderData.fillDeadline = _fillDeadline;

        vm.warp(orderData.fillDeadline);

        vm.deal(kakaroto, gasPaymentQuote);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.prank(kakaroto);
        vm.expectRevert(Hyperlane7683.OrderFillNotExpired.selector);
        destinationRouter.refund{ value: gasPaymentQuote }(orders);
    }

    function test_refund_InvalidOrderDomain() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        orderData.fillDeadline = _fillDeadline;

        vm.warp(orderData.fillDeadline + 1);

        vm.deal(kakaroto, gasPaymentQuote);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.prank(kakaroto);
        vm.expectRevert(Hyperlane7683.InvalidOrderDomain.selector);
        originRouter.refund{ value: gasPaymentQuote }(orders);
    }

    function test_refund_MustHaveRemoteCounterpart() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();
        orderData.originDomain = 3;
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        orderData.fillDeadline = _fillDeadline;

        vm.warp(orderData.fillDeadline + 1);

        vm.deal(kakaroto, gasPaymentQuote);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.prank(kakaroto);
        vm.expectRevert("No router enrolled for domain: 3");
        destinationRouter.refund{ value: gasPaymentQuote }(orders);
    }

    function test__fillOrder_InvalidOrderId() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();

        orderData.fillDeadline = _fillDeadline;

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        vm.expectRevert(Hyperlane7683.InvalidOrderId.selector);
        destinationRouter.fill("invalidOrderId", OrderEncoder.encode(orderData), fillerData);

        vm.stopPrank();
    }

    function test__fillOrder_OrderFillExpired() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();

        orderData.fillDeadline = _fillDeadline;

        vm.warp(orderData.fillDeadline + 1);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        vm.expectRevert(Hyperlane7683.OrderFillExpired.selector);
        destinationRouter.fill(OrderEncoder.id(orderData), OrderEncoder.encode(orderData), fillerData);

        vm.stopPrank();
    }

    function test__fillOrder_InvalidOrderDomain() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();
        orderData.destinationDomain = 3;
        orderData.fillDeadline = _fillDeadline;

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        vm.expectRevert(Hyperlane7683.InvalidOrderDomain.selector);
        destinationRouter.fill(OrderEncoder.id(orderData), OrderEncoder.encode(orderData), fillerData);

        vm.stopPrank();
    }

    function test__fillOrder_works() public enrollRouters {
        uint32 _fillDeadline = uint32(block.timestamp) + 100;

        OrderData memory orderData = prepareOrderData();

        orderData.fillDeadline = _fillDeadline;

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        uint256[] memory balancesBefore = _balances(outputToken);

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);

        destinationRouter.fill(OrderEncoder.id(orderData), OrderEncoder.encode(orderData), fillerData);

        uint256[] memory balancesAfter = _balances(outputToken);

        assertEq(balancesBefore[balanceId[vegeta]] - amount, balancesAfter[balanceId[vegeta]]);
        assertEq(balancesBefore[balanceId[karpincho]] + amount, balancesAfter[balanceId[karpincho]]);

        vm.stopPrank();
    }

    function test_resolve_onchain_works(uint32 _fillDeadline) public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        orderData.fillDeadline = _fillDeadline;

        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        ResolvedCrossChainOrder memory resolvedOrder = originRouter.resolve(order);

        assertResolvedOrder(
            resolvedOrder,
            OrderEncoder.encode(orderData),
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            destinationRouterB32,
            destinationRouterB32,
            origin
        );
    }

    function test_resolve_offchain_works(uint32 _fillDeadline, uint32 _openDeadline) public enrollRouters {
        vm.assume(_openDeadline >= block.timestamp);
        vm.assume(_fillDeadline < block.timestamp + 86400);

        OrderData memory orderData = prepareOrderData();
        orderData.fillDeadline = _fillDeadline;

        uint256 permitNonce = 0;
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(OrderEncoder.encode(orderData), permitNonce, _openDeadline, _fillDeadline);

        ResolvedCrossChainOrder memory resolvedOrder = originRouter.resolveFor(order, new bytes(0));

        assertResolvedOrder(
            resolvedOrder,
            OrderEncoder.encode(orderData),
            kakaroto,
            _fillDeadline,
            _openDeadline,
            destinationRouterB32,
            destinationRouterB32,
            origin
        );
    }

    function test_resolve_InvalidOrderType(uint32 _fillDeadline) public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, bytes32("someInvalidType"));

        vm.expectRevert(abi.encodeWithSelector(Hyperlane7683.InvalidOrderType.selector, bytes32("someInvalidType")));
        originRouter.resolve(order);
    }
    function test_resolve_InvalidOriginDomain(uint32 _fillDeadline) public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        vm.expectRevert(abi.encodeWithSelector(Hyperlane7683.InvalidOriginDomain.selector, origin));
        destinationRouter.resolve(order);
    }

    function test_resolve__mustHaveRemoteRouter(uint32 _fillDeadline) public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        orderData.destinationDomain = 3;
        OnchainCrossChainOrder memory order =
            _prepareOnchainOrder(OrderEncoder.encode(orderData), _fillDeadline, OrderEncoder.orderDataType());

        vm.expectRevert("No router enrolled for domain: 3");
        originRouter.resolve(order);
    }
}
