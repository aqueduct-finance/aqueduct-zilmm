const hre = require("hardhat");

const superfluidHost = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';

const main = async () => {
  const Pool = await hre.ethers.getContractFactory("Pool");
  const pool = await Pool.deploy(superfluidHost);
  await pool.deployed();

  console.log("Pool deployed to:", pool.address);
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
