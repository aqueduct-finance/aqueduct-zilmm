// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperfluidToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "./libraries/UQ128x128.sol";
import "./libraries/math.sol";
import "./interfaces/IAqueductHost.sol";
import "./interfaces/IAqueductToken.sol";

contract SuperApp is SuperAppBase, IAqueductHost {
    using UQ128x128 for uint256;

    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Pool variables --- */
    address public factory;
    uint256 poolFee;
    IAqueductToken public token0;
    IAqueductToken public token1;

    uint128 private flowIn0;
    uint128 private flowIn1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    int96 private feesFlow0;
    int96 private feesFlow1;
    int256 private feesTotal0Last;
    int256 private feesTotal1Last;

    // LP flow cumulatives
    int96 private liquidityFlow0;
    int96 private liquidityFlow1;
    uint256 liquidity0CumulativeLast;
    uint256 liquidity1CumulativeLast;

    // map user address to their starting price cumulatives
    struct UserPriceCumulative {
        int96 flowIn0;
        int96 flowIn1;
        int96 flowOut0;
        int96 flowOut1;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
        uint256 fees0Cumulative;
        uint256 fees1Cumulative;
        int256 initialFeesTotal0;
        int256 initialFeesTotal1;
        int96 liquidityFlow0;
        int96 liquidityFlow1;
    }
    mapping(address => UserPriceCumulative) private userPriceCumulatives;

    // map user address to their reward percentage
    struct UserRewardPercentage {
        uint256 reward0Percentage;
        uint256 reward1Percentage;
    }
    mapping(address => UserRewardPercentage) private userRewardPercentages;
    uint256 private fees0CumulativeLast;
    uint256 private fees1CumulativeLast;
    uint256 private rewards0CumulativeLast;
    uint256 private rewards1CumulativeLast;

    constructor(ISuperfluid host) payable {
        assert(address(host) != address(0));

        _host = host;
        factory = msg.sender;

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;

        host.registerApp(configWord);
    }

    // called once by the factory at time of deployment
    function initialize(
        IAqueductToken _token0,
        IAqueductToken _token1,
        uint224 _poolFee
    ) external {
        require(msg.sender == factory, "FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
    }

    /* --- Helper functions --- */

    /* Gets the opposite token in the pool given one supertoken (assumes tokenIn is part of pool) */
    function getOppositeToken(ISuperToken tokenIn)
        internal
        view
        returns (ISuperToken)
    {
        return address(tokenIn) == address(token0) ? token1 : token0;
    }

    function getUserFromCtx(bytes calldata _ctx)
        internal
        view
        returns (address user)
    {
        return _host.decodeCtx(_ctx).msgSender;
    }

    /* Gets the incoming flowRate for a given supertoken/user */
    function getFlowRateIn(ISuperToken token, address user)
        internal
        view
        returns (int96)
    {
        (, int96 flowRate, , ) = cfa.getFlow(token, user, address(this));

        return flowRate;
    }

    /* Gets the outgoing flowRate for a given supertoken/user */
    function getFlowRateOut(ISuperToken token, address user)
        internal
        view
        returns (int96)
    {
        (, int96 flowRate, , ) = cfa.getFlow(token, address(this), user);

        return flowRate;
    }

    /* Gets the fee percentage for a given supertoken/user */
    function getFeePercentage(
        int96 flowA,
        int96 flowB,
        uint128 poolFlowA,
        uint128 poolFlowB
    ) internal pure returns (uint256) {
        // handle special case
        if (flowB == 0 || poolFlowB == 0) {
            return UQ128x128.Q128;
        }

        // TODO: check that int96 -> uint128 cast is safe - expected that a flow between sender and receiver will always be positive
        uint256 userRatio = UQ128x128.encode(uint128(uint96(flowA))).uqdiv(
            uint128(uint96(flowB))
        );
        uint256 poolRatio = UQ128x128.encode(poolFlowA).uqdiv(poolFlowB);

        if ((userRatio + poolRatio) == 0) {
            return UQ128x128.Q128;
        } else {
            return
                math.difference(userRatio, poolRatio) / (userRatio + poolRatio);
        }
    }

    /* --- Pool functions --- */

    function getFlows()
        public
        view
        returns (
            uint128 _flowIn0,
            uint128 _flowIn1,
            uint32 _blockTimestampLast
        )
    {
        _flowIn0 = flowIn0;
        _flowIn1 = flowIn1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getUserPriceCumulatives(address user)
        external
        view
        returns (uint256 pc0, uint256 pc1)
    {
        UserPriceCumulative memory upc = userPriceCumulatives[user];
        pc0 = upc.price0Cumulative;
        pc1 = upc.price1Cumulative;
    }

    function getCumulativesAtTime(uint256 timestamp)
        internal
        view
        returns (uint256 pc0, uint256 pc1)
    {
        uint32 timestamp32 = uint32(timestamp % 2**32);
        uint32 timeElapsed = timestamp32 - blockTimestampLast;
        uint128 _flowIn0 = flowIn0;
        uint128 _flowIn1 = flowIn1;

        pc0 = price0CumulativeLast;
        pc1 = price1CumulativeLast;
        if (_flowIn0 > 0 && _flowIn1 > 0) {
            pc1 += (uint256(UQ128x128.encode(_flowIn1).uqdiv(_flowIn0)) *
                timeElapsed);
            pc0 += (uint256(UQ128x128.encode(_flowIn0).uqdiv(_flowIn1)) *
                timeElapsed);
        }
    }

    function getRealTimeCumulatives()
        external
        view
        returns (uint256 pc0, uint256 pc1)
    {
        (pc0, pc1) = getCumulativesAtTime(block.timestamp);
    }

    /*
    function getFeeCumulativesAtTime(uint256 timestamp)
        internal
        view
        returns (uint256 fc0, uint256 fc1)
    {
        (uint256 pc0, uint256 pc1) = getCumulativesAtTime(timestamp);

        fc0 = UQ128x128.decode(
            UQ128x128.decode(fees0CumulativeLast * poolFee) * pc0
        );
        fc1 = UQ128x128.decode(
            UQ128x128.decode(fees1CumulativeLast * poolFee) * pc1
        );
    }

    function getRealTimeFeeCumulatives()
        external
        view
        returns (uint256 fc0, uint256 fc1)
    {
        (fc0, fc1) = getFeeCumulativesAtTime(block.timestamp);
    }
*/

    function getFeesTotalAtTime(address token, uint256 timestamp)
        internal
        view
        returns (int256 feesTotal)
    {
        int96 feesFlowRate;
        int256 oldFeesTotal;
        if (token == address(token0)) {
            feesFlowRate = feesFlow0;
            oldFeesTotal = feesTotal0Last;
        } else {
            feesFlowRate = feesFlow1;
            oldFeesTotal = feesTotal1Last;
        }

        uint256 userCumulativeDelta = getUserCumulativeDelta(
            token,
            address(this),
            timestamp
        );
        feesTotal =
            oldFeesTotal +
            (int256(feesFlowRate) * int256(userCumulativeDelta));
    }

    function getRealTimeFeesTotal(address token)
        public
        view
        returns (int256 feesTotal)
    {
        feesTotal = getFeesTotalAtTime(token, block.timestamp);
    }

    function getLiquidityCumulativeAtTime(address token, uint256 timestamp)
        internal
        view
        returns (uint256 liquidityCumulative)
    {
        if (token == address(token0)) {
            liquidityCumulative =
                liquidity0CumulativeLast +
                (uint256(int256(liquidityFlow0)) *
                    (timestamp - blockTimestampLast));
        } else {
            liquidityCumulative =
                liquidity1CumulativeLast +
                (uint256(int256(liquidityFlow1)) *
                    (timestamp - blockTimestampLast));
        }
    }

    function getRealTimeLiquidityCumulative(address token)
        public
        view
        returns (uint256 liquidityCumulative)
    {
        liquidityCumulative = getLiquidityCumulativeAtTime(
            token,
            block.timestamp
        );
    }

    function getUserCumulativeDelta(
        address token,
        address user,
        uint256 timestamp
    ) public view returns (uint256 cumulativeDelta) {
        if (token == address(token0)) {
            (uint256 S, ) = getCumulativesAtTime(timestamp);
            uint256 S0 = userPriceCumulatives[user].price0Cumulative;
            cumulativeDelta = S - S0;
        } else if (token == address(token1)) {
            (, uint256 S) = getCumulativesAtTime(timestamp);
            uint256 S0 = userPriceCumulatives[user].price1Cumulative;
            cumulativeDelta = S - S0;
        }
    }

    function getRealTimeUserCumulativeDelta(address token, address user)
        external
        view
        returns (uint256 cumulativeDelta)
    {
        cumulativeDelta = getUserCumulativeDelta(token, user, block.timestamp);
    }

    event userReward(
        uint256 feesTotal,
        uint256 feesInitial,
        uint256 rewardPercentage,
        int96 flowIn,
        uint256 poolFlowIn,
        int256 tokenType
    );

    /*
    function getUserReward(
        address token,
        address user,
        uint256 timestamp
    ) public view returns (int256 reward) {
        if (user == address(this)) {
            //reward = 0;
            
            // prev: temp comment out:
            if (token == address(token0)) {
                (uint256 feesTotal, ) = getFeeCumulativesAtTime(timestamp);
                uint256 feesInitial = userPriceCumulatives[user]
                    .fees0Cumulative;
                reward =
                    int256(
                        UQ128x128.decode(
                            (feesTotal - feesInitial) * rewards0CumulativeLast
                        )
                    ) * -1;
            } else if (token == address(token1)) {
                (, uint256 feesTotal) = getFeeCumulativesAtTime(timestamp);
                uint256 feesInitial = userPriceCumulatives[user]
                    .fees1Cumulative;
                reward =
                    int256(
                        UQ128x128.decode(
                            (feesTotal - feesInitial) * rewards1CumulativeLast
                        )
                    ) * -1;
            }
            
        } else {
            if (token == address(token0)) {
                if (flowIn0 > 0) {
                    (uint256 feesTotal, ) = getFeeCumulativesAtTime(timestamp);
                    uint256 feesInitial = userPriceCumulatives[user]
                        .fees0Cumulative;
                    reward = int256(
                        UQ128x128.decode(
                            ((userRewardPercentages[user].reward0Percentage *
                                uint256(
                                    int256(userPriceCumulatives[user].flowIn0)
                                )) / flowIn0) * (feesTotal - feesInitial)
                        )
                    );
                }
            } else if (token == address(token1)) {
                if (flowIn1 > 0) {
                    (, uint256 feesTotal) = getFeeCumulativesAtTime(timestamp);
                    uint256 feesInitial = userPriceCumulatives[user]
                        .fees1Cumulative;
                    reward = int256(
                        UQ128x128.decode(
                            ((userRewardPercentages[user].reward1Percentage *
                                uint256(
                                    int256(userPriceCumulatives[user].flowIn1)
                                )) / flowIn1) * (feesTotal - feesInitial)
                        )
                    );
                }
            }
        }
    }
*/

    function getUserReward(
        address token,
        address user,
        uint256 timestamp
    ) public view returns (int256 reward) {
        int256 feesTotal = getFeesTotalAtTime(token, timestamp);

        int256 initialFeesTotal = userPriceCumulatives[user].initialFeesTotal0;
        if (token == address(token0)) {
            initialFeesTotal = userPriceCumulatives[user].initialFeesTotal0;
        } else {
            initialFeesTotal = userPriceCumulatives[user].initialFeesTotal1;
        }

        // if address is pool, subtract fees total
        if (user == address(this)) {
            reward =
                -1 *
                ((feesTotal - initialFeesTotal) / int256(UQ128x128.Q128));
        } else {
            // otherwise, compute LP's percentage of fees total
            if (token == address(token0)) {
                (uint256 initialTimestamp, , , ) = cfa.getAccountFlowInfo(
                    token0,
                    user
                );
                uint256 timeDelta = timestamp - initialTimestamp;
                if (
                    userPriceCumulatives[user].liquidityFlow0 > 0 &&
                    timeDelta > 0 &&
                    getLiquidityCumulativeAtTime(token, timestamp) > 0
                ) {
                    reward =
                        (((feesTotal - initialFeesTotal) /
                            int256(UQ128x128.Q128)) *
                            int256(userPriceCumulatives[user].liquidityFlow0)) /
                        int256(
                            getLiquidityCumulativeAtTime(token, timestamp) /
                                (timeDelta)
                        );
                }
            } else {
                (uint256 initialTimestamp, , , ) = cfa.getAccountFlowInfo(
                    token1,
                    user
                );
                uint256 timeDelta = timestamp - initialTimestamp;
                if (
                    userPriceCumulatives[user].liquidityFlow1 > 0 &&
                    timeDelta > 0 &&
                    getLiquidityCumulativeAtTime(token, timestamp) > 0
                ) {
                    reward =
                        (((feesTotal - initialFeesTotal) /
                            int256(UQ128x128.Q128)) *
                            int256(userPriceCumulatives[user].liquidityFlow1)) /
                        int256(
                            getLiquidityCumulativeAtTime(token, timestamp) /
                                (timeDelta)
                        );
                }
            }
        }
    }

    function getRealTimeUserReward(address token, address user)
        external
        view
        returns (int256 reward)
    {
        reward = getUserReward(token, user, block.timestamp);
    }

    function getTwapNetFlowRate(address token, address user)
        external
        view
        returns (int96 netFlowRate)
    {
        if (token == address(token0)) {
            netFlowRate = userPriceCumulatives[user].flowOut0;
        } else {
            netFlowRate = userPriceCumulatives[user].flowOut1;
        }
    }

    // update flow reserves and, on the first call per block, price accumulators
    function _update(
        uint128 _flowIn0,
        uint128 _flowIn1,
        int96 relFlowIn0,
        int96 relFlowIn1,
        int96 relFlowOut0,
        int96 relFlowOut1,
        address user
    ) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (_flowIn0 != 0 && _flowIn1 != 0) {
            if (timeElapsed <= 0) {
                timeElapsed = 0;
            }

            price1CumulativeLast +=
                uint256(UQ128x128.encode(_flowIn1).uqdiv(_flowIn0)) *
                timeElapsed;
            price0CumulativeLast +=
                uint256(UQ128x128.encode(_flowIn0).uqdiv(_flowIn1)) *
                timeElapsed;

            // update user and pool initial price cumulatives
            if (relFlowOut0 != 0) {
                userPriceCumulatives[user]
                    .price0Cumulative = price0CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price0Cumulative = price0CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price1Cumulative = price1CumulativeLast;
            }
            if (relFlowOut1 != 0) {
                userPriceCumulatives[user]
                    .price1Cumulative = price1CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price0Cumulative = price0CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price1Cumulative = price1CumulativeLast;
            }
        }

        if (relFlowIn0 != 0) {
            userPriceCumulatives[user].flowIn0 += relFlowIn0;
        }
        if (relFlowIn1 != 0) {
            userPriceCumulatives[user].flowIn1 += relFlowIn1;
        }
        if (relFlowOut0 != 0) {
            userPriceCumulatives[user].flowOut0 += relFlowOut0;
            userPriceCumulatives[address(this)].flowOut0 -= relFlowOut0;
        }
        if (relFlowOut1 != 0) {
            userPriceCumulatives[user].flowOut1 += relFlowOut1;
            userPriceCumulatives[address(this)].flowOut1 -= relFlowOut1;
        }

        flowIn0 = math.safeUnsignedAdd(_flowIn0, relFlowIn0);
        flowIn1 = math.safeUnsignedAdd(_flowIn1, relFlowIn1);

        blockTimestampLast = blockTimestamp;
    }

    struct UpdatedFees {
        uint256 feePercentage0;
        uint256 feePercentage1;
        uint256 feeMultiplier0;
        uint256 feeMultiplier1;
    }

    // fees are dependent upon flowRates of both tokens, update both at once
    function _updateFees(
        uint128 _flowIn0,
        uint128 _flowIn1,
        int96 previousUserFlowIn0,
        int96 previousUserFlowIn1,
        int96 userFlowIn0,
        int96 userFlowIn1,
        address user
    )
        private
        returns (
            int96 userFlowOut0,
            int96 userFlowOut1,
            int96 userLiquidityFlow0,
            int96 userLiquidityFlow1
        )
    {
        // remove previous rewards from reward accumulators
        /*
        if (_flowIn0 > 0) {
            rewards0CumulativeLast -=
                (userRewardPercentages[user].reward0Percentage *
                    uint256(int256(previousUserFlowIn0))) /
                _flowIn0;
        }
        if (_flowIn1 > 0) {
            rewards1CumulativeLast -=
                (userRewardPercentages[user].reward1Percentage *
                    uint256(int256(previousUserFlowIn1))) /
                _flowIn1;
        }
        */

        // calculate expected pool reserves
        _flowIn0 = math.safeUnsignedAdd(
            _flowIn0,
            userFlowIn0 - previousUserFlowIn0
        );
        _flowIn1 = math.safeUnsignedAdd(
            _flowIn1,
            userFlowIn1 - previousUserFlowIn1
        );

        // calculate fee percentages
        UpdatedFees memory updatedFees;
        updatedFees.feePercentage0 = getFeePercentage(
            userFlowIn0,
            userFlowIn1,
            _flowIn0,
            _flowIn1
        );
        updatedFees.feeMultiplier0 =
            UQ128x128.Q128 -
            ((updatedFees.feePercentage0 * poolFee) / UQ128x128.Q128);

        updatedFees.feePercentage1 = getFeePercentage(
            userFlowIn1,
            userFlowIn0,
            _flowIn1,
            _flowIn0
        );
        updatedFees.feeMultiplier1 =
            UQ128x128.Q128 -
            ((updatedFees.feePercentage1 * poolFee) / UQ128x128.Q128);

        // remove previous fees from fee accumulators
        /*
        // TODO: underflow is technically possible here, add checks?
        fees0CumulativeLast -= UQ128x128.decode(
            uint96(previousUserFlowIn0) *
            (UQ128x128.Q128 - userRewardPercentages[user].reward0Percentage)
        );
        fees1CumulativeLast -= UQ128x128.decode(
            uint96(previousUserFlowIn1) *
            (UQ128x128.Q128 - userRewardPercentages[user].reward1Percentage)
        );
        */

        // set both reward percentages
        userRewardPercentages[user].reward0Percentage = (UQ128x128.Q128 -
            updatedFees.feePercentage0);
        userRewardPercentages[user].reward1Percentage = (UQ128x128.Q128 -
            updatedFees.feePercentage1);

        // update fee accumulators
        /*
        fees0CumulativeLast += UQ128x128.decode(
            uint96(userFlowIn0) *
                (UQ128x128.Q128 - userRewardPercentages[user].reward0Percentage)
        );
        fees1CumulativeLast += UQ128x128.decode(
            uint96(userFlowIn1) *
                (UQ128x128.Q128 - userRewardPercentages[user].reward1Percentage)
        );
        */

        // update reward accumulators
        /*
        // temp comment out
        if (_flowIn0 > 0) {
            rewards0CumulativeLast +=
                (userRewardPercentages[user].reward0Percentage *
                    uint256(int256(userFlowIn0))) /
                _flowIn0;
        }
        if (_flowIn1 > 0) {
            rewards1CumulativeLast +=
                (userRewardPercentages[user].reward1Percentage *
                    uint256(int256(userFlowIn1))) /
                _flowIn1;
        }
        */

        // set user and pool fee cumulatives
        /*
        userPriceCumulatives[user].fees0Cumulative = UQ128x128.decode(
            UQ128x128.decode(fees0CumulativeLast * poolFee) *
                price0CumulativeLast
        );
        // prev commented out:
        userPriceCumulatives[address(this)]
            .fees0Cumulative = userPriceCumulatives[user].fees0Cumulative;
        userPriceCumulatives[user].fees1Cumulative = UQ128x128.decode(
            UQ128x128.decode(fees1CumulativeLast * poolFee) *
                price1CumulativeLast
        );
        // prev commented out:
        userPriceCumulatives[address(this)]
            .fees1Cumulative = userPriceCumulatives[user].fees1Cumulative;
        */

        /*
        // calculate fees_total at this time
        //moved::
        int256 feesTotal0 = getRealTimeFeesTotal(address(token0));
        int256 feesTotal1 = getRealTimeFeesTotal(address(token1));

        // set fees_intial for both user and pool
        userPriceCumulatives[user].initialFeesTotal0 = feesTotal0;
        userPriceCumulatives[user].initialFeesTotal1 = feesTotal1;
        userPriceCumulatives[address(this)].initialFeesTotal0 = feesTotal0;
        userPriceCumulatives[address(this)].initialFeesTotal1 = feesTotal1;
        */

        // calculate outflows
        // TODO: check for overflow
        userFlowOut0 = int96(
            int256(
                UQ128x128.decode(
                    updatedFees.feeMultiplier1 * uint256(uint96(userFlowIn1))
                )
            )
        );
        userFlowOut1 = int96(
            int256(
                UQ128x128.decode(
                    updatedFees.feeMultiplier0 * uint256(uint96(userFlowIn0))
                )
            )
        );

        // calculate liquidity flows
        userLiquidityFlow0 = int96(
            int256(
                UQ128x128.decode(
                    (UQ128x128.Q128 - updatedFees.feePercentage0) *
                        uint256(uint96(userFlowIn0))
                )
            )
        );
        userLiquidityFlow1 = int96(
            int256(
                UQ128x128.decode(
                    (UQ128x128.Q128 - updatedFees.feePercentage1) *
                        uint256(uint96(userFlowIn1))
                )
            )
        );

        // update fees Flow cumulatives
        //old
        //feesFlow0 -= getFlowRateOut(token0, user);
        //feesFlow1 -= getFlowRateOut(token1, user);
        //feesFlow0 += userFlowOut0;
        //feesFlow1 += userFlowOut1;

        /*
        //moved 
        feesFlow0 -= userPriceCumulatives[user].flowIn1 - userPriceCumulatives[user].flowOut0; //getFlowRateOut(token0, user);
        feesFlow1 -= userPriceCumulatives[user].flowIn0 - userPriceCumulatives[user].flowOut1; //getFlowRateOut(token1, user);
        feesFlow0 += userFlowIn1 - userFlowOut0;
        feesFlow1 += userFlowIn0 - userFlowOut1;
        */
    }

    function getFeesFlows() external view returns (int96 flow0, int96 flow1) {
        flow0 = feesFlow0;
        flow1 = feesFlow1;
    }

    /*
    function getFeeTotalAndInitial() external view returns (int96 total, int96 initial) {
        total = getRealTimeFeesTotal(token0);
        initial = userPriceCumulatives[address(this)].initialFeesTotal0;
    }
*/

    /* --- Superfluid callbacks --- */

    struct Flow {
        address user;
        int96 userFlowIn0;
        int96 userFlowIn1;
        int96 userFlowOut0;
        int96 userFlowOut1;
        int96 userLiquidityFlow0;
        int96 userLiquidityFlow1;
        int96 previousUserFlowOut0;
        int96 previousUserFlowOut1;
        int96 previousUserFlowIn;
        uint256 initialTimestamp0;
        uint256 initialTimestamp1;
        bool forceSettleUserBalances;
        bool forceSettlePoolBalances;
    }

    //onlyExpected(_agreementClass)
    function afterAgreementCreated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );

        // avoid stack too deep
        Flow memory flow;
        flow.user = getUserFromCtx(_ctx);
        //flow.oppositeToken = getOppositeToken(_superToken);

        flow.userFlowIn0 = getFlowRateIn(token0, flow.user);
        flow.userFlowIn1 = getFlowRateIn(token1, flow.user);

        flow.previousUserFlowOut0 = getFlowRateOut(token0, flow.user);
        flow.previousUserFlowOut1 = getFlowRateOut(token1, flow.user);

        if (address(_superToken) == address(token0)) {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                0,
                flow.userFlowIn1,
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        } else {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                flow.userFlowIn0,
                0,
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        }

        // update other stream if fees were updated
        if (address(_superToken) == address(token0)) {
            newCtx = cfaV1.createFlowWithCtx(
                _ctx,
                flow.user,
                token1,
                flow.userFlowOut1
            );
            if (flow.previousUserFlowOut0 != flow.userFlowOut0) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut0
                );
            }
        } else {
            newCtx = cfaV1.createFlowWithCtx(
                _ctx,
                flow.user,
                token0,
                flow.userFlowOut0
            );
            if (flow.previousUserFlowOut1 != flow.userFlowOut1) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut1
                );
            }
        }

        {
            // update fees totals
            feesTotal0Last = getRealTimeFeesTotal(address(token0));
            feesTotal1Last = getRealTimeFeesTotal(address(token1));

            // update recorded fees totals
            //int256 feesTotal0 = getRealTimeFeesTotal(address(token0));
            //int256 feesTotal1 = getRealTimeFeesTotal(address(token1));
            userPriceCumulatives[flow.user].initialFeesTotal0 = feesTotal0Last;
            userPriceCumulatives[flow.user].initialFeesTotal1 = feesTotal1Last;
            userPriceCumulatives[address(this)]
                .initialFeesTotal0 = feesTotal0Last;
            userPriceCumulatives[address(this)]
                .initialFeesTotal1 = feesTotal1Last;
        }

        // update fees flows
        feesFlow0 -=
            userPriceCumulatives[flow.user].flowIn1 -
            userPriceCumulatives[flow.user].flowOut0;
        feesFlow1 -=
            userPriceCumulatives[flow.user].flowIn0 -
            userPriceCumulatives[flow.user].flowOut1;
        feesFlow0 += flow.userFlowIn1 - flow.userFlowOut0;
        feesFlow1 += flow.userFlowIn0 - flow.userFlowOut1;

        // update liquidity accumulators
        liquidity0CumulativeLast = getRealTimeLiquidityCumulative(
            address(token0)
        );
        liquidity1CumulativeLast = getRealTimeLiquidityCumulative(
            address(token1)
        );

        // update liquidity flows
        liquidityFlow0 -= userPriceCumulatives[flow.user].liquidityFlow0;
        liquidityFlow1 -= userPriceCumulatives[flow.user].liquidityFlow1;
        liquidityFlow0 += flow.userLiquidityFlow0;
        liquidityFlow1 += flow.userLiquidityFlow1;
        userPriceCumulatives[flow.user].liquidityFlow0 = flow
            .userLiquidityFlow0;
        userPriceCumulatives[flow.user].liquidityFlow1 = flow
            .userLiquidityFlow1;

        // rebalance
        _update(
            flowIn0,
            flowIn1,
            address(_superToken) == address(token0)
                ? flow.userFlowIn0
                : int96(0),
            address(_superToken) == address(token1)
                ? flow.userFlowIn1
                : int96(0),
            flow.userFlowOut0 - flow.previousUserFlowOut0,
            flow.userFlowOut1 - flow.previousUserFlowOut1,
            flow.user
        );
    }

    function beforeAgreementUpdated(
        ISuperToken _superToken,
        address, // agreementClass
        bytes32, // agreementId
        bytes calldata, // agreementData
        bytes calldata _ctx
    )
        external
        view
        virtual
        override
        returns (
            bytes memory // cbdata
        )
    {
        // keep track of old flowRate to calc net change in afterAgreementTerminated
        address user = getUserFromCtx(_ctx);
        int96 flowRate = getFlowRateIn(_superToken, user);

        // get previous initial flow timestamps (in case balance needs to be manually settled)
        (uint256 initialTimestamp0, , , ) = cfa.getAccountFlowInfo(
            token0,
            user
        );
        (uint256 initialTimestamp1, , , ) = cfa.getAccountFlowInfo(
            token1,
            user
        );

        return abi.encode(flowRate, initialTimestamp0, initialTimestamp1);
    }

    // onlyExpected(_agreementClass)
    function afterAgreementUpdated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );

        // avoid stack too deep
        Flow memory flow;
        flow.user = getUserFromCtx(_ctx);

        flow.userFlowIn0 = getFlowRateIn(token0, flow.user);
        flow.userFlowIn1 = getFlowRateIn(token1, flow.user);

        flow.previousUserFlowOut0 = getFlowRateOut(token0, flow.user);
        flow.previousUserFlowOut1 = getFlowRateOut(token1, flow.user);

        (
            flow.previousUserFlowIn,
            flow.initialTimestamp0,
            flow.initialTimestamp1
        ) = abi.decode(_cbdata, (int96, uint256, uint256));

        // settle balances if necessary
        flow.forceSettleUserBalances =
            userPriceCumulatives[flow.user].flowOut0 ==
            userPriceCumulatives[flow.user].flowOut1;
        if (flow.forceSettleUserBalances) {
            token0.settleTwapBalance(flow.user, flow.initialTimestamp0);
            token1.settleTwapBalance(flow.user, flow.initialTimestamp1);
        }

        // update fees
        if (address(_superToken) == address(token0)) {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                flow.previousUserFlowIn, //abi.decode(_cbdata, (int96)),
                flow.userFlowIn1,
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        } else {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                flow.userFlowIn0,
                flow.previousUserFlowIn, //abi.decode(_cbdata, (int96)),
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        }

        // update flows
        if (address(_superToken) == address(token0)) {
            newCtx = cfaV1.updateFlowWithCtx(
                _ctx,
                flow.user,
                token1,
                flow.userFlowOut1
            );
            if (flow.previousUserFlowOut0 != flow.userFlowOut0) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut0
                );
            }
        } else {
            newCtx = cfaV1.updateFlowWithCtx(
                _ctx,
                flow.user,
                token0,
                flow.userFlowOut0
            );
            if (flow.previousUserFlowOut1 != flow.userFlowOut1) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut1
                );
            }
        }

        // rebalance
        _update(
            flowIn0,
            flowIn1,
            address(_superToken) == address(token0)
                ? flow.userFlowIn0 - flow.previousUserFlowIn //abi.decode(_cbdata, (int96))
                : int96(0),
            address(_superToken) == address(token1)
                ? flow.userFlowIn1 - flow.previousUserFlowIn //abi.decode(_cbdata, (int96))
                : int96(0),
            flow.userFlowOut0 - flow.previousUserFlowOut0,
            flow.userFlowOut1 - flow.previousUserFlowOut1,
            flow.user
        );

        // update cumualtives if necessary
        if (flow.forceSettleUserBalances) {
            userPriceCumulatives[flow.user]
                .price0Cumulative = price0CumulativeLast;
            userPriceCumulatives[flow.user]
                .price1Cumulative = price1CumulativeLast;
        }
    }

    function beforeAgreementTerminated(
        ISuperToken _superToken,
        address, // agreementClass
        bytes32, // agreementId
        bytes calldata, // agreementData
        bytes calldata _ctx
    )
        external
        view
        virtual
        override
        returns (
            bytes memory // cbdata
        )
    {
        // keep track of old flowRate to calc net change in afterAgreementTerminated
        address user = getUserFromCtx(_ctx);
        int96 flowRate = getFlowRateIn(_superToken, user);

        // get previous initial flow timestamps (in case balance needs to be manually settled)
        (uint256 initialTimestamp0, , , ) = cfa.getAccountFlowInfo(
            token0,
            user
        );
        (uint256 initialTimestamp1, , , ) = cfa.getAccountFlowInfo(
            token1,
            user
        );

        return abi.encode(flowRate, initialTimestamp0, initialTimestamp1);
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );

        // avoid stack too deep
        Flow memory flow;
        flow.user = getUserFromCtx(_ctx);

        flow.userFlowIn0 = getFlowRateIn(token0, flow.user);
        flow.userFlowIn1 = getFlowRateIn(token1, flow.user);

        flow.previousUserFlowOut0 = getFlowRateOut(token0, flow.user);
        flow.previousUserFlowOut1 = getFlowRateOut(token1, flow.user);

        (
            flow.previousUserFlowIn,
            flow.initialTimestamp0,
            flow.initialTimestamp1
        ) = abi.decode(_cbdata, (int96, uint256, uint256));

        // settle balances if necessary
        flow.forceSettleUserBalances =
            userPriceCumulatives[flow.user].flowOut0 ==
            userPriceCumulatives[flow.user].flowOut1;
        if (flow.forceSettleUserBalances) {
            token0.settleTwapBalance(flow.user, flow.initialTimestamp0);
            token1.settleTwapBalance(flow.user, flow.initialTimestamp1);
        }

        // update fees
        if (address(_superToken) == address(token0)) {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                flow.previousUserFlowIn, //abi.decode(_cbdata, (int96)),
                flow.userFlowIn1,
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        } else {
            (
                flow.userFlowOut0,
                flow.userFlowOut1,
                flow.userLiquidityFlow0,
                flow.userLiquidityFlow1
            ) = _updateFees(
                flowIn0,
                flowIn1,
                flow.userFlowIn0,
                flow.previousUserFlowIn, //abi.decode(_cbdata, (int96)),
                flow.userFlowIn0,
                flow.userFlowIn1,
                flow.user
            );
        }

        // update flows
        if (address(_superToken) == address(token0)) {
            newCtx = cfaV1.deleteFlowWithCtx(
                _ctx,
                address(this),
                flow.user,
                token1
            );
            if (flow.previousUserFlowOut0 != flow.userFlowOut0) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut0
                );
            }
        } else {
            newCtx = cfaV1.deleteFlowWithCtx(
                _ctx,
                address(this),
                flow.user,
                token0
            );
            if (flow.previousUserFlowOut1 != flow.userFlowOut1) {
                newCtx = cfaV1.updateFlowWithCtx(
                    newCtx,
                    flow.user,
                    _superToken,
                    flow.userFlowOut1
                );
            }
        }

        // rebalance
        _update(
            flowIn0,
            flowIn1,
            address(_superToken) == address(token0)
                ? flow.userFlowIn0 - flow.previousUserFlowIn //abi.decode(_cbdata, (int96))
                : int96(0),
            address(_superToken) == address(token1)
                ? flow.userFlowIn1 - flow.previousUserFlowIn //abi.decode(_cbdata, (int96))
                : int96(0),
            flow.userFlowOut0 - flow.previousUserFlowOut0,
            flow.userFlowOut1 - flow.previousUserFlowOut1,
            flow.user
        );

        // update cumualtives if necessary
        if (flow.forceSettleUserBalances) {
            userPriceCumulatives[flow.user]
                .price0Cumulative = price0CumulativeLast;
            userPriceCumulatives[flow.user]
                .price1Cumulative = price1CumulativeLast;
        }
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType() == CFA_ID;
    }

    modifier onlyHost() {
        require(
            msg.sender == address(cfaV1.host),
            "RedirectAll: support only one host"
        );
        _;
    }

    modifier onlyExpected(address agreementClass) {
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
    }
}
