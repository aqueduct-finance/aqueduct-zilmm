// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "./libraries/UQ112x112.sol";
import "./interfaces/IPoolFactory.sol";

contract SuperApp is SuperAppBase {
    using UQ112x112 for uint224;

    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid host;

    /* --- Pool variables --- */
    ISuperToken public immutable token0;
    ISuperToken public immutable token1;

    uint112 private flowIn0;
    uint112 private flowIn1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    // map user address to their starting price cumulatives
    struct UserPriceCumulative {
        int96 netFlowRate0;
        int96 netFlowRate1;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }
    mapping(address => UserPriceCumulative) public userPriceCumulatives;

    constructor() payable {
        (host, token0, token1, flowIn0, flowIn1) = IPoolFactory(msg.sender).parameters();
        assert(address(host) != address(0));

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;

        host.registerApp(configWord);
    }

    /* --- Helper functions --- */

    function getTokenPair() external view returns (ISuperToken, ISuperToken) {
        return (token0, token1);
    }

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
        return host.decodeCtx(_ctx).msgSender;
    }

    /* Gets the incoming flowRate for a given supertoken/user */
    function getFlowRate(ISuperToken token, address user)
        internal
        view
        returns (int96)
    {
        (, int96 flowRate, , ) = cfa.getFlow(token, user, address(this));

        return flowRate;
    }

    /* --- Pool functions --- */

    function getFlows()
        public
        view
        returns (
            uint112 _flowIn0,
            uint112 _flowIn1,
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
        returns (
            int96 netFlowRate0,
            int96 netFlowRate1,
            uint256 price0Cumulative,
            uint256 price1Cumulative
        )
    {
        UserPriceCumulative memory upc = userPriceCumulatives[user];
        netFlowRate0 = upc.netFlowRate0;
        netFlowRate1 = upc.netFlowRate1;
        price0Cumulative = upc.price0Cumulative;
        price1Cumulative = upc.price1Cumulative;
    }

    function getCumulativesAtTime(uint256 timestamp)
        public
        view
        returns (uint256 pc0, uint256 pc1)
    {
        uint32 timestamp32 = uint32(timestamp % 2**32);
        uint32 timeElapsed = timestamp32 - blockTimestampLast;
        uint112 _flowIn0 = flowIn0;
        uint112 _flowIn1 = flowIn1;

        pc0 = price0CumulativeLast;
        pc1 = price1CumulativeLast;
        if (_flowIn0 > 0 && _flowIn1 > 0) {
            pc1 += (uint256(UQ112x112.encode(_flowIn1).uqdiv(_flowIn0)) *
                timeElapsed);
            pc0 += (uint256(UQ112x112.encode(_flowIn0).uqdiv(_flowIn1)) *
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

    // function getUserCumulativeDelta(
    //     address token,
    //     address user,
    //     uint256 timestamp
    // ) public view returns (uint256 cumulativeDelta) {
    //     if (token == address(token0)) {
    //         (uint256 S, ) = getCumulativesAtTime(timestamp);
    //         uint256 S0 = userPriceCumulatives[user].price0Cumulative;
    //         cumulativeDelta = UQ112x112.decode(S - S0);
    //         cumulativeDelta = S - S0;
    //     } else if (token == address(token1)) {
    //         (, uint256 S) = getCumulativesAtTime(timestamp);
    //         uint256 S0 = userPriceCumulatives[user].price1Cumulative;
    //         cumulativeDelta = UQ112x112.decode(S - S0);
    //         cumulativeDelta = S - S0;
    //     }
    // }

    // function getRealTimeUserCumulativeDelta(address token, address user)
    //     external
    //     view
    //     returns (uint256 cumulativeDelta)
    // {
    //     cumulativeDelta = getUserCumulativeDelta(token, user, block.timestamp);
    // }

    // function getTwapNetFlowRate(address token, address user)
    //     external
    //     view
    //     returns (int96 netFlowRate)
    // {
    //     if (token == address(token0)) {
    //         netFlowRate = userPriceCumulatives[user].netFlowRate0;
    //     } else if (token == address(token1)) {
    //         netFlowRate = userPriceCumulatives[user].netFlowRate1;
    //     }
    // }

    function safeUnsignedAdd(uint112 a, int96 b)
        internal
        pure
        returns (uint112)
    {
        // TODO: this can still technically underflow, add try/catch?
        // This is used for computing pool net flow, which should never be < 0
        return b < 0 ? a - uint96(b * -1) : a + uint96(b);
    }

    // update flow reserves and, on the first call per block, price accumulators
    function _update(
        uint112 _flowIn0,
        uint112 _flowIn1,
        int96 relFlow0,
        int96 relFlow1,
        address user
    ) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (flowIn0 != 0 && flowIn1 != 0) {
            if (timeElapsed <= 0) {
                timeElapsed = 0;
            }

            price1CumulativeLast +=
                uint256(UQ112x112.encode(flowIn1).uqdiv(flowIn0)) *
                timeElapsed;
            price0CumulativeLast +=
                uint256(UQ112x112.encode(flowIn0).uqdiv(flowIn1)) *
                timeElapsed;

            // update user's price initial price cumulative
            if (relFlow0 != 0) {
                userPriceCumulatives[user]
                    .price1Cumulative = price1CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price1Cumulative = price1CumulativeLast;
            }
            if (relFlow1 != 0) {
                userPriceCumulatives[user]
                    .price0Cumulative = price0CumulativeLast;
                userPriceCumulatives[address(this)]
                    .price0Cumulative = price0CumulativeLast;
            }
        }

        if (relFlow0 != 0) {
            userPriceCumulatives[user].netFlowRate1 += relFlow0;
            userPriceCumulatives[address(this)].netFlowRate1 -= relFlow0;
        }
        if (relFlow1 != 0) {
            userPriceCumulatives[user].netFlowRate0 += relFlow1;
            userPriceCumulatives[address(this)].netFlowRate0 -= relFlow1;
        }
        
        flowIn0 = safeUnsignedAdd(flowIn0, relFlow0);
        flowIn1 = safeUnsignedAdd(flowIn1, relFlow1);

        blockTimestampLast = blockTimestamp;
    }

    /* --- Superfluid callbacks --- */

    struct Flow {
        address user;
        int96 flowRate;
        int96 netFlowRate;
    }

    //onlyExpected(_agreementClass)
    function afterAgreementCreated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata
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
        flow.flowRate = getFlowRate(_superToken, flow.user);

        //(uint112 _flowIn0, uint112 _flowIn1,) = getFlows(); // gas savings TODO: we can optimize here by loading storage vars into stack, but we also need to avoid stack too deep errors

        // rebalance
        if (address(_superToken) == address(token0)) {
            _update(flowIn0, flowIn1, flow.flowRate, 0, flow.user);
        } else {
            _update(flowIn0, flowIn1, 0, flow.flowRate, flow.user);
        }

        // redirect stream of opposite token back to user and return new context
        // TODO: subtract fee from outgoing flow
        newCtx = cfaV1.createFlowWithCtx(
            _ctx,
            flow.user,
            getOppositeToken(_superToken),
            flow.flowRate
        );
        //newCtx = _ctx;
    }

    function beforeAgreementUpdated(
        ISuperToken _superToken,
        address, /*agreementClass*/
        bytes32, /*agreementId*/
        bytes calldata, /*agreementData*/
        bytes calldata _ctx
    )
        external
        view
        virtual
        override
        returns (
            bytes memory /*cbdata*/
        )
    {
        // keep track of old flowRate to calc net change in afterAgreementUpdated
        address user = getUserFromCtx(_ctx);
        int96 flowRate = getFlowRate(_superToken, user);
        return abi.encode(flowRate);
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
        flow.flowRate = getFlowRate(_superToken, flow.user);
        flow.netFlowRate = flow.flowRate - abi.decode(_cbdata, (int96));

        // rebalance
        if (address(_superToken) == address(token0)) {
            _update(flowIn0, flowIn1, flow.netFlowRate, 0, flow.user);
        } else {
            _update(flowIn0, flowIn1, 0, flow.netFlowRate, flow.user);
        }

        newCtx = cfaV1.updateFlowWithCtx(
            _ctx,
            flow.user,
            getOppositeToken(_superToken),
            flow.flowRate
        );
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
        int96 flowRate = getFlowRate(_superToken, user);
        return abi.encode(flowRate);
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
        flow.flowRate = getFlowRate(_superToken, flow.user);
        flow.netFlowRate = flow.flowRate - abi.decode(_cbdata, (int96));

        // rebalance
        if (address(_superToken) == address(token0)) {
            _update(flowIn0, flowIn1, flow.netFlowRate, 0, flow.user);
        } else {
            _update(flowIn0, flowIn1, 0, flow.netFlowRate, flow.user);
        }

        newCtx = cfaV1.deleteFlowWithCtx(
            _ctx,
            address(this),
            flow.user,
            getOppositeToken(_superToken)
        );
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
