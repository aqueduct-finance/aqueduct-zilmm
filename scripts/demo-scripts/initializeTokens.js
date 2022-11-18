require("dotenv").config();
const { ethers } = require("hardhat");
const fs = require("fs");

const SUPERFLUID_HOST = "0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6";
const AQUEDUCT_HOST = "0x36858E815F9B495fF19e65cB9b9614Ec263f5A4B";
const FDAI_ADDRESS = "0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7";

const main = async () => {
    // DEPLOY SUPER APP
    const Pool = await ethers.getContractFactory("Pool");
    const pool = await Pool.deploy(SUPERFLUID_HOST);
    await pool.deployed();
    fs.writeFileSync(
        "superAppAddress.js",
        `exports.superAppAddress = "${pool.address}"`
    );
    console.log("Pool deployed to:", pool.address);

    // DEPLOY TOKENS
    const AqueductToken = await ethers.getContractFactory("AqueductToken");

    const token0 = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
    await token0.deployed();
    fs.writeFileSync(
        "token0Address.js",
        `exports.token0Address = "${token0.address}"`
    );
    console.log("token0 deployed to:", token0.address);

    const token1 = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
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
