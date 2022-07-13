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
const fdaixAddress = '0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90'; //mumbai: '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';
const daiAddress = '0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735';

// uniswap
//const uniswapFactory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';

// superfluid
const superfluidHost = '0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6'; // mumbai: '0xEB796bdb90fFA0f28255275e16936D25d3418603';
const resolverAddress = '0x659635Fab0A0cef1293f7eb3c7934542B6A6B31A'; // mumbai: '0x8C54C83FbDe3C59e59dd6E324531FB93d4F504d3';

describe("SuperApp Tests", function () {

    // global vars to be assigned in beforeEach
    let SuperApp;
    let superApp;
    let token0;
    let token1;
    let owner;
    let addr1;
    let addr2;
    let addrs;
    let testWalletSigner;

    // superfluid
    let sf;
    let signer;
    let addr1Signer;

    // delay helper function
    const delay = async (seconds) => {
        await hre.ethers.provider.send('evm_increaseTime', [seconds]);
        await hre.ethers.provider.send("evm_mine");
    };

    const getSumOfAllBalances = async () => {
        const a = (await token0.balanceOf(testWalletAddress)) / 10**18;
        const b = (await token1.balanceOf(testWalletAddress)) / 10**18;
        const c = (await token0.balanceOf(superApp.address)) / 10**18;
        const d = (await token1.balanceOf(superApp.address)) / 10**18;
        const e = (await token0.balanceOf(addr1.address)) / 10**18;
        const f = (await token1.balanceOf(addr1.address)) / 10**18;

        return (a + b + c + d + e + f) * 10**18;
        //return a;
    }

    // runs before every test
    beforeEach(async function () {
        // get signers
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [testWalletAddress],
        });
        testWalletSigner = await ethers.getSigner(testWalletAddress);

        // deploy SuperApp
        SuperApp = await ethers.getContractFactory("SuperApp");
        superApp = await SuperApp.deploy(
            superfluidHost
        );
        await superApp.deployed();

        // deploy tokens
        let Token = await ethers.getContractFactory("AqueductToken");
        token0 = await Token.deploy(superfluidHost, superApp.address);
        await token0.deployed();
        await token0.initialize(daiAddress, 18, "Aqueduct Token", "AQUA");

        token1 = await Token.deploy(superfluidHost, superApp.address);
        await token1.deployed();
        await token1.initialize(daiAddress, 18, "Aqueduct Token 2", "AQUA2");

        // init pool
        //await superApp.initialize(token0.address, token1.address, 100000000000, 100000000000);
        await superApp.initialize(token0.address, token1.address, 0, 0);

        // init superfluid sdk
        sf = await Framework.create({
            networkName: 'custom',
            provider: ethers.provider,
            dataMode: 'WEB3_ONLY',
            resolverAddress: resolverAddress
        });

        signer = sf.createSigner({
            privateKey: process.env.PRIVATE_KEY,
            provider: ethers.provider,
        });

        let addr1PC = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
        addr1Signer = sf.createSigner({
            privateKey: addr1PC,
            provider: ethers.provider,
        });
    })

    describe("generic streaming tests", function () {
        it("test stream (expected no revert)", async function () {
            // upgrade tokens
            const daiContract = await ethers.getContractAt("contracts/SuperApp.sol:IERC20", daiAddress);
            let amnt = '100000000000000000000'; // 100
            await daiContract.connect(testWalletSigner).approve(token0.address, amnt);
            await token0.connect(testWalletSigner).upgrade(amnt);
            await daiContract.connect(testWalletSigner).approve(token1.address, amnt);
            await token1.connect(testWalletSigner).upgrade(amnt);

            // manually add liquidity to the pool
            let amnt2 = '10000000000000000000'; // 10
            await token0.connect(testWalletSigner).transfer(superApp.address, amnt2);
            await token1.connect(testWalletSigner).transfer(superApp.address, amnt2);

            console.log("Contract's token0 balance: " + (await token0.balanceOf(superApp.address) / 10**18));
            console.log("Contract's token1 balance: " + (await token1.balanceOf(superApp.address) / 10**18));

            // check that differences between all balances stay net 0
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(5);
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(360000000);
            console.log("All balances: " + await getSumOfAllBalances())

            // create flow of token0 into the Super App
            const createFlowOperation = sf.cfaV1.createFlow({
                sender: testWalletAddress,
                receiver: superApp.address,
                superToken: token0.address,
                flowRate: "100000000000"
            });
            const txnResponse = await createFlowOperation.exec(signer);
            await txnResponse.wait();

            // create flow of token1 into the Super App
            const createFlowOperation2 = sf.cfaV1.createFlow({
                sender: testWalletAddress,
                receiver: superApp.address,
                superToken: token1.address,
                flowRate: "100000000000"
            });
            const txnResponse2 = await createFlowOperation2.exec(signer);
            await txnResponse2.wait();

            //console.log("Flows: " + await superApp.getFlows());

            // check that differences between all balances stay net 0
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(5);
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(360000000);
            console.log("All balances: " + await getSumOfAllBalances())

            // perform one way swap with second test wallet
            await token0.connect(testWalletSigner).transfer(addr1.address, amnt2); // transfer some tokens to addr1
            console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
            const createFlowOperation3 = sf.cfaV1.createFlow({
                sender: addr1.address,
                receiver: superApp.address,
                superToken: token0.address,
                flowRate: "10000000"
            });
            const txnResponse3 = await createFlowOperation3.exec(addr1Signer);
            await txnResponse3.wait();

            // check that differences between all balances stay net 0
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(5);
            console.log("All balances: " + await getSumOfAllBalances())
            await delay(36000);
            console.log("All balances: " + await getSumOfAllBalances())

            // check addr1 balance of input token
            console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
            console.log("User's token1 balance: " + await token1.balanceOf(addr1.address));
            await delay(5);
            console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
            console.log("User's token1 balance: " + await token1.balanceOf(addr1.address));
            await delay(36000);
            console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
            console.log("User's token1 balance: " + await token1.balanceOf(addr1.address));

            /*
            // cancel flows
            const deleteFlowOperation3 = sf.cfaV1.deleteFlow({
                sender: addr1.address,
                receiver: superApp.address,
                superToken: token0.address
            });
            const txnResponse4 = await deleteFlowOperation3.exec(addr1Signer);
            await txnResponse4.wait();

            await delay(36000);
            console.log("All balances: " + await getSumOfAllBalances())

            console.log('token0 flowrate: ' + await superApp.getTwapNetFlowRate(token0.address, addr1.address));
            console.log('token1 flowrate: ' + await superApp.getTwapNetFlowRate(token1.address, addr1.address));
            */


            //await delay(360000);
            //console.log("All balances: " + await getSumOfAllBalances())
            // test cumulatives
            /*
            console.log("User2's token0 cumulative: " + await superApp.getRealTimeUserCumulativeDelta(token0.address, addr1.address));
            console.log("User2's token1 cumulative: " + await superApp.getRealTimeUserCumulativeDelta(token1.address, addr1.address));
            await delay(60)
            console.log("User2's token0 cumulative: " + await superApp.getRealTimeUserCumulativeDelta(token0.address, addr1.address));
            console.log("User2's token1 cumulative: " + await superApp.getRealTimeUserCumulativeDelta(token1.address, addr1.address));
            */
        })
    })
})

