// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IPool {
    function getTokenPair() external view returns (ISuperToken, ISuperToken);
    
    function getUserPriceCumulatives(address user)
        external
        view
        returns (
            int96 netFlowRate0,
            int96 netFlowRate1,
            uint256 price0Cumulative,
            uint256 price1Cumulative
        );

    /**
     * @return cumulativeDelta computed as S - S0
    */
    function getUserCumulativeDelta(address token, address user, uint256 timestamp) external view returns (uint256 cumulativeDelta);

    function getTwapNetFlowRate(address token, address user)
        external
        view
        returns (int96 netFlowRate);
}