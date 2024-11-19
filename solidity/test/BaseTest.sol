// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";

import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { IEIP712 } from "@uniswap/permit2/src/interfaces/IEIP712.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPermit2, ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

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

contract BaseTest is Test, DeployPermit2 {
    Base7683 internal _base7683;

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

    uint256 internal forkId;

    mapping(address => uint256) internal balanceId;
    address[] internal users;

    function setUp() public virtual {
        // forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15986407);

        (kakaroto, kakarotoPK) = makeAddrAndKey("kakaroto");
        (karpincho, karpinchoPK) = makeAddrAndKey("karpincho");
        (vegeta, vegetaPK) = makeAddrAndKey("vegeta");

        inputToken = new ERC20("Input Token", "IN");
        outputToken = new ERC20("Output Token", "OUT");

        permit2 = deployPermit2();
        DOMAIN_SEPARATOR = IEIP712(permit2).DOMAIN_SEPARATOR();

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

        users.push(kakaroto);
        users.push(karpincho);
        users.push(vegeta);
        users.push(counterpart);
    }

    function _prepareOnchainOrder(
        bytes memory orderData,
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
            orderData: orderData
        });
    }

    function _prepareGaslessOrder(
        address originSettler,
        address user,
        uint64 originChainId,
        bytes memory orderData,
        uint256 permitNonce,
        uint32 openDeadline,
        uint32 fillDeadline,
        bytes32 orderDataType
    )
        internal
        pure
        returns (GaslessCrossChainOrder memory)
    {
        return GaslessCrossChainOrder({
            originSettler: originSettler,
            user: user,
            nonce: permitNonce,
            originChainId: originChainId,
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderDataType: orderDataType,
            orderData: orderData
        });
    }

    function _getOrderIDFromLogs() internal returns (bytes32, ResolvedCrossChainOrder memory) {
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

    function _balances(ERC20 _token) internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = _token.balanceOf(users[i]);
        }

        return balances;
    }

    bytes32 constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 constant FULL_WITNESS_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)"
    );

    bytes32 constant FULL_WITNESS_BATCH_TYPEHASH = keccak256(
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)TokenPermissions(address token,uint256 amount)"
    );

    function _getPermitBatchWitnessSignature(
        address spender,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        uint256 privateKey,
        bytes32 typeHash,
        bytes32 witness,
        bytes32 domainSeparator
    )
        internal
        pure
        returns (bytes memory sig)
    {
        bytes32[] memory tokenPermissions = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
        }

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        typeHash,
                        keccak256(abi.encodePacked(tokenPermissions)),
                        spender,
                        permit.nonce,
                        permit.deadline,
                        witness
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function _defaultERC20PermitMultiple(
        address[] memory tokens,
        uint256 nonce,
        uint256 _amount,
        uint32 _deadline
    )
        internal
        pure
        returns (ISignatureTransfer.PermitBatchTransferFrom memory)
    {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            permitted[i] = ISignatureTransfer.TokenPermissions({ token: tokens[i], amount: _amount });
        }
        return ISignatureTransfer.PermitBatchTransferFrom({ permitted: permitted, nonce: nonce, deadline: _deadline });
    }

    function _getSignature(
        address spender,
        bytes32 witness,
        address token,
        uint256 permitNonce,
        uint256 _amount,
        uint32 _deadline,
        uint256 sigPk
    )
        internal
        view
        returns (bytes memory sig)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        ISignatureTransfer.PermitBatchTransferFrom memory permit =
            _defaultERC20PermitMultiple(tokens, permitNonce, _amount, _deadline);

        return
            _getPermitBatchWitnessSignature(spender, permit, sigPk, FULL_WITNESS_BATCH_TYPEHASH, witness, DOMAIN_SEPARATOR);
    }

    function assertResolvedOrder(
        ResolvedCrossChainOrder memory resolvedOrder,
        bytes memory orderData,
        address _user,
        uint32 _fillDeadline,
        uint32 _openDeadline,
        bytes32 _recipient,
        bytes32 _destinationSettler,
        uint64 _originChainId
    )
        internal
        view
    {
        assertEq(resolvedOrder.maxSpent.length, 1);
        assertEq(resolvedOrder.maxSpent[0].token, TypeCasts.addressToBytes32(address(outputToken)));
        assertEq(resolvedOrder.maxSpent[0].amount, amount);
        assertEq(resolvedOrder.maxSpent[0].recipient, _recipient);
        assertEq(resolvedOrder.maxSpent[0].chainId, destination);

        assertEq(resolvedOrder.minReceived.length, 1);
        assertEq(resolvedOrder.minReceived[0].token, TypeCasts.addressToBytes32(address(inputToken)));
        assertEq(resolvedOrder.minReceived[0].amount, amount);
        assertEq(resolvedOrder.minReceived[0].recipient, bytes32(0));
        assertEq(resolvedOrder.minReceived[0].chainId, origin);

        assertEq(resolvedOrder.fillInstructions.length, 1);
        assertEq(resolvedOrder.fillInstructions[0].destinationChainId, destination);
        assertEq(resolvedOrder.fillInstructions[0].destinationSettler, _destinationSettler);

        assertEq(resolvedOrder.fillInstructions[0].originData, orderData);

        assertEq(resolvedOrder.user, _user);
        assertEq(resolvedOrder.originChainId, _originChainId);
        assertEq(resolvedOrder.openDeadline, _openDeadline);
        assertEq(resolvedOrder.fillDeadline, _fillDeadline);
    }

    function orderDataById(bytes32 orderId) internal view returns (bytes memory orderData) {
        (ResolvedCrossChainOrder memory resolvedOrder) = abi.decode(_base7683.orders(orderId), (ResolvedCrossChainOrder));
        orderData = resolvedOrder.fillInstructions[0].originData;
    }

    function assertOrder(
        bytes32 orderId,
        bytes memory orderData,
        uint256[] memory balancesBefore,
        ERC20 token,
        address sender,
        address receiver,
        bytes32 expectedStatus
    )
        internal
        view
    {
        bytes memory savedOrderData = orderDataById(orderId);
        bytes32 status = _base7683.orderStatus(orderId);

        assertEq(savedOrderData, orderData);
        assertTrue(status == expectedStatus);

        uint256[] memory balancesAfter = _balances(token);
        assertEq(balancesBefore[balanceId[sender]] - amount, balancesAfter[balanceId[sender]]);
        assertEq(balancesBefore[balanceId[receiver]] + amount, balancesAfter[balanceId[receiver]]);
    }

    function assertOpenOrder(
        bytes32 orderId,
        address sender,
        bytes memory orderData,
        uint256[] memory balancesBefore,
        address user
    )
        internal
        view
    {
        bytes memory savedOrderData = orderDataById(orderId);

        assertFalse(_base7683.isValidNonce(sender, 1));
        assertEq(savedOrderData, orderData);
        assertOrder(orderId, orderData, balancesBefore, inputToken, user, address(_base7683), _base7683.OPENED());
    }
}
