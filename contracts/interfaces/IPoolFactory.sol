// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import "./IPool.sol";

interface IPoolFactory {
    function parameters()
        external
        view
        returns (
            ISuperfluid _host, ISuperToken _token0, ISuperToken _token1, uint112 _flowIn0, uint112 _flowIn1
        );

    function addAccountPool(address _account) external;

    function removeAccountPool(address _account, address _pool) external;

    function realtimeBalanceOf(
        int256 _agreementDynamicBalance,
        address _token,
        address _account,
        uint256 _timestamp,
        uint256 _initialTimestamp
    ) external view returns (int256 realtimeBalance);
}