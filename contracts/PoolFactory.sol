// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "hardhat/console.sol";

import {ISuperfluid, ISuperApp} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SafeCast} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperfluidToken.sol";

import "./interfaces/IPoolFactory.sol";
import "./SuperApp.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IAqueductToken.sol";

// PROBLEM //
// 1. Create mapping - user address to an array of pool addresses
// 2. Create a realtimeBalanceOf function that iterates over an array of pool addresses that a user is connected to
// 3. See comments on CustomSuperfluidToken.sol

contract PoolFactory is IPoolFactory {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct Parameters {
        ISuperfluid host;
        ISuperToken token0;
        ISuperToken token1;
        uint112 flowIn0;
        uint112 flowIn1;
    }

    struct AccountPoolList {
        IPool[10] pools;
        uint index;
    }

    Parameters public parameters;
    ISuperfluid public host;

    mapping(address => AccountPoolList) public accountPoolList;
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

    function realtimeBalanceOf(
        int256 _agreementDynamicBalance,
        address _token,
        address _account,
        uint256 _timestamp,
        uint256 _initialTimestamp
    ) external view returns (int256 realtimeBalance) {
        console.log("6. Entered realtimeBalanceOf function in PoolFactory.sol");
        console.log("_agreementDynamicBalance: ", uint256(_agreementDynamicBalance));
        console.log("_token: ", _token);
        console.log("_account: ", _account);
        console.log("_timestamp: ", _timestamp);
        console.log("_initialTimestamp: ", _initialTimestamp);

        AccountPoolList memory accountPools = accountPoolList[_account];

        address firstPool = address(accountPools.pools[0]);
        console.log("7. accountPools: ", firstPool);

        uint accountPoolsLength = accountPools.pools.length;
        console.log("8. accountPoolsLength: ", accountPoolsLength);

        // TODO: This array has a fixed length so this require statement will always pass
        require(accountPoolsLength > 0, "Aqueduct: NO_POOLS_ASSOCIATED");
        for (uint i = 0; i < accountPoolsLength; i++) {
            console.log("9. Entered realtimeBalanceOf for loop in PoolFactory.sol");
        
            int96 netFlowRate = accountPools.pools[i].getTwapNetFlowRate(_token, _account);
            console.log("netFlowRate: ", uint96(netFlowRate));

            uint256 cumulativeDelta = accountPools.pools[i].getUserCumulativeDelta(_token, _account, _timestamp);

            // modify balance to include TWAP streams
            _agreementDynamicBalance -=
                int256(netFlowRate) *
                (_timestamp - _initialTimestamp).toInt256();

            _agreementDynamicBalance +=
                (int256(netFlowRate) * int256(cumulativeDelta)) /
                2**112;
            
            realtimeBalance = _agreementDynamicBalance;
        }
    }

    /**
     * adds a pool to an account. This can be upto a maximum of 10
     * Increments the index so the function knows where to insert the next pool in the array.
    */
    function addAccountPool(address _account) external {
        require(accountPoolList[_account].pools.length <= 10, "Aqueduct: 10_POOL_LIMIT");
        AccountPoolList memory accountPools = accountPoolList[_account];
        accountPools.pools[accountPools.index] = IPool(msg.sender);
        accountPools.index++;
    }

    /**
     * removes a pool that is associated with an account
     * decrements the index so that the array does not fill up with unused pools
    */
    function removeAccountPool(address _account, address _pool) external {
        AccountPoolList memory accountPools = accountPoolList[_account];
        uint accountPoolsLength = accountPools.pools.length;

        IPool[10] memory pools = accountPools.pools;

        for (uint i = 0; i < accountPoolsLength; i++) {
            if (pools[i] == IPool(_pool)) {
                // i = the pool to delete
                for (uint x = i; x < accountPoolsLength - 1; x++) {
                    pools[x] = pools[x+1];
                }

                delete pools[accountPoolsLength - 1];
                accountPools.index--;
                break;  
            }
        }
    }
}