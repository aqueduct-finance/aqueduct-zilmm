// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

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

    /**
        @return netFlowRate the net flow rate of the given token/address with respect to the aqueductHost contract
    */
    function getTwapNetFlowRate(address token, address user)
        external
        view
        returns (int96 netFlowRate);

    /**
        @return reward a user's reward for the specific token at the given timestamp
    */
    function getUserReward(
        address token,
        address user,
        uint256 timestamp
    ) external view returns (int256 reward);
}
