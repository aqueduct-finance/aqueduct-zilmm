// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "./libraries/UQ112x112.sol";
import "./interfaces/IAqueductHost.sol";

contract SuperApp is SuperAppBase, IAqueductHost {
    using UQ112x112 for uint224;

    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Pool variables --- */
    address public factory;
    ISuperToken public token0;
    ISuperToken public token1;

    uint112 private flowIn0;
    uint112 private flowIn1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    enum IncomingStreamType {
        SWAP,
        LIQUIDITY
    }

    // map user address to their starting price cumulatives
    struct UserPriceCumulative {
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }
    mapping(address => UserPriceCumulative) private userPriceCumulatives;

    constructor(ISuperfluid host) payable {
        assert(address(host) != address(0));

        _host = host;
        factory = msg.sender;
        //token0 = ISuperToken(0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f); // fDAIx address (mumbai) // TODO: set these using init function from a factory contract
        //token1 = ISuperToken(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4); // MATICx address (mumbai)

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;

        host.registerApp(configWord);
    }

    // called once by the factory at time of deployment
    function initialize(ISuperToken _token0, ISuperToken _token1, uint112 in0, uint112 in1) external {
        require(msg.sender == factory, "FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
        flowIn0 = in0;
        flowIn1 = in1;
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

    /* Gets address of wallet that initiated stream (msg.sender would just point to this contract) */
    function getParamsFromCtx(bytes calldata _ctx)
        internal
        view
        returns (IncomingStreamType streamType, address user)
    {
        ISuperfluid.Context memory decompiledContext = _host.decodeCtx(_ctx);
        streamType = abi.decode(
            decompiledContext.userData,
            (IncomingStreamType)
        );
        user = decompiledContext.msgSender;
    }

    function getUserFromCtx(bytes calldata _ctx)
        internal
        view
        returns (address user)
    {
        return _host.decodeCtx(_ctx).msgSender;
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
        uint112 _flowIn0 = flowIn0;
        uint112 _flowIn1 = flowIn1;

        pc0 = price0CumulativeLast;
        pc1 = price1CumulativeLast;
        if (_flowIn0 > 0 && _flowIn1 > 0) {
            pc0 += (uint256(UQ112x112.encode(_flowIn1).uqdiv(_flowIn0)) * timeElapsed);
            pc1 += (uint256(UQ112x112.encode(_flowIn0).uqdiv(_flowIn1)) * timeElapsed);
        }
    }

    function getRealTimeCumulatives()
        external
        view
        returns (uint256 pc0, uint256 pc1)
    {
        (pc0, pc1) = getCumulativesAtTime(block.timestamp);
    }

    function getUserCumulativeDelta(
        address token,
        address user,
        uint256 timestamp
    ) public view returns (uint256 cumulativeDelta) {
        if (token == address(token0)) {
            (uint256 S, ) = getCumulativesAtTime(timestamp);
            uint256 S0 = userPriceCumulatives[user].price0Cumulative;
            cumulativeDelta = UQ112x112.decode(S - S0);
        }
        if (token == address(token1)) {
            (, uint256 S) = getCumulativesAtTime(timestamp);
            uint256 S0 = userPriceCumulatives[user].price1Cumulative;
            cumulativeDelta = UQ112x112.decode(S - S0);
        }
    }

    function getRealTimeUserCumulativeDelta(address token, address user)
        external
        view
        returns (uint256 cumulativeDelta)
    {
        cumulativeDelta = getUserCumulativeDelta(token, user, block.timestamp);
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

            price0CumulativeLast +=
                uint256(UQ112x112.encode(flowIn1).uqdiv(flowIn0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint256(UQ112x112.encode(flowIn0).uqdiv(flowIn1)) *
                timeElapsed;

            // update user's price initial price cumulative
            // TODO: for update and termination, make sure balance is settled first
            if (relFlow0 != 0) {
                userPriceCumulatives[user]
                    .price1Cumulative = price1CumulativeLast;
            }
            if (relFlow1 != 0) {
                userPriceCumulatives[user]
                    .price0Cumulative = price0CumulativeLast;
            }
        }

        flowIn0 = relFlow0 < 0
                    ? flowIn0 - uint96(relFlow0)
                    : flowIn0 + uint96(relFlow0);

        flowIn1 = relFlow1 < 0
                    ? flowIn1 - uint96(relFlow1)
                    : flowIn1 + uint96(relFlow1);

        blockTimestampLast = blockTimestamp;
    }

    /* --- Superfluid callbacks --- */

    struct Flow {
        IncomingStreamType streamType;
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
        {
            /*
            (IncomingStreamType streamType, address user) = getParamsFromCtx(
                _ctx
            );
            flow.streamType = streamType;
            */

            flow.user = getUserFromCtx(_ctx);
        }
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
        return abi.encodePacked(flowRate);
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
        {
            (IncomingStreamType streamType, address user) = getParamsFromCtx(
                _ctx
            );
            flow.streamType = streamType;
            flow.user = user;
        }
        flow.flowRate = getFlowRate(_superToken, flow.user);
        flow.netFlowRate = abi.decode(_cbdata, (int96)) - flow.flowRate;

        // rebalance
        if (address(_superToken) == address(token0)) {
            _update(flowIn0, flowIn1, flow.netFlowRate, 0, flow.user);
        } else {
            _update(flowIn0, flowIn1, 0, flow.netFlowRate, flow.user);
        }

        // TODO: settle user's balance (look into how superfluid updates a stream)

        newCtx = cfaV1.updateFlowWithCtx(
            _ctx,
            flow.user,
            getOppositeToken(_superToken),
            flow.flowRate
        );
    }

    function beforeAgreementTerminated(
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
        // keep track of old flowRate to calc net change in afterAgreementTerminated
        address user = getUserFromCtx(_ctx);
        int96 flowRate = getFlowRate(_superToken, user);
        return abi.encodePacked(flowRate);
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
        {
            (IncomingStreamType streamType, address user) = getParamsFromCtx(
                _ctx
            );
            flow.streamType = streamType;
            flow.user = user;
        }
        flow.flowRate = getFlowRate(_superToken, flow.user);
        flow.netFlowRate = abi.decode(_cbdata, (int96)) - flow.flowRate;

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
