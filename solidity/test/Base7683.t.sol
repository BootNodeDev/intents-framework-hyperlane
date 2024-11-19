// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IEIP712 } from "@uniswap/permit2/src/interfaces/IEIP712.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    Output,
    FillInstruction
} from "../src/ERC7683/IERC7683.sol";
import { Base7683 } from "../src/Base7683.sol";

import {
    BaseTest
} from "./BaseTest.sol";

event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

event Filled(bytes32 orderId, bytes originData, bytes fillerData);

contract Base7683ForTest is Base7683, StdCheats {
    bytes32 public counterpart;

    bytes32[] public refundedOrderIds;
    bytes32[] public settledOrderIds;
    bytes[] public settledReceivers;

    uint32 internal _origin;
    uint32 internal _destination;
    address internal inputToken;
    address internal outputToken;

    bytes32 public filledId;
    bytes public filledOriginData;
    bytes public filledFillerData;

    constructor(
      address _permit2,
      uint32 _local,
      uint32 _remote,
      address _inputToken,
      address _outputToken
    ) Base7683(_permit2) {
        _origin = _local;
        _destination = _remote;
        inputToken = _inputToken;
        outputToken = _outputToken;
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
        return _resolvedOrder(
            order.user,
            order.openDeadline,
            order.fillDeadline,
            order.orderData
        );
    }

    function _resolveOrder(OnchainCrossChainOrder memory order)
        internal
        view
        override
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce)
    {
        return _resolvedOrder(
            msg.sender,
            type(uint32).max,
            order.fillDeadline,
            order.orderData
        );
    }

    function _resolvedOrder(
        address _sender,
        uint32 _openDeadline,
        uint32 _fillDeadline,
        bytes memory _orderData
    )
        internal
        view
        returns (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce)
    {
        // this can be used by the filler to approve the tokens to be spent on destination
        Output[] memory maxSpent = new Output[](1);
        maxSpent[0] = Output({
            token: TypeCasts.addressToBytes32(outputToken),
            amount: 100,
            recipient: counterpart,
            chainId: _destination
        });

        // this can be used by the filler know how much it can expect to receive
        Output[] memory minReceived = new Output[](1);
        minReceived[0] = Output({
            token: TypeCasts.addressToBytes32(inputToken),
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

        resolvedOrder = ResolvedCrossChainOrder({
            user: _sender,
            originChainId: _origin,
            openDeadline: _openDeadline,
            fillDeadline: _fillDeadline,
            minReceived: minReceived,
            maxSpent: maxSpent,
            fillInstructions: fillInstructions
        });

        orderId = keccak256("someId");
        nonce = 1;
    }

    function _fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) internal override {
        filledId = _orderId;
        filledOriginData = _originData;
        filledFillerData = _fillerData;
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
        super.setUp();

        base = new Base7683ForTest(permit2, origin, destination, address(inputToken), address(outputToken));
        base.setCounterpart(TypeCasts.addressToBytes32(counterpart));

        _base7683 = Base7683(address(base));

        balanceId[address(base)] = 4;
        users.push(address(base));
    }

    function prepareOnchainOrder(
        bytes memory orderData,
        uint32 fillDeadline
    )
        internal
        pure
        returns (OnchainCrossChainOrder memory)
    {
        return _prepareOnchainOrder(orderData, fillDeadline, "someOrderType");
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
            address(base),
            kakaroto,
            uint64(origin),
            orderData,
            permitNonce,
            openDeadline,
            fillDeadline,
            "someOrderType"
        );
    }

    // open
    function test_open_works(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, _fillDeadline);

        vm.startPrank(kakaroto);
        inputToken.approve(address(base), amount);

        assertTrue(base.isValidNonce(kakaroto, 1));
        uint256[] memory balancesBefore = _balances(inputToken);

        vm.recordLogs();
        base.open(order);

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            base.counterpart(),
            base.counterpart(),
            base.localDomain()
        );

        assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto);

        vm.stopPrank();
    }

    // TODO test_open_InvalidNonce

    // openFor
    function test_openFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        vm.assume(_openDeadline > block.timestamp);
        vm.prank(kakaroto);
        inputToken.approve(permit2, type(uint256).max);

        uint256 permitNonce = 0;
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(orderData, permitNonce, _openDeadline, _fillDeadline);

        bytes32 witness = base.witnessHash(base.resolveFor(order, new bytes(0)));
        bytes memory sig = _getSignature(
            address(base),
            witness,
            address(inputToken),
            permitNonce,
            amount,
            _openDeadline,
            kakarotoPK
        );

        vm.startPrank(karpincho);
        inputToken.approve(address(base), amount);

        assertTrue(base.isValidNonce(kakaroto, 1));
        uint256[] memory balancesBefore = _balances(inputToken);

        vm.recordLogs();
        base.openFor(order, sig, new bytes(0));

        (bytes32 orderId, ResolvedCrossChainOrder memory resolvedOrder) = _getOrderIDFromLogs();

        assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            _openDeadline,
            base.counterpart(),
            base.counterpart(),
            base.localDomain()
        );

        assertOpenOrder(orderId, kakaroto, orderData, balancesBefore, kakaroto);

        vm.stopPrank();
    }

    // TODO test_openFor_OrderOpenExpired
    // TODO test_openFor_InvalidGaslessOrderSettler
    // TODO test_openFor_InvalidGaslessOrderOriginChain
    // TODO test_openFor_InvalidNonce

    // resolve
    function test_resolve_works(uint32 _fillDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        OnchainCrossChainOrder memory order =
            prepareOnchainOrder(orderData, _fillDeadline);

        vm.prank(kakaroto);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolve(order);

        assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            type(uint32).max,
            base.counterpart(),
            base.counterpart(),
            base.localDomain()
        );
    }

    // resolveFor
    function test_resolveFor_works(uint32 _fillDeadline, uint32 _openDeadline) public {
        bytes memory orderData = abi.encode("some order data");
        GaslessCrossChainOrder memory order =
            prepareGaslessOrder(orderData, 0, _openDeadline, _fillDeadline);

        vm.prank(karpincho);
        ResolvedCrossChainOrder memory resolvedOrder = base.resolveFor(order, new bytes(0));

        assertResolvedOrder(
            resolvedOrder,
            orderData,
            kakaroto,
            _fillDeadline,
            _openDeadline,
            base.counterpart(),
            base.counterpart(),
            base.localDomain()
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
        assertEq(base.filledOrders(orderId), orderData);
        assertEq(base.orderFillerData(orderId), fillerData);

        assertEq(base.filledId(), orderId);
        assertEq(base.filledOriginData(), orderData);
        assertEq(base.filledFillerData(), fillerData);

        vm.stopPrank();
    }

    // TODO test_fill_InvalidOrderStatus
}
