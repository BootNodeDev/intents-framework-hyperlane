/* -*- c-basic-offset: 4 -*- */
// SPDX-License-hash: MIT
pragma solidity 0.8.25;

struct Intent {
    // creator of the intent
    address creator;
    // ID of chain where we want instructions executed
    uint256 destinationChainID;
    // address on destinationChain where we want instructions executed
    address[] targets;
    // instructions we want executed
    bytes[] data;
    // addresses of reward tokens
    address[] rewardTokens;
    // corresponding amounts of reward tokens
    uint256[] rewardAmounts;
    // intent expiry timestamp
    uint256 expiryTime;
    // true if it has been withdrawn already
    bool hasBeenWithdrawn;
    // hash of counter, chainid
    bytes32 nonce;
    // address of the prover this intent will be checked against
    address prover;
}

/**
 * This contract is the source chain portion of the Eco Protocol's intent system.
 *
 * It can be used to create intents as well as withdraw the associated rewards.
 * Its counterpart is the inbox contract that lives on the destination chain.
 * This contract makes a call to the prover contract (on the source chain) in order to verify intent fulfillment.
 */
interface IIntentSource {
    /**
     * @notice emitted on a call to withdraw() by someone who is not entitled to the rewards for a
     * given intent.
     * @param _hash the hash of the intent, also the key to the intents mapping
     */
    error UnauthorizedWithdrawal(bytes32 _hash);

    /**
     * @notice emitted on a call to withdraw() for an intent whose rewards have already been withdrawn.
     * @param _hash the hash of the intent on which withdraw was attempted
     */
    error NothingToWithdraw(bytes32 _hash);

    /**
     * @notice emitted on a call to createIntent where _expiry is less than MINIMUM_DURATION
     * seconds later than the block timestamp at time of call
     */
    error ExpiryTooSoon();

    /**
     * @notice emitted on a call to createIntent where _targets and _data have different lengths, or when one of their lengths is zero.
     */
    error CalldataMismatch();

    /**
     * @notice emitted on a call to createIntent where _rewardTokens and _rewardAmounts have different lengths, or when one of their lengths is zero.
     */
    error RewardsMismatch();

    /**
     * @notice emitted on a successful call to createIntent
     * @param _hash the hash of the intent, also the key to the intents mapping
     * @param _creator the address that created the intent
     * @param _destinationChain the destination chain
     * @param _targets the address on _destinationChain at which the instruction sets need to be executed
     * @param _data the instructions to be executed on _targets
     * @param _rewardTokens the addresses of reward tokens
     * @param _rewardAmounts the amounts of reward tokens
     * @param _expiryTime the time by which the storage proof must have been created in order for the solver to redeem rewards.
     * @param _prover the prover contract address for the intent
     */
    //only three of these attributes can be indexed, i chose what i thought would be the three most interesting to fillers
    event IntentCreated(
        bytes32 indexed _hash,
        address _creator,
        uint256 indexed _destinationChain,
        address[] _targets,
        bytes[] _data,
        address[] _rewardTokens,
        uint256[] _rewardAmounts,
        uint256 _expiryTime,
        bytes32 nonce,
        address indexed _prover
    );

    /**
     * @notice emitted on successful call to withdraw
     * @param _hash the hash of the intent on which withdraw was attempted
     * @param _recipient the address that received the rewards for this intent
     */
    event Withdrawal(bytes32 _hash, address indexed _recipient);

    /**
     * @notice Creates an intent to execute instructions on a contract on a supported chain in exchange for a bundle of assets.
     * @dev If a proof ON THE SOURCE CHAIN is not completed by the expiry time, the reward funds will not be redeemable by the solver, REGARDLESS OF WHETHER THE INSTRUCTIONS WERE EXECUTED.
     * The onus of that time management (i.e. how long it takes for data to post to L1, etc.) is on the intent solver.
     * @dev The inbox contract on the destination chain will be the msg.sender for the instructions that are executed.
     * @param _destinationChain the destination chain
     * @param _targets the addresses on _destinationChain at which the instruction sets need to be executed
     * @param _data the instructions to be executed on _targets
     * @param _rewardTokens the addresses of reward tokens
     * @param _rewardAmounts the amounts of reward tokens
     * @param _expiryTime the time by which the storage proof must have been created in order for the solver to redeem rewards.
     * @param _prover the prover against which the intent's status will be checked
     */
    function createIntent(
        uint256 _destinationChain,
        address _inbox,
        address[] calldata _targets,
        bytes[] calldata _data,
        address[] calldata _rewardTokens,
        uint256[] calldata _rewardAmounts,
        uint256 _expiryTime,
        address _prover
    ) external;

    /**
     * @notice allows withdrawal of reward funds locked up for a given intent
     * @param _hash the key corresponding to this intent in the intents mapping
     */
    function withdrawRewards(bytes32 _hash) external;

    /**
     * @notice fetches entire intent
     * @dev this is necessary since the default getter will not include reference fields
     * @param _hash the hash for the intent
     */
    function getIntent(bytes32 _hash) external view returns (Intent memory);
}
