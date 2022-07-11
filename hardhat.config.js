require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-truffle5');
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.14",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 100000000
  },
  networks: {
    mumbai: {
      url: process.env.ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
    rinkeby: {
      url: process.env.RINKEBY_ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};