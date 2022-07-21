# Aqueduct V1

Superfluid native stream-only dex.

## To deploy PoolFactory and initialize a pool:

1. Run the `deploy.js` script that deploys `PoolFactory.sol`
2. Upgrade two tokens into our custom super tokens
3. Run the `initPool.js` script and pass in the addresses of the upgraded custom super tokens

## To test locally:

1. Run `npm install`
1. Add a .env file with `GOERLI_ALCHEMY_KEY` and `PRIVATE_KEY` variables
1. Update `testWalletAddress` in testSuperApp.js to your wallet address
1. Run `npx hardhat test`

To run the demo scripts:

```bash
npx hardhat run scripts/demo-scripts/initializeTokens.js --network rinkeby
npx hardhat run scripts/demo-scripts/upgradeTokens.js --network rinkeby
npx hardhat run scripts/demo-scripts/addLiquidity.js --network rinkeby
```
