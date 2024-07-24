//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test {
    /* Events */
    event RaffleEnter(address indexed player);

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 25 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    Raffle raffle;
    HelperConfig helperConfig;
    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitialisedInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////////
    // enterRaffle      //
    //////////////////////

    function testRaffleRevertsWhenNotSentEnoughFund() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__InsufficientEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        assert(raffle.getPlayer(0) == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////////
    // checkUpKeep      //
    //////////////////////

    function testUpKeepIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);

        // vm.prank(PLAYER);
        // raffle.enterRaffle{value: entranceFee}();
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == false);
    }

    function testUpKeepIfRaffleIsNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == false);
    }

    function testUpKeepIfHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == false);
    }

    function testUpKeepIfAllParametersAreTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == true);
    }

    //////////////////////
    // performUpKeep    //
    //////////////////////

    function testPerformUpKeepIfUpKeepNeededIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
    }

    function testPerformUpKeepIfTestUpKeepIsFalse() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // uint256 currentBalance = address(raffle).balance;
        // uint256 numPlayers = raffle.getNumberOfPlayers();
        // Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.expectRevert();
        raffle.performUpkeep("");
    }

    //////////////////////
    // fulfillRandomWords/
    //////////////////////

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testperformUpKeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(rState == Raffle.RaffleState.CALCULATING);
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testfullFillRandomWordsCannotBeCalledBeforePerformUpKeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testfullFillRandomWordsPicksWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i <= additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        assert(uint256(raffle.getRaffleState()) == 0);

        assert(raffle.getRecentWinner() != address(0));

        assert(raffle.getNumberOfPlayers() == 0);

        assert(previousTimeStamp < raffle.getLastTimeStamp());

        console.log(raffle.getRecentWinner().balance);

        console.log(STARTING_USER_BALANCE + prize - entranceFee);
        assert(
            raffle.getRecentWinner().balance ==
                ((STARTING_USER_BALANCE - entranceFee) + prize)
        );
    }
}
