const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
);

const SUPERFLUID_HOST = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9";
const AQUEDUCT_HOST = "0x03aF3a3A05A81089C8f2205f547e17c885AEe430";
const FDAI_ADDRESS = "0x88271d333C72e51516B67f5567c728E702b3eeE8";
const TEST_ADDRESS = "0xF918CB48A11AF9C740407843c2218D8e00E52875"; // address with fDAI which has NOT been upgraded

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

        token0 = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
        await token0.deployed();
        await token0.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 0", "AQUA0");

        token1 = await AqueductToken.deploy(SUPERFLUID_HOST, AQUEDUCT_HOST);
        await token1.deployed();
        await token1.initialize(FDAI_ADDRESS, 18, "Aqueduct Token 1", "AQUA1");

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TEST_ADDRESS],
        });
        testWalletSigner = await ethers.getSigner(TEST_ADDRESS);
    });

    it("Upgrades tokens and deploys new pool", async () => {
        const daiContract = await ethers.getContractAt(
            IERC20.abi,
            FDAI_ADDRESS
        );
        const fDAIBalance = await daiContract.balanceOf(
            testWalletSigner.address
        );
        console.log("fDAIBalance: ", fDAIBalance);
        let amnt = "100000000000000000000"; // 100 - this address is one of mine and holds 800 fDAI
        await daiContract
            .connect(testWalletSigner)
            .approve(token0.address, amnt);
        await token0.connect(testWalletSigner).upgrade(amnt);
        // TODO: reverting here
        expect(await token0.balanceOf(testWalletSigner.address)).to.equal(
            amountToUpgrade
        );

        await daiContract
            .connect(testWalletSigner)
            .approve(token1.address, amountToUpgrade);
        token1 = await token1.connect(testWalletSigner);
        await token1.upgrade(amountToUpgrade, {
            gasLimit: 1000000,
        });
        expect(await token1.balanceOf(testWalletSigner.address)).to.equal(
            amountToUpgrade
        );

        // TODO: deploy new pool
    });
});
