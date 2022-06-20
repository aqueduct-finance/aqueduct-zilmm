//import { Framework } from "@superfluid-finance/sdk-core";
//import { ethers } from "hardhat";
const { Framework } = require('@superfluid-finance/sdk-core');
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("contracts/SuperApp.sol:IERC20");
require("dotenv").config();

// test wallets
const testWalletAddress = '0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1';

// tokens
const maticxAddress = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';
const fdaixAddress = '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';

// uniswap
const uniswapFactory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';

// superfluid
const superfluidHost = '0xEB796bdb90fFA0f28255275e16936D25d3418603';

describe("SuperApp Tests", function () {

    // global vars to be assigned in beforeEach
    let SuperApp;
    let superApp;
    let owner;
    let addr1;
    let addr2;
    let addrs;
    let testWalletSigner;

    // superfluid
    let sf;
    let signer;

    // runs before every test
    beforeEach(async function () {
        // get signers
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        testWalletSigner = await ethers.getSigner(testWalletAddress);

        // deploy SuperApp
        SuperApp = await ethers.getContractFactory("SuperApp");
        superApp = await SuperApp.deploy(
            superfluidHost,
            uniswapFactory
        );
        await superApp.deployed();

        // init superfluid sdk
        sf = await Framework.create({
            networkName: 'custom',
            provider: ethers.provider,
            dataMode: 'WEB3_ONLY',
            resolverAddress: '0x8C54C83FbDe3C59e59dd6E324531FB93d4F504d3'
        });

        signer = sf.createSigner({
            privateKey: process.env.PRIVATE_KEY,
            provider: ethers.provider,
        });
    })

    describe("generic streaming tests", function () {
        it("test stream (expected no revert)", async function () {

            // manually add liquidity to the pool
            const maticxContract = await ethers.getContractAt("contracts/SuperApp.sol:IERC20", maticxAddress);
            await maticxContract.connect(testWalletSigner).transfer(superApp.address, '250000000000000000'); // 0.25 maticx

            console.log("Contract's maticx balance: " + await maticxContract.balanceOf(superApp.address));

            // create flow of fDAIx into the Super App
            const createFlowOperation = sf.cfaV1.createFlow({
                sender: testWalletAddress,
                receiver: superApp.address,
                superToken: fdaixAddress,
                flowRate: "100000000000"
            });
            const txnResponse = await createFlowOperation.exec(signer);
            await txnResponse.wait();

            // TODO: test for amount going in / out of contract via stream
        })
    })
})

