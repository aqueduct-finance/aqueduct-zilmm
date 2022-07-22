const hre = require("hardhat");
const fs = require("fs");

const SUPERFLUID_HOST = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9";

const main = async () => {
    const PoolFactory = await hre.ethers.getContractFactory("PoolFactory");
    const poolFactory = await PoolFactory.deploy(SUPERFLUID_HOST);
    await poolFactory.deployed();

    fs.writeFileSync(
        "poolFactoryAddress.js",
        `exports.poolFactoryAddress = "${poolFactory.address}"`
    );

    console.log("PoolFactory deployed to:", poolFactory.address);
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
