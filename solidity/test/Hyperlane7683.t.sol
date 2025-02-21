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
import { Hyperlane7683 } from "../src/Hyperlane7683.sol";
import { Hyperlane7683Message } from "../src/libs/Hyperlane7683Message.sol";

contract Hyperlane7683ForTest is Hyperlane7683 {
    uint32[] public  refundedMessageOrigin;
    bytes32[] public refundedMessageSender;
    bytes32[] public refundedOrderId;
    bytes32[] public settledOrderId;
    bytes32[] public settledOrderReceiver;
    uint32[] public  settledMessageOrigin;
    bytes32[] public settledMessageSender;

    constructor(address _mailbox, address permitt2) Hyperlane7683(_mailbox, permitt2) { }

    function dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    )
        public
        payable
    {
        _dispatchSettle(_originDomain, _orderIds, _ordersFillerData);
    }

    function dispatchRefund(uint32 _originDomain, bytes32[] memory _orderIds) public payable {
        _dispatchRefund(_originDomain, _orderIds);
    }

    function _handleSettleOrder(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId,
        bytes32 _receiver
    ) internal override {
        settledMessageOrigin.push(_messageOrigin);
        settledMessageSender.push(_messageSender);
        settledOrderId.push(_orderId);
        settledOrderReceiver.push(_receiver);
    }

    function _handleRefundOrder(
        uint32 _messageOrigin,
        bytes32 _messageSender,
        bytes32 _orderId
    ) internal override {
        refundedMessageOrigin.push(_messageOrigin);
        refundedMessageSender.push(_messageSender);
        refundedOrderId.push(_orderId);
    }

    function get7383LocalDomain() public view returns (uint32) {
        return _localDomain();
    }
}

contract Hyperlane7683Test is BaseTest {
    using TypeCasts for address;

    using TypeCasts for address;

    MockHyperlaneEnvironment internal environment;

    TestInterchainGasPaymaster internal igp;

    Hyperlane7683ForTest internal originRouter;
    Hyperlane7683ForTest internal destinationRouter;

    bytes32 internal originRouterB32;
    bytes32 internal destinationRouterB32;
    bytes32 internal destinationRouterOverrideB32;

    uint256 gasPaymentQuote;
    uint256 gasPaymentQuoteOverride;
    uint256 internal constant GAS_LIMIT = 60_000;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner");
    address internal sender = makeAddr("sender");

    function _deployProxiedRouter(MockMailbox _mailbox, address _owner) internal returns (Hyperlane7683ForTest) {
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

        originRouter = _deployProxiedRouter(environment.mailboxes(origin), owner);

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
    }

    receive() external payable { }

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

    function test__dispatchSettle_works() public enrollRouters {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = bytes32("someOrderId1");
        orderIds[1] = bytes32("someOrderId2");
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = abi.encode(receiver1);
        ordersFillerData[1] = abi.encode(receiver2);

        deal(kakaroto, 1_000_000);

        vm.expectCall(
            address(environment.mailboxes(origin)),
            gasPaymentQuote,
            abi.encodeCall(
                MockMailbox.dispatch,
                (
                    destination,
                    destinationRouterB32,
                    Hyperlane7683Message.encodeSettle(orderIds, ordersFillerData),
                    StandardHookMetadata.formatMetadata(
                        uint256(0), originRouter.destinationGas(destination), kakaroto, ""
                    ),
                    IPostDispatchHook(address(originRouter.hook()))
                )
            )
        );

        vm.prank(kakaroto);
        originRouter.dispatchSettle{ value: gasPaymentQuote }(destination, orderIds, ordersFillerData);
    }

    function test__dispatchRefund_works() public enrollRouters {
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = bytes32("someOrderId1");
        orderIds[1] = bytes32("someOrderId2");

        deal(kakaroto, 1_000_000);

        vm.expectCall(
            address(environment.mailboxes(origin)),
            gasPaymentQuote,
            abi.encodeCall(
                MockMailbox.dispatch,
                (
                    destination,
                    destinationRouterB32,
                    Hyperlane7683Message.encodeRefund(orderIds),
                    StandardHookMetadata.formatMetadata(
                        uint256(0), originRouter.destinationGas(destination), kakaroto, ""
                    ),
                    IPostDispatchHook(address(originRouter.hook()))
                )
            )
        );

        vm.prank(kakaroto);
        originRouter.dispatchRefund{ value: gasPaymentQuote }(destination, orderIds);
    }

    function test__handle_settle_works() public enrollRouters {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = bytes32("someOrderId1");
        orderIds[1] = bytes32("someOrderId2");
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = abi.encode(receiver1);
        ordersFillerData[1] = abi.encode(receiver2);

        deal(kakaroto, 1_000_000);
        vm.prank(kakaroto);
        destinationRouter.dispatchSettle{ value: gasPaymentQuote }(origin, orderIds, ordersFillerData);

        environment.processNextPendingMessageFromDestination();

        assertEq(originRouter.settledMessageOrigin(0), destination);
        assertEq(originRouter.settledMessageOrigin(1), destination);

        assertEq(originRouter.settledMessageSender(0), TypeCasts.addressToBytes32(address(destinationRouter)));
        assertEq(originRouter.settledMessageSender(1), TypeCasts.addressToBytes32(address(destinationRouter)));

        assertEq(originRouter.settledOrderId(0), orderIds[0]);
        assertEq(originRouter.settledOrderId(1), orderIds[1]);

        assertEq(originRouter.settledOrderReceiver(0), TypeCasts.addressToBytes32(receiver1));
        assertEq(originRouter.settledOrderReceiver(1), TypeCasts.addressToBytes32(receiver2));
    }

    function test__handle_refund_works() public enrollRouters {
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = bytes32("someOrderId1");
        orderIds[1] = bytes32("someOrderId2");

        deal(kakaroto, 1_000_000);

        vm.prank(kakaroto);
        destinationRouter.dispatchRefund{ value: gasPaymentQuote }(origin, orderIds);

        environment.processNextPendingMessageFromDestination();

        assertEq(originRouter.refundedOrderId(0), orderIds[0]);
        assertEq(originRouter.refundedOrderId(1), orderIds[1]);
    }
}
