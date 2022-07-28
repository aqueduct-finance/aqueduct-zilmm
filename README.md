# Aqueduct V1

Superfluid native stream-only dex.

## To deploy PoolFactory and initialize a pool:

1. Run the `deploy.js` script that deploys `PoolFactory.sol`
2. Deploy two new Aqueduct Tokens and initialize them. You can use the `initializeTokens.js` script to do this.
3. Run the `initPool.js` script and pass in the addresses of the pool factory and upgraded custom super tokens

You should be able to run the following scripts in this order to achieve the above steps:

```bash
npx hardhat run scripts/deploy.js --network goerli
npx hardhat run scripts/demo-scripts/initializeTokens.js --network goerli
npx hardhat run scripts/initPool.js --network goerli
```

## To test locally:

1. Run `npm install`
1. Add a .env file with `GOERLI_ALCHEMY_KEY` and `PRIVATE_KEY` variables
1. Update `testWalletAddress` in testSuperApp.js to your wallet address
1. Run `npx hardhat test`
