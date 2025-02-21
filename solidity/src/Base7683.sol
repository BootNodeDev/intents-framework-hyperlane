// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

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

/**
 * @title Base7683
 * @notice Implements the ERC7683 standard for cross-chain order resolution, filling, settlement, and refunding.
 * @author BootNode
 * @dev Contains logic for managing orders without requiring specifics of the order data type.
 * Notice that settling and refunding is not described in the ERC7683 but it is included here to provide a common
 * interface for solvers to use.
 */
abstract contract Base7683 is IOriginSettler, IDestinationSettler {
    // ============ Libraries ============
    using SafeERC20 for IERC20;

    // ============ Constants ============
    /// @notice The instance of the Permit2 contract.
    IPermit2 public immutable PERMIT2;

    /// @notice Type hash used for encoding ResolvedCrossChainOrder.
    bytes32 public constant RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH = keccak256(
        "ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)"
    );

    /// @notice The witness type string used in PERMIT2 transactions.
    string public constant witnessTypeString =
        "ResolvedCrossChainOrder witness)ResolvedCrossChainOrder(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, Output[] maxSpent, Output[] minReceived, FillInstruction[] fillInstructions)Output(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)FillInstruction(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)TokenPermissions(address token,uint256 amount)";

    /// @notice Possible statuses for an order. Other possible statuses should be defined in the inheriting contract.
    bytes32 public constant UNKNOWN = "";
    bytes32 public constant OPENED = "OPENED";
    bytes32 public constant FILLED = "FILLED";

    // ============ Structs ============
    /**
     * @dev Represents data for an order that has been filled.
     * @param originData The origin-specific data for the order.
     * @param fillerData The filler-specific data for the order.
     */
    struct FilledOrder {
        bytes originData;
        bytes fillerData;
    }

    // ============ Public Storage ============

    /// @notice Tracks the used nonces for each address.
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice Stores the resolved orders by their ID.
    mapping(bytes32 orderId => bytes orderData) public openOrders;

    /// @notice Tracks filled orders and their associated data.
    mapping(bytes32 orderId => FilledOrder filledOrder) public filledOrders;

    /// @notice Tracks the status of each order by its ID.
    mapping(bytes32 orderId => bytes32 status) public orderStatus;

    // ============ Upgrade Gap ============
    /// @dev Reserved space for future storage variables to ensure upgradeability.
    uint256[47] private __GAP;

    // ============ Events ============
    /**
     * @notice Emitted when an order is filled.
     * @param orderId The ID of the filled order.
     * @param originData The origin-specific data for the order.
     * @param fillerData The filler-specific data for the order.
     */
    event Filled(bytes32 orderId, bytes originData, bytes fillerData);

    /**
     * @notice Emitted when a batch of orders is settled.
     * @param orderIds The IDs of the orders being settled.
     * @param ordersFillerData The filler data for the settled orders.
     */
    event Settle(bytes32[] orderIds, bytes[] ordersFillerData);

    /**
     * @notice Emitted when a batch of orders is refunded.
     * @param orderIds The IDs of the refunded orders.
     */
    event Refund(bytes32[] orderIds);

    /**
     * @notice Emitted when a nonce is invalidated for an address.
     * @param owner The address whose nonce was invalidated.
     * @param nonce The invalidated nonce.
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
    /**
     * @notice Initializes the contract with the given Permit2 contract address.
     * @param _permit2 The address of the Permit2 contract.
     */
    constructor(address _permit2) {
        PERMIT2 = IPermit2(_permit2);
    }

    // ============ Initializers ============

    // ============ External Functions ============

    /**
     * @notice Opens a gasless cross-chain order on behalf of a user.
     * @dev To be called by the filler.
     * @dev This method must emit the Open event
     * @param _order The GaslessCrossChainOrder definition
     * @param _signature The user's signature over the order
     * @param _originFillerData Any filler-defined data required by the settler
     */
    function openFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _signature,
        bytes calldata _originFillerData
    )
        external
        virtual
    {
        if (block.timestamp > _order.openDeadline) revert OrderOpenExpired();
        if (_order.originSettler != address(this)) revert InvalidGaslessOrderSettler();
        if (_order.originChainId != _localDomain()) revert InvalidGaslessOrderOrigin();

        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(_order, _originFillerData);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
        orderStatus[orderId] = OPENED;
        _useNonce(_order.user, nonce);

        _permitTransferFrom(resolvedOrder, _signature, _order.nonce, address(this));

        emit Open(orderId, resolvedOrder);
    }

    /**
     * @notice Opens a cross-chain order
     * @dev To be called by the user
     * @dev This method must emit the Open event
     * @param _order The OnchainCrossChainOrder definition
     */
    function open(OnchainCrossChainOrder calldata _order) external payable virtual {
        (ResolvedCrossChainOrder memory resolvedOrder, bytes32 orderId, uint256 nonce) = _resolveOrder(_order);

        openOrders[orderId] = abi.encode(_order.orderDataType, _order.orderData);
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

    /**
     * @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param _order The GaslessCrossChainOrder definition
     * NOT USED originFillerData Any filler-defined data required by the settler
     * @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolveFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _originFillerData
    )
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder)
    {
        (_resolvedOrder,,) = _resolveOrder(_order, _originFillerData);
    }

    /**
     * @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param _order The OnchainCrossChainOrder definition
     * @return _resolvedOrder ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolve(OnchainCrossChainOrder calldata _order)
        public
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder)
    {
        (_resolvedOrder,,) = _resolveOrder(_order);
    }

    /**
     * @notice Fills a single leg of a particular order on the destination chain
     * @param _orderId Unique order identifier for this order
     * @param _originData Data emitted on the origin to parameterize the fill
     * @param _fillerData Data provided by the filler to inform the fill or express their preferences. It should
     * contain the bytes32 encoded address of the receiver which is used at settlement time
     */
    function fill(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) external payable virtual {
        if (orderStatus[_orderId] != UNKNOWN) revert InvalidOrderStatus();

        _fillOrder(_orderId, _originData, _fillerData);

        orderStatus[_orderId] = FILLED;
        filledOrders[_orderId] = FilledOrder(_originData, _fillerData);

        emit Filled(_orderId, _originData, _fillerData);
    }

    /**
     * @notice Settles a batch of filled orders on the chain where the orders were opened.
     * @dev Pays the filler the amount locked when the orders were opened.
     * The settled status should not be changed here but rather on the origin chain. To allow the filler to retry in
     * case some error occurs.
     * Ensuring the order is eligible for settling in the origin chain is the responsibility of the caller.
     * @param _orderIds An array of IDs for the orders to settle.
     */
    function settle(bytes32[] calldata _orderIds) external payable {
        bytes[] memory ordersOriginData = new bytes[](_orderIds.length);
        bytes[] memory ordersFillerData = new bytes[](_orderIds.length);
        for (uint256 i = 0; i < _orderIds.length; i += 1) {
            // all orders must be FILLED
            if (orderStatus[_orderIds[i]] != FILLED) revert InvalidOrderStatus();

            ordersOriginData[i] = filledOrders[_orderIds[i]].originData;
            ordersFillerData[i] = filledOrders[_orderIds[i]].fillerData;
        }

        _settleOrders(_orderIds, ordersOriginData, ordersFillerData);

        emit Settle(_orderIds, ordersFillerData);
    }

    /**
     * @notice Refunds a batch of expired GaslessCrossChainOrders on the chain where the orders were opened.
     * The refunded status should not be changed here but rather on the origin chain. To allow the user to retry in
     * case some error occurs.
     * Ensuring the order is eligible for refunding in the origin chain is the responsibility of the caller.
     * @param _orders An array of GaslessCrossChainOrders to refund.
     */
    function refund(GaslessCrossChainOrder[] memory _orders) external payable {
        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            orderIds[i] = orderId;

            if (orderStatus[orderId] != UNKNOWN) revert InvalidOrderStatus();
            if (block.timestamp <= _orders[i].fillDeadline) revert OrderFillNotExpired();
        }

        _refundOrders(_orders, orderIds);

        emit Refund(orderIds);
    }

    /**
     * @notice Refunds a batch of expired OnchainCrossChainOrder on the chain where the orders were opened.
     * The refunded status should not be changed here but rather on the origin chain. To allow the user to retry in
     * case some error occurs.
     * Ensuring the order is eligible for refunding the origin chain is the responsibility of the caller.
     * @param _orders An array of GaslessCrossChainOrders to refund.
     */
    function refund(OnchainCrossChainOrder[] memory _orders) external payable {
        bytes32[] memory orderIds = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i += 1) {
            bytes32 orderId = _getOrderId(_orders[i]);
            orderIds[i] = orderId;

            if (orderStatus[orderId] != UNKNOWN) revert InvalidOrderStatus();
            if (block.timestamp <= _orders[i].fillDeadline) revert OrderFillNotExpired();
        }

        _refundOrders(_orders, orderIds);

        emit Refund(orderIds);
    }

    /**
     * @notice Invalidates a nonce for the user calling the function.
     * @param _nonce The nonce to invalidate.
     */
    function invalidateNonces(uint256 _nonce) external virtual {
        _useNonce(msg.sender, _nonce);

        emit NonceInvalidation(msg.sender, _nonce);
    }

    /**
     * @notice Checks whether a given nonce is valid.
     * @param _from The address whose nonce validity is being checked.
     * @param _nonce The nonce to check.
     * @return isValid True if the nonce is valid, false otherwise.
     */
    function isValidNonce(address _from, uint256 _nonce) external view virtual returns (bool) {
        return !usedNonces[_from][_nonce];
    }

    // ============ Public Functions ============

    /**
     * @notice Computes the Permit2 witness hash for a given ResolvedCrossChainOrder.
     * @param _resolvedOrder The ResolvedCrossChainOrder to compute the witness hash for.
     * @return The computed witness hash.
     */
    function witnessHash(ResolvedCrossChainOrder memory _resolvedOrder) public pure virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                RESOLVED_CROSS_CHAIN_ORDER_TYPEHASH,
                _resolvedOrder.user,
                _resolvedOrder.originChainId,
                _resolvedOrder.openDeadline,
                _resolvedOrder.fillDeadline,
                _resolvedOrder.maxSpent,
                _resolvedOrder.minReceived,
                _resolvedOrder.fillInstructions
            )
        );
    }

    // ============ Internal Functions ============

    /**
     * @notice Marks a nonce as used by setting its bit in the appropriate bitmap.
     * @dev Ensures that a nonce cannot be reused by flipping the corresponding bit in the bitmap.
     * Reverts if the nonce is already used.
     * @param _from The address for which the nonce is being used.
     * @param _nonce The nonce to mark as used.
     */
    function _useNonce(address _from, uint256 _nonce) internal {
        if (usedNonces[_from][_nonce]) revert InvalidNonce();
        usedNonces[_from][_nonce] = true;
    }

    /**
     * @notice Executes a batch token transfer using the Permit2 `permitWitnessTransferFrom` method.
     * @dev Transfers tokens specified in a resolved cross-chain order to the receiver.
     * @param _resolvedOrder The resolved order specifying tokens and amounts to transfer.
     * @param _signature The user's signature for the permit.
     * @param _nonce The unique nonce associated with the order.
     * @param _receiver The address that will receive the tokens.
     */
    function _permitTransferFrom(
        ResolvedCrossChainOrder memory _resolvedOrder,
        bytes calldata _signature,
        uint256 _nonce,
        address _receiver
    )
        internal
    {
        ISignatureTransfer.TokenPermissions[] memory permitted =
            new ISignatureTransfer.TokenPermissions[](_resolvedOrder.minReceived.length);

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](_resolvedOrder.minReceived.length);

        for (uint256 i = 0; i < _resolvedOrder.minReceived.length; i++) {
            permitted[i] = ISignatureTransfer.TokenPermissions({
                token: TypeCasts.bytes32ToAddress(_resolvedOrder.minReceived[i].token),
                amount: _resolvedOrder.minReceived[i].amount
            });
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails({
                to: _receiver,
                requestedAmount: _resolvedOrder.minReceived[i].amount
            });
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: _nonce,
            deadline: _resolvedOrder.openDeadline
        });

        PERMIT2.permitWitnessTransferFrom(
            permit, transferDetails, _resolvedOrder.user, witnessHash(_resolvedOrder), witnessTypeString, _signature
        );
    }

    /**
     * @notice Resolves a GaslessCrossChainOrder into a ResolvedCrossChainOrder.
     * @dev To be implemented by the inheriting contract. Contains logic specific to the order type and data.
     * @param _order The GaslessCrossChainOrder to resolve.
     * @param _originFillerData Any filler-defined data required by the settler
     * @return _resolvedOrder A ResolvedCrossChainOrder with hydrated data.
     * @return _orderId The unique identifier for the order.
     * @return _nonce The nonce associated with the order.
     */
    function _resolveOrder(GaslessCrossChainOrder memory _order, bytes calldata _originFillerData)
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder, bytes32 _orderId, uint256 _nonce);

    /**
     * @notice Resolves an OnchainCrossChainOrder into a ResolvedCrossChainOrder.
     * @dev To be implemented by the inheriting contract. Contains logic specific to the order type and data.
     * @param _order The OnchainCrossChainOrder to resolve.
     * @return _resolvedOrder A ResolvedCrossChainOrder with hydrated data.
     * @return _orderId The unique identifier for the order.
     * @return _nonce The nonce associated with the order.
     */
    function _resolveOrder(OnchainCrossChainOrder memory _order)
        internal
        view
        virtual
        returns (ResolvedCrossChainOrder memory _resolvedOrder, bytes32 _orderId, uint256 _nonce);

    /**
     * @notice Fills an order with specific origin and filler data.
     * @dev To be implemented by the inheriting contract. Defines how to process the origin and filler data.
     * @param _orderId The unique identifier for the order to fill.
     * @param _originData Data emitted on the origin chain to parameterize the fill.
     * @param _fillerData Data provided by the filler, including preferences and additional information.
     */
    function _fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData) internal virtual;

    /**
     * @notice Settles a batch of orders using their origin and filler data.
     * @dev To be implemented by the inheriting contract. Contains the specific logic for settlement.
     * @param _orderIds An array of order IDs to settle.
     * @param _ordersOriginData The origin data for the orders being settled.
     * @param _ordersFillerData The filler data for the orders being settled.
     */
    function _settleOrders(
        bytes32[] calldata _orderIds,
        bytes[] memory _ordersOriginData,
        bytes[] memory _ordersFillerData
    )
        internal
        virtual;

    /**
     * @notice Refunds a batch of OnchainCrossChainOrders.
     * @dev To be implemented by the inheriting contract. Contains logic specific to refunds.
     * @param _orders An array of OnchainCrossChainOrders to refund.
     * @param _orderIds An array of IDs for the orders to refund.
     */
    function _refundOrders(OnchainCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal virtual;

    /**
     * @notice Refunds a batch of GaslessCrossChainOrders.
     * @dev To be implemented by the inheriting contract. Contains logic specific to refunds.
     * @param _orders An array of GaslessCrossChainOrders to refund.
     * @param _orderIds An array of IDs for the orders to refund.
     */
    function _refundOrders(GaslessCrossChainOrder[] memory _orders, bytes32[] memory _orderIds) internal virtual;

    /**
     * @notice Retrieves the local domain identifier.
     * @dev To be implemented by the inheriting contract. Specifies the logic to determine the local domain.
     * @return The local domain ID.
     */
    function _localDomain() internal view virtual returns (uint32);

    /**
     * @notice Computes the unique identifier for a GaslessCrossChainOrder.
     * @dev To be implemented by the inheriting contract. Specifies the logic to compute the order ID.
     * @param _order The GaslessCrossChainOrder to compute the ID for.
     * @return The unique identifier for the order.
     */
    function _getOrderId(GaslessCrossChainOrder memory _order) internal pure virtual returns (bytes32);

    /**
     * @notice Computes the unique identifier for an OnchainCrossChainOrder.
     * @dev To be implemented by the inheriting contract. Specifies the logic to compute the order ID.
     * @param _order The OnchainCrossChainOrder to compute the ID for.
     * @return The unique identifier for the order.
     */
    function _getOrderId(OnchainCrossChainOrder memory _order) internal pure virtual returns (bytes32);
}
