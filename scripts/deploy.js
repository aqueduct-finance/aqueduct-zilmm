const hre = require("hardhat");

const host = '0xEB796bdb90fFA0f28255275e16936D25d3418603';
// const maticx = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';
//const fDAIx = '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';

const main = async () => {
  const SuperApp = await hre.ethers.getContractFactory("SuperApp");
  const superApp = await SuperApp.deploy(host);
  await superApp.deployed();

  console.log("SuperApp deployed to:", superApp.address);
}

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log('Error deploying contract', error);
    process.exit(1);
  }
}

runMain();
