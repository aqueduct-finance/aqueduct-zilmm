// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

contract fTokenDistributor {
    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Internal --- */
    uint256 _distDiscreteAmount;
    int96 _distFlowRate;
    ISuperToken _distToken0;
    ISuperToken _distToken1;
    mapping(address => ISuperToken) private userTokenAssignment;
    address middleAddress = 0x80000000FBAfb48D033b9f14Fa49F38000000000; // roughly the middle address in (0, max_address)

    constructor(
        ISuperfluid host,
        ISuperToken distToken0,
        ISuperToken distToken1,
        uint256 distDiscreteAmount,
        int96 distFlowRate
    ) payable {
        assert(address(host) != address(0));

        _host = host;
        _distFlowRate = distFlowRate;
        _distToken0 = distToken0;
        _distToken1 = distToken1;
        _distDiscreteAmount = distDiscreteAmount;

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);
    }

    // Send small discrete amount and stream the rest
    function requestTokens() external {
        // only send a discrete amount once per user
        if (address(userTokenAssignment[msg.sender]) == address(0)) {
            // "randomly" assign token based on sender address
            ISuperToken userToken = msg.sender > middleAddress
                ? _distToken0
                : _distToken1;
            userTokenAssignment[msg.sender] = userToken;
            userToken.transfer(msg.sender, _distDiscreteAmount);
        }
        cfaV1.createFlow(
            msg.sender,
            userTokenAssignment[msg.sender],
            _distFlowRate
        );
    }
}
