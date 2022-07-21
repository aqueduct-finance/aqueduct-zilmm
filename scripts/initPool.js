const hre = require("hardhat");

const PoolFactory = "0x03aF3a3A05A81089C8f2205f547e17c885AEe430";
const token0 = "0x6130677802D32e430c72DbFdaf90d6d058137f0F";
const token1 = "0x9103E14E3AaF4E136BFe6AF1Bf2Aeff8fc5b99b9";

const main = async () => {
    const poolFactory = await hre.ethers.getContractAt(
        "PoolFactory",
        PoolFactory
    );

    console.log("Pool factory address: ", poolFactory.address);

    const pool = await poolFactory.createPool(token0, token1, 0, 0, {
        gasLimit: 500000,
    });
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
