// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IEIP712 } from "@uniswap/permit2/src/interfaces/IEIP712.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";
import { Base7683 } from "../src/Base7683.sol";

event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);
event Filled(bytes32 orderId, bytes originData, bytes fillerData);
event Settle(bytes32[] orderIds, bytes[] ordersFillerData);
event Refund(bytes32[] orderIds);
event Settled(bytes32 orderId, address receiver);
event Refunded(bytes32 orderId, address receiver);

contract Base7683ForTest is Base7683 {
    bytes32 public counterpart;

    bytes32[] public refundedOrderIds;
    bytes32[] public settledOrderIds;
    bytes[] public settledReceivers;

    uint32 internal immutable _origin;
    uint32 internal immutable _destination;

    constructor(address _permit2, uint32 _local, uint32 _remote) Base7683(_permit2) {
        _origin = _local;
        _destination = _remote;
    }

    function setCounterpart(bytes32 _counterpart) public {
        counterpart = _counterpart;
    }

    function settleOrder(bytes32 _orderId) external {
        _settleOrder(_orderId, TypeCasts.addressToBytes32(msg.sender), _destination);
    }

    function refundOrder(bytes32 _orderId) external {
        _refundOrder(_orderId, _destination);
    }

    function _handleSettlement(bytes32[] memory _orderIds, bytes[] memory receivers) internal override {
        settledOrderIds = _orderIds;
        settledReceivers = receivers;
    }

    function _handleRefund(bytes32[] memory _orderIds) internal override {
        refundedOrderIds = _orderIds;
    }

    function _mustHaveRemoteCounterpart(uint32) internal view override returns (bytes32) {
        return counterpart;
    }

    function _localDomain() internal view override returns (uint32) {
        return _origin;
    }

    function localDomain() public view returns (uint32) {
        return _localDomain();
    }
}

