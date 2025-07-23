// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A simple Raffle contract
 * @author xunLin8
 * @notice This contract is a simple raffle system where users can enter the raffle and a winner is selected randomly.
 * @dev Implements Chainlink VRFv2.5
 * VRF -> Verifiable Randomness Function
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /** Errors */
    error Raffle__SendMoreToEnterRaffle(); // the prefix__ is present to give context for where the revert is coming from
    error Raffle__NotCompleted(); // error for when the raffle is not completed, i.e. the time interval has not passed
    error Raffle__TransferFailed(); // error for when the transfer of prizemoney fails
    error Raffle__NotOpen(); // error for when the raffle is not open to enter
    error Raffle__UpkeepNotNeeded(uint256 balance, uint playersLength, uint256 raffleState);

    /** Type Declarations */
    // enum is a user-defined type that consists of a set of named values
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    } // each one of these values get mapped to uint256 values

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // number of confirmations before the random number is considered valid
    uint32 private constant NUM_WORDS = 1; // number of random words to request

    uint256 private immutable i_entranceFee; // entrance fee to enter the raffle in wei (1 ETH = 10^18 wei)
    uint256 private immutable i_interval; // interval between raffle draws/duration of the lottery in seconds
    bytes32 private immutable i_keyHash; // the key hash for the Chainlink VRF is the gas I'm willing to pay for the random number
    uint256 private immutable i_subscriptionId; // subscription ID for Chainlink VRF
    uint32 private immutable i_callbackGasLimit; // gas limit for the callback function

    address payable[] private s_players;
    uint256 private s_lastTimeStamp; // last time the raffle was drawn
    address private s_recentWinner; // the most recent winner of the raffle
    RaffleState private s_raffleState; // state of the raffle // should start as OPEN => 0, and then change to CALCULATING => 1 when the winner is being calculated/picked

    /** Events */
    // 1. Makes migration easier
    // 2. Makes front end "indexing" easier
    event RaffleEntered(address indexed player); // indexed is a keyword that allows us to filter the event by the address of the player
    event WinnerPicked(address indexed winner); // event for when a winner is picked
    event RequestRaffleWinner(uint256 indexed requestId); // event for when a request for a random number is made, indexed allows us to filter the event by the request ID

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane, uint256 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee; // set the entrance fee to the one passed in
        i_interval = interval; // set the interval to the one passed in
        i_keyHash = gasLane; // set the key hash to the one passed in, this is the gas lane for the Chainlink VRF
        i_subscriptionId = subscriptionId; // set the subscription ID to the one passed in
        i_callbackGasLimit = callbackGasLimit; // set the callback gas limit to the one passed in

        s_lastTimeStamp = block.timestamp; // set the last time stamp to the current block timestamp
        s_raffleState = RaffleState.OPEN; // set the default raffle state to open
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent!");
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle()); // newest version but not as gas efficient as the conditional
        if (msg.value < i_entranceFee) {
            // most gas efficient
            revert Raffle__SendMoreToEnterRaffle(); // A custom error is used to replace the gas-costly string, it results in gas efficiency cause it doesn't deal with the costly string value
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen(); // revert the transaction if the raffle is not open, i.e. the raffle is calculating a winner
        }

        s_players.push(payable(msg.sender)); // add the player to the players array, we use payable here because we want to be able to send ETH to the player when they win, 
        // msg.sender is the address of the player who is entering the raffle

        // anytime we update the storage, make sure to emit an event, to let the application/frontend know that something has occurred
        emit RaffleEntered(msg.sender); // emit the event when a player enters the raffle
    }

    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH (has players)
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded /* in-param initialisation defaults to false */, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval; // check if the time interval has passed
        bool isOpen = (s_raffleState == RaffleState.OPEN); // check if the raffle is open
        bool hasPlayers = (s_players.length > 0); // check if there are players in the raffle
        bool hasBalance = (address(this).balance > 0); // check if the contract has a balance

        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers); // return true if all conditions are met
        // upkeepNeeded is true if all the conditions are met, otherwise it is false
        return (upkeepNeeded, ""); // return the upkeepNeeded bool result and an empty bytes array for performData
    }

    // 1. Pick a random winner
    // 2. Use random number to pick a player
    // 3. Be automatically called
    function performUpkeep( bytes calldata /* performData */) external {
        // block.timestamp is a global variable that returns the current block timestamp

        // if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //     // check if the interval has passed
        //     revert Raffle__NotCompleted();
        // }
        (bool upkeepNeeded, ) = checkUpkeep(""); // call the checkUpKeep function to see if upkeep is needed        // whenever we use a variable inside a function it can never be calldata, cause anything generated from a smart contract is never calldata, calldata can only be generated from the user's transactions
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState)); // revert the transaction if upkeep is not needed // we pass the balance of the contract, the number of players and the raffle state to the error for debugging purposes
        }

        s_raffleState = RaffleState.CALCULATING; // set the raffle state to calculating, so people can't enter the raffle while the winner is being calculated

        // Getting a Random number for Chainlink VRF is a two step process
        // 1. Request a random number
        // 2. Receive/Get the random number from the Chainlink callback function
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false})) // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
        });

        uint256 requestID = s_vrfCoordinator.requestRandomWords(request);
    
        // this emit is actually redundant because the s_vrfCoordinator.requestRandomWords function already emits an event in VRFConsumerBaseV2Plus, but we are keeping it for consistency
        emit RequestRaffleWinner(requestID); // emit the event when a request for a random number is made, this will be used to track the request ID in the frontend
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // Checks: require, conditionals
        
        // Effects (Internal contract State Updates)
        uint256 indexOfWinner = randomWords[0] % s_players.length; // get the index of the winner
        address payable recentWinner = s_players[indexOfWinner]; // get the address of the winner
        s_recentWinner = recentWinner; // set the recent winner to the winner
        
        s_raffleState = RaffleState.OPEN; // set the raffle state back to open for the next raffle
        s_players = new address payable[](0); // reset the players array to an empty array for the next raffle
        s_lastTimeStamp = block.timestamp; // set the last time stamp to the current block timestamp for the next raffle
        
        emit WinnerPicked(s_recentWinner); // emit the event when a winner is picked // emit the event with the recent winner's address

        // Interactions (External Contract Interactions)
        // Solidity uses parentheses () for tuple assignment.
        (bool success,) = recentWinner.call{value: address(this).balance}(""); // send the balance of the entire contract to the winner
        if(!success) {
            revert Raffle__TransferFailed(); // revert the transaction if the transfer fails
        }

    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
