// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { ICrossL2ProverV2 } from "@polymerdao/prover-contracts/interfaces/ICrossL2ProverV2.sol";
import { OrderData, OrderEncoder } from "./libs/OrderEncoder.sol";
import { BasicSwap7683 } from "./BasicSwap7683.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Polymer7683
 * @author PolymerLabs
 * @notice This contract builds on top of BasicSwap7683 as a messaging layer using Polymer.
 * @dev It integrates with the Polymer protocol for cross-chain event verification.
 */
contract Polymer7683 is BasicSwap7683, Ownable {
    // ============ Constants ============
    string public constant CLIENT_TYPE = "polymer"; // Used for proof verification

    // ============ Public Storage ============
    ICrossL2ProverV2 public immutable prover;
    uint256 public immutable localChainId;
    mapping(uint256 => address) public destinationContracts;

    // Keep track of processed events to prevent replay
    mapping(bytes32 eventHash => bool processed) public processedEvents;

    // ============ Events ============
    /**
     * @notice Event emitted when a destination contract is updated
     * @param chainId The chain ID for the destination
     * @param contractAddress The new contract address
     */
    event DestinationContractUpdated(uint256 indexed chainId, address contractAddress);

    // ============ Errors ============
    error InvalidProof();
    error InvalidChainId();
    error InvalidEmitter();
    error EventAlreadyProcessed();
    error InvalidEventData();
    error InvalidDestinationContract();
    error UnregisteredDestinationChain();

    // ============ Constructor ============
    /**
     * @notice Initializes the Polymer7683 contract with the specified Prover and PERMIT2 address.
     * @param _prover The address of the Polymer CrossL2Prover contract
     * @param _permit2 The address of the permit2 contract
     * @param _localChainId The chain ID of the chain this contract is deployed on
     */
    constructor(
        ICrossL2ProverV2 _prover,
        address _permit2,
        uint256 _localChainId
    ) BasicSwap7683(_permit2) {
        prover = _prover;
        localChainId = _localChainId;
    }

    // ============ Admin Functions ============
    function setDestinationContract(uint256 chainId, address contractAddress) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidDestinationContract();
        destinationContracts[chainId] = contractAddress;
        emit DestinationContractUpdated(chainId, contractAddress);
    }

    // ============ External Functions ============
    /**
     * @notice Process a settlement proof from a destination chain
     * @param orderId The order ID being settled
     * @param eventProof The proof of the Fill event from the destination chain
     * @param logIndex The index of the log in the receipt
     * @param destinationChainId The chain ID where the fill occurred
     */
    function handleSettlementWithProof(
        bytes32 orderId,
        bytes calldata eventProof,
        uint256 logIndex,
        uint256 destinationChainId
    ) external {
        // 1. Verify event using Polymer prover
        (
            uint32 provenChainId,
            address actualEmitter,
            bytes memory topics,
            bytes memory data
        ) = prover.validateEvent(eventProof);

        // 2. Decode the Filled event data
        (
         bytes32 eventOrderId,
         bytes memory originData,
         bytes memory fillerData
        ) = abi.decode(data, (bytes32, bytes, bytes));

        // 3. Decode the original order data to get expected destination chain
        OrderData memory orderData = OrderEncoder.decode(originData);

        // 4. Validate the proven chain ID matches the order's intended destination
        if (provenChainId != orderData.destinationDomain) {
            revert InvalidChainId();
        }

        // 5. Verify the destination contract is registered
        address expectedEmitter = destinationContracts[destinationChainId];
        if (expectedEmitter == address(0)) revert UnregisteredDestinationChain();

        // 6. Validate the emitter matches our registered destination contract
        if (actualEmitter != expectedEmitter) revert InvalidEmitter();

        // 7. Verify this event hasn't been processed before (prevent replay)
        bytes32 eventHash = keccak256(abi.encodePacked(eventProof, logIndex, destinationChainId));
        if (processedEvents[eventHash]) revert EventAlreadyProcessed();
        processedEvents[eventHash] = true;

        // 8. Validate order ID matches
        if (orderId != eventOrderId) revert InvalidEventData();
        
        // 9. Process settlement for the order
        _handleSettleOrder(orderId, abi.decode(fillerData, (bytes32)));
    }

    /**
     * @notice Process a refund proof from a destination chain
     * @param orderId The order ID being refunded
     * @param eventProof The proof of the Refund event from the destination chain
     * @param logIndex The index of the log in the receipt
     * @param destinationChainId The chain ID where the refund was initiated
     */
    function handleRefundWithProof(
        bytes32 orderId,
        bytes calldata eventProof,
        uint256 logIndex,
        uint256 destinationChainId
    ) external {
        // 1. Verify the destination contract is registered
        address expectedEmitter = destinationContracts[destinationChainId];
        if (expectedEmitter == address(0)) revert UnregisteredDestinationChain();

        // 2. Verify event using Polymer prover
        (
            uint32 chainId,
            address actualEmitter,
            bytes memory topics,
            bytes memory data
        ) = prover.validateEvent(eventProof);

        // 3. Validate the chain ID matches our expected destination chain
        if (chainId != destinationChainId) {
            revert InvalidChainId();
        }

        // 4. Validate the emitter matches our registered destination contract
        if (actualEmitter != expectedEmitter) revert InvalidEmitter();

        // 5. Verify this event hasn't been processed before (prevent replay)
        bytes32 eventHash = keccak256(abi.encodePacked(eventProof, logIndex, destinationChainId));
        if (processedEvents[eventHash]) revert EventAlreadyProcessed();
        processedEvents[eventHash] = true;

        // 6. Parse the Refund event data
        bytes32[] memory eventOrderIds = abi.decode(data, (bytes32[]));

        // 7. Validate order ID is in the refunded set
        bool found = false;
        for (uint256 i = 0; i < eventOrderIds.length; i++) {
            if (eventOrderIds[i] == orderId) {
                found = true;
                break;
            }
        }
        if (!found) revert InvalidEventData();

        // 8. Process refund for the order
        _handleRefundOrder(orderId);
    }

    // ============ Internal Functions ============

    /**
     * @notice Dispatches a settlement instruction by emitting a Filled event that will be proven on the origin chain
     * @param _originDomain The domain to which the settlement message is sent
     * @param _orderIds The IDs of the orders to settle
     * @param _ordersFillerData The filler data for the orders
     */
    function _dispatchSettle(
        uint32 _originDomain,
        bytes32[] memory _orderIds,
        bytes[] memory _ordersFillerData
    ) internal override {
        for (uint256 i = 0; i < _orderIds.length; i++) {
            FilledOrder memory order = filledOrders[_orderIds[i]];
            emit Filled(_orderIds[i], order.originData, order.fillerData);
        }
    }

    /**
     * @notice Dispatches a refund instruction by emitting a Refund event that will be proven on the origin chain
     * @param _originDomain The domain to which the refund message is sent
     * @param _orderIds The IDs of the orders to refund
     */
    function _dispatchRefund(
        uint32 _originDomain,
        bytes32[] memory _orderIds
    ) internal override {
        emit Refund(_orderIds);
    }

    /**
     * @notice Retrieves the local domain identifier
     * @return The local domain ID (chain ID)
     */
    function _localDomain() internal view override returns (uint32) {
        return uint32(localChainId);
    }
}
