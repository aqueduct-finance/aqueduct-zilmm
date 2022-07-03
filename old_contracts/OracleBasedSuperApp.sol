// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./OracleLibrary.sol";

contract SuperApp is SuperAppBase {
    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Uniswap --- */
    IUniswapV3Factory public immutable uniswapFactory;

    /* --- Pool variables --- */
    ISuperToken public token0;
    ISuperToken public token1;
    int96 tokenRatio = 1; // tokenRatio = amount(token0) / amount(token1)
    address wmaticAddress = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;

    constructor(ISuperfluid host, address _uniswapFactory) payable {
        assert(address(host) != address(0));

        _host = host;
        token0 = ISuperToken(0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f); // fDAIx address (mumbai)
        token1 = ISuperToken(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4); // MATICx address (mumbai)

        uniswapFactory = IUniswapV3Factory(_uniswapFactory);

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP | // remove once added
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP; // remove once added

        host.registerApp(configWord);
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

    function getUnderlyingTokenSafe(ISuperToken token)
        internal
        view
        returns (address)
    {
        address underlyingToken = token.getUnderlyingToken();
        return underlyingToken == address(0) ? wmaticAddress : underlyingToken;
    }

    /* Gets address of wallet that initiated stream (msg.sender would just point to this contract) */
    function getUserFromCtx(bytes calldata _ctx)
        internal
        view
        returns (address)
    {
        //ISuperfluid.Context memory decompiledContext = _host.decodeCtx(_ctx);
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

    /* Oracle helper func */
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /* Interacts with Uniswap V3 price oracle */
    function estimateAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint128 _amountIn,
        uint32 _secondsAgo, // duration of the TWAP - Time-weighted average price
        uint24 _fee
    ) internal view returns (uint256 amountOut) {
        address pool = uniswapFactory.getPool(_tokenIn, _tokenOut, _fee);
        require(
            pool != address(0),
            string.concat(
                "Pool does not exist:  ",
                "Token:",
                Strings.toHexString(uint256(uint160(_tokenIn)), 20),
                "Token2:",
                Strings.toHexString(uint256(uint160(_tokenOut)), 20),
                "Pool:",
                Strings.toHexString(uint256(uint160(pool)), 20)
            )
        );

        // Some of this code is copied from the UniswapV3 Oracle library
        // we save gas by removing the code that calculates the harmonic mean liquidity
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 tick = int24(tickCumulativesDelta / int56(int32(_secondsAgo)));
        // Always round to negative infinity
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int56(int32(_secondsAgo)) != 0)
        ) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            _amountIn,
            _tokenIn,
            _tokenOut
        );
    }

    /* --- Pool functions --- */

    /* Converts the incoming flowRate into expected outgoing flowRate of the opposite token */
    function getOppositeFlowRate(ISuperToken tokenIn, int96 flowRate)
        internal
        view
        returns (int96)
    {
        /*
        return
            address(tokenIn) == address(token0)
                ? (flowRate / tokenRatio)
                : (flowRate * tokenRatio);
        */

        // TODO: calculate a global ratio in the rebalance function and use that here instead of this:
        uint32 secondsIn = 10;
        uint256 amountOut = estimateAmountOut(
            getUnderlyingTokenSafe(tokenIn),
            getUnderlyingTokenSafe(getOppositeToken(tokenIn)),
            uint128(uint96(flowRate)),
            secondsIn,
            3000
        );

        return int96(int256(amountOut));
    }

    /* 
        The primary function for updating the pool
        Should be called on every stream update / periodically by a keeper
        
        Serves two functions:
            1) Update tokenRatio variable for determining stream ratio (use price oracle)
            2) Interface with Uniswap to ensure that pool's token amounts match correct ratio
    */
    function rebalance() public {
        // TODO: this is not finished / tested, do that and add rebalance function to all SF callbacks
        // Update ratio
        uint32 secondsIn = 10;
        uint128 amountIn = 100000000000000000000;
        uint256 amountOut = estimateAmountOut(
            token0.getUnderlyingToken(),
            token1.getUnderlyingToken(),
            amountIn,
            secondsIn,
            3000
        );
        tokenRatio = int96(int256(amountIn / amountOut));
    }

    /* --- Superfluid callbacks --- */

    struct Flow {
        address user;
        int96 flowRate;
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

        Flow memory flow;
        flow.user = getUserFromCtx(_ctx);
        flow.flowRate = getFlowRate(_superToken, flow.user);

        // redirect stream of opposite token back to user and return new context
        // TODO: subtract fee from outgoing flow
        // TODO: calculate correct ratio for new flowRate
        // TODO: rebalance
        newCtx = cfaV1.createFlowWithCtx(
            _ctx,
            flow.user,
            getOppositeToken(_superToken),
            getOppositeFlowRate(_superToken, flow.flowRate)
        );
    }

    // onlyExpected(_agreementClass)
    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );
        address user = getUserFromCtx(_ctx);
        int96 flowRate = getFlowRate(_superToken, user);

        newCtx = cfaV1.updateFlowWithCtx(
            _ctx,
            user,
            getOppositeToken(_superToken),
            flowRate
        );
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // TODO: rebalance after stream ends

        //if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
        //    return _ctx;

        require(
            address(_superToken) == address(token0) ||
                address(_superToken) == address(token1),
            "RedirectAll: token not in pool"
        );
        address user = getUserFromCtx(_ctx);

        newCtx = cfaV1.deleteFlowWithCtx(
            _ctx,
            address(this),
            user,
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
