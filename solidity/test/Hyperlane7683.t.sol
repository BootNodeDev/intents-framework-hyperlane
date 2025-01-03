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

contract Hyperlane7683BaseTest is Test, DeployPermit2 {
    using TypeCasts for address;

    MockHyperlaneEnvironment internal environment;

    address permit2;

    uint32 internal origin = 1;
    uint32 internal destination = 2;

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

    function deployProxiedRouter(MockMailbox _mailbox, address _owner) public returns (Hyperlane7683ForTest) {
        Hyperlane7683ForTest implementation = new Hyperlane7683ForTest(address(_mailbox), permit2);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(Hyperlane7683.initialize.selector, address(0), address(0), _owner)
        );

        return Hyperlane7683ForTest(address(proxy));
    }

    function setUp() public virtual {
        environment = new MockHyperlaneEnvironment(origin, destination);

        permit2 = deployPermit2();

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
        balanceId[address(originRouter)] = 4;
        balanceId[address(destinationRouter)] = 5;
        balanceId[address(igp)] = 6;
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
            destinationSettler: destinationRouterB32,
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

    function getOrderIDFromLogs() internal returns (bytes32, ResolvedCrossChainOrder memory) {
        Vm.Log[] memory _logs = vm.getRecordedLogs();

        ResolvedCrossChainOrder memory resolvedOrder;
        bytes32 orderID;

        for (uint256 i = 0; i < _logs.length; i++) {
            Vm.Log memory _log = _logs[i];
            // // Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder)

            if (_log.topics[0] != Open.selector) {
                continue;
            }
            orderID = _log.topics[1];

            (resolvedOrder) = abi.decode(_log.data, (ResolvedCrossChainOrder));
        }
        return (orderID, resolvedOrder);
    }

    function balances(ERC20 token) internal view returns (uint256[] memory) {
        uint256[] memory _balances = new uint256[](7);
        _balances[0] = token.balanceOf(kakaroto);
        _balances[1] = token.balanceOf(karpincho);
        _balances[2] = token.balanceOf(vegeta);
        _balances[3] = token.balanceOf(counterpart);
        _balances[4] = token.balanceOf(address(originRouter));
        _balances[5] = token.balanceOf(address(destinationRouter));
        _balances[6] = token.balanceOf(address(igp));

        return _balances;
    }

    function test_settle_work() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.stopPrank();

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.startPrank(vegeta);
        outputToken.approve(address(destinationRouter), amount);
        destinationRouter.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Settle(orderIds, ordersFillerData);

        vm.deal(vegeta, gasPaymentQuote);
        uint256 balanceBefore = address(vegeta).balance;

        destinationRouter.settle{ value: gasPaymentQuote }(orderIds);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Settled(orderId, vegeta);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = balances(inputToken);

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

    // TODO tests settle reverts

    function test_refund_onchain_work() public enrollRouters {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(originRouter), amount);

        vm.recordLogs();
        originRouter.open(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.warp(orderData.fillDeadline + 1);

        OrderData[] memory ordersData = new OrderData[](1);
        ordersData[0] = orderData;

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true, address(destinationRouter));
        emit Refund(orderIds);

        vm.deal(kakaroto, gasPaymentQuote);
        uint256 balanceBefore = address(kakaroto).balance;

        destinationRouter.refund{ value: gasPaymentQuote }(orders);

        vm.expectEmit(false, false, false, true, address(originRouter));
        emit Refunded(orderId, kakaroto);

        environment.processNextPendingMessageFromDestination();

        uint256[] memory balancesAfter = balances(inputToken);

        assertTrue(originRouter.orderStatus(orderId) == originRouter.REFUNDED());
        assertTrue(destinationRouter.orderStatus(orderId) == destinationRouter.UNKNOWN());

        assertEq(
            balancesBefore[balanceId[address(originRouter)]] - amount, balancesAfter[balanceId[address(originRouter)]]
        );
        assertEq(balancesBefore[balanceId[kakaroto]] + amount, balancesAfter[balanceId[kakaroto]]);

        uint256 balanceAfter = address(kakaroto).balance;
        assertIgpPayment(balanceBefore, balanceAfter);

        vm.stopPrank();
    }

    // TODO test_refund_gasless_work
    // TODO tests refund reverts

    // TODO test_resolve_onchain

    // TODO test_resolve_gassless
}
