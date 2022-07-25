// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IPoolFactory {
    function parameters()
        external
        view
        returns (
            ISuperfluid _host, ISuperToken _token0, ISuperToken _token1, uint112 _flowIn0, uint112 _flowIn1
        );
}