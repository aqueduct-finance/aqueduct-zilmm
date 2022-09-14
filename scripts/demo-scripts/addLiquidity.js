require("dotenv").config();
const { ethers } = require("hardhat");
const { Framework } = require("@superfluid-finance/sdk-core");

const { superAppAddress } = require("./../../superAppAddress.js");
const { token0Address } = require("./../../token0Address.js");
const { token1Address } = require("./../../token1Address.js");

const LP_ADDRESS = "0x888D08001F91D0eEc2f16364779697462A9A713D"; // swap this for your own address

const main = async () => {
    // GET CONTRACTS
    const pool = await hre.ethers.getContractAt(
        "Pool",
        superAppAddress
    );
    const token0 = await hre.ethers.getContractAt(
        "AqueductToken",
        token0Address
    );
    const token1 = await hre.ethers.getContractAt(
        "AqueductToken",
        token1Address
    );

    // INITIALIZE SUPERFLUID SDK
    const provider = ethers.provider;
    const superfluid = await Framework.create({
        chainId: 4,
        provider: provider,
    });
    console.log("Superfluid initialized");

    const signer = superfluid.createSigner({
        privateKey: process.env.PRIVATE_KEY,
        provider: provider,
    });
    console.log("Signer: ", signer.address);

    // TODO: failing here - Error: cannot estimate gas; transaction may fail or may require manual gas limit
    // create flow of token0 into the Super App
    const createFlowOperation = superfluid.cfaV1.createFlow(
        {
            sender: LP_ADDRESS,
            receiver: pool.address,
            superToken: token0.address,
            flowRate: "1000000000",
        },
        { gasLimit: 500000 }
    );
    const txnResponse = await createFlowOperation.exec(signer, {
        gasLimit: 500000,
    });
    await txnResponse.wait();
    console.log("token0 stream created");

    // create flow of token1 into the Super App
    const createFlowOperation2 = superfluid.cfaV1.createFlow({
        sender: LP_ADDRESS,
        receiver: pool.address,
        superToken: token1.address,
        flowRate: "1000000000",
    });
    const txnResponse2 = await createFlowOperation2.exec(signer, {
        gasLimit: 500000,
    });
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
