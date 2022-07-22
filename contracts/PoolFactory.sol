// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperApp} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import "./interfaces/IPoolFactory.sol";
import "./SuperApp.sol";
import "./interfaces/IPool.sol";

contract PoolFactory is IPoolFactory {
    struct Parameters {
        ISuperfluid host;
        ISuperToken token0;
        ISuperToken token1;
        uint112 flowIn0;
        uint112 flowIn1;
    }

    Parameters public parameters;
    ISuperfluid public host;

    mapping(address => mapping(address => address)) public getPool;

    event PoolCreated(address _token0, address _token1, address _pool);

    constructor(ISuperfluid _host) {
        host = _host;
    }

    function createPool(
        address _tokenA,
        address _tokenB,
        uint112 _flowIn0,
        uint112 _flowIn1
    ) external returns (address pool) {
        require(_tokenA != _tokenB, "Aqueduct: IDENTICAL_ADDRESSES");
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(token0 != address(0), 'Aqueduct: ZERO_ADDRESS');
        require(getPool[token0][token1] == address(0), 'Aqueduct: POOL_EXISTS');

        ISuperToken superToken0 = ISuperToken(token0); // TODO: is it safe to cast from address to ISuperToken?
        ISuperToken superToken1 = ISuperToken(token1);

        // parameters are passed to the pool this way to avoid having constructor arguments in the pool contract, which results in the init 
        // code hash of the pool being constant allowing the CREATE2 address of the pool to be cheaply computed on-chain
        parameters = Parameters({host: host, token0: superToken0, token1: superToken1, flowIn0: _flowIn0, flowIn1: _flowIn1});
        // TODO: RESEARCH CLONE FACTORY PATTERN TO SAVE GAS COSTS
        // This syntax is a newer way to invoke create2 without assembly, you just need to pass salt
        pool = address(new SuperApp{salt: keccak256(abi.encode(host, superToken0, superToken1, _flowIn0, _flowIn1))}());
        delete parameters;

        getPool[token0][token1] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0] = pool;
        emit PoolCreated(token0, token1, pool);
    }

    // TODO: move to dedicated Aqueduct Host contract
    function getUserCumulativeDelta(
        address targetToken,
        address oppositeToken,
        address user,
        uint256 timestamp
    ) public view returns (uint256 cumulativeDelta) {
        address pool = getPool[targetToken][oppositeToken];
        require(getPool[targetToken][oppositeToken] != address(0), 'Aqueduct: POOL_DOESNT_EXIST');

        (, , uint256 price0Cumulative, uint256 price1Cumulative) = IPool(pool).getUserPriceCumulatives(user);
        (ISuperToken token0, ISuperToken token1) = IPool(pool).getTokenPair();

        if (targetToken == address(token0)) {
            (uint256 S, ) = IPool(pool).getCumulativesAtTime(timestamp);
            uint256 S0 = price0Cumulative;
            cumulativeDelta = UQ112x112.decode(S - S0);
            cumulativeDelta = S - S0;
        } else if (targetToken == address(token1)) {
            (, uint256 S) = IPool(pool).getCumulativesAtTime(timestamp);
            uint256 S0 = price1Cumulative;
            cumulativeDelta = UQ112x112.decode(S - S0);
            cumulativeDelta = S - S0;
        }
    }

    // TODO: move to dedicated Aqueduct Host contract
    function getRealTimeUserCumulativeDelta(
        address targetToken,
        address oppositeToken,
        address user
    )
        external
        view
        returns (uint256 cumulativeDelta)
    {
        cumulativeDelta = getUserCumulativeDelta(targetToken, oppositeToken, user, block.timestamp);
    }

    // TODO: move to dedicated Aqueduct Host contract
    function getTwapNetFlowRate(
        address targetToken,
        address oppositeToken,
        address user
    )
        external
        view
        returns (int96 netFlowRate)
    {
        address pool = getPool[targetToken][oppositeToken];
        require(getPool[targetToken][oppositeToken] != address(0), 'Aqueduct: POOL_DOESNT_EXIST');

        (int96 netFlowRate0, int96 netFlowRate1, , ) = IPool(pool).getUserPriceCumulatives(user);
        (ISuperToken token0, ISuperToken token1) = IPool(pool).getTokenPair();

        if (targetToken == address(token0)) {
            netFlowRate = netFlowRate0;
        } else if (targetToken == address(token1)) {
            netFlowRate = netFlowRate1;
        }
    }
}