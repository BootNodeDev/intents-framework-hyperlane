const Output =
  "(bytes32 token, uint256 amount, bytes32 recipient, uint64 chainId)";
const FillInstruction =
  "(uint64 destinationChainId, bytes32 destinationSettler, bytes originData)";
const ResolvedCrossChainOrder = `(address user, uint64 originChainId, uint32 openDeadline, uint32 fillDeadline, ${Output}[] maxSpent, ${Output}[] minReceived, ${FillInstruction}[] fillInstructions)`;

export default [
  `event Open(bytes32 indexed orderId, ${ResolvedCrossChainOrder} resolvedOrder)`,

  // "function openFor(GaslessCrossChainOrder calldata order, bytes calldata signature, bytes calldata originFillerData) external",
  // "function open(OnchainCrossChainOrder calldata order) external",
  // "function resolveFor(GaslessCrossChainOrder calldata order, bytes calldata originFillerData) external view returns (ResolvedCrossChainOrder memory)",
  // "function resolve(OnchainCrossChainOrder calldata order) external view returns (ResolvedCrossChainOrder memory)",
] as const;
