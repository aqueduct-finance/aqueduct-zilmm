require("dotenv").config();
const { ethers } = require("hardhat");
const { Framework } = require("@superfluid-finance/sdk-core");

const { superAppAddress } = require("./../../superAppAddress.js");
const { token0Address } = require("./../../token0Address.js");
const { token1Address } = require("./../../token1Address.js");

const main = async () => {
    const provider = ethers.provider;
    const signer = provider.getSigner();

    // GET CONTRACTS
    const superApp = await hre.ethers.getContractAt(
        "SuperApp",
        superAppAddress
    );
    const token0 = await hre.ethers.getContractAt(
        "AqueductToken",
        token0Address
    );
    const token1 = await hre.ethers.getContractAt(
        "TestToken", // The name of the fDAI token contract from etherscan
        token1Address
    );

    // INITIALIZE SUPERFLUID SDK
    const superfluid = await Framework.create({
        chainId: 4,
        provider: provider,
    });

    // const signer = superfluid.createSigner({
    //     privateKey: process.env.PRIVATE_KEY,
    //     provider: ethers.provider,
    // });

    // create flow of token0 into the Super App
    const DEV4 = "0x92C6D258907aF51F40DDE64E8476014B2dC8CAe9";
    const createFlowOperation = superfluid.cfaV1.createFlow({
        sender: DEV4, // TODO: Add my address and make sure it work
        receiver: superApp.address,
        superToken: token0.address,
        flowRate: "1000000000",
    });
    const txnResponse = await createFlowOperation.exec(signer);
    await txnResponse.wait();
    console.log("token0 stream created");

    // create flow of token1 into the Super App
    const DEV3 = "0xF918CB48A11AF9C740407843c2218D8e00E52875";
    const createFlowOperation2 = superfluid.cfaV1.createFlow({
        sender: DEV3, // TODO: Add another of my addresses and make sure it works
        receiver: superApp.address,
        superToken: token1.address,
        flowRate: "1000000000",
    });
    const txnResponse2 = await createFlowOperation2.exec(signer);
    await txnResponse2.wait();
    console.log("token1 stream created");
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
