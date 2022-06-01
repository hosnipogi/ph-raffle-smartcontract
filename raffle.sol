//SPDX-License-Identifier: GPL-3.0
 
pragma solidity >=0.7.0 <0.9.0;
 
enum State {
    ACTIVE,
    INACTIVE
}

struct allPlayersFromSpecificGame {
    address [] allAddress;
    mapping( address => uint[]) playersWithSlotsTaken;
}

contract Raffle {
    uint public entranceFee;
    uint adminFee; 

    address payable[6] players; // max players;
    address payable admin;
    address genesis = 0x0000000000000000000000000000000000000000;

    uint public pricePool;
    uint public amountToRefund;

    State public gameState;

    event ReadyToDrawRaffle(uint indexed numPlayers, uint pricePool);
    event RaffleWinner(address indexed winner, uint winnings);
    event NewPlayer(address indexed player, uint[] indexed slotsTaken, uint indexed totalActivePlayers);

    bytes32 public gameId;
    mapping(bytes32 => allPlayersFromSpecificGame) Game;

    constructor() {
        entranceFee = 1000000000000000000;
        adminFee = entranceFee / 10; // 10% admin fee
        admin = payable(msg.sender);
        gameState = State.ACTIVE;

        gameId = keccak256(abi.encodePacked(block.timestamp));
        Game[gameId];
    }

    /****************************** GAME LOGIC *******************************/

    modifier gameIsActive {
        require(gameState == State.ACTIVE, "Game is temporarily suspended");
        _;
    }

    function playerSelectMultipleSlots(uint[] memory indexes) external payable gameIsActive returns(bool success) {
        require(msg.value == entranceFee * indexes.length, "Please input the exact amount to proceed");
        
        for (uint i; i<indexes.length; i++) {
            uint current = indexes[i];
            require(current <= players.length - 1, "Not within allowed slot numbers");
            require(players[current] == genesis, "Slot taken");
            players[current] = payable(msg.sender);
        }
        
        // Game[gameId].allAddress.push(msg.sender);
        // uint[] storage arr = Game[gameId].playersWithSlotsTaken[msg.sender];
        // for(uint i; i<indexes.length; i++) {
        //     arr.push(indexes[i]);
        // }

        uint lessFees = (msg.value * (entranceFee - adminFee)) / entranceFee;
        pricePool += lessFees;
        
        (uint activePlayers,) = getNumPlayers();
        emit NewPlayer(msg.sender, indexes, activePlayers);

        if (players.length == activePlayers ) {
            emit ReadyToDrawRaffle(activePlayers, pricePool);
        }

        success = true;
    }

    function drawRaffle() private {
        (uint random, uint activePlayers, uint[] memory selectedSlots) = tempRandom();
        require(activePlayers > 0, "Minimum number of players not met");
        uint index = random % activePlayers;

        address payable winner;

        if (activePlayers != players.length) {
            uint pickFromSelectedSlotsOnly = selectedSlots[index];            
            winner =  players[pickFromSelectedSlotsOnly];
        } else {
            winner =  players[index];
        }

        uint adminsTF = getContractBalance() - pricePool; // for transparency sake
        winner.transfer(pricePool);
        admin.transfer(adminsTF);

        emit RaffleWinner(winner, pricePool);

        reset();
    }

    function playerForceDrawRaffle() external payable gameIsActive {
        uint feesRequired = exactFeeRequiredToClose();
        require(msg.value >= feesRequired, "Not enough fees");
        
        drawRaffle();
    }

    /****************************** UTILS *******************************/

    function tempRandom() private view returns(uint, uint, uint[] memory) {
        (uint activePlayers,uint[] memory selectedSlots) = getNumPlayers();
        bytes memory encodedBytes = abi.encodePacked(block.difficulty, block.timestamp, activePlayers);
        return (uint(keccak256(encodedBytes)), activePlayers, selectedSlots);
    }

    function getNumPlayers() public view returns(uint, uint[] memory) {
        uint activePlayers;
        uint[] memory slotsTaken = new uint[](players.length);

        for  (uint i; i<players.length; i++) {
            if (players[i] != genesis) {
                slotsTaken[activePlayers] = i;
                activePlayers++;
            }
        }

        uint[] memory allAvailSlotsOnly = new uint[](activePlayers);

        for (uint i; i<activePlayers; i++) {
            allAvailSlotsOnly[i] = slotsTaken[i];
        }

        return (activePlayers, allAvailSlotsOnly);
    }

    function exactFeeRequiredToClose() public view returns(uint) {
        (uint activePlayers,) = getNumPlayers();

        uint slotsOpen = players.length - activePlayers;
        return slotsOpen * entranceFee;
    }

    function reset() private {
        pricePool = 0;
        delete players;
    }

    /****************************** ADMIN FUNCTIONS *******************************/

    modifier isAdmin() {
        require(msg.sender == admin, "admin access required");
        _;
    }

    function getContractBalance() public view returns(uint) {
        return address(this).balance;
    }

    function adminForceDraw() external isAdmin {
        drawRaffle();
    }

    function adminUpdateEntranceFee(uint amount) external isAdmin {
        (uint activePlayers,) = getNumPlayers();
        require(activePlayers == 0, "Player slot not empty");

        entranceFee = amount;
        adminFee = amount / 10;
    }

    function adminGetPlayersArray() public view isAdmin returns(address[] memory) {
        address[] memory playersArray = new address[](players.length);
        for (uint i; i < players.length; i++) {
            playersArray[i] = players[i];
        }
        return playersArray;
    }

    function adminAbortAndRefund() payable public isAdmin returns(bool, uint) {
        (uint activePlayers,) = getNumPlayers();
        require(activePlayers > 0, "No players, aborting..");

        address[] memory activePlayersArray = adminGetPlayersArray();
        for (uint i; i < activePlayersArray.length; i++) {
            address currentAddress = activePlayersArray[i];

            if (currentAddress != genesis) {
                uint numEntries;
                for (uint j; j < activePlayersArray.length; j++) { // check for multiple entries of the same address
                    if (currentAddress == activePlayersArray[j]) {
                        numEntries++;
                    }
                }


                if (numEntries > 0) {
                    amountToRefund = entranceFee * numEntries;

                    require(getContractBalance() >= amountToRefund, "Not enough balance to refund");
                    adminSendTo(payable(currentAddress), amountToRefund);
                    // (bool success,) = currentAddress.call{
                    //     value: amountToRefund
                    // }("");

                    // require(success == true, "Error in sending");
                    // refunded += 1;
                }
            }
            
        }

        reset();
        // success = true;
        // refunded = 1;

        return (true, 1);
    }

    function adminSendTo(address payable _to, uint amount) private isAdmin returns(bool success) {
        _to.transfer(amount);
        success = true;
    }

    function adminSuspendGame(bool refundAndRestartGame) external isAdmin returns(bool, uint) {
        gameState = State.INACTIVE;

        if (refundAndRestartGame) {
            return adminAbortAndRefund();
        }

        return (true, 0);
    }

    function adminResumeGame() external isAdmin returns(bool success) {
        gameState = State.ACTIVE;
        success = true;
    }

}
