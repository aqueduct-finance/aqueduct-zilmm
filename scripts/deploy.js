const hre = require("hardhat");

const superfluidHost = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9"; // rinkeby: '0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6'; //mumbai: '0xEB796bdb90fFA0f28255275e16936D25d3418603';
//const uniswapFactory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
// const maticx = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';
//const fDAIx = '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';

const main = async () => {
    const PoolFactory = await hre.ethers.getContractFactory("PoolFactory");
    const poolFactory = await PoolFactory.deploy(superfluidHost);
    await poolFactory.deployed();

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
