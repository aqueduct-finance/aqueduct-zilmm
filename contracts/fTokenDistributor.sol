// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

contract fTokenDistributor {
    
    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Internal --- */
    uint256 _distDiscreteAmount;
    int96 _distFlowRate;
    ISuperToken _distToken;
    mapping(address => bool) private userAlreadyGotFunds;

    constructor(ISuperfluid host, ISuperToken distToken, uint256 distDiscreteAmount, int96 distFlowRate) payable {
        assert(address(host) != address(0));

        _host = host;
        _distFlowRate = distFlowRate;
        _distToken = distToken;
        _distDiscreteAmount = distDiscreteAmount;

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);
    }

    // Send small discrete amount and stream the rest
    function requestTokens()
        external
    {
        // only send a discrete amount once per user
        if (userAlreadyGotFunds[msg.sender] == false) {
            _distToken.transfer(msg.sender, _distDiscreteAmount);
            userAlreadyGotFunds[msg.sender] = true;
        }
        cfaV1.createFlow(msg.sender, _distToken, _distFlowRate);
    }
}
