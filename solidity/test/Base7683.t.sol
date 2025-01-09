// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { IEIP712 } from "@uniswap/permit2/src/interfaces/IEIP712.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";
import { Base7683 } from "../src/Base7683.sol";

import { BaseTest } from "./BaseTest.sol";

event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

event Refund(bytes32[] orderIds);

contract Base7683ForTest is Base7683, StdCheats {
    bytes32 public counterpart;

    bool internal _native = false;
    uint32 internal _origin;
    uint32 internal _destination;
    address internal inputToken;
    address internal outputToken;

    bytes32 public filledId;
    bytes public filledOriginData;
    bytes public filledFillerData;

    bytes32[] public settledOrderIds;
    bytes[] public settledOrdersOriginData;
    bytes[] public settledOrdersFillerData;

    bytes32[] public refundedOrderIds;

    constructor(
        address _permit2,
        uint32 _local,
        uint32 _remote,
        address _inputToken,
        address _outputToken
    )
        Base7683(_permit2)
    {
        _origin = _local;
        _destination = _remote;
        inputToken = _inputToken;
        outputToken = _outputToken;
    }

    function setNative(bool _isNative) public {
        _native = _isNative;
    }

    function setCounterpart(bytes32 _counterpart) public {
        counterpart = _counterpart;
    }

    function _resolveOrder(GaslessCrossChainOrder memory order)
        internal
        view
        override
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolvedOrder(order.user, order.openDeadline, order.fillDeadline, order.orderData);
    }

    function _resolveOrder(OnchainCrossChainOrder memory order)
        internal
        view
        override
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolvedOrder(msg.sender, type(uint32).max, order.fillDeadline, order.orderData);
    }

    function _resolvedOrder(
        address _sender,
        uint32 _openDeadline,
        uint32 _fillDeadline,
        bytes memory _orderData
    )
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce)
    {
        // this can be used by the filler to approve the tokens to be spent on destination
        Output[] memory maxSpent = new Output[](1);
        maxSpent[0] = Output({
            token: _native ? TypeCasts.addressToBytes32(address(0)) : TypeCasts.addressToBytes32(outputToken),
            amount: 100,
            recipient: counterpart,
            chainId: _destination
        });

        // this can be used by the filler know how much it can expect to receive
        Output[] memory minReceived = new Output[](1);
        minReceived[0] = Output({
            token: _native ? TypeCasts.addressToBytes32(address(0)) : TypeCasts.addressToBytes32(inputToken),
            amount: 100,
            recipient: bytes32(0),
            chainId: _origin
        });

        // this can be user by the filler to know how to fill the order
        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        fillInstructions[0] = FillInstruction({
            destinationChainId: _destination,
            destinationSettler: counterpart,
            originData: _orderData
        });

        orderId = keccak256("someId");

        resolvedOrder = ResolvedCrossChainOrder({
            user: _sender,
            originChainId: _origin,
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            orderId: orderId,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });

        nonce = 1;
    }

    function _getOrderId(GaslessCrossChainOrder memory order) internal pure override returns (bytes32) {
        return keccak256(order.orderData);
    }

    function _getOrderId(OnchainCrossChainOrder memory order) internal pure override returns (bytes32) {
        return keccak256(order.orderData);
    }

    function _fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) internal override {
        filledId = _orderId;
        filledOriginData = _originData;
        filledFillerData = _fillerData;
    }

    function _settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory _ordersOriginData,
        bytes[] memory _ordersFillerData
    )
        internal
        override
    {
        settledOrderIds = _orderIds;
        settledOrdersOriginData = _ordersOriginData;
        settledOrdersFillerData = _ordersFillerData;
    }

    function _refundOrders(GaslessCrossChainOrder[] memory, bytes32[] memory _orderIds) internal override {
        refundedOrderIds = _orderIds;
    }

    function _refundOrders(OnchainCrossChainOrder[] memory, bytes32[] memory _orderIds) internal override {
        refundedOrderIds = _orderIds;
    }

    function _localDomain() internal view override returns (uint32) {
        return _origin;
    }

    function localDomain() public view returns (uint32) {
        return _localDomain();
    }
}

