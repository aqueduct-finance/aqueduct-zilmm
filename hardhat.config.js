require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-truffle5');
require("dotenv").config();

module.exports = {
  solidity: "0.8.13",
  networks: {
    mumbai: {
      url: process.env.ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};