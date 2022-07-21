const hre = require("hardhat");

const PoolFactory = "0x7c2910bdE2E295789e52B0A574c37fe42Afcab70";
const token0 = "0x1F664c1457B11e7B79f7dbC1ca4dDd1c36efe286";
const token1 = "0xE16504503EB7A5dAfE2101a47c8402d757D6352D";

const main = async () => {
    const poolFactory = await hre.ethers.getContractAt(
        "PoolFactory",
        PoolFactory
    );

    console.log("Pool factory address: ", poolFactory.address);

    const pool = await poolFactory.createPool(token0, token1, 0, 0, {
        gasLimit: 1000000,
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
