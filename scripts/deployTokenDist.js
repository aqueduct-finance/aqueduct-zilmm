const hre = require("hardhat");
require("dotenv").config();

const SUPERFLUID_HOST = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';
const SUPER_TOKEN_ADDRESS_0 = "0xB133415Ae49150bCd8cDB7f515c30EbA2b42F2fe"; // fDAIxp
const SUPER_TOKEN_ADDRESS_1 = "0x3a36cD6D55e260E0a3448cd8905c51517bb7EbA8"; // fUSDCxp
const DIST_DISCRETE_AMOUNT = '100000000000000000000'; // == 100
const DIST_FLOW_RATE = '500000000000000'; // == 0.0005/s == ~16,000/year

const main = async () => {
    const TokenDist = await hre.ethers.getContractFactory("fTokenDistributor");
    const tokenDist = await TokenDist.deploy(SUPERFLUID_HOST, SUPER_TOKEN_ADDRESS_0, SUPER_TOKEN_ADDRESS_1, DIST_DISCRETE_AMOUNT, DIST_FLOW_RATE);
    await tokenDist.deployed();

    console.log("fTokenDistributor deployed to:", tokenDist.address);
};

const runMain = async () => {
    try {
        await main();
        process.exit(0);
    } catch (error) {
        console.log("An error has occurred: ", error);
        process.exit(1);
    }
};

runMain();
