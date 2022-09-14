const { Framework } = require('@superfluid-finance/sdk-core');
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20")
require("dotenv").config();

// test wallets
const testWalletAddress = '0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1';

// tokens
const fdaixAddress = '0x88271d333C72e51516B67f5567c728E702b3eeE8';
const daiAddress = '0x88271d333C72e51516B67f5567c728E702b3eeE8';

// superfluid
const superfluidHost = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';
const resolverAddress = '0x3710AB3fDE2B61736B8BB0CE845D6c61F667a78E';

describe("Pool Tests", function () {

    // global vars to be assigned in beforeEach
    let Pool;
    let pool;
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
    let addr2Signer;

    // delay helper function
    const delay = async (seconds) => {
        await hre.ethers.provider.send('evm_increaseTime', [seconds]);
        await hre.ethers.provider.send("evm_mine");
    };

    const logSumOfAllBalances2 = async () => {
        var sum = (await token0.balanceOf(testWalletAddress)) / 10**18;
        sum += (await token1.balanceOf(testWalletAddress)) / 10**18;
        sum += (await token0.balanceOf(pool.address)) / 10**18;
        sum += (await token1.balanceOf(pool.address)) / 10**18;
        sum += (await token0.balanceOf(addr1.address)) / 10**18;
        sum += (await token1.balanceOf(addr1.address)) / 10**18;
        sum += (await token0.balanceOf(addr2.address)) / 10**18;
        sum += (await token1.balanceOf(addr2.address)) / 10**18;

        // add deposits
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 10**18;

        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 10**18;

        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 10**18;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 10**18;

        console.log('Sum of all balances: ' + sum);
    }

    const logSumOfAllBalances = async () => {
        var lpSum = (await token0.balanceOf(testWalletAddress)) / 1;
        lpSum += (await token1.balanceOf(testWalletAddress)) / 1;
        var poolSum = (await token0.balanceOf(pool.address)) / 1;
        poolSum += (await token1.balanceOf(pool.address)) / 1;
        var userASum = (await token0.balanceOf(addr1.address)) / 1;
        userASum += (await token1.balanceOf(addr1.address)) / 1;
        var userBSum = (await token0.balanceOf(addr2.address)) / 1;
        userBSum += (await token1.balanceOf(addr2.address)) / 1;

        // add deposits
        lpSum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        lpSum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 1;

        userASum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        userASum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 1;

        userBSum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        userBSum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolSum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;

        // log all
        console.log('LP sum: ' + lpSum);
        console.log('Pool sum: ' + poolSum);
        console.log('UserA sum: ' + userASum);
        console.log('UserB sum: ' + userBSum);
        console.log('Sum of all balances: ' + (lpSum + poolSum + userASum + userBSum));
    }

    const logSumOfAllBalances3 = async () => {
        var sum = (await token0.balanceOf(addr2.address)) / 1;
        sum += (await token1.balanceOf(addr2.address)) / 1;

        // add deposits
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1;
        sum += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;
        sum += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;

        console.log('Sum of all balances: ' + sum);
    }

    const logAllBalances = async () => {
        console.log('____________________________')
        console.log('LP:  ' + await token0.balanceOf(testWalletAddress) + ',  ' + await token1.balanceOf(testWalletAddress));
        console.log('LP ∆:  ' + await pool.getRealTimeUserCumulativeDelta(token0.address, testWalletAddress) + ',  ' + await pool.getRealTimeUserCumulativeDelta(token1.address, testWalletAddress));
        console.log('LP nF:  ' + await pool.getTwapNetFlowRate(token0.address, testWalletAddress) + ',  ' + await pool.getTwapNetFlowRate(token1.address, testWalletAddress));
        console.log('LP sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: testWalletAddress, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: testWalletAddress, providerOrSigner: addr1Signer}));
        console.log('lp deposits 0: ' + ((await sf.cfaV1.getFlow({superToken: token0.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: testWalletSigner})).deposit / 1));
        console.log('lp deposits 1: ' + ((await sf.cfaV1.getFlow({superToken: token1.address, sender: testWalletAddress, receiver: pool.address, providerOrSigner: testWalletSigner})).deposit / 1));
        console.log('lp rewards 0: ' + await pool.getRealTimeUserReward(token0.address, testWalletAddress));
        console.log('lp rewards 1: ' + await pool.getRealTimeUserReward(token1.address, testWalletAddress));

        console.log('pool:  ' + await token0.balanceOf(pool.address) + ',  ' + await token1.balanceOf(pool.address));
        console.log('pool ∆:  ' + await pool.getRealTimeUserCumulativeDelta(token0.address, pool.address) + ',  ' + await pool.getRealTimeUserCumulativeDelta(token1.address, pool.address));
        console.log('pool nF:  ' + await pool.getTwapNetFlowRate(token0.address, pool.address) + ',  ' + await pool.getTwapNetFlowRate(token1.address, pool.address));
        console.log('pool sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: pool.address, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: pool.address, providerOrSigner: addr1Signer}));
        var poolDeposits0 = (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 1;
        poolDeposits0 += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolDeposits0 += (await sf.cfaV1.getFlow({superToken: token0.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;
        console.log('pool deposits 0: ' + poolDeposits0);
        var poolDeposits1 = (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: testWalletAddress, providerOrSigner: addr1Signer})).deposit / 1;
        poolDeposits1 += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr1.address, providerOrSigner: addr1Signer})).deposit / 1;
        poolDeposits1 += (await sf.cfaV1.getFlow({superToken: token1.address, sender: pool.address, receiver: addr2.address, providerOrSigner: addr1Signer})).deposit / 1;
        console.log('pool deposits 1: ' + poolDeposits1);
        console.log('pool rewards 0: ' + await pool.getRealTimeUserReward(token0.address, pool.address));
        console.log('pool rewards 1: ' + await pool.getRealTimeUserReward(token1.address, pool.address));
        
        console.log('userA:  ' + await token0.balanceOf(addr1.address) + ',  ' + await token1.balanceOf(addr1.address));
        console.log('userA ∆:  ' + await pool.getRealTimeUserCumulativeDelta(token0.address, addr1.address) + ',  ' + await pool.getRealTimeUserCumulativeDelta(token1.address, addr1.address));
        console.log('userA nF:  ' + await pool.getTwapNetFlowRate(token0.address, addr1.address) + ',  ' + await pool.getTwapNetFlowRate(token1.address, addr1.address));
        console.log('userA sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: addr1.address, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: addr1.address, providerOrSigner: addr1Signer}));
        console.log('userA deposits 0: ' + ((await sf.cfaV1.getFlow({superToken: token0.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1));
        console.log('userA deposits 1: ' + ((await sf.cfaV1.getFlow({superToken: token1.address, sender: addr1.address, receiver: pool.address, providerOrSigner: addr1Signer})).deposit / 1));
        console.log('userA rewards 0: ' + await pool.getRealTimeUserReward(token0.address, addr1.address));
        console.log('userA rewards 1: ' + await pool.getRealTimeUserReward(token1.address, addr1.address));

        console.log('userB:  ' + await token0.balanceOf(addr2.address) + ',  ' + await token1.balanceOf(addr2.address));
        console.log('userB ∆:  ' + await pool.getRealTimeUserCumulativeDelta(token0.address, addr2.address) + ',  ' + await pool.getRealTimeUserCumulativeDelta(token1.address, addr2.address));
        console.log('userB nF:  ' + await pool.getTwapNetFlowRate(token0.address, addr2.address) + ',  ' + await pool.getTwapNetFlowRate(token1.address, addr2.address));
        console.log('userB sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: addr2.address, providerOrSigner: addr2Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: addr2.address, providerOrSigner: addr2Signer}));
        console.log('userB deposits 0: ' + ((await sf.cfaV1.getFlow({superToken: token0.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr2Signer})).deposit / 1));
        console.log('userB deposits 1: ' + ((await sf.cfaV1.getFlow({superToken: token1.address, sender: addr2.address, receiver: pool.address, providerOrSigner: addr2Signer})).deposit / 1));
        console.log('userB rewards 0: ' + await pool.getRealTimeUserReward(token0.address, addr2.address));
        console.log('userB rewards 1: ' + await pool.getRealTimeUserReward(token1.address, addr2.address));
    }

    const logInitialCumulatives = async () => {
        const cumulatives = await pool.getUserPriceCumulatives(testWalletAddress);
        console.log('initial cumulatives: ' + cumulatives);
    }

    const logCumulatives = async () => {
        const cumulatives = await pool.getRealTimeCumulatives();
        console.log('realtime cumulatives: ' + cumulatives);
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

        // deploy Pool
        Pool = await ethers.getContractFactory("Pool");
        pool = await Pool.deploy(
            superfluidHost
        );
        await pool.deployed();

        // deploy tokens
        let Token = await ethers.getContractFactory("AqueductToken");
        token0 = await Token.deploy(superfluidHost, pool.address);
        await token0.deployed();
        await token0.initialize(daiAddress, 18, "Aqueduct Token", "AQUA");

        token1 = await Token.deploy(superfluidHost, pool.address);
        await token1.deployed();
        await token1.initialize(daiAddress, 18, "Aqueduct Token 2", "AQUA2");

        // init pool
        const poolFee = BigInt(2**128 * 0.01); // 1% fee - multiply by 2^112 to conform to UQ112x112
        //const poolFee = 0;
        await pool.initialize(token0.address, token1.address, poolFee);

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

        let addr2PC = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';
        addr2Signer = sf.createSigner({
            privateKey: addr2PC,
            provider: ethers.provider,
        })
    })

    describe("generic streaming tests", function () {
        it("test stream (expected no revert)", async function () {
            // log addresses for testing
            console.log('pool address: ' + pool.address);
            console.log('lp address: ' + testWalletAddress);
            console.log('userA address: ' + addr1.address);
            console.log('userB address: ' + addr2.address);

            // get first block (for tracking events)
            //const firstBlock = (await ethers.provider.getBlock("latest")).number;

            // upgrade tokens
            const daiContract = await ethers.getContractAt(IERC20.abi, daiAddress);
            let amnt = '100000000000000000000'; // 100
            await daiContract.connect(testWalletSigner).approve(token0.address, amnt);
            await token0.connect(testWalletSigner).upgrade(amnt);
            await daiContract.connect(testWalletSigner).approve(token1.address, amnt);
            await token1.connect(testWalletSigner).upgrade(amnt);

            // manually add liquidity to the pool
            let amnt2 = '10000000000000000000'; // 10
            await token0.connect(testWalletSigner).transfer(pool.address, amnt2);
            await token1.connect(testWalletSigner).transfer(pool.address, amnt2);

            // TODO: require these
            //console.log("Contract's token0 balance: " + (await token0.balanceOf(pool.address) / 10**18));
            //console.log("Contract's token1 balance: " + (await token1.balanceOf(pool.address) / 10**18));

            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            // create flow of token0 into the Super App
            console.log('\n_____ LP token0 --> token1 _____')
            const createFlowOperation = sf.cfaV1.createFlow({
                sender: testWalletAddress,
                receiver: pool.address,
                superToken: token0.address,
                flowRate: "100000000000"
            }); //100000000000
            const createFlowRes = await createFlowOperation.exec(signer);
            await createFlowRes.wait();
            
            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            // create flow of token1 into the Super App
            console.log('\n_____ LP token0 <-- token1 _____')
            const createFlowOperation2 = sf.cfaV1.createFlow({
                sender: testWalletAddress,
                receiver: pool.address,
                superToken: token1.address,
                flowRate: "100000000000"
            });
            const createFlowRes2 = await createFlowOperation2.exec(signer);
            await createFlowRes2.wait();

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            // perform one way swap with second test wallet
            console.log('\n_____ User A token0 --> token1 _____')
            await token0.connect(testWalletSigner).transfer(addr1.address, amnt2); // transfer some tokens to addr1
            //console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
            const createFlowOperation3 = sf.cfaV1.createFlow({
                sender: addr1.address,
                receiver: pool.address,
                superToken: token0.address,
                flowRate: "10000000000"//"10000000000"
            });
            const createFlowRes3 = await createFlowOperation3.exec(addr1Signer);
            await createFlowRes3.wait();

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            // perform one way swap in opposite direction with third test wallet
            console.log('\n_____ User B token0 <-- token1 _____')
            await token1.connect(testWalletSigner).transfer(addr2.address, amnt2); // transfer some tokens to addr2
            const createFlowOperation4 = sf.cfaV1.createFlow({
                sender: addr2.address,
                receiver: pool.address,
                superToken: token1.address,
                flowRate: "5000000"//"5000000"
            });
            const createFlowRes4 = await createFlowOperation4.exec(addr2Signer);
            await createFlowRes4.wait();

            /*
            var firstBlock = (await ethers.provider.getBlock("latest")).number;

            await pool.connect(testWalletSigner).testUserReward(token0.address, testWalletAddress);
            await pool.connect(testWalletSigner).testUserReward(token1.address, testWalletAddress);

            // get all events
            var currentBlock = (await ethers.provider.getBlock("latest")).number;
            console.log((await pool.queryFilter("userReward", firstBlock, currentBlock)));
            */

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            // cancel flows
            console.log('\n_____ User B token0 <-x- token1 _____')
            const deleteFlowOperation = sf.cfaV1.deleteFlow({
                sender: addr2.address,
                receiver: pool.address,
                superToken: token1.address
            });
            const deleteFlowRes = await deleteFlowOperation.exec(addr2Signer);
            await deleteFlowRes.wait();

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            console.log('\n_____ User A token0 -x-> token1 _____')
            const deleteFlowOperation2 = sf.cfaV1.deleteFlow({
                sender: addr1.address,
                receiver: pool.address,
                superToken: token0.address
            });
            const deleteFlowRes2 = await deleteFlowOperation2.exec(addr1Signer);
            await deleteFlowRes2.wait();

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            console.log('\n_____ LP token0 <-x- token1 _____')
            const deleteFlowOperation3 = sf.cfaV1.deleteFlow({
                sender: testWalletAddress,
                receiver: pool.address,
                superToken: token1.address
            });
            const deleteFlowRes3 = await deleteFlowOperation3.exec(testWalletSigner);
            await deleteFlowRes3.wait();
            
            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            console.log('\n_____ LP token0 -x-> token1 _____')
            const deleteFlowOperation4 = sf.cfaV1.deleteFlow({
                sender: testWalletAddress,
                receiver: pool.address,
                superToken: token0.address
            });
            const deleteFlowRes4 = await deleteFlowOperation4.exec(testWalletSigner);
            await deleteFlowRes4.wait();

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();

            await delay(36000);

            // all
            await logCumulatives();
            await logAllBalances();
            await logSumOfAllBalances();
        })
    })
})

