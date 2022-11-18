// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Interface of the Aqueduct host contract
 */
interface IAqueductHost {
    /**
        @return cumulativeDelta computed as S - S0
    */
    function getUserCumulativeDelta(
        address token,
        address user,
        uint256 timestamp
    ) external view returns (uint256 cumulativeDelta);
}
