// const { Framework } = require('@superfluid-finance/sdk-core');
// const { ethers } = require("hardhat");
// const IERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20")
// require("dotenv").config();

// // test wallets
// const testWalletAddress = '0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1';

// // tokens
// const fdaixAddress = '0x88271d333C72e51516B67f5567c728E702b3eeE8';
// const daiAddress = '0x88271d333C72e51516B67f5567c728E702b3eeE8';

// // superfluid
// const superfluidHost = '0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9';
// const resolverAddress = '0x3710AB3fDE2B61736B8BB0CE845D6c61F667a78E';

// describe("SuperApp Tests", function () {

//     // global vars to be assigned in beforeEach
//     let SuperApp;
//     let superApp;
//     let token0;
//     let token1;
//     let owner;
//     let addr1;
//     let addr2;
//     let addrs;
//     let testWalletSigner;

//     // superfluid
//     let sf;
//     let signer;
//     let addr1Signer;
//     let addr2Signer;

//     // delay helper function
//     const delay = async (seconds) => {
//         await hre.ethers.provider.send('evm_increaseTime', [seconds]);
//         await hre.ethers.provider.send("evm_mine");
//     };

//     const logSumOfAllBalances = async () => {
//         var sum = (await token0.balanceOf(testWalletAddress)) / 10**18;
//         sum += (await token1.balanceOf(testWalletAddress)) / 10**18;
//         sum += (await token0.balanceOf(superApp.address)) / 10**18;
//         sum += (await token1.balanceOf(superApp.address)) / 10**18;
//         sum += (await token0.balanceOf(addr1.address)) / 10**18;
//         sum += (await token1.balanceOf(addr1.address)) / 10**18;
//         sum += (await token0.balanceOf(addr2.address)) / 10**18;
//         sum +=(await token1.balanceOf(addr2.address)) / 10**18;

//         console.log('Sum of all balances: ' + sum);
//     }

//     const logAllBalances = async () => {
//         console.log('____________________________')
//         console.log('LP:  ' + await token0.balanceOf(testWalletAddress) + ',  ' + await token1.balanceOf(testWalletAddress));
//         console.log('LP ∆:  ' + await superApp.getRealTimeUserCumulativeDelta(token0.address, testWalletAddress) + ',  ' + await superApp.getRealTimeUserCumulativeDelta(token1.address, testWalletAddress));
//         console.log('LP nF:  ' + await superApp.getTwapNetFlowRate(token0.address, testWalletAddress) + ',  ' + await superApp.getTwapNetFlowRate(token1.address, testWalletAddress));
//         console.log('LP sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: testWalletAddress, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: testWalletAddress, providerOrSigner: addr1Signer}));
//         console.log('pool:  ' + await token0.balanceOf(superApp.address) + ',  ' + await token1.balanceOf(superApp.address));
//         console.log('pool ∆:  ' + await superApp.getRealTimeUserCumulativeDelta(token0.address, superApp.address) + ',  ' + await superApp.getRealTimeUserCumulativeDelta(token1.address, superApp.address));
//         console.log('pool nF:  ' + await superApp.getTwapNetFlowRate(token0.address, superApp.address) + ',  ' + await superApp.getTwapNetFlowRate(token1.address, superApp.address));
//         console.log('pool sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: superApp.address, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: superApp.address, providerOrSigner: addr1Signer}));
//         console.log('userA:  ' + await token0.balanceOf(addr1.address) + ',  ' + await token1.balanceOf(addr1.address));
//         console.log('userA ∆:  ' + await superApp.getRealTimeUserCumulativeDelta(token0.address, addr1.address) + ',  ' + await superApp.getRealTimeUserCumulativeDelta(token1.address, addr1.address));
//         console.log('userA nF:  ' + await superApp.getTwapNetFlowRate(token0.address, addr1.address) + ',  ' + await superApp.getTwapNetFlowRate(token1.address, addr1.address));
//         console.log('userA sfF:  ' + await sf.cfaV1.getNetFlow({superToken: token0.address, account: addr1.address, providerOrSigner: addr1Signer}) + ',  ' + await sf.cfaV1.getNetFlow({superToken: token1.address, account: addr1.address, providerOrSigner: addr1Signer}));
//     }

//     const logInitialCumulatives = async () => {
//         const cumulatives = await superApp.getUserPriceCumulatives(testWalletAddress);
//         console.log('initial cumulatives: ' + cumulatives);
//     }

//     const logCumulatives = async () => {
//         const cumulatives = await superApp.getRealTimeCumulatives();
//         console.log('realtime cumulatives: ' + cumulatives);
//     }

//     // runs before every test
//     beforeEach(async function () {
//         // get signers
//         [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
//         await hre.network.provider.request({
//             method: "hardhat_impersonateAccount",
//             params: [testWalletAddress],
//         });
//         testWalletSigner = await ethers.getSigner(testWalletAddress);

//         // deploy SuperApp
//         SuperApp = await ethers.getContractFactory("SuperApp");
//         superApp = await SuperApp.deploy(
//             superfluidHost
//         );
//         await superApp.deployed();

