/*const { expect } = require("chai");
const { ethers } = require("hardhat");

// Pre-requisites
// - Tests against mainnet POLYGON using forking using TEST_ADDRESS
// - TEST_ADDRESS wallet needs some aqueductToken
// - TEST_ADDRESS wallet should not have any SuperToken

// Polygon addresses
const SUPERFLUID_HOST = "0x3E14dC1b13c488a8d5D310918780c983bD5982E7";
const DAI_ADDRESS = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";
const TEST_ADDRESS = "0x3226C9EaC0379F04Ba2b1E1e1fcD52ac26309aeA";

describe("AqueductToken", () => {
    let aqueductToken;
    let owner;
    let dai;

    before(async () => {
        const AqueductToken = await ethers.getContractFactory("AqueductToken");
        aqueductToken = await AqueductToken.deploy(SUPERFLUID_HOST);
        await aqueductToken.deployed();

        await aqueductToken.initialize(
            DAI_ADDRESS,
            18,
            "Aqueduct Token",
            "AQUA"
        );

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TEST_ADDRESS],
        });
        owner = await ethers.getSigner(TEST_ADDRESS);

        dai = await ethers.getContractAt(
            "contracts/IERC20.sol:IERC20",
            DAI_ADDRESS
        );
    });

    it("Upgrades holder of DAI tokens to AqueductToken", async () => {
        const testUserDAIBalance = (
            await dai.balanceOf(owner.address)
        ).toString();

        await dai
            .connect(owner)
            .approve(aqueductToken.address, testUserDAIBalance);

        aqueductToken = await aqueductToken.connect(owner);
        await aqueductToken.upgrade(testUserDAIBalance, {
            gasLimit: 1000000,
        });

        expect(await aqueductToken.balanceOf(owner.address)).to.equal(
            testUserDAIBalance
        );
    });
});
*/