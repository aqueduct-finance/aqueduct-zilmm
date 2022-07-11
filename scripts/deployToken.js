const hre = require("hardhat");
require("dotenv").config();

const SUPERFLUID_HOST = "0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6";
const AQUEDUCT_HOST = "0x36858E815F9B495fF19e65cB9b9614Ec263f5A4B";
const DAI_ADDRESS = "0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735";

const main = async () => {
    const AqueductToken = await hre.ethers.getContractFactory("AqueductToken");
    const aqueductToken = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
    await aqueductToken.deployed();

    console.log("AqueductToken deployed to:", aqueductToken.address);

    await aqueductToken.initialize(DAI_ADDRESS, 18, "Aqueduct Token", "AQUA");
    console.log("AqueductToken initialized");

    const message = await aqueductToken.readMessage();
    console.log("Message: ", message);
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