//         // deploy tokens
//         let Token = await ethers.getContractFactory("AqueductToken");
//         token0 = await Token.deploy(superfluidHost, superApp.address);
//         await token0.deployed();
//         await token0.initialize(daiAddress, 18, "Aqueduct Token", "AQUA");

//         token1 = await Token.deploy(superfluidHost, superApp.address);
//         await token1.deployed();
//         await token1.initialize(daiAddress, 18, "Aqueduct Token 2", "AQUA2");

//         // init pool
//         await superApp.initialize(token0.address, token1.address, 0, 0);

//         // init superfluid sdk
//         sf = await Framework.create({
//             networkName: 'custom',
//             provider: ethers.provider,
//             dataMode: 'WEB3_ONLY',
//             resolverAddress: resolverAddress
//         });

//         signer = sf.createSigner({
//             privateKey: process.env.PRIVATE_KEY,
//             provider: ethers.provider,
//         });

//         let addr1PC = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
//         addr1Signer = sf.createSigner({
//             privateKey: addr1PC,
//             provider: ethers.provider,
//         });

//         let addr2PC = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';
//         addr2Signer = sf.createSigner({
//             privateKey: addr2PC,
//             provider: ethers.provider,
//         })
//     })

//     describe("generic streaming tests", function () {
//         it("test stream (expected no revert)", async function () {
//             // upgrade tokens
//             const daiContract = await ethers.getContractAt(IERC20.abi, daiAddress);
//             let amnt = '100000000000000000000'; // 100
//             await daiContract.connect(testWalletSigner).approve(token0.address, amnt);
//             await token0.connect(testWalletSigner).upgrade(amnt);
//             await daiContract.connect(testWalletSigner).approve(token1.address, amnt);
//             await token1.connect(testWalletSigner).upgrade(amnt);

//             // manually add liquidity to the pool
//             let amnt2 = '10000000000000000000'; // 10
//             await token0.connect(testWalletSigner).transfer(superApp.address, amnt2);
//             await token1.connect(testWalletSigner).transfer(superApp.address, amnt2);

//             // TODO: require these
//             //console.log("Contract's token0 balance: " + (await token0.balanceOf(superApp.address) / 10**18));
//             //console.log("Contract's token1 balance: " + (await token1.balanceOf(superApp.address) / 10**18));

//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             // create flow of token0 into the Super App
//             console.log('\n_____ LP token0 --> token1 _____')
//             const createFlowOperation = sf.cfaV1.createFlow({
//                 sender: testWalletAddress,
//                 receiver: superApp.address,
//                 superToken: token0.address,
//                 flowRate: "100000000000"
//             }); //100000000000
//             const createFlowRes = await createFlowOperation.exec(signer);
//             await createFlowRes.wait();

//             // create flow of token1 into the Super App
//             console.log('\n_____ LP token0 <-- token1 _____')
//             const createFlowOperation2 = sf.cfaV1.createFlow({
//                 sender: testWalletAddress,
//                 receiver: superApp.address,
//                 superToken: token1.address,
//                 flowRate: "100000000000"
//             });
//             const createFlowRes2 = await createFlowOperation2.exec(signer);
//             await createFlowRes2.wait();

//             // all
//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             await delay(36000);

//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             // perform one way swap with second test wallet
//             console.log('\n_____ User A token0 --> token1 _____')
//             await token0.connect(testWalletSigner).transfer(addr1.address, amnt2); // transfer some tokens to addr1
//             //console.log("User's token0 balance: " + await token0.balanceOf(addr1.address));
//             const createFlowOperation3 = sf.cfaV1.createFlow({
//                 sender: addr1.address,
//                 receiver: superApp.address,
//                 superToken: token0.address,
//                 flowRate: "10000000000"
//             });
//             const createFlowRes3 = await createFlowOperation3.exec(addr1Signer);
//             await createFlowRes3.wait();

//             // all
//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             await delay(36000);

//             // all
//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             // perform one way swap in opposite direction with third test wallet
//             console.log('\n_____ User B token0 <-- token1 _____')
//             await token1.connect(testWalletSigner).transfer(addr2.address, amnt2); // transfer some tokens to addr1
//             const createFlowOperation4 = sf.cfaV1.createFlow({
//                 sender: addr2.address,
//                 receiver: superApp.address,
//                 superToken: token1.address,
//                 flowRate: "5000000"
//             });
//             const createFlowRes4 = await createFlowOperation4.exec(addr2Signer);
//             await createFlowRes4.wait();

//             // all
//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             await delay(36000);

//             // all
//             await logCumulatives();
//             await logAllBalances();
//             await logSumOfAllBalances();

//             // cancel flows
//             const deleteFlowOperation3 = sf.cfaV1.deleteFlow({
//                 sender: addr1.address,
//                 receiver: superApp.address,
//                 superToken: token0.address
//             });
//             const deleteFlowRes = await deleteFlowOperation3.exec(addr1Signer);
//             const deleteFlowTxRes = await deleteFlowRes.wait();
//         })
//     })
// })