contract Base7683Test is BaseTest {
    Base7683ForTest internal base;
    // address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public override {
        // forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15986407);
        super.setUp();

        base = new Base7683ForTest(permit2, origin, destination, address(inputToken), address(outputToken));
        base.setCounterpart(TypeCasts.addressToBytes32(counterpart));

        _base7683 = Base7683(address(base));

        balanceId[address(base)] = 4;
        users.push(address(base));
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
            address(base), kakaroto, uint64(origin), orderData, permitNonce, openDeadline, fillDeadline, "someOrderType"
        );
    }

    // open
    function test_open_works(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);

        assertTrue(base.isValidNonce(kakaroto, 1));
        uint256[] memory balancesBefore = _balances(inputToken);

        vm.recordLogs();
        base.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            base.counterpart(),
            base.counterpart(),
            base.localDomain(),
            address(inputToken),
            address(outputToken)
        );

        _assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto);

        vm.stopPrank();
    }

    function test_open_native_works(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");
        base.setNative(true);

        vm.startPrank(kakaroto);

        assertTrue(base.isValidNonce(kakaroto, 1));
        uint256[] memory balancesBefore = _balances();

        vm.recordLogs();
        base.open{ value: amount }(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            base.counterpart(),
            base.counterpart(),
            base.localDomain(),
            address(0),
            address(0)
        );

        _assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto, true);

        vm.stopPrank();
    }

    function test_open_InvalidNonce(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");

        vm.startPrank(kakaroto);

        base.invalidateNonces(1);

        vm.expectRevert(Base7683.InvalidNonce.selector);
        base.open(order);

        vm.stopPrank();
    }

    function test_open_native_InvalidNativeAmount(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");
        base.setNative(true);

        vm.startPrank(kakaroto);

        vm.expectRevert(Base7683.InvalidNativeAmount.selector);
        base.open{ value: amount - 1 }(order);

        vm.stopPrank();
    }

    // openFor
    function test_openFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        bytes32 witness = base.witnessHash(base.resolveFor(order, new bytes(0)));
        bytes memory sig =
            _getSignature(address(base), witness, address(inputToken), permitNonce, amount, _openDeadline, kakarotoPK);

        vm.startPrank(karpincho);
        // inputToken.approve(address(base), amount);

        assertTrue(base.isValidNonce(kakaroto, 1));
        uint256[] memory balancesBefore = _balances(inputToken);

        vm.recordLogs();
        base.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        _assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            _openDeadline,
            base.counterpart(),
            base.counterpart(),
            base.localDomain(),
            address(inputToken),
            address(outputToken)
        );
        _assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto);

        vm.stopPrank();
    }

    function test_openFor_OrderOpenExpired(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline < block.timestamp);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        bytes memory sig = new bytes(0);

        vm.startPrank(karpincho);

        vm.expectRevert(Base7683.OrderOpenExpired.selector);
        base.openFor(order, sig, new bytes(0));

        vm.stopPrank();
    }

    function test_openFor_InvalidGaslessOrderSettler(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        order.originSettler = makeAddr("someOtherSettler");

        bytes memory sig = new bytes(0);

        vm.startPrank(karpincho);

        vm.expectRevert(Base7683.InvalidGaslessOrderSettler.selector);
        base.openFor(order, sig, new bytes(0));

        vm.stopPrank();
    }

    function test_openFor_InvalidGaslessOrderOrigin(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        order.originChainId = 3;

        bytes memory sig = new bytes(0);

        vm.startPrank(karpincho);

        vm.expectRevert(Base7683.InvalidGaslessOrderOrigin.selector);
        base.openFor(order, sig, new bytes(0));

        vm.stopPrank();
    }

    function test_openFor_InvalidNonce(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        vm.startPrank(kakaroto);
        base.invalidateNonces(1);
        vm.stopPrank();

        bytes memory sig = new bytes(0);

        vm.startPrank(karpincho);

        vm.expectRevert(Base7683.InvalidNonce.selector);
        base.openFor(order, sig, new bytes(0));

        vm.stopPrank();
    }

    // resolve
    function test_resolve_works(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");

        vm.prank(kakaroto);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolve(order);

        _assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            base.counterpart(),
            base.counterpart(),
            base.localDomain(),
            address(inputToken),
            address(outputToken)
        );
    }

    // resolveFor
    function test_resolveFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, 0, _openDeadline, _fillDeadline);

        vm.prank(karpincho);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolveFor(order, new bytes(0));

        _assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            _openDeadline,
            base.counterpart(),
            base.counterpart(),
            base.localDomain(),
            address(inputToken),
            address(outputToken)
        );
    }

    // fill
    function test_fill_works() public {
        bytes memory orderData = abi.encode("some order data");
        bytes32 orderId = "someOrderId";

        vm.startPrank(vegeta);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true);
        emit Filled(orderId, orderData, fillerData);

        base.fill(orderId, orderData, fillerData);

        assertEq(base.orderStatus(orderId), base.FILLED());

        (bytes memory _originData, bytes memory _fillerData) = base.filledOrders(orderId);

        assertEq(_originData, orderData);
        assertEq(_fillerData, fillerData);

        assertEq(base.filledId(), orderId);
        assertEq(base.filledOriginData(), orderData);
        assertEq(base.filledFillerData(), fillerData);

        vm.stopPrank();
    }

    function test_fill_InvalidOrderStatus_FILLED() public {
        bytes memory orderData = abi.encode("some order data");
        bytes32 orderId = "someOrderId";

        vm.startPrank(vegeta);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        base.fill(orderId, orderData, fillerData);

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        base.fill(orderId, orderData, fillerData);

        vm.stopPrank();
    }

    function test_fill_InvalidOrderStatus_OPENED(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, _fillDeadline, "someOrderType");

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);
        base.open(order);
        vm.stopPrank();

        bytes32 orderId = keccak256("someId");

        vm.startPrank(vegeta);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        base.fill(orderId, orderData, fillerData);

        vm.stopPrank();
    }

    // settle
    function test_settle_work() public {
        bytes memory orderData = abi.encode("some order data");
        bytes memory fillerData = abi.encode("some filler data");
        bytes32 orderId = "someOrderId";

        vm.startPrank(vegeta);

        base.fill(orderId, orderData, fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true, address(base));
        emit Settle(orderIds, ordersFillerData);

        base.settle(orderIds);

        assertEq(base.orderStatus(orderId), base.FILLED()); // settling does not change the status
        assertEq(base.settledOrderIds(0), orderId);
        assertEq(base.settledOrdersOriginData(0), orderData);
        assertEq(base.settledOrdersFillerData(0), fillerData);
        vm.stopPrank();
    }

    function test_settle_multiple_work() public {
        bytes memory orderData1 = abi.encode("some order data 1");
        bytes memory fillerData1 = abi.encode("some filler data 1");
        bytes32 orderId1 = "someOrderId 1";

        bytes memory orderData2 = abi.encode("some order data 2");
        bytes memory fillerData2 = abi.encode("some filler data 2");
        bytes32 orderId2 = "someOrderId 2";

        vm.startPrank(vegeta);

        base.fill(orderId1, orderData1, fillerData1);
        base.fill(orderId2, orderData2, fillerData2);

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;
        bytes[] memory ordersFillerData = new bytes[](2);
        ordersFillerData[0] = fillerData1;
        ordersFillerData[1] = fillerData2;

        vm.expectEmit(false, false, false, true, address(base));
        emit Settle(orderIds, ordersFillerData);

        base.settle(orderIds);

        assertEq(base.orderStatus(orderId1), base.FILLED()); // settling does not change the status
        assertEq(base.settledOrderIds(0), orderId1);
        assertEq(base.settledOrdersOriginData(0), orderData1);
        assertEq(base.settledOrdersFillerData(0), fillerData1);

        assertEq(base.orderStatus(orderId2), base.FILLED()); // settling does not change the status
        assertEq(base.settledOrderIds(1), orderId2);
        assertEq(base.settledOrdersOriginData(1), orderData2);
        assertEq(base.settledOrdersFillerData(1), fillerData2);
        vm.stopPrank();
    }

    function test_settle_InvalidOrderStatus() public {
        bytes32 orderId = "someOrderId";

        vm.startPrank(vegeta);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        base.settle(orderIds);

        vm.stopPrank();
    }

    // refund
    function test_refund_onChain_work() public {
        bytes memory orderData = abi.encode("some order data");
        uint32 fillDeadline = uint32(block.timestamp - 1);
        bytes32 orderId = keccak256(orderData);
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, fillDeadline, "someOrderType");

        vm.startPrank(vegeta);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        base.refund(orders);

        assertEq(base.orderStatus(orderId), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(0), orderId);
        vm.stopPrank();
    }

    function test_refund_multi_onChain_work() public {
        uint32 fillDeadline = uint32(block.timestamp - 1);

        bytes memory orderData1 = abi.encode("some order data 1");
        bytes32 orderId1 = keccak256(orderData1);
        OnchainCrossChainOrder memory order1 = _prepareOnchainOrder(orderData1, fillDeadline, "someOrderType");

        bytes memory orderData2 = abi.encode("some order data 2");
        bytes32 orderId2 = keccak256(orderData2);
        OnchainCrossChainOrder memory order2 = _prepareOnchainOrder(orderData2, fillDeadline, "someOrderType");

        vm.startPrank(vegeta);

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](2);
        orders[0] = order1;
        orders[1] = order2;

        base.refund(orders);

        assertEq(base.orderStatus(orderId1), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(0), orderId1);

        assertEq(base.orderStatus(orderId2), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(1), orderId2);
        vm.stopPrank();
    }

    function test_refund_onChain_InvalidOrderStatus() public {
        bytes memory orderData = abi.encode("some order data");
        uint32 fillDeadline = uint32(block.timestamp - 1);
        bytes32 orderId = keccak256(orderData);
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, fillDeadline, "someOrderType");

        bytes memory fillerData = abi.encode("some filler data");
        base.fill(orderId, orderData, fillerData);

        vm.startPrank(vegeta);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        base.refund(orders);

        vm.stopPrank();
    }

    function test_refund_onChain_OrderFillNotExpired() public {
        bytes memory orderData = abi.encode("some order data");
        uint32 fillDeadline = uint32(block.timestamp + 1);
        OnchainCrossChainOrder memory order = _prepareOnchainOrder(orderData, fillDeadline, "someOrderType");

        vm.startPrank(vegeta);

        OnchainCrossChainOrder[] memory orders = new OnchainCrossChainOrder[](1);
        orders[0] = order;

        vm.expectRevert(Base7683.OrderFillNotExpired.selector);
        base.refund(orders);

        vm.stopPrank();
    }

    function test_refund_gasless_work() public {
        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        uint32 fillDeadline = uint32(block.timestamp - 1);
        uint32 openDeadline = uint32(block.timestamp - 10);
        bytes32 orderId = keccak256(orderData);
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, openDeadline, fillDeadline);

        vm.startPrank(vegeta);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        base.refund(orders);

        assertEq(base.orderStatus(orderId), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(0), orderId);
        vm.stopPrank();
    }

    function test_refund_multi_gasless_work() public {
        uint256 permitNonce = 0;
        uint32 fillDeadline = uint32(block.timestamp - 1);
        uint32 openDeadline = uint32(block.timestamp - 10);

        bytes memory orderData1 = abi.encode("some order data 1");
        bytes32 orderId1 = keccak256(orderData1);
        GaslessCrossChainOrder memory order1 = _prepareGaslessOrder(orderData1, permitNonce, openDeadline, fillDeadline);

        bytes memory orderData2 = abi.encode("some order data2");
        bytes32 orderId2 = keccak256(orderData2);
        GaslessCrossChainOrder memory order2 = _prepareGaslessOrder(orderData2, permitNonce, openDeadline, fillDeadline);

        vm.startPrank(vegeta);

        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](2);
        orders[0] = order1;
        orders[1] = order2;

        base.refund(orders);

        assertEq(base.orderStatus(orderId1), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(0), orderId1);

        assertEq(base.orderStatus(orderId2), base.UNKNOWN()); // refunding does not change the status
        assertEq(base.refundedOrderIds(1), orderId2);
        vm.stopPrank();
    }

    function test_refund_gasless_InvalidOrderStatus() public {
        uint256 permitNonce = 0;
        uint32 fillDeadline = uint32(block.timestamp - 1);
        uint32 openDeadline = uint32(block.timestamp - 10);

        bytes memory orderData = abi.encode("some order data");
        bytes32 orderId = keccak256(orderData);
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, openDeadline, fillDeadline);

        bytes memory fillerData = abi.encode("some filler data");
        base.fill(orderId, orderData, fillerData);

        vm.startPrank(vegeta);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        vm.expectRevert(Base7683.InvalidOrderStatus.selector);
        base.refund(orders);

        vm.stopPrank();
    }

    function test_refund_gasless_OrderFillNotExpired() public {
        uint256 permitNonce = 0;
        uint32 fillDeadline = uint32(block.timestamp + 2);
        uint32 openDeadline = uint32(block.timestamp - 10);
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order = _prepareGaslessOrder(orderData, permitNonce, openDeadline, fillDeadline);

        vm.startPrank(vegeta);

        GaslessCrossChainOrder[] memory orders = new GaslessCrossChainOrder[](1);
        orders[0] = order;

        vm.expectRevert(Base7683.OrderFillNotExpired.selector);
        base.refund(orders);

        vm.stopPrank();
    }
}
