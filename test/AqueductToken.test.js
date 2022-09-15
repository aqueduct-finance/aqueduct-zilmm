const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AqueductToken", () => {
  let aqueductToken;
  let mockERC20;

  before(async () => {
    const superfluidHost = "0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9";
    Pool = await ethers.getContractFactory("Pool");
    pool = await Pool.deploy(superfluidHost);
    await pool.deployed();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy("MockERC20", "MOCK", 0);
    await mockERC20.deployed();

    const AqueductToken = await ethers.getContractFactory("AqueductToken");
    aqueductToken = await AqueductToken.deploy(superfluidHost, pool.address);
    await aqueductToken.deployed();
    await aqueductToken.initialize(
      mockERC20.address,
      18,
      "Aqueduct Token",
      "AQUA"
    );
  });

  it("Upgrades DAI to AqueductToken", async () => {
    const owner = (await ethers.getSigners())[0];
    mockERC20 = await mockERC20.connect(owner);
    await mockERC20.mint(owner.address, ethers.utils.parseEther("100"));

    const mockERC20Balance = (
      await mockERC20.balanceOf(owner.address)
    ).toString();

    await mockERC20
      .connect(owner)
      .approve(aqueductToken.address, mockERC20Balance);

    await aqueductToken.connect(owner).upgrade(mockERC20Balance, {
      gasLimit: 1000000,
    });

    expect(await aqueductToken.balanceOf(owner.address)).to.equal(
      mockERC20Balance
    );
  });

  it("Downgrades AqueductToken to underlying token", async () => {
    const owner = (await ethers.getSigners())[1];
    mockERC20 = await mockERC20.connect(owner);
    await mockERC20.mint(owner.address, ethers.utils.parseEther("100"));

    const mockERC20Balance = (
      await mockERC20.balanceOf(owner.address)
    ).toString();

    await mockERC20
      .connect(owner)
      .approve(aqueductToken.address, mockERC20Balance);

    await (
      await aqueductToken.connect(owner).upgrade(mockERC20Balance, {
        gasLimit: 1000000,
      })
    ).wait();

    await aqueductToken.connect(owner).downgrade(mockERC20Balance, {
      gasLimit: 1000000,
    });

    expect(await aqueductToken.balanceOf(owner.address)).to.equal(0);
    expect(await mockERC20.balanceOf(owner.address)).to.equal(mockERC20Balance);
  });
});
