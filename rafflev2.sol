//SPDX-License-Identifier: GPL-3.0
 
pragma solidity >=0.7.0 <0.9.0;
 
enum State {
    RUNNING,
    SUSPENDED,
    ABANDONED,
    COMPLETED
}

struct GameInterface {
    State state;
    address[] allPlayersAddress;
    uint[] allSlotsTaken;
    mapping( address => uint[]) playersWithSelectedSlots;
}

contract Raffle {
    uint public entranceFee;
    uint public pricePool;
    uint public gameId;

    uint maxSlots = 6;
    uint adminFee; 

    uint public dummy;
    uint public dummy2;

    address payable admin;
    address genesis = 0x0000000000000000000000000000000000000000;

    mapping(uint => GameInterface) Game;

    event ReadyToDrawRaffle(uint indexed _gameId, uint indexed numSlotsClosed, uint pricePool);
    event RaffleWinner(uint indexed _gameId, address indexed winner, uint winnings, uint winningDigit);
    event NewPlayer(uint indexed _gameId, address indexed player, uint[] slotsTaken);
    
    constructor() {
        entranceFee = 1000000000000000000;
        adminFee = entranceFee / 10; // 10% admin fee
        admin = payable(msg.sender);

        gameId = 1;
        Game[gameId].state = State.RUNNING;
    }

    /****************************** GAME LOGIC *******************************/

    modifier gameIsRunning {
        require(Game[gameId].state == State.RUNNING, "Game is suspended");
        _;
    }

    function playerSelectMultipleSlots(uint[] memory slots) external payable gameIsRunning returns(bool success) {
        GameInterface storage game = Game[gameId];
        uint[] storage selectedSlotsOfPlayer = game.playersWithSelectedSlots[msg.sender];
        uint[] storage slotsTaken = game.allSlotsTaken;

        require(msg.value == entranceFee * slots.length, "Please input the exact amount to proceed");
        require(slotsTaken.length < maxSlots, "All Slots taken");

        if (selectedSlotsOfPlayer.length == 0) {
            game.allPlayersAddress.push(msg.sender);
        }

        for (uint i; i<slots.length; i++) {
            require(slots[i] < maxSlots, "Pick slot less than max slot");
            if (slotsTaken.length != 0) {
                for (uint j;j<slotsTaken.length;j++) {
                    require(slots[i] != slotsTaken[j], "Slot taken");
                }
            }
            slotsTaken.push(slots[i]);
            selectedSlotsOfPlayer.push(slots[i]);
        }

        uint lessFees = (msg.value * (entranceFee - adminFee)) / entranceFee;
        pricePool += lessFees;
        
        emit NewPlayer(gameId, msg.sender, slots);

        if (slotsTaken.length == maxSlots) {
            emit ReadyToDrawRaffle(gameId, slotsTaken.length, pricePool);
        }

        success = true;
    }

    function drawRaffle() private {
        (uint winningDigit, uint[] memory allSlots) = generateWinningDigit();
        (uint totalClosedSlots,) = getSlotsClosed();
        require(totalClosedSlots > 0, "Minimum number of players not met");

        uint orig = winningDigit;
        
        dummy = orig;
        address payable winner;

        if (totalClosedSlots != maxSlots) {
            bool found = false;
            while (found == false) {
                for (uint i; i < totalClosedSlots; i++) {
                    if (winningDigit == allSlots[i]) {
                        found = true;
                        break;
                    }
                    continue;
                }

                if (found == false) {
                    (winningDigit,) = generateWinningDigit(); // reroll the winning digit if not found;
                    dummy2 = winningDigit;
                }
            }
        }

        winner = payable(findWinner(winningDigit));
        assert(winner != genesis);

        // uint adminsTF = getContractBalance() - pricePool; // for transparency sake
        // winner.transfer(pricePool);
        // admin.transfer(adminsTF);

        emit RaffleWinner(gameId, winner, pricePool, winningDigit);

        // reset(State.COMPLETED);
    }

    function playerForceDrawRaffle() external payable gameIsRunning {
        uint feesRequired = exactFeeRequiredToClose();
        require(msg.value >= feesRequired, "Not enough fees");
        
        drawRaffle();
    }

    /****************************** UTILS *******************************/

    function generateWinningDigit() public view returns(uint, uint[] memory) { // make private
        (uint slotsClosed,uint[] memory slots) = getSlotsClosed();
        bytes memory encodedBytes = abi.encodePacked(block.difficulty, block.timestamp, slotsClosed);
        return ((uint(keccak256(encodedBytes)) % (slotsClosed + 1)), slots); // temporary random func, need to add 1 to include last player
    }

    function getContractBalance() public view returns(uint) {
        return address(this).balance;
    }

    function findWinner(uint winningDigit) private view returns(address) {
        GameInterface storage game = Game[gameId];
        address[] memory players = game.allPlayersAddress;
        address winner;
        assert(players.length > 0);

        for (uint i;i<players.length;i++) {
            address currentPlayerIndex = players[i];
            for (uint j;j< game.playersWithSelectedSlots[currentPlayerIndex].length;j++) {
                if (winningDigit == game.playersWithSelectedSlots[currentPlayerIndex][j]) {
                    winner = players[i];
                    break;
                }
            }
        }

        require(winner != genesis, "Winner not found");
        return winner;
    }

    function getSlotsClosed() public view returns(uint, uint[] memory) {
        uint[] memory slotsClosed = Game[gameId].allSlotsTaken;
        return (slotsClosed.length, slotsClosed);
    }

    function exactFeeRequiredToClose() public view returns(uint) {
        (uint slotsClosed,) = getSlotsClosed();

        uint slotsOpen = maxSlots - slotsClosed;
        return slotsOpen * entranceFee;
    }

    function reset(State state) private {
        pricePool = 0;
        Game[gameId].state = state;
        gameId++;
    }

    /****************************** ADMIN SETTER FUNCTIONS *******************************/

    modifier isAdmin() {
        require(msg.sender == admin, "admin access required");
        _;
    }

    function adminForceDraw() external isAdmin {
        drawRaffle();
    }

    function adminUpdateEntranceFee(uint amount) external isAdmin {
        (uint slotsClosed,) = getSlotsClosed();
        require(slotsClosed == 0, "Some slots have been closed already");

        entranceFee = amount;
        adminFee = amount / 10;
    }

    function adminSuspendGame(bool restart) external isAdmin returns(bool success) {
        Game[gameId].state = State.SUSPENDED;

        if (restart) {
            reset(State.ABANDONED);
        }

        success = true;
    }

    function adminResumeGame() external isAdmin returns(bool success) {
        Game[gameId].state = State.RUNNING;
        success = true;
    }

    /****************************** ADMIN GETTER FUNCTIONS *******************************/

    function adminGetAllPlayersAddress(uint _gameId) external view isAdmin returns(address[] memory) {
        return Game[_gameId].allPlayersAddress;
    }

    function adminGetPlayerSlots(uint _gameId, address _player) external view isAdmin returns(uint[] memory) {
        return Game[_gameId].playersWithSelectedSlots[_player];
    }

}
