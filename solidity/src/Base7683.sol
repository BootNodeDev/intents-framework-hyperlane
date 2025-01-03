// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { IPermit2, ISignatureTransfer } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import {
    GaslessCrossChainOrder,
    OnchainCrossChainOrder,
    ResolvedCrossChainOrder,
    IOriginSettler,
    IDestinationSettler
} from "./ERC7683/IERC7683.sol";

abstract contract Base7683 is IOriginSettler, IDestinationSettler {
    // ============ Libraries ============
    using SafeERC20 for IERC20;

    // ============ Constants ============

    IPermit2 public immutable PERMIT2;

    bytes32 public constant RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH = keccak256(
        "ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)"
    );

    string public constant witnessTypeString =
        "ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)TokenPermissions(address token,uint256 amount)";

    // to be used to check the status of the order on orderStatus mapping. Other possible statuses should be defined in
    // the inheriting contract
    bytes32 public constant UNKNOWN = "";
    bytes32 public constant OPENED = "OPENED";
    bytes32 public constant FILLED = "FILLED";

    // ============ Public Storage ============

    struct FilledOrder {
        bytes originData;
        bytes fillerData;
    }

    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    mapping(bytes32 orderId => bytes resolvedOrder) public orders;

    mapping(bytes32 orderId => FilledOrder filledOrder) public filledOrders;

    mapping(bytes32 orderId => bytes32 status) public orderStatus;

    // ============ Upgrade Gap ============

    uint256[47] private __GAP;

    // ============ Events ============

    event Filled(bytes32 orderId, bytes originData, bytes fillerData);
    event Settle(bytes32[] orderIds, bytes[] ordersFillerData);
    event Refund(bytes32[] orderIds);

    /**
     * @notice Emits an event when the owner successfully invalidates an unordered nonce.
     */
    event NonceInvalidation(address indexed owner, uint256 nonce);

    // ============ Errors ============

    error OrderOpenExpired();
    error InvalidOrderStatus();
    error InvalidGaslessOrderSettler();
    error InvalidGaslessOrderOrigin();
    error InvalidNonce();
    error InvalidOrderOrigin();
    error OrderFillNotExpired();
    error InvalidNativeAmount();

    // ============ Constructor ============

    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
    }

    // ============ Initializers ============

    // ============ External Functions ============

    /// @notice Opens a gasless cross-chain order on behalf of a user.
    /// @dev To be called by the filler.
    /// @dev This method must emit the Open event
    /// @param order The GaslessCrossChainOrder definition
    /// @param signature The user's signature over the order
    /// NOT USED originFillerData Any filler-defined data required by the settler
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata
    )
        external
        virtual
    {
        if (block.timestamp > order.openDeadline) revert OrderOpenExpired();
        if (order.originSettler != address(this)) revert InvalidGaslessOrderSettler();
        if (order.originChainId != _localDomain()) revert InvalidGaslessOrderOrigin();

        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(order);

        orders[orderId] = abi.encode(resolvedOrder);
        orderStatus[orderId] = OPENED;
        _useNonce(order.user, nonce);

        _permitTransferFrom(resolvedOrder, signature, order.nonce, address(this));

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Opens a cross-chain order
    /// @dev To be called by the user
    /// @dev This method must emit the Open event
    /// @param order The OnchainCrossChainOrder definition
    // TODO - add support for native token
    function open(OnchainCrossChainOrder calldata order) external payable virtual {
        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(order);

        orders[orderId] = abi.encode(resolvedOrder);
        orderStatus[orderId] = OPENED;
        _useNonce(msg.sender, nonce);

        uint256 totalValue;
        for (uint256 i = 0; i < resolvedOrder.minReceived.length; i++) {
            address token = TypeCasts.bytes32ToAddress(resolvedOrder.minReceived[i].token);
            if (token == address(0)) {
                totalValue += resolvedOrder.minReceived[i].amount;
            } else {
                IERC20(token).safeTransferFrom(msg.sender, address(this), resolvedOrder.minReceived[i].amount);
            }
        }

        if (msg.value != totalValue) revert InvalidNativeAmount();

        emit Open(orderId, resolvedOrder);
    }

    /// @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param order The GaslessCrossChainOrder definition
    /// NOT USED originFillerData Any filler-defined data required by the settler
    /// @return resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata
    )
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory resolvedOrder)
    {
        (resolvedOrder,,) = _resolveOrder(order);
    }

    /// @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
    /// @dev Intended to improve standardized integration of various order types and settlement contracts
    /// @param order The OnchainCrossChainOrder definition
    /// @return resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
    function resolve(OnchainCrossChainOrder calldata order)
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory resolvedOrder)
    {
        (resolvedOrder,,) = _resolveOrder(order);
    }

    /// @notice Fills a single leg of a particular order on the destination chain
    /// @param _orderId Unique order identifier for this order
    /// @param _originData Data emitted on the origin to parameterize the fill
    /// @param _fillerData Data provided by the filler to inform the fill or express their preferences. It should
    /// contain the bytes32 encoded address of the receiver which is the used at settlement time
    // TODO - add support for native token
    function fill(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) external payable virtual {
        if (orderStatus[_orderId] != UNKNOWN) revert InvalidOrderStatus();

        _fillOrder(_orderId, _originData, _fillerData);

        orderStatus[_orderId] = FILLED;
        // TODO - unify _originData and _fillerData into a single struct
        filledOrders[_orderId] = FilledOrder(_originData, _fillerData);

        emit Filled(_orderId, _originData, _fillerData);
    }

    function settle(bytes32[] calldata _orderIds) external payable {
        bytes[] memory ordersOriginData = new bytes[](_orderIds.length);
        bytes[] memory ordersFillerData = new bytes[](_orderIds.length);
        for (uint256 i = 0; i < _orderIds.length; i += 1) {
            // all orders must be FILLED
            if (orderStatus[_orderIds[i]] != FILLED) revert InvalidOrderStatus();

            // It may be good idea not to change the status here (on destination) but only on the origin.
            // If the filler fills the order and settles it before it is opened on the origin, there should be a way for
            // the filler to retry settling the order. Another scenario is some of the orders are not from the same
            // origin domain as the first one which may be used to handle the settlement of the complete batch.
            // Is caller responsibility to ensure the order hasn't been settled on origin yet
            ordersOriginData[i] = filledOrders[_orderIds[i]].originData;
            ordersFillerData[i] = filledOrders[_orderIds[i]].fillerData;
        }

        _settleOrders(_orderIds, ordersOriginData, ordersFillerData);

        emit Settle(_orderIds, ordersFillerData);
    }

    // TODO - refactor this two
    function refund(GaslessCrossChainOrder[] memory _orders) external payable {
        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            orderIds[i] = orderId;

            if (orderStatus[orderId] != UNKNOWN) revert InvalidOrderStatus();
            if (block.timestamp <= _orders[i].fillDeadline) revert OrderFillNotExpired();

            // the status is changed on origin, the caller responsibility to ensure the order hasn't been refunded
            // on origin yet. In case one of the orders is not from the same origin domain as the first one, the caller
            // can retry the refund
        }

        _refundOrders(_orders, orderIds);

        emit Refund(orderIds);
    }

    function refund(OnchainCrossChainOrder[] memory _orders) external payable {
        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            orderIds[i] = orderId;

            if (orderStatus[orderId] != UNKNOWN) revert InvalidOrderStatus();
            if (block.timestamp <= _orders[i].fillDeadline) revert OrderFillNotExpired();

            // the status is changed on origin, the caller responsibility to ensure the order hasn't been refunded
            // on origin yet. In case one of the orders is not from the same origin domain as the first one, the caller
            // can retry the refund
        }

        _refundOrders(_orders, orderIds);

        emit Refund(orderIds);
    }

    // ============ Public Functions ============

    function witnessHash(ResolvedCrossChainOrder memory resolvedOrder) public pure virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH,
                resolvedOrder.user,
                resolvedOrder.originChainId,
                resolvedOrder.openDeadline,
                resolvedOrder.fillDeadline,
                resolvedOrder.maxSpent,
                resolvedOrder.minReceived,
                resolvedOrder.fillInstructions
            )
        );
    }

    /// @notice Invalidates the a nonce for the user calling the function
    /// @param nonce The nonce to get the associated word and bit positions
    function invalidateNonces(uint256 nonce) external virtual {
        _useNonce(msg.sender, nonce);

        emit NonceInvalidation(msg.sender, nonce);
    }

    function isValidNonce(address from, uint256 nonce) external view virtual returns (bool) {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;

        return nonceBitmap[from][wordPos] & bit == 0;
    }

    // ============ Internal Functions ============

    /// @notice Returns the index of the bitmap and the bit position within the bitmap. Used for unordered nonces
    /// @param nonce The nonce to get the associated word and bit positions
    /// @return wordPos The word position or index into the nonceBitmap
    /// @return bitPos The bit position
    /// @dev The first 248 bits of the nonce value is the index of the desired bitmap
    /// @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
    function bitmapPositions(uint256 nonce) private pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }

    /// @notice Checks whether a nonce is taken and sets the bit at the bit position in the bitmap at the word position
    /// @param from The address to use the nonce at
    /// @param nonce The nonce to spend
    function _useNonce(address from, uint256 nonce) internal {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;
        uint256 flipped = nonceBitmap[from][wordPos] ^= bit;

        if (flipped & bit == 0) revert InvalidNonce();
    }

    function _permitTransferFrom(
        ResolvedCrossChainOrder memory resolvedOrder,
        bytes calldata signature,
        uint256 nonce,
        address receiver
    )
        internal
    {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](resolvedOrder.minReceived.length);

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](resolvedOrder.minReceived.length);

        for (uint256 i = 0; i < resolvedOrder.minReceived.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({
                token: TypeCasts.bytes32ToAddress(resolvedOrder.minReceived[i].token),
                amount: resolvedOrder.minReceived[i].amount
            });
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails({
                to: receiver,
                requestedAmount: resolvedOrder.minReceived[i].amount
            });
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: nonce,
            deadline: resolvedOrder.openDeadline
        });

        PERMIT2.permitWitnessTransferFrom(
            permit, transferDetails, resolvedOrder.user, witnessHash(resolvedOrder), witnessTypeString, signature
        );
    }

    /**
     * @dev To be implemented by the inheriting contract with specific logic fot the orderDataType and orderData
     */
    function _resolveOrder(GaslessCrossChainOrder memory order)
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce);

    /**
     * @dev To be implemented by the inheriting contract with specific logic fot the orderDataType and orderData
     */
    function _resolveOrder(OnchainCrossChainOrder memory order)
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory, bytes32 orderId, uint256 nonce);

    function _fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) internal virtual;

    function _settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory ordersOriginData,
        bytes[] memory ordersFillerData
    )
        internal
        virtual;

    function _refundOrders(OnchainCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal virtual;
    function _refundOrders(GaslessCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal virtual;

    /**
     * @dev To be implemented by the inheriting contract with specific logic, should return the local domain
     */
    function _localDomain() internal view virtual returns (uint32);

    function _getOrderId(GaslessCrossChainOrder memory order) internal pure virtual returns (bytes32);
    function _getOrderId(OnchainCrossChainOrder memory order) internal pure virtual returns (bytes32);

    function getfilledOrder(bytes32 orderId) external view returns (FilledOrder memory) {
        return filledOrders[orderId];
    }
}
