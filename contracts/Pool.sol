// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperfluidToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "./libraries/UQ128x128.sol";
import "./interfaces/IAqueductHost.sol";
import "./interfaces/IAqueductToken.sol";

import "hardhat/console.sol";

contract Pool is SuperAppBase {
    using UQ128x128 for uint256;

    /**************************************************************************
     * Pool/SuperApp state
     *************************************************************************/

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
    uint256 token0IndexId;
    uint256 token1IndexId;
    uint256 token0RewardIndexId;
    uint256 token1RewardIndexId;

    constructor(ISuperfluid host) payable {
        assert(address(host) != address(0));

        _host = host;
        factory = msg.sender;

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

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

        // create indices
        token0IndexId = createIndex(_token0, address(this));
        token1IndexId = createIndex(_token1, address(this));
        token0RewardIndexId = createIndex(_token0, address(this));
        token1RewardIndexId = createIndex(_token1, address(this));
    }

    /**************************************************************************
     * DCFA state
     *************************************************************************/

    /* --- Index data --- */
    uint256 nextIndexId = 0;
    struct IndexData {
        uint32 blockTimestampLast;
        uint96 totalFlowRate;
        uint256 cumulativeLast; // encoded as a UQ128x128
        uint128 totalUnits;
        ISuperfluidToken token;
        address publisher;
    }
    mapping(uint256 => IndexData) internal indexData;

    /* --- Subscriber data --- */
    struct SubscriptionData {
        uint256 initialCumulative;
        uint128 units;
        uint256 iId;
    }
    struct SubscriptionEntries {
        mapping(uint256 => bool) exists;
        //mapping(uint256 => uint256) iIdToSubIndex;
        //SubscriptionData[] subscriptions;
        mapping(uint256 => SubscriptionData) subscriptions;
        uint256[] iIds;
    }
    // account => token => entries
    mapping(address => mapping(ISuperfluidToken => SubscriptionEntries))
        internal subscriberData;

    /* --- Publisher data --- */
    struct IndexEntries {
        mapping(uint256 => bool) exists;
        uint256[] iIds;
    }
    // account => token => entries
    mapping(address => mapping(ISuperfluidToken => IndexEntries))
        internal publisherData;

    /**************************************************************************
     * temp DCFA implementation
     *************************************************************************/

    function realtimeBalanceOf(
        ISuperfluidToken token,
        address account,
        uint256 time
    )
        external
        view
        returns (
            int256 dynamicBalance,
            uint256 deposit,
            uint256 owedDeposit
        )
    {
        // as a subscriber
        {
            uint256[] memory iIdList = subscriberData[account][token].iIds;

            for (uint32 i = 0; i < iIdList.length; ++i) {
                if (subscriberData[account][token].exists[iIdList[i]] == true) {
                    SubscriptionData memory sdata = subscriberData[account][
                        token
                    ].subscriptions[iIdList[i]];
                    IndexData memory idata = indexData[iIdList[i]];
                    uint256 realTimeCumulative = _getCumulativeAtTime(
                        time,
                        idata.blockTimestampLast,
                        idata.cumulativeLast,
                        idata.totalFlowRate,
                        idata.totalUnits
                    );
                    dynamicBalance =
                        dynamicBalance +
                        (
                            int256(
                                UQ128x128.decode(
                                    uint256(sdata.units) *
                                        (realTimeCumulative -
                                            sdata.initialCumulative)
                                )
                            )
                        );
                }
            }
        }

        // as a publisher
        {
            uint256[] memory iIdList = publisherData[account][token].iIds;

            for (uint32 i = 0; i < iIdList.length; ++i) {
                IndexData memory idata = indexData[iIdList[i]];
                uint256 realTimeCumulative = _getCumulativeAtTime(
                    time,
                    idata.blockTimestampLast,
                    idata.cumulativeLast,
                    idata.totalFlowRate,
                    idata.totalUnits
                );
                dynamicBalance =
                    dynamicBalance -
                    (
                        int256(
                            UQ128x128.decode(
                                uint256(idata.totalUnits) *
                                    (realTimeCumulative - idata.cumulativeLast)
                            )
                        )
                    );
            }
        }

        // TODO: design and implement deposits structure
        deposit = 0;
        owedDeposit = 0;
    }

    function createIndex(ISuperfluidToken token, address publisher)
        internal
        returns (uint256 iId)
    {
        // get next index / increment counter
        iId = nextIndexId;
        nextIndexId++;

        // add publisher
        require(publisherData[publisher][token].exists[iId] == false);
        publisherData[publisher][token].exists[iId] == true;
        publisherData[publisher][token].iIds.push(iId);
        indexData[iId].publisher = publisher;
        indexData[iId].token = token;
    }

    function updateFlowRate(uint256 iId, uint96 totalFlowRate) internal {
        IndexData memory idata = indexData[iId];

        // settle publisher balance
        uint256 realTimeCumulative = _getCumulativeAtTime(
            block.timestamp,
            idata.blockTimestampLast,
            idata.cumulativeLast,
            idata.totalFlowRate,
            idata.totalUnits
        );
        idata.token.settleBalance(
            idata.publisher,
            -1 *
                int256(
                    UQ128x128.decode(
                        uint256(idata.totalUnits) *
                            (realTimeCumulative - idata.cumulativeLast)
                    )
                )
        );

        // "settle" cumulative based on previous multiplier
        indexData[iId].cumulativeLast = realTimeCumulative;

        // update index
        indexData[iId].totalFlowRate = totalFlowRate;
        indexData[iId].blockTimestampLast = uint32(block.timestamp % 2**32);
    }

    function getIndexData(uint256 iId)
        public
        view
        returns (
            uint32 blockTimestampLast,
            uint96 totalFlowRate,
            uint256 cumulativeLast,
            uint128 totalUnits
        )
    {
        IndexData memory idata = indexData[iId];
        blockTimestampLast = idata.blockTimestampLast;
        totalFlowRate = idata.totalFlowRate;
        cumulativeLast = idata.cumulativeLast;
        totalUnits = idata.totalUnits;
    }

    function crudSubscription(
        uint256 iId,
        address account,
        uint128 units
    ) internal {
        IndexData memory idata = indexData[iId];
        if (units > 0) {
            if (subscriberData[account][idata.token].exists[iId] == false) {
                // create
                subscriberData[account][idata.token].iIds.push(iId);
                subscriberData[account][idata.token].exists[iId] = true;
            }

            // update
            _updateSubscription(iId, account, units);
        } else {
            // delete
            // TODO: find way to remove from sId list
            // TEMP: just set exist flag to false
            subscriberData[account][idata.token].exists[iId] = false;
            _updateSubscription(iId, account, 0);
        }
    }

    function _updateSubscription(
        uint256 iId,
        address account,
        uint128 units
    ) internal {
        IndexData memory idata = indexData[iId];
        SubscriptionData memory sdata = subscriberData[account][idata.token]
            .subscriptions[iId];

        // settle user's balance
        uint256 realTimeCumulative = _getCumulativeAtTime(
            block.timestamp,
            idata.blockTimestampLast,
            idata.cumulativeLast,
            idata.totalFlowRate,
            idata.totalUnits
        );
        idata.token.settleBalance(
            account,
            int256(
                UQ128x128.decode(
                    uint256(sdata.units) *
                        (realTimeCumulative - sdata.initialCumulative)
                )
            )
        );

        // settle publisher's balance
        idata.token.settleBalance(
            idata.publisher,
            -1 *
                int256(
                    UQ128x128.decode(
                        uint256(idata.totalUnits) *
                            (realTimeCumulative - idata.cumulativeLast)
                    )
                )
        );

        // settle index cumulative and update variables
        indexData[iId].cumulativeLast = _getCumulativeAtTime(
            block.timestamp,
            idata.blockTimestampLast,
            idata.cumulativeLast,
            idata.totalFlowRate,
            idata.totalUnits
        );
        indexData[iId].totalUnits -= sdata.units;
        indexData[iId].totalUnits += units;
        indexData[iId].blockTimestampLast = uint32(block.timestamp % 2**32);

        // update subscription
        subscriberData[account][idata.token].subscriptions[iId].units = units;
        subscriberData[account][idata.token]
            .subscriptions[iId]
            .initialCumulative = indexData[iId].cumulativeLast;
    }

    function getSubscriberData(
        ISuperfluidToken token,
        address account,
        uint256 iId
    ) public view returns (uint256 initialCumulative, uint128 units) {
        SubscriptionData memory sdata = subscriberData[account][token]
            .subscriptions[iId];
        initialCumulative = sdata.initialCumulative;
        units = sdata.units;
    }

    function _getCumulativeAtTime(
        uint256 timestamp,
        uint32 blockTimestampLast,
        uint256 cumulativeLast,
        uint96 totalFlowRate,
        uint128 totalUnits
    ) private pure returns (uint256 c) {
        c =
            cumulativeLast +
            (UQ128x128.encode(uint128(totalFlowRate)).uqdiv(totalUnits) *
                (timestamp - uint256(blockTimestampLast)));
    }

    /**************************************************************************
     * Superfluid callbacks
     *************************************************************************/

    struct SwapData {
        address user;
        uint256 tokenIId;
        uint256 oppTokenIId;
        uint256 tokenRewardIId;
        uint256 oppTokenRewardIId;
        uint128 tokenFlowIn;
        uint128 oppTokenFlowIn;
        uint128 poolTokenFlowIn;
        uint128 poolOppTokenFlowIn;
    }

    function _handleCallback(
        ISuperToken _superToken,
        bytes calldata _agreementData
    ) internal {
        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );

        SwapData memory sdata;
        (sdata.user, ) = abi.decode(_agreementData, (address, address));
        (
            sdata.tokenIId,
            sdata.oppTokenIId,
            sdata.tokenRewardIId,
            sdata.oppTokenRewardIId
        ) = getIndexIds(_superToken);
        (
            sdata.tokenFlowIn,
            sdata.oppTokenFlowIn,
            sdata.poolTokenFlowIn,
            sdata.poolOppTokenFlowIn
        ) = getTokenFlows(
            _superToken,
            address(_superToken) == address(token0) ? token1 : token0,
            sdata.user
        );

        // add user as subscriber (units == flow in)
        crudSubscription(sdata.oppTokenIId, sdata.user, sdata.tokenFlowIn);

        // if LP, add them as subscriber to rewards index (update for both tokens)
        uint256 rewardPercentage = getRewardPercentage(
            sdata.tokenFlowIn,
            sdata.oppTokenFlowIn,
            sdata.poolTokenFlowIn,
            sdata.poolOppTokenFlowIn
        );
        // safe downcast from uint256 to uint128 -> flowIn is uint128 and feePercentage <= 1
        crudSubscription(
            sdata.tokenRewardIId,
            sdata.user,
            uint128(UQ128x128.decode(sdata.oppTokenFlowIn * rewardPercentage))
        );
        crudSubscription(
            sdata.oppTokenRewardIId,
            sdata.user,
            uint128(UQ128x128.decode(sdata.tokenFlowIn * rewardPercentage))
        );

        // update total flow of incoming token
        updateFlowRate(
            sdata.tokenIId,
            (uint96(sdata.poolTokenFlowIn) * 99) / 100
        ); // this adds a 1% pool fee
        //updateFlowRate(sdata.tokenIId, uint96(sdata.poolTokenFlowIn));

        // update flow of rewards index
        updateFlowRate(
            sdata.tokenRewardIId,
            (uint96(sdata.poolTokenFlowIn) * 1) / 100
        ); // assuming 1% pool fee
    }

    function afterAgreementCreated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, //_agreementId
        bytes calldata _agreementData,
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        _handleCallback(_superToken, _agreementData);
        newCtx = _ctx;
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, // _agreementId,
        bytes calldata _agreementData,
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        _handleCallback(_superToken, _agreementData);
        newCtx = _ctx;
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, // _agreementId,
        bytes calldata _agreementData,
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        _handleCallback(_superToken, _agreementData);
        newCtx = _ctx;
    }

    /**************************************************************************
     * Helpers
     *************************************************************************/

    function getFlowRateIn(ISuperToken token, address user)
        internal
        view
        returns (uint128)
    {
        (, int96 flowRate, , ) = cfa.getFlow(token, user, address(this));
        return uint128(uint96(flowRate));
    }

    function getIndexIds(ISuperToken token)
        internal
        view
        returns (
            uint256 tokenIId,
            uint256 oppTokenIId,
            uint256 tokenRewardIId,
            uint256 oppTokenRewardIId
        )
    {
        if (address(token) == address(token0)) {
            tokenIId = token0IndexId;
            oppTokenIId = token1IndexId;
            tokenRewardIId = token0RewardIndexId;
            oppTokenRewardIId = token1RewardIndexId;
        } else {
            tokenIId = token1IndexId;
            oppTokenIId = token0IndexId;
            tokenRewardIId = token1RewardIndexId;
            oppTokenRewardIId = token0RewardIndexId;
        }
    }

    function getTokenFlows(
        ISuperToken token,
        ISuperToken oppToken,
        address user
    )
        internal
        view
        returns (
            uint128 tokenFlowIn,
            uint128 oppTokenFlowIn,
            uint128 poolTokenFlowIn,
            uint128 poolOppTokenFlowIn
        )
    {
        (, int96 _tokenFlowIn, , ) = cfa.getFlow(token, user, address(this));
        (, int96 _oppTokenFlowIn, , ) = cfa.getFlow(
            oppToken,
            user,
            address(this)
        );
        poolTokenFlowIn = uint128(uint96(cfa.getNetFlow(token, address(this))));
        poolOppTokenFlowIn = uint128(
            uint96(cfa.getNetFlow(oppToken, address(this)))
        );
        tokenFlowIn = uint128(uint96(_tokenFlowIn));
        oppTokenFlowIn = uint128(uint96(_oppTokenFlowIn));
    }

    function getRewardPercentage(
        uint128 tokenFlow,
        uint128 oppTokenFlow,
        uint128 poolTokenFlow,
        uint128 poolOppTokenFlow
    ) internal pure returns (uint256) {
        // handle special case
        if (oppTokenFlow == 0 || poolOppTokenFlow == 0) {
            return 0;
        }

        // TODO: check that int96 -> uint128 cast is safe - expected that a flow between sender and receiver will always be positive
        uint256 userRatio = UQ128x128.encode(tokenFlow).uqdiv(oppTokenFlow);
        uint256 poolRatio = UQ128x128.encode(poolTokenFlow).uqdiv(
            poolOppTokenFlow
        );

        if ((userRatio + poolRatio) == 0) {
            return 0;
        } else {
            return
                UQ128x128.Q128 -
                (difference(userRatio, poolRatio) / (userRatio + poolRatio));
        }
    }

    // computes the absolute difference between two unsigned values
    function difference(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x - y : y - x;
    }

    modifier onlyHost() {
        require(
            msg.sender == address(cfaV1.host),
            "RedirectAll: support only one host"
        );
        _;
    }

    /**************************************************************************
     * Getters
     *************************************************************************/

    function _getUserData(
        ISuperToken token,
        address account,
        uint256 time,
        uint256 iId
    )
        internal
        view
        returns (
            uint256 initialCumulative,
            uint256 realTimeCumulative,
            uint128 units
        )
    {
        (initialCumulative, units) = getSubscriberData(token, account, iId);

        (
            uint32 blockTimestampLast,
            uint96 totalFlowRate,
            uint256 cumulativeLast,
            uint128 totalUnits
        ) = getIndexData(iId);

        realTimeCumulative = _getCumulativeAtTime(
            time,
            blockTimestampLast,
            cumulativeLast,
            totalFlowRate,
            totalUnits
        );
    }

    function getUserSwapData(
        ISuperToken token,
        address account,
        uint256 time
    )
        external
        view
        returns (
            uint256 initialCumulative,
            uint256 realTimeCumulative,
            uint128 units
        )
    {
        (initialCumulative, realTimeCumulative, units) = _getUserData(
            token,
            account,
            time,
            address(token) == address(token0) ? token0IndexId : token1IndexId
        );
    }

    function getUserRewardData(
        ISuperToken token,
        address account,
        uint256 time
    )
        external
        view
        returns (
            uint256 initialCumulative,
            uint256 realTimeCumulative,
            uint128 units
        )
    {
        (initialCumulative, realTimeCumulative, units) = _getUserData(
            token,
            account,
            time,
            address(token) == address(token0)
                ? token0RewardIndexId
                : token1RewardIndexId
        );
    }
}
