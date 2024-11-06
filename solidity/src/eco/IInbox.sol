pragma solidity 0.8.25;

interface IInbox {

    // Event emitted when an intent is succesfully fulfilled
    event Fulfillment(bytes32 indexed _hash, uint256 indexed _sourceChainID, address indexed _claimant);

    // Event emitted when an intent is succesfully fulfilled and ready to be slow-path proven
    event ToBeProven(bytes32 indexed _hash, uint256 indexed _sourceChainID, address indexed _claimant);

    // Event emitted when an intent is successfully fulfilled with the instant hyperprover path
    event HyperInstantFulfillment(bytes32 indexed _hash, uint256 indexed _sourceChainID, address indexed _claimant);

    // Event emitted when an intent is fulfilled and added to a batch to be proven with the hyperprover
    event AddToBatch(bytes32 indexed _hash, uint256 indexed _sourceChainID, address indexed _claimant, address _prover);

    // Event emitted when solving is made public
    event SolvingIsPublic();

    // Event emitted when a change is made to the solver whitelist
    event SolverWhitelistChanged(address indexed _solver, bool indexed _canSolve);

    // Event emitted when the prover address of a chain is set
    event ProverSet(uint256 indexed _chainID, address indexed _prover);

    // Error thrown when solving intents is not public and a non-whitelisted address made a solve attempt
    error UnauthorizedSolveAttempt(address _solver);

    // Error thrown when the intent can no longer be fulfilled because its timestamp has expired
    error IntentExpired();

    // Error thrown when the intent has already been fulfilled
    error IntentAlreadyFulfilled(bytes32 _hash);

    // Error thrown when the intent call failed while itertating through the callAddresses
    error IntentCallFailed(address _addr, bytes _data, bytes _returnData);

    // Error thrown when the hash generated on the inbox contract does not match the expected hash
    error InvalidHash(bytes32 _expectedHash);

    // Error thrown when a solver attempts to make a call to the hyperlane mailbox
    error CallToMailbox();

    // Error thrown when the number of intents in a call to sendBatch exceeds MAX_BATCH_SIZE
    error BatchTooLarge();

    // Error thrown when an intent that is not yet fulfilled is sent as part of a hyperprove batch
    error IntentNotFulfilled(bytes32 _hash);

    // Error thrown when the fee sent by the solver for a hyperprover fulfillment is less than the fee required by the mailbox
    error InsufficientFee(uint256 _requiredFee);

    /**
     * This function is the main entry point for fulfilling an intent. It validates that the intentHash is the hash of the other parameters.
     * It then calls the addresses with their respective calldata, and if successful marks the intent as fulfilled and emits an event.
     * @param _sourceChainID The chainID of the source chain
     * @param _targets The array of addresses to call
     * @param _data The array of calldata
     * @param _expiryTime The timestamp at which the intent expires
     * @param _nonce The nonce of the calldata. Composed of the hash on the src chain of a global nonce & chainID
     * @param _claimant The address who can claim the reward on the src chain. Not part of the hash
     * @param _expectedHash The hash a solver should expect to be generated from the params above.
     * @dev this is a guardrail to make sure solves dont accidentally solve intents that cannot be proven.
     * @return results The results of the calls as an array of bytes
     */
    function fulfillStorage(
        uint256 _sourceChainID,
        address[] calldata _targets,
        bytes[] calldata _data,
        uint256 _expiryTime,
        bytes32 _nonce,
        address _claimant,
        bytes32 _expectedHash
    ) external returns (bytes[] memory);

    /**
     * Same as above but with the added _prover parameter. This fulfill method is used to fulfill an intent that is proving with the HyperProver and wishes to prove immediately.
     * @param _sourceChainID The chainID of the source chain
     * @param _targets The array of addresses to call
     * @param _data The array of calldata
     * @param _expiryTime The timestamp at which the intent expires
     * @param _nonce The nonce of the calldata. Composed of the hash on the src chain of a global nonce & chainID
     * @param _claimant The address who can claim the reward on the src chain. Not part of the hash
     * @param _expectedHash The hash a solver should expect to be generated from the params above.
     * @dev this is a guardrail to make sure solves dont accidentally solve intents that cannot be proven.
     * @param _prover The prover against which this intent will be checked
     * @return results The results of the calls as an array of bytes
     */
    function fulfillHyperInstant(
        uint256 _sourceChainID,
        address[] calldata _targets,
        bytes[] calldata _data,
        uint256 _expiryTime,
        bytes32 _nonce,
        address _claimant,
        bytes32 _expectedHash,
        address _prover
    ) external payable returns (bytes[] memory);

    /**
     * Same as above but with the added _prover parameter. This fulfill method is used to fulfill an intent that is proving with the HyperProver, but defers proving to lower cost.
     * @param _sourceChainID The chainID of the source chain
     * @param _targets The array of addresses to call
     * @param _data The array of calldata
     * @param _expiryTime The timestamp at which the intent expires
     * @param _nonce The nonce of the calldata. Composed of the hash on the src chain of a global nonce & chainID
     * @param _claimant The address who can claim the reward on the src chain. Not part of the hash
     * @param _expectedHash The hash a solver should expect to be generated from the params above.
     * @dev this is a guardrail to make sure solves dont accidentally solve intents that cannot be proven.
     * @param _prover The prover against which this intent will be checked
     * @return results The results of the calls as an array of bytes
     */

    function fulfillHyperBatched(
        uint256 _sourceChainID,
        address[] calldata _targets,
        bytes[] calldata _data,
        uint256 _expiryTime,
        bytes32 _nonce,
        address _claimant,
        bytes32 _expectedHash,
        address _prover
    ) external returns (bytes[] memory);

    /**
     * Sends a batch of intents to the hyperprover in a single message.
     * All intents should be between the same source and destination chains and should be proven against the same hyperprover.
     * @param _sourceChainID The chainID of the source chain
     * @param _prover The prover against which these intents will be proven. Should be the same for all intents in a given batch
     * @param _intentHashes The array of intent hashes to be proven
     */
    function sendBatch(uint256 _sourceChainID, address _prover, bytes32[] calldata _intentHashes) external payable;

    function fetchFee(uint256 _sourceChainID, bytes memory _messageBody, bytes32 _prover) external view returns (uint256 fee);
}
