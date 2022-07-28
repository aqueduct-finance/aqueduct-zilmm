const hre = require("hardhat");

const { poolFactoryAddress } = require("./../poolFactoryAddress.js");
const { token0Address } = require("./../token0Address.js");
const { token1Address } = require("./../token1Address.js");

const main = async () => {
    const poolFactory = await hre.ethers.getContractAt(
        "PoolFactory",
        poolFactoryAddress
    );

    console.log("Pool factory address: ", poolFactory.address);

    const pool = await poolFactory.createPool(
        token0Address,
        token1Address,
        0,
        0,
        {
            gasLimit: 2000000,
        }
    );
    await pool.wait();
    console.log("Pool deployed to: ", pool.to);
};

const runMain = async () => {
    try {
        await main();
        process.exit(0);
    } catch (error) {
        console.log("Error deploying contract", error);
        process.exit(1);
    }
};

runMain();
