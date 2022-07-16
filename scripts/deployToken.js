const hre = require("hardhat");
require("dotenv").config();

const SUPERFLUID_HOST = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9'; // rinkeby "0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6";
const AQUEDUCT_HOST = "0x33E5dCa68c3597F3c6aCb00df61E44d0259DB5fF";
const DAI_ADDRESS = '0x88271d333C72e51516B67f5567c728E702b3eeE8'; // rinkeby: "0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735";
const USDC_ADDRESS = '0xc94dd466416A7dFE166aB2cF916D3875C049EBB7';

const main = async () => {
    const AqueductToken = await hre.ethers.getContractFactory("AqueductToken");
    const aqueductToken = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
    await aqueductToken.deployed();

    console.log("AqueductToken deployed to:", aqueductToken.address);

    await aqueductToken.initialize(DAI_ADDRESS, 18, "Aqueduct DAI Token", "fDAIxp");
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
