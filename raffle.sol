//SPDX-License-Identifier: GPL-3.0
 
pragma solidity >=0.5.0 <0.9.0;
 
contract Raffle {
    uint public entranceFee;
    uint adminFee; // 10% fee

    address payable[100] players; // max players;
    address payable admin;
    address genesis = 0x0000000000000000000000000000000000000000;

    uint public pricePool;

    event ReadyToDrawRaffle(uint indexed numPlayers, uint pricePool);
    event RaffleWinner(address indexed winner, uint winnings);
    event NewPlayer(address indexed player, uint[] indexed slotsTaken, uint indexed totalActivePlayers);

    constructor() {
        entranceFee = 600000000000000;
        adminFee = entranceFee / 10;
        admin = payable(msg.sender);
    }

    function playerSelectMultipleSlots(uint[] memory indexes) external payable returns(bool success) {
        require(msg.value == entranceFee * indexes.length, "Please input the exact amount to proceed");
        
        for (uint i; i<indexes.length; i++) {
            uint current = indexes[i];
            require(current <= players.length - 1, "Not within allowed slot numbers");
            require(players[current] == genesis, "Slot taken");
            players[current] = payable(msg.sender);
        }
        
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

    function playerForceDrawRaffle() external payable {
        uint feesRequired = exactFeeRequiredToClose();
        require(msg.value >= feesRequired, "Not enough fees");
        
        drawRaffle();
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

    modifier isAdmin() {
        require(msg.sender == admin, "admin access required");
        _;
    }

    function getContractBalance() private view returns(uint) {
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

    function getPlayersArray() external view isAdmin returns(address[] memory){
        address[] memory playersArray = new address[](players.length);
        for (uint i; i < players.length; i++) {
            playersArray[i] = players[i];
        }
        return playersArray;
    }

}
