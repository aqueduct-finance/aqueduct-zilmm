const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
);

const SUPERFLUID_HOST = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9";
const FDAI_ADDRESS = "0x88271d333C72e51516B67f5567c728E702b3eeE8";

describe("PoolFactory", () => {
    let poolFactory;
    let token0;
    let token1;

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
    });

    it("Deploys new pool", async () => {
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
});
