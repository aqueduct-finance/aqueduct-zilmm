const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
);

const SUPERFLUID_HOST = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9";
const FDAI_ADDRESS = "0x88271d333C72e51516B67f5567c728E702b3eeE8";
const TEST_WALLET_ADDRESS = "0x91AdDB0E8443C83bAf2aDa6B8157B38f814F0bcC";

describe("PoolFactory", () => {
    let poolFactory;
    let token0;
    let token1;
    let testWalletSigner;

    before(async () => {
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy(SUPERFLUID_HOST);
        await poolFactory.deployed();

        const AqueductToken = await ethers.getContractFactory("AqueductToken");

        token0 = await AqueductToken.deploy(
            SUPERFLUID_HOST,
            poolFactory.address
        );
        await token0.deployed();
        await token0.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 0", "AQUA0");

        token1 = await AqueductToken.deploy(
            SUPERFLUID_HOST,
            poolFactory.address
        );
        await token1.deployed();
        await token1.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 1", "AQUA1");

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TEST_WALLET_ADDRESS],
        });
        testWalletSigner = await ethers.getSigner(TEST_WALLET_ADDRESS);
    });

    it("Deploys new pool and upgrades user tokens", async () => {
        const pool = await poolFactory.createPool(
            token0.address,
            token1.address,
            0,
            0,
            {
                gasLimit: 10000000,
            }
        );
        await pool.wait();
        console.log("Pool deployed to: ", pool.to);
    });

    it("Upgrades tokens", async () => {
        const daiContract = await ethers.getContractAt(
            IERC20.abi,
            FDAI_ADDRESS
        );

        const balance = await daiContract.balanceOf(TEST_WALLET_ADDRESS);
        console.log("dai balance : ", balance);

        let amnt = "100000000000000000000"; // 100
        await daiContract
            .connect(testWalletSigner)
            .approve(token0.address, amnt);
        await token0.connect(testWalletSigner).upgrade(amnt);
        await daiContract
            .connect(testWalletSigner)
            .approve(token1.address, amnt);
        await token1.connect(testWalletSigner).upgrade(amnt);

        // TODO: cannot assert against the balance of token0 until a stream into a pool has been created, due to our realTimeBalanceOf function in PoolFactory.sol
        // const token0Balance = await token0
        //     .connect(testWalletSigner)
        //     .balanceOf(TEST_WALLET_ADDRESS);
        // console.log(token0Balance);

        const newBalance = await daiContract.balanceOf(TEST_WALLET_ADDRESS);
        console.log("new dai balance : ", newBalance);
    });
});
