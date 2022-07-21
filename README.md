# Aqueduct V1

Superfluid native stream-only dex.

## To test locally:

1. Run `npm install`
1. Add a .env file with `GOERLI_ALCHEMY_KEY` and `PRIVATE_KEY` variables
2. Update `testWalletAddress` in testSuperApp.js to your wallet address
3. Run `npx hardhat test`

To run the demo scripts:

```bash
npx hardhat run scripts/demo-scripts/initializeTokens.js --network rinkeby
npx hardhat run scripts/demo-scripts/upgradeTokens.js --network rinkeby
npx hardhat run scripts/demo-scripts/addLiquidity.js --network rinkeby
```