contract Base7683Test is Test, DeployPermit2 {
    Base7683ForTest internal base;
    // address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address permit2;
    ERC20 internal inputToken;
    ERC20 internal outputToken;

    address internal kakaroto;
    uint256 internal kakarotoPK;
    address internal karpincho;
    uint256 internal karpinchoPK;
    address internal vegeta;
    uint256 internal vegetaPK;
    address internal counterpart = makeAddr("counterpart");

    uint32 internal origin = 1;
    uint32 internal destination = 2;
    uint256 internal amount = 100;

    bytes32 DOMAIN_SEPARATOR;
    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant FULL_WITNESS_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,GaslessCrossChainOrder witness)GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint64 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType,bytes orderData)TokenPermissions(address token,uint256 amount)"
    );

    uint256 internal forkId;

    mapping(address => uint256) internal balanceId;

    function setUp() public {
        // forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15986407);

        (kakaroto, kakarotoPK) = makeAddrAndKey("kakaroto");
        (karpincho, karpinchoPK) = makeAddrAndKey("karpincho");
        (vegeta, vegetaPK) = makeAddrAndKey("vegeta");

        inputToken = new ERC20("Input Token", "IN");
        outputToken = new ERC20("Output Token", "OUT");

        permit2 = deployPermit2();
        DOMAIN_SEPARATOR = IEIP712(permit2).DOMAIN_SEPARATOR();

        base = new Base7683ForTest(permit2, origin, destination);
        base.setCounterpart(TypeCasts.addressToBytes32(counterpart));

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
        balanceId[address(base)] = 4;
    }

    function prepareOrderData() internal view returns (OrderData memory) {
        return OrderData({
            sender: TypeCasts.addressToBytes32(kakaroto),
            recipient: TypeCasts.addressToBytes32(karpincho),
            inputToken: TypeCasts.addressToBytes32(address(inputToken)),
            outputToken: TypeCasts.addressToBytes32(address(outputToken)),
            amountIn: amount,
            amountOut: amount,
            senderNonce: base.senderNonce(kakaroto),
            originDomain: origin,
            destinationDomain: destination,
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
        OrderData memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline,
        bytes32 orderDataType
    )
        internal
        view
        returns (GaslessCrossChainOrder memory)
    {
        return GaslessCrossChainOrder({
            originSettler: address(base),
            user: kakaroto,
            nonce: permitNonce,
            originChainId: uint64(origin),
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: OrderEncoder.encode(orderData)
        });
    }

    function assertResolvedOrder(
        ResolvedCrossChainOrder memory resolvedOrder,
        OrderData memory orderData,
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
        assertEq(resolvedOrder.maxSpent[0].recipient, base.counterpart());
        assertEq(resolvedOrder.maxSpent[0].chainId, destination);

        assertEq(resolvedOrder.minReceived.length, 1);
        assertEq(resolvedOrder.minReceived[0].token, TypeCasts.addressToBytes32(address(inputToken)));
        assertEq(resolvedOrder.minReceived[0].amount, amount);
        assertEq(resolvedOrder.minReceived[0].recipient, bytes32(0));
        assertEq(resolvedOrder.minReceived[0].chainId, origin);

        assertEq(resolvedOrder.fillInstructions.length, 1);
        assertEq(resolvedOrder.fillInstructions[0].destinationChainId, destination);
        assertEq(resolvedOrder.fillInstructions[0].destinationSettler, base.counterpart());

        orderData.fillDeadline = _fillDeadline;
        assertEq(resolvedOrder.fillInstructions[0].originData, OrderEncoder.encode(orderData));

        assertEq(resolvedOrder.user, _user);
        assertEq(resolvedOrder.originChainId, base.localDomain());
        assertEq(resolvedOrder.openDeadline, _openDeadline);
        assertEq(resolvedOrder.fillDeadline, _fillDeadline);
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
        uint256[] memory _balances = new uint256[](5);
        _balances[0] = token.balanceOf(kakaroto);
        _balances[1] = token.balanceOf(karpincho);
        _balances[2] = token.balanceOf(vegeta);
        _balances[3] = token.balanceOf(counterpart);
        _balances[4] = token.balanceOf(address(base));

        return _balances;
    }

    function balances() internal view returns (uint256[] memory) {
        uint256[] memory _balances = new uint256[](5);
        _balances[0] = kakaroto.balance;
        _balances[1] = karpincho.balance;
        _balances[2] = vegeta.balance;
        _balances[3] = counterpart.balance;
        _balances[4] = address(base).balance;

        return _balances;
    }

    function orderDataById(bytes32 orderId) internal view returns (OrderData memory orderData) {
        (
            bytes32 _sender,
            bytes32 _recipient,
            bytes32 _inputToken,
            bytes32 _outputToken,
            uint256 _amountIn,
            uint256 _amountOut,
            uint256 _senderNonce,
            uint32 _originDomain,
            uint32 _destinationDomain,
            uint32 _fillDeadline,
            bytes memory _data
        ) = base.orders(orderId);

        orderData.sender = _sender;
        orderData.recipient = _recipient;
        orderData.inputToken = _inputToken;
        orderData.outputToken = _outputToken;
        orderData.amountIn = _amountIn;
        orderData.amountOut = _amountOut;
        orderData.senderNonce = _senderNonce;
        orderData.originDomain = _originDomain;
        orderData.destinationDomain = _destinationDomain;
        orderData.fillDeadline = _fillDeadline;
        orderData.data = _data;
    }

    function assertOrder(
        bytes32 orderId,
        OrderData memory orderData,
        uint256[] memory balancesBefore,
        ERC20 token,
        address sender,
        address receiver,
        Base7683.OrderStatus expectedStatus
    )
        internal
        view
    {
        OrderData memory savedOrderData = orderDataById(orderId);
        Base7683.OrderStatus status = base.orderStatus(orderId);

        assertEq(OrderEncoder.encode(savedOrderData), OrderEncoder.encode(orderData));
        assertTrue(status == expectedStatus);

        uint256[] memory balancesAfter = balances(token);
        assertEq(balancesBefore[balanceId[sender]] - amount, balancesAfter[balanceId[sender]]);
        assertEq(balancesBefore[balanceId[receiver]] + amount, balancesAfter[balanceId[receiver]]);
    }

    function assertOpenOrder(
        bytes32 orderId,
        address sender,
        OrderData memory orderData,
        uint256[] memory balancesBefore,
        address user,
        uint256 nonceBefore
    )
        internal
        view
    {
        OrderData memory savedOrderData = orderDataById(orderId);

        assertEq(base.senderNonce(sender), nonceBefore + 1);
        assertEq(OrderEncoder.encode(savedOrderData), OrderEncoder.encode(orderData));
        assertOrder(orderId, orderData, balancesBefore, inputToken, user, address(base), Base7683.OrderStatus.OPENED);
    }

    // open
    function test_open_works(uint32 _fillDeadline) public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, _fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);

        uint256 nonceBefore = base.senderNonce(kakaroto);
        uint256[] memory balancesBefore = balances(inputToken);

        vm.recordLogs();
        base.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = getOrderIDFromLogs();

        assertResolvedOrder(resolvedOrder, orderData, kakaroto, _fillDeadline, type(uint32).max);

        assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto, nonceBefore);

        vm.stopPrank();
    }

    function test_open__native_token_works(uint32 _fillDeadline) public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));

        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, _fillDeadline, OrderEncoder.orderDataType());

        deal(kakaroto, 1_000_000);

        vm.startPrank(kakaroto);

        uint256 nonceBefore = base.senderNonce(kakaroto);
        uint256[] memory balancesBefore = balances();

        vm.recordLogs();
        base.open{value: amount}(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = getOrderIDFromLogs();

        // assertResolvedOrder(resolvedOrder, orderData, kakaroto, _fillDeadline, type(uint32).max);
        assertEq(resolvedOrder.maxSpent.length, 1);
        assertEq(resolvedOrder.maxSpent[0].token, TypeCasts.addressToBytes32(address(0)));
        assertEq(resolvedOrder.maxSpent[0].amount, amount);
        assertEq(resolvedOrder.maxSpent[0].recipient, base.counterpart());
        assertEq(resolvedOrder.maxSpent[0].chainId, destination);

        assertEq(resolvedOrder.minReceived.length, 1);
        assertEq(resolvedOrder.minReceived[0].token, TypeCasts.addressToBytes32(address(0)));
        assertEq(resolvedOrder.minReceived[0].amount, amount);
        assertEq(resolvedOrder.minReceived[0].recipient, bytes32(0));
        assertEq(resolvedOrder.minReceived[0].chainId, origin);

        assertEq(resolvedOrder.fillInstructions.length, 1);
        assertEq(resolvedOrder.fillInstructions[0].destinationChainId, destination);
        assertEq(resolvedOrder.fillInstructions[0].destinationSettler, base.counterpart());

        orderData.fillDeadline = _fillDeadline;
        assertEq(resolvedOrder.fillInstructions[0].originData, OrderEncoder.encode(orderData));

        assertEq(resolvedOrder.user, kakaroto);
        assertEq(resolvedOrder.originChainId, base.localDomain());
        assertEq(resolvedOrder.openDeadline, type(uint32).max);
        assertEq(resolvedOrder.fillDeadline, _fillDeadline);

        // assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto, nonceBefore);
        OrderData memory savedOrderData = orderDataById(orderId);

        assertEq(base.senderNonce(kakaroto), nonceBefore + 1);
        assertEq(OrderEncoder.encode(savedOrderData), OrderEncoder.encode(orderData));
        // assertOrder(orderId, orderData, balancesBefore, inputToken, user, address(base), Base7683.OrderStatus.OPENED);

        Base7683.OrderStatus status = base.orderStatus(orderId);

        assertEq(OrderEncoder.encode(savedOrderData), OrderEncoder.encode(orderData));
        assertTrue(status == Base7683.OrderStatus.OPENED);

        uint256[] memory balancesAfter = balances();
        assertEq(balancesBefore[balanceId[kakaroto]] - amount, balancesAfter[balanceId[kakaroto]]);
        assertEq(balancesBefore[balanceId[address(base)]] + amount, balancesAfter[balanceId[address(base)]]);

        vm.stopPrank();
    }

    function getPermitWitnessTransferSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 privateKey,
        bytes32 typehash,
        bytes32 witness,
        bytes32 domainSeparator
    )
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(typehash, tokenPermissions, address(base), permit.nonce, permit.deadline, witness))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function defaultERC20PermitWitnessTransfer(
        address _token,
        uint256 _nonce,
        uint256 _amount,
        uint32 _deadline
    )
        internal
        pure
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: _token, amount: _amount }),
            nonce: _nonce,
            deadline: _deadline
        });
    }

    // openFor
    function test_openFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint256 permitNonce = 0;
        OrderData memory orderData = prepareOrderData();
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline, OrderEncoder.orderDataType());

        bytes32 witness = base.witnessHash(order);
        ISignatureTransfer.PermitTransferFrom memory permit =
            defaultERC20PermitWitnessTransfer(address(inputToken), permitNonce, amount, _openDeadline);
        bytes memory sig =
            getPermitWitnessTransferSignature(permit, kakarotoPK, FULL_WITNESS_TYPEHASH, witness, DOMAIN_SEPARATOR);

        vm.startPrank(karpincho);
        inputToken.approve(address(base), amount);

        uint256 nonceBefore = base.senderNonce(karpincho);
        uint256[] memory balancesBefore = balances(inputToken);

        vm.recordLogs();
        base.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = getOrderIDFromLogs();

        assertResolvedOrder(resolvedOrder, orderData, kakaroto, _fillDeadline, _openDeadline);

        assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto, nonceBefore);

        vm.stopPrank();
    }

    // resolve
    function test_resolve_works(uint32 _fillDeadline) public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, _fillDeadline, OrderEncoder.orderDataType());

        vm.prank(kakaroto);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolve(order);

        assertResolvedOrder(resolvedOrder, orderData, kakaroto, _fillDeadline, type(uint32).max);
    }

    // resolveFor
    function test_resolveFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        OrderData memory orderData = prepareOrderData();
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(orderData, 0, _openDeadline, _fillDeadline, OrderEncoder.orderDataType());

        vm.prank(karpincho);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolveFor(order, new bytes(0));

        assertResolvedOrder(resolvedOrder, orderData, kakaroto, _fillDeadline, _openDeadline);
    }

    // fill
    function test_fill_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.originDomain = destination;
        orderData.destinationDomain = origin;

        bytes32 orderId = OrderEncoder.id(orderData);

        uint256[] memory balancesBefore = balances(outputToken);

        vm.startPrank(vegeta);
        outputToken.approve(address(base), amount);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true);
        emit Filled(orderId, OrderEncoder.encode(orderData), fillerData);

        base.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        assertOrder(orderId, orderData, balancesBefore, outputToken, vegeta, karpincho, Base7683.OrderStatus.FILLED);
        assertEq(base.orderFillerData(orderId), fillerData);

        vm.stopPrank();
    }

    function test_fill_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));

        orderData.originDomain = destination;
        orderData.destinationDomain = origin;

        bytes32 orderId = OrderEncoder.id(orderData);

        deal(vegeta, 1_000_000);

        uint256[] memory balancesBefore = balances();

        vm.startPrank(vegeta);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(vegeta));

        vm.expectEmit(false, false, false, true);
        emit Filled(orderId, OrderEncoder.encode(orderData), fillerData);

        base.fill{value: amount}(orderId, OrderEncoder.encode(orderData), fillerData);

        // assertOrder(orderId, orderData, balancesBefore, outputToken, vegeta, karpincho, Base7683.OrderStatus.FILLED);
        OrderData memory savedOrderData = orderDataById(orderId);
        Base7683.OrderStatus status = base.orderStatus(orderId);

        assertEq(OrderEncoder.encode(savedOrderData), OrderEncoder.encode(orderData));
        assertTrue(status == Base7683.OrderStatus.FILLED);

        uint256[] memory balancesAfter = balances();
        assertEq(balancesBefore[balanceId[vegeta]] - amount, balancesAfter[balanceId[vegeta]]);
        assertEq(balancesBefore[balanceId[karpincho]] + amount, balancesAfter[balanceId[karpincho]]);

        assertEq(base.orderFillerData(orderId), fillerData);

        vm.stopPrank();
    }

    // settle
    function test_settle_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.originDomain = destination;
        orderData.destinationDomain = origin;

        bytes32 orderId = OrderEncoder.id(orderData);

        bytes memory fillerData = abi.encode(TypeCasts.addressToBytes32(karpincho));

        vm.startPrank(vegeta);
        outputToken.approve(address(base), amount);
        base.fill(orderId, OrderEncoder.encode(orderData), fillerData);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        bytes[] memory ordersFillerData = new bytes[](1);
        ordersFillerData[0] = fillerData;

        vm.expectEmit(false, false, false, true);
        emit Settle(orderIds, ordersFillerData);

        base.settle(orderIds);

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.SETTLED);
        assertEq(base.settledOrderIds(0), orderId);
        assertEq(base.settledReceivers(0), fillerData);

        vm.stopPrank();
    }

    // refund
    function test_refund_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.originDomain = destination;
        orderData.destinationDomain = origin;

        bytes32 orderId = OrderEncoder.id(orderData);
        vm.warp(orderData.fillDeadline + 1);

        OrderData[] memory ordersData = new OrderData[](1);
        ordersData[0] = orderData;

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = OrderEncoder.id(orderData);

        vm.expectEmit(false, false, false, true);
        emit Refund(orderIds);

        base.refund(ordersData);

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.REFUNDED);
        assertEq(OrderEncoder.encode(orderDataById(orderId)), OrderEncoder.encode(orderData));
        assertEq(base.refundedOrderIds(0), orderId);
    }

    // _settleOrder
    function test_settleOrder_works() public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);

        vm.recordLogs();
        base.open(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.stopPrank();

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, vegeta);

        vm.prank(vegeta);
        base.settleOrder(orderId);

        uint256[] memory balancesAfter = balances(inputToken);

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.SETTLED);
        assertEq(balancesBefore[balanceId[address(base)]] - amount, balancesAfter[balanceId[address(base)]]);
        assertEq(balancesBefore[balanceId[vegeta]] + amount, balancesAfter[balanceId[vegeta]]);
    }

    function test_settleOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));

        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        deal(kakaroto, 1_000_000);

        vm.startPrank(kakaroto);

        vm.recordLogs();
        base.open{value: amount}(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.stopPrank();

        uint256[] memory balancesBefore = balances();

        vm.expectEmit(false, false, false, true);
        emit Settled(orderId, vegeta);

        vm.prank(vegeta);
        base.settleOrder(orderId);

        uint256[] memory balancesAfter = balances();

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.SETTLED);
        assertEq(balancesBefore[balanceId[address(base)]] - amount, balancesAfter[balanceId[address(base)]]);
        assertEq(balancesBefore[balanceId[vegeta]] + amount, balancesAfter[balanceId[vegeta]]);
    }

    // _refundOrder
    function test_refundOrder_works() public {
        OrderData memory orderData = prepareOrderData();
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);

        vm.recordLogs();
        base.open(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.stopPrank();

        vm.warp(orderData.fillDeadline + 1);

        uint256[] memory balancesBefore = balances(inputToken);

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        vm.prank(vegeta);
        base.refundOrder(orderId);

        uint256[] memory balancesAfter = balances(inputToken);

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.REFUNDED);
        assertEq(balancesBefore[balanceId[address(base)]] - amount, balancesAfter[balanceId[address(base)]]);
        assertEq(balancesBefore[balanceId[kakaroto]] + amount, balancesAfter[balanceId[kakaroto]]);
    }

    function test_refundOrder_native_works() public {
        OrderData memory orderData = prepareOrderData();
        orderData.inputToken = TypeCasts.addressToBytes32(address(0));
        orderData.outputToken = TypeCasts.addressToBytes32(address(0));

        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, orderData.fillDeadline, OrderEncoder.orderDataType());

        deal(kakaroto, 1_000_000);

        vm.startPrank(kakaroto);

        vm.recordLogs();
        base.open{value: amount}(order);

        (bytes32 orderId,) = getOrderIDFromLogs();

        vm.stopPrank();

        vm.warp(orderData.fillDeadline + 1);

        uint256[] memory balancesBefore = balances();

        vm.expectEmit(false, false, false, true);
        emit Refunded(orderId, kakaroto);

        vm.prank(vegeta);
        base.refundOrder(orderId);

        uint256[] memory balancesAfter = balances();

        assertTrue(base.orderStatus(orderId) == Base7683.OrderStatus.REFUNDED);
        assertEq(balancesBefore[balanceId[address(base)]] - amount, balancesAfter[balanceId[address(base)]]);
        assertEq(balancesBefore[balanceId[kakaroto]] + amount, balancesAfter[balanceId[kakaroto]]);
    }
}
