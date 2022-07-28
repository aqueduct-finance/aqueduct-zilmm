// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAqueductToken {
    function getUserPriceCumulatives(address user)
        external
        view
        returns (
            int96 netFlowRate,
            uint256 priceCumulative
        );

    function setUserPriceCumulatives(address user, address pool, uint256 priceCumulative) external;

    function setUserNetFlowRate(address user, address pool, int96 relativeFlowRate) external;
}