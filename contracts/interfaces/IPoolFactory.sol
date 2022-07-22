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

    /**
        @return cumulativeDelta computed as S - S0
    */
    function getUserCumulativeDelta(
        address targetToken,
        address oppositeToken,
        address user,
        uint256 timestamp
    ) external view returns (uint256 cumulativeDelta);

    /**
        @return netFlowRate the net flow rate of the given token/address with respect to the aqueductHost contract
    */
    function getTwapNetFlowRate(address targetToken, address oppositeToken, address user)
        external
        view
        returns (int96 netFlowRate);
}