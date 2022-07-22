const hre = require("hardhat");

const POOL_FACTORY = "0x7c2910bdE2E295789e52B0A574c37fe42Afcab70";
const { token0Address } = require("./../token0Address.js");
const { token1Address } = require("./../token1Address.js");

const main = async () => {
    const poolFactory = await hre.ethers.getContractAt(
        "PoolFactory",
        POOL_FACTORY
    );

    console.log("Pool factory address: ", poolFactory.address);

    const pool = await poolFactory.createPool(
        token0Address,
        token1Address,
        0,
        0,
        {
            gasLimit: 1000000,
        }
    );
    await pool.wait();
    console.log("Pool deployed to: ", pool);
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
