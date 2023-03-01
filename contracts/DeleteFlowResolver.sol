// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import "./interfaces/IFlowScheduler.sol";

contract DeleteFlowResolver {
    /// @notice address of deployed Flow Scheduler contract
    IFlowScheduler public flowScheduler;
    /// @notice address of deployed CFA contract
    IConstantFlowAgreementV1 public cfa;

    constructor(address _flowScheduler, IConstantFlowAgreementV1 _cfa) {
        flowScheduler = IFlowScheduler(_flowScheduler);
        cfa = _cfa;
    }

    /**
     * @dev Gelato resolver that checks whether a stream can be deleted
     * @notice Make sure ACL permissions and ERC20 approvals are set for `flowScheduler`
     *         before using Gelato automation with this resolver
     * @return bool whether there is a valid Flow Scheduler action to be taken or not
     * @return bytes the function payload to be executed (empty if none)
     */
    function checker(
        address superToken,
        address sender,
        address receiver
    ) external view returns (bool, bytes memory) {
        IFlowScheduler.FlowSchedule memory flowSchedule = flowScheduler
            .getFlowSchedule(superToken, sender, receiver);

        (, int96 currentFlowRate, , ) = cfa.getFlow(
            ISuperToken(superToken),
            sender,
            receiver
        );

        // 1. end date must be set (flow schedule exists)
        // 2. end date must have been past
        // 3. flow must have actually exist to be deleted
        if (
            flowSchedule.endDate != 0 &&
            block.timestamp >= flowSchedule.endDate &&
            currentFlowRate != 0
        ) {
            // return canExec as true and executeDeleteFlow payload
            return (
                true,
                abi.encodeCall(
                    IFlowScheduler.executeDeleteFlow,
                    (
                        ISuperToken(superToken),
                        sender,
                        receiver,
                        "" // not supporting user data
                    )
                )
            );
        }

        // return canExec as false and non-executable payload
        return (false, "0x");
    }
}
