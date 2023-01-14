/**
 * 
 * Deploys an fDAI wrapper and fUSDC wrapper and creates pool all at once.
 * 
 * to run: npx hardhat run --network goerli scripts/deployAll.js
 * 
 */

const hre = require("hardhat");

const superfluidHost = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';
const fDAI = '0x88271d333C72e51516B67f5567c728E702b3eeE8';
const fUSDC = '0xc94dd466416A7dFE166aB2cF916D3875C049EBB7';

const delay = ms => new Promise(res => setTimeout(res, ms));

const main = async () => {
    const SuperApp = await hre.ethers.getContractFactory("Pool");
    const superApp = await SuperApp.deploy(superfluidHost);
    await superApp.deployed();

    console.log("Pool: ", superApp.address);

    await delay(60000);

    await hre.run("verify:verify", {
        address: superApp.address,
        constructorArguments: [superfluidHost],
    });

    // deploy tokens
    let Token = await hre.ethers.getContractFactory("AqueductToken");
    const token0 = await Token.deploy(superfluidHost, superApp.address);
    await token0.deployed();
    await token0.initialize(fDAI, 18, "Aqueduct fDAI", "fDAIxp");
    console.log("fDAIxp (token0): " + token0.address)

    await delay(60000);

    await hre.run("verify:verify", {
        address: token0.address,
        constructorArguments: [superfluidHost, superApp.address],
    });

    const token1 = await Token.deploy(superfluidHost, superApp.address);
    await token1.deployed();
    await token1.initialize(fUSDC, 18, "Aqueduct fUSDC", "fUSDCxp");
    console.log("fUSDCxp (token1): " + token1.address)

    await delay(60000);

    await hre.run("verify:verify", {
        address: token1.address,
        constructorArguments: [superfluidHost, superApp.address],
    });

    // init pool
    const poolFee = BigInt((2 ** 128) * 0.01); // 1% fee - multiply by 2^112 to conform to UQ112x112
    console.log("Fee: 1%")
    await superApp.initialize(token0.address, token1.address, poolFee);
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
