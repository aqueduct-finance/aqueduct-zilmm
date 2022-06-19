// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

contract SuperApp is SuperAppBase {

    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    ISuperfluid _host;

    /* --- Pool variables --- */
    ISuperToken private token0;
    ISuperToken private token1;

    constructor(
        ISuperfluid host
    ) payable {
        assert(address(host) != address(0));

        _host = host;
        token0 = ISuperToken(0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f); // fDAIx address (mumbai)
        token1 = ISuperToken(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4); // MATICx address (mumbai)

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP | // remove once added
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP; // remove once added

        host.registerApp(configWord);
    }

    /* --- Helper functions --- */

    function getOppositeToken(ISuperToken tokenIn) internal view returns (ISuperToken) {
        return address(tokenIn) == address(token0) ? token1 : token0;
    }
    

    /* --- Superfluid callbacks --- */

    //onlyExpected(_agreementClass)
    function afterAgreementCreated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata
        bytes calldata _ctx
    )
        external
        override
        onlyHost
        returns (bytes memory newCtx)
    {
        require(address(_superToken) == address(token0) || address(_superToken) == address(token1), "RedirectAll: token not in pool");
        // get address of wallet that initiated stream (msg.sender would just point to this contract)
        ISuperfluid.Context memory decompiledContext = _host.decodeCtx(_ctx);
        (, int96 flowRate, , ) = cfa.getFlow(
            _superToken,
            decompiledContext.msgSender,
            address(this)
        );

        // redirect stream of opposite token back to user and return new context
        // TODO: subtract fee from outgoing flow
        // TODO: calculate correct ratio for now flowRate
        // TODO: rebalance
        newCtx = cfaV1.createFlowWithCtx(_ctx, decompiledContext.msgSender, getOppositeToken(_superToken), flowRate);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        // TODO: rebalance after stream update / update stream of opposite token
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // TODO: rebalance after stream ends / cancel stream of opposite token

        //if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
        //    return _ctx;
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType() == CFA_ID;
    }

    modifier onlyHost() {
        require(
            msg.sender == address(cfaV1.host),
            "RedirectAll: support only one host"
        );
        _;
    }

    modifier onlyExpected(address agreementClass) {
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
    }
}
