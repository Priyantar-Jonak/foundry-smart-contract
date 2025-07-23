// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console} from "forge-std/console.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    // Could have accessed these values from the helperConfig using config.entranceFee, config.interval, etc. , but just pasted here to make it simpler
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE= 10 ether;

    event RaffleEntered(address indexed player); // indexed is a keyword that allows us to filter the event by the address of the player
    event WinnerPicked(address indexed winner); // event for when a winner is picked
    
    modifier raffleEntered() { // This modifier will be used to arrange the raffle state before acting and asserting that require a player to have entered the raffle
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); // player enters the raffle
        vm.warp(block.timestamp + interval + 1); // 1 => 1 day // warp the time to simulate the passage of time // sets block.timestamp to whatever we want it to be
        vm.roll(block.number + 1); // roll the block number to simulate a new block
        _;
    }

    function setUp() external { // This function will run before each test
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializeInOpenState() public view { // This test will check if the raffle is initialized in the OPEN state
        // assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // more readable
    }

    // Enter Raffle Tests
    function testEnterRaffleRevertsWhenNotEnoughEth() public { // This test will check if the enterRaffle function reverts when a player tries to enter with less than the entrance fee
        // Arrage
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle(); // less than entrance fee
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public { // This test will check if the raffle records the player when they enter
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public { // This test will check if the enterRaffle function emits an event when a player enters the raffle
        // Arrange
        vm.prank(PLAYER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public raffleEntered { // This test will check if players are not allowed to enter the raffle while it is calculating the winner
        // Arrange // modifier raffleEntered will take care of this

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotOpen.selector); // expect revert when trying to enter while raffle is not open
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }


    // CheckUpkeep Tests
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public { // This test will check if the checkUpkeep function returns false when the raffle has no balance
        // Arrange
        vm.warp(block.timestamp + interval + 1); // 1 => 1 day // warp the time to simulate the passage of time // sets block.timestamp to whatever we want it to be
        vm.roll(block.number + 1); // roll the block number to simulate a new block
    
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }
        
    function testCheckUpKeepReturnsFalseIfRaffleIsClosed() public raffleEntered { // This test will check if the checkUpkeep function returns false when the raffle is closed
        // Arrange // modifier raffleEntered will take care of this

        // Act
        raffle.performUpkeep(""); // perform upkeep to calculate the winner

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    
    // PerformUpkeep Tests
    function testUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEntered { // This test will check if the performUpkeep function can only run if checkUpkeep is true
        // Arrange // modifier raffleEntered will take care of this

        // Act / Assert
        raffle.performUpkeep(""); // perform upkeep to calculate the winner
        
        // there is a better way to test this, with
        /**
        ```
        (bool success, ) = raffle.call(abi.encodeWithSignature("performUpkeep(bytes)", ""));
        assert(success);
        ```
        */
        // but for now, we will just assume that if it doesn't revert, it works
        
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public { // This test will check if the performUpkeep function reverts when checkUpkeep is false
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); // player enters the raffle
        currentBalance += entranceFee; // current balance of the raffle
        numPlayers = 1; // number of players in the raffle

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleState)
        ); // expect revert when trying to perform upkeep when checkUpkeep is false
        raffle.performUpkeep(""); // perform upkeep to calculate the winner
    }

    // What if we need to get data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered { // This test will check if the performUpkeep function updates the raffle state and emits a requestId
        // Arrange // modifier raffleEntered will take care of this
        
        // Act
        vm.recordLogs(); // start recording logs
        raffle.performUpkeep(""); // perform upkeep to calculate the winner
        Vm.Log[] memory entries = vm.getRecordedLogs(); // get the recorded logs
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the first log entry which stores something useful in this regard

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0); // requestId should be greater than 0
        assert(uint256(raffleState) == 1); // raffle state should be CALCULATING
    }

    // FulfillRandomWords Tests

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered { // This test will check if the fulfillRandomWords function can only be called after performUpkeep for each requestId by fuzzing the randomRequestId
        // This is a stateless fuzz test // the meaning will be discovered later in the stablecoins or security/auditing course
        // Arrange // modifier raffleEntered will take care of this

        // Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector); // expect revert when trying to fulfill random words before perform upkeep
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId, // this is a random request id that we are passing to the function, to ensure fuzz testing
            address(raffle) // address of the raffle contract
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered { // This test will check if the fulfillRandomWords function picks a winner, resets the raffle and sends money to the winner
        // Arrange // modifier raffleEntered will take care of a part of this 
        uint256 additionalEntrants = 3; // total 4
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether); // sets balance + next tx comes from newPlayer
            raffle.enterRaffle{value: entranceFee}(); // now properly from newPlayer
            
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp(); 
        uint256 winnerStartingBalance = expectedWinner.balance; // this will be the balance of the winner before the raffle is fulfilled 

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle)); // get the random number(s) from thhe requestId(s) we have recorded
        
        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1); // total number of players is additionalEntrants + 1 (the player that entered in the setup function)

        assert(recentWinner == expectedWinner); // the winner should be the expected winner
        assert(uint256(raffleState) == 0); // the raffle state should be OPEN
        assert(winnerBalance == winnerStartingBalance + prize); // the winner's balance should be equal to their starting balance plus the prize
        assert(endingTimeStamp > startingTimeStamp); // the ending timestamp should be greater than the starting timestamp
    }
}