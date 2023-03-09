// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import "./interfaces/IFlowScheduler.sol";
import "./gelato/OpsTaskCreator.sol";

contract DeleteFlowResolverTaskCreator is OpsTaskCreator {
    /// @notice address of deployed Flow Scheduler contract
    IFlowScheduler public flowScheduler;

    /// @notice address of deployed CFA contract
    IConstantFlowAgreementV1 public cfa;

    /// @notice ID for gelato task
    bytes32 public taskId;

    event DeleteFlowTaskCreated(bytes32 taskId);

    constructor(
        address _flowScheduler,
        IConstantFlowAgreementV1 _cfa,
        address payable _ops,
        address _fundsOwner
    ) OpsTaskCreator(_ops, _fundsOwner) {
        flowScheduler = IFlowScheduler(_flowScheduler);
        cfa = _cfa;
    }

    receive() external payable {}

    function createTask(
        address superToken,
        address sender,
        address receiver
    ) external payable {
        require(taskId == bytes32(""), "Already started task");

        ModuleData memory moduleData = ModuleData({
            modules: new Module[](2),
            args: new bytes[](2)
        });

        moduleData.modules[0] = Module.RESOLVER;
        moduleData.modules[1] = Module.PROXY;

        moduleData.args[0] = _resolverModuleArg(
            address(this),
            abi.encodeCall(this.checker, (superToken, sender, receiver))
        );
        moduleData.args[1] = _proxyModuleArg();

        bytes32 id = _createTask(
            address(this),
            abi.encode("executeDeleteFlow(ISuperToken,address,address)"),
            moduleData,
            ETH
        );

        taskId = id;
        emit DeleteFlowTaskCreated(id);
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

        // TODO: what effect do these strings have on gas?
        if (flowSchedule.endDate == 0)
            return (false, bytes("End date must be set"));
        if (block.timestamp <= flowSchedule.endDate)
            return (false, bytes("End date must be in the past"));
        if (currentFlowRate == 0) return (false, bytes("Flow should exist"));

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
}
