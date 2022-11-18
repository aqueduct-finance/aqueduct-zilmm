// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

/**
 * @title Aqueduct token interface
 * @author Aqueduct
 */
interface IAqueductToken is ISuperToken {
    /// @dev settles twap balance; can only be called by token or aqueduct host
    function settleTwapBalance(address account, uint256 initialTimestamp)
        external;
    //function settleTwapBalance(address account, uint256 initialTimestamp) external;
}
