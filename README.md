# PH Raffle smart contract

- Players chooses a number from 1 - 100
- A player can choose multiple numbers
- A player can force draw the raffle but must send an amount equivalent to the total amount of open slots left
- When all slots are closed, an event is triggered for admin to draw the raffle, effectively selecting a random winner. 
- The admin gets a 10% fee from the total price pool
- Upon selecting the random winner, the raffle is reset