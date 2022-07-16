const hre = require("hardhat");

const superfluidHost = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';

const main = async () => {
  const SuperApp = await hre.ethers.getContractFactory("SuperApp");
  const superApp = await SuperApp.deploy(superfluidHost);
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
