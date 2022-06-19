# realtime-dex-poc
## Description
This contract is a Super App that currently represents a fDAIx / MATICx pool.

## To test:
1) Add a .env file with ```ALCHEMY_KEY``` and ```PRIVATE_KEY``` variables (alchemy key should be for mumbai)
2) Deploy using ```npx hardhat run --network mumbai scripts/deploy.js```
3) Manually transfer fDAIx and/or MATICx to the deployed contract
4) From the SF dashboard, either stream in fDAIx or MATICx
5) You should see the opposite token being immediately streamed back into your account
