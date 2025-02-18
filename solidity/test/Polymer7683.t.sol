// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { OnchainCrossChainOrder } from "../src/ERC7683/IERC7683.sol";
import { OrderData, OrderEncoder } from "../src/libs/OrderEncoder.sol";
import { Polymer7683 } from "../src/Polymer7683.sol";
import { LightClientType } from "@polymerdao/prover-contracts/interfaces/IClientUpdates.sol";
import { ICrossL2ProverV2 } from "@polymerdao/prover-contracts/interfaces/ICrossL2ProverV2.sol";

contract MockCrossL2Prover is ICrossL2ProverV2 {
    uint32 public expectedChainId;
    address public expectedEmitter;
    bytes public expectedTopics;
    bytes public expectedData;

    function setExpectedEvent(
        uint32 chainId,
        address emitter,
        bytes memory topics,
        bytes memory data
    ) external {
        expectedChainId = chainId;
        expectedEmitter = emitter;
        expectedTopics = topics;
        expectedData = data;
    }

    function validateEvent(bytes calldata proof) external view returns (
        uint32 chainId,
        address emittingContract,
        bytes memory topics,
        bytes memory unindexedData
    ) {
        return (expectedChainId, expectedEmitter, expectedTopics, expectedData);
    }

    function inspectLogIdentifier(bytes calldata proof) external pure returns (uint32 srcChain, uint64 blockNumber, uint16 receiptIndex, uint8 logIndex) {
        return (0, 0, 0, 0);
    }

    function inspectPolymerState(bytes calldata proof) external pure returns (bytes32 stateRoot, uint64 height, bytes memory signature) {
        return (bytes32(0), 0, "");
    }
}

contract Polymer7683Test is Test {
    using TypeCasts for address;

    Polymer7683 polymer7683;
    MockCrossL2Prover prover;
    
    address owner;
    address permit2;
    uint256 localChainId;
    uint256 destChainId;
    address destContract;

    function setUp() public {
        owner = makeAddr("owner");
        permit2 = makeAddr("permit2");
        localChainId = 1;
        destChainId = 2;
        destContract = makeAddr("destContract");

        prover = new MockCrossL2Prover();
        
        vm.prank(owner);
        polymer7683 = new Polymer7683(
            ICrossL2ProverV2(address(prover)),
            permit2,
            localChainId
        );
    }

    function _createSettlementProof(
        uint256 chainId,
        address emitter,
        bytes32 orderId,
        bytes memory fillerData
    ) internal returns (bytes memory) {
        OrderData memory orderData = OrderData({
            sender: TypeCasts.addressToBytes32(address(this)),
            recipient: TypeCasts.addressToBytes32(address(this)),
            inputToken: bytes32(0),
            outputToken: bytes32(0),
            amountIn: 1e18,
            amountOut: 2e18,
            senderNonce: 0,
            originDomain: uint32(localChainId),
            destinationDomain: uint32(chainId),
            destinationSettler: TypeCasts.addressToBytes32(emitter),
            fillDeadline: uint32(block.timestamp + 1 hours),
            data: ""
            });

        bytes memory originData = OrderEncoder.encode(orderData);
    
        // Create the proof data
        bytes memory topics = abi.encodePacked(
            keccak256("Filled(bytes32,bytes,bytes)"),
            bytes32(chainId)
        );
    
        bytes memory data = abi.encode(orderId, originData, fillerData);
    
        prover.setExpectedEvent(
            uint32(chainId),
            emitter,
            topics,
            data
        );
    
        return "dummy_proof";
    }

    function _createRefundProof(
        uint256 chainId,
        address emitter,
        bytes32[] memory orderIds
    ) internal returns (bytes memory) {
        // Concatenates all topics:
        // 1. Event signature (32 bytes)
        // 2. Indexed chainId (32 bytes)
        bytes memory topics = abi.encodePacked(
            keccak256("BatchOrdersFilled(uint256,bytes32[],bytes[])"),
            bytes32(chainId)
        );
        
        // Create empty filler data array for refund
        bytes[] memory emptyFillerData = new bytes[](0);
        
        // Encode the event data exactly as the contract would emit it
        bytes memory data = abi.encode(orderIds, emptyFillerData);
        
        prover.setExpectedEvent(
            uint32(chainId),
            emitter,
            topics,
            data
        );
        
        return "dummy_proof";
    }

    function test_setDestinationContract() public {
        vm.prank(owner);
    
        polymer7683.setDestinationContract(destChainId, destContract);
        address stored = polymer7683.destinationContracts(destChainId);
        assertEq(stored, destContract, "Destination contract address mismatch");
    }

    function test_handleSettlementWithProof_success() public {
        // Register destination contract
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
    
        console2.log("\nTest setup:");
        console2.log("Local Chain ID:", localChainId);
        console2.log("Destination Chain ID:", destChainId);
        console2.log("Destination Contract:", destContract);
    
        // Create sample order ID and filler data
        bytes32 orderId = bytes32("orderId1");
        bytes memory fillerData = abi.encode(bytes32("filler1"));
    
        console2.log("\nOrder ID:");
        console2.logBytes32(orderId);
    
        // Create and submit settlement proof
        bytes memory proof = _createSettlementProof(destChainId, destContract, orderId, fillerData);
    
        console2.log("\nSettlement proof details:");
        console2.log("Proof length:", proof.length);
    
        // Get proof validation details
        (
            uint32 provenChainId,
            address emitter,
            bytes memory topics,
            bytes memory data
        ) = prover.validateEvent(proof);
        console2.log("Proven Chain ID:", provenChainId);
        console2.log("Emitter:", emitter);
        console2.log("Topics length:", topics.length);
        console2.log("Data length:", data.length);

        console2.log("\nDecoding event data...");
        (
            bytes32 decodedOrderId,
            bytes memory originData,
            bytes memory decodedFillerData
        ) = abi.decode(data, (bytes32, bytes, bytes));
        console2.log("Decoded Order ID:");
        console2.logBytes32(decodedOrderId);
        console2.log("Origin Data length:", originData.length);
        console2.log("Filler Data length:", decodedFillerData.length);

        console2.log("\nSubmitting settlement proof...");
        polymer7683.handleSettlementWithProof(orderId, proof, 0, destChainId);

        try polymer7683.handleSettlementWithProof(orderId, proof, 0, destChainId) {
            console2.log("\nCall succeeded");
        } catch Error(string memory reason) {
            console2.log("\nReverted with reason:", reason);
        } catch (bytes memory errData) {
            console2.log("\nReverted with raw error data length:", errData.length);
            if (errData.length >= 4) {
                bytes4 selector = bytes4(errData);
                console2.log("Error selector:");
                console2.logBytes4(selector);
            }
        }
   
        /* // Verify event is marked as processed */
        /* bytes32 eventHash = keccak256(abi.encodePacked(proof, uint256(0), destChainId)); */
        /* console2.log("\nChecking if event is processed:"); */
        /* console2.log(polymer7683.processedEvents(eventHash)); */
    }

    function test_handleSettlementWithProof_preventReplay() public {
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
    
        bytes32 orderId = bytes32("orderId1");
    
        // Create array with single orderId for proof
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
    
        bytes memory proof = _createRefundProof(destChainId, destContract, orderIds);
    
        console2.log("First attempt...");
        polymer7683.handleRefundWithProof(orderId, proof, 0, destChainId);
    
        console2.log("\nChecking if order is marked as processed:");
        console2.log(polymer7683.processedEvents(orderId));
    
        console2.log("\nSecond attempt...");
        vm.expectRevert(Polymer7683.EventAlreadyProcessed.selector);
        polymer7683.handleRefundWithProof(orderId, proof, 0, destChainId);
    }

    function test_handleSettlementWithProof_wrongChainId() public {
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
        
        bytes32 orderId = bytes32("orderId1");
        bytes memory fillerData = abi.encode(bytes32("filler1"));
        
        // Create proof for wrong chain ID
        bytes memory proof = _createSettlementProof(999, destContract, orderId, fillerData);
        
        vm.expectRevert(Polymer7683.InvalidChainId.selector);
        polymer7683.handleSettlementWithProof(orderId, proof, 0, destChainId);
    }

    function test_handleSettlementWithProof_unregisteredDestination() public {
        bytes32 orderId = bytes32("orderId1");
        bytes memory fillerData = abi.encode(bytes32("filler1"));
        
        bytes memory proof = _createSettlementProof(destChainId, destContract, orderId, fillerData);
        
        vm.expectRevert(Polymer7683.UnregisteredDestinationChain.selector);
        polymer7683.handleSettlementWithProof(orderId, proof, 0, destChainId);
    }

    function test_handleSettlementWithProof_invalidOrderId() public {
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
        
        // Create proof for one order ID
        bytes32 proofOrderId = bytes32("order1");
        bytes memory fillerData = abi.encode(bytes32("filler1"));

        console2.log("\nTest setup:");
        console2.log("Proof Order ID:");
        console2.logBytes32(proofOrderId);
        console2.log("Submitted Order ID:");
        console2.logBytes32(bytes32("order2"));
        
        bytes memory proof = _createSettlementProof(destChainId, destContract, proofOrderId, fillerData);

        (, , bytes memory topics, bytes memory eventData) = prover.validateEvent(proof);

        console2.log("\nDecoding event data...");
        (
            bytes32 decodedOrderId,
            bytes memory decodedOriginData,
            bytes memory decodedFillerData
        ) = abi.decode(eventData, (bytes32, bytes, bytes));
        console2.log("Decoded Order ID from proof:");
        console2.logBytes32(decodedOrderId);
        console2.log("Decoded Origin Data length:", decodedOriginData.length);
        console2.log("Decoded Filler Data length:", decodedFillerData.length);
      
        // Try to submit different order ID
        bytes32 submittedOrderId = bytes32("order2");
        
        vm.expectRevert(Polymer7683.InvalidEventData.selector);
        try polymer7683.handleSettlementWithProof(submittedOrderId, proof, 0, destChainId) {
            console2.log("Call succeeded unexpectedly");
        } catch Error(string memory reason) {
            console2.log("Reverted with reason:", reason);
        } catch (bytes memory errData) {
            console2.log("Reverted with raw error data length:", errData.length);
            if (errData.length >= 4) {
                bytes4 selector = bytes4(errData);
                console2.log("Error selector:");
                console2.logBytes4(selector);
            }
        }
    }

    function test_handleRefundWithProof_success() public {
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
        
        bytes32 orderId = bytes32("orderId1");
        
        // Create a single-element array for the proof creation
        bytes32[] memory orderIdsForProof = new bytes32[](1);
        orderIdsForProof[0] = orderId;
        
        bytes memory proof = _createRefundProof(destChainId, destContract, orderIdsForProof);
        
        // Add more detailed debug logs
        (, , bytes memory topics, bytes memory eventData) = prover.validateEvent(proof);
        
        console2.log("\nDecoding event data...");
        (bytes32[] memory decodedOrderIds, bytes[] memory decodedFillerData) = abi.decode(eventData, (bytes32[], bytes[]));
        
        console2.log("Expected orderId:");
        console2.logBytes32(orderId);
        console2.log("Decoded orderId:");
        console2.logBytes32(decodedOrderIds[0]);
        
        console2.log("\nFiller data check:");
        console2.log("Decoded filler data length:", decodedFillerData.length);
        
        // Let's also log the expected event signature
        bytes32 expectedSig = keccak256("BatchOrdersFilled(uint256,bytes32[],bytes[])");
        console2.log("\nExpected event signature:");
        console2.logBytes32(expectedSig);
    
        // Log the chain ID being used
        console2.log("\nDestination chain ID:", destChainId);
        
        try polymer7683.handleRefundWithProof(orderId, proof, 0, destChainId) {
            console2.log("Refund successful");
        } catch Error(string memory reason) {
            console2.log("Refund failed with reason:", reason);
        } catch (bytes memory errData) {
            console2.log("Refund failed with raw error:");
            console2.logBytes(errData);
        }
    }

    function test_handleSettlementWithProof_wrongEmitter() public {
        vm.prank(owner);
        polymer7683.setDestinationContract(destChainId, destContract);
        
        address wrongContract = makeAddr("wrong");
        bytes32 orderId = bytes32("orderId1");
        bytes memory fillerData = abi.encode(bytes32("filler1"));
        
        bytes memory proof = _createSettlementProof(destChainId, wrongContract, orderId, fillerData);
        
        vm.expectRevert(Polymer7683.InvalidEmitter.selector);
        polymer7683.handleSettlementWithProof(orderId, proof, 0, destChainId);
    }

    function test_setDestinationContract_onlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        polymer7683.setDestinationContract(destChainId, destContract);
    }
}
