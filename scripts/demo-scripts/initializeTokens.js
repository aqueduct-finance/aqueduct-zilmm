require("dotenv").config();
const { ethers } = require("hardhat");
const fs = require("fs");

const SUPERFLUID_HOST = "0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6";
const { poolFactoryAddress } = require("../../poolFactoryAddress.js");
const FDAI_ADDRESS = "0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7";

const main = async () => {
    // DEPLOY TOKENS
    const AqueductToken = await ethers.getContractFactory("AqueductToken");

    const token0 = await AqueductToken.deploy(
        SUPERFLUID_HOST,
        poolFactoryAddress
    );
    await token0.deployed();
    fs.writeFileSync(
        "token0Address.js",
        `exports.token0Address = "${token0.address}"`
    );
    console.log("token0 deployed to:", token0.address);

    const token1 = await AqueductToken.deploy(
        SUPERFLUID_HOST,
        poolFactoryAddress
    );
    await token1.deployed();
    fs.writeFileSync(
        "token1Address.js",
        `exports.token1Address = "${token1.address}"`
    );
    console.log("token1 deployed to:", token1.address);

    // INITIALIZE TOKEN0
    await token0.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 0", "AQUA0");
    console.log("token0 initialized");

    // INITIALIZE TOKEN1
    await token1.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 1", "AQUA1");
    console.log("token1 initialized");
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
