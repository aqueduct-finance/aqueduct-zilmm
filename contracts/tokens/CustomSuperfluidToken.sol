// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.14;

import "hardhat/console.sol";

import {ISuperfluid, ISuperAgreement, ISuperfluidGovernance, ISuperfluidToken, SafeCast, EventsEmitter, FixedSizeData} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperfluidToken.sol";
import {IERC20} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ERC777Helper} from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC777Helper.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import "./../interfaces/IPoolFactory.sol";

/**
 * @title Superfluid's token implementation
 *
 * @author Superfluid
 */
abstract contract CustomSuperfluidToken is ISuperfluidToken {
    bytes32 private constant _REWARD_ADDRESS_CONFIG_KEY =
        keccak256("org.superfluid-finance.superfluid.rewardAddress");

    using SafeCast for uint256;
    using SafeCast for int256;
    using ERC777Helper for ERC777Helper.Operators;

    /// @dev Superfluid contract
    ISuperfluid internal immutable _host;

    /// @dev Active agreement bitmap
    mapping(address => uint256) internal _inactiveAgreementBitmap;

    /// @dev Settled balance for the account
    mapping(address => int256) internal _balances;

    /// @dev Total supply
    uint256 internal _totalSupply;

    // NOTE: for future compatibility, these are reserved solidity slots
    // The sub-class of SuperfluidToken solidity slot will start after _reserve13
    uint256 internal _reserve4;
    uint256 private _reserve5;
    uint256 private _reserve6;
    uint256 private _reserve7;
    uint256 private _reserve8;
    uint256 private _reserve9;
    uint256 private _reserve10;
    uint256 private _reserve11;
    uint256 private _reserve12;
    uint256 internal _reserve13;

    /// @dev The underlying ERC20 token
    IERC20 internal _underlyingToken;

    /// @dev Decimals of the underlying token
    uint8 internal _underlyingDecimals;

    /// @dev TokenInfo Name property
    string internal _name;

    /// @dev TokenInfo Symbol property
    string internal _symbol;

    /// @dev ERC20 Allowances Storage
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @dev ERC777 operators support data
    ERC777Helper.Operators internal _operators;

    // NOTE: for future compatibility, these are reserved solidity slots
    // The sub-class of SuperToken solidity slot will start after _reserve22
    uint256 internal _reserve22;
    uint256 private _reserve23;
    uint256 private _reserve24;
    uint256 private _reserve25;
    uint256 private _reserve26;
    uint256 private _reserve27;
    uint256 private _reserve28;
    uint256 private _reserve29;
    uint256 private _reserve30;
    uint256 internal _reserve31;

    // Aqueduct host contract
    IPoolFactory internal immutable _poolFactory;

    constructor(ISuperfluid host, IPoolFactory aqueductHost) {
        _host = host;
        _poolFactory = aqueductHost;
    }

    /// @dev ISuperfluidToken.getHost implementation
    function getHost()
        external
        view
        override(ISuperfluidToken)
        returns (address host)
    {
        return address(_host);
    }

    /**************************************************************************
     * Real-time balance functions
     *************************************************************************/

    /// @dev ISuperfluidToken.realtimeBalanceOf implementation
    function realtimeBalanceOf(address account, uint256 timestamp)
        public
        view
        override
        returns (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit
        )
    {
        console.log("3. Entered realtimeBalanceOf function in CustomSuperfluidToken.sol");
        availableBalance = _balances[account];
        ISuperAgreement[] memory activeAgreements = getAccountActiveAgreements(
            account
        );
        for (uint256 i = 0; i < activeAgreements.length; i++) {
            // get regular balance
            console.log("4. Entered realtimeBalanceOf for loop in CustomSuperfluidToken.sol");
            (
                int256 agreementDynamicBalance,
                uint256 agreementDeposit,
                uint256 agreementOwedDeposit
            ) = activeAgreements[i].realtimeBalanceOf(this, account, timestamp);

            // only apply custom functionality for CFA
            // TODO: find a way to check if activeAgreements[i] is CFA (the code below assumes that activeAgreements[0] is CFA)
            if (i == 0) {
                // get account's flow timestamp
                (uint256 initialTimestamp, , , ) = IConstantFlowAgreementV1(
                    address(
                        _host.getAgreementClass(
                            keccak256(
                                "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
                            )
                        )
                    )
                ).getAccountFlowInfo(this, account);
                console.log("5. Get initialTimestamp from cfa in CustomSuperfluidToken.sol. initialTimestamp: ", initialTimestamp);

                int256 realtimeBalance = _poolFactory.realtimeBalanceOf(
                    agreementDynamicBalance,
                    address(this),
                    account,
                    timestamp,
                    initialTimestamp
                );
                console.log("Retrieved realtimeBalance from PoolFactory.sol in CustomSuperfluidToken.sol");

                agreementDynamicBalance = realtimeBalance;

                // 1. Move these blocks to the factory
                // 2. Do this for each stream and then add the values together
                // 3. Set result to agreementDynamicBalance
                // modify balance to include TWAP streams
            }

            deposit = deposit + agreementDeposit;
            owedDeposit = owedDeposit + agreementOwedDeposit;
            // 1. Available Balance = Dynamic Balance - Max(0, Deposit - OwedDeposit)
            // 2. Deposit should not be shared between agreements
            availableBalance =
                availableBalance +
                agreementDynamicBalance -
                (
                    agreementDeposit > agreementOwedDeposit
                        ? (agreementDeposit - agreementOwedDeposit)
                        : 0
                ).toInt256();
        }
    }

    // not currently used
    function twapBalanceOf(
        address account,
        uint256 mostRecentCumulative,
        uint256 userEnterPoolCumulative
    ) public view returns (uint256 balance) {
        // formula: B=r*(S-S0)
        // Where B is the balance and r is the flowrate
        // Where S is most recent cumulative
        // Where S0 is recorded cumulative from when user entered the pool

        uint96 flowRate; // call getAgreementStateSlot here. We will need to decode the result

        balance =
            uint256(uint96(flowRate)) *
            (mostRecentCumulative - userEnterPoolCumulative);
    }

    /// @dev ISuperfluidToken.realtimeBalanceOfNow implementation
    function realtimeBalanceOfNow(address account)
        public
        view
        override
        returns (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit,
            uint256 timestamp
        )
    {
        console.log("2. Entered realtimeBalanceOfNow function in CustomSuperfluidToken.sol");
        timestamp = _host.getNow();
        (availableBalance, deposit, owedDeposit) = realtimeBalanceOf(
            account,
            timestamp
        );
    }

    function isAccountCritical(address account, uint256 timestamp)
        public
        view
        override
        returns (bool isCritical)
    {
        (int256 availableBalance, , ) = realtimeBalanceOf(account, timestamp);
        return availableBalance < 0;
    }

    function isAccountCriticalNow(address account)
        external
        view
        override
        returns (bool isCritical)
    {
        return isAccountCritical(account, _host.getNow());
    }

    function isAccountSolvent(address account, uint256 timestamp)
        public
        view
        override
        returns (bool isSolvent)
    {
        (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit
        ) = realtimeBalanceOf(account, timestamp);
        // Available Balance = Realtime Balance - Max(0, Deposit - OwedDeposit)
        int256 realtimeBalance = availableBalance +
            (deposit > owedDeposit ? (deposit - owedDeposit) : 0).toInt256();
        return realtimeBalance >= 0;
    }

    function isAccountSolventNow(address account)
        external
        view
        override
        returns (bool isSolvent)
    {
        return isAccountSolvent(account, _host.getNow());
    }

    /// @dev ISuperfluidToken.getAccountActiveAgreements implementation
    function getAccountActiveAgreements(address account)
        public
        view
        override
        returns (ISuperAgreement[] memory)
    {
        return _host.mapAgreementClasses(~_inactiveAgreementBitmap[account]);
    }

    /**************************************************************************
     * Token implementation helpers
     *************************************************************************/

    function _mint(address account, uint256 amount) internal {
        _balances[account] = _balances[account] + amount.toInt256();
        _totalSupply = _totalSupply + amount;
    }

    function _burn(address account, uint256 amount) internal {
        (int256 availableBalance, , ) = realtimeBalanceOf(
            account,
            _host.getNow()
        );
        require(
            availableBalance >= amount.toInt256(),
            "SuperfluidToken: burn amount exceeds balance"
        );
        _balances[account] = _balances[account] - amount.toInt256();
        _totalSupply = _totalSupply - amount;
    }

    function _move(
        address from,
        address to,
        int256 amount
    ) internal {
        (int256 availableBalance, , ) = realtimeBalanceOf(from, _host.getNow());
        require(
            availableBalance >= amount,
            "SuperfluidToken: move amount exceeds balance"
        );
        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount;
    }

    function _getRewardAccount() internal view returns (address rewardAccount) {
        ISuperfluidGovernance gov = _host.getGovernance();
        rewardAccount = gov.getConfigAsAddress(
            _host,
            this,
            _REWARD_ADDRESS_CONFIG_KEY
        );
    }

    /**************************************************************************
     * Super Agreement hosting functions
     *************************************************************************/

    /// @dev ISuperfluidToken.createAgreement implementation
    function createAgreement(bytes32 id, bytes32[] calldata data)
        external
        override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        require(
            !FixedSizeData.hasData(slot, data.length),
            "SuperfluidToken: agreement already created"
        );
        FixedSizeData.storeData(slot, data);
        emit AgreementCreated(agreementClass, id, data);
    }

    /// @dev ISuperfluidToken.getAgreementData implementation
    function getAgreementData(
        address agreementClass,
        bytes32 id,
        uint256 dataLength
    ) external view override returns (bytes32[] memory data) {
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        data = FixedSizeData.loadData(slot, dataLength);
    }

    /// @dev ISuperfluidToken.updateAgreementData implementation
    function updateAgreementData(bytes32 id, bytes32[] calldata data)
        external
        override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        FixedSizeData.storeData(slot, data);
        emit AgreementUpdated(msg.sender, id, data);
    }

    /// @dev ISuperfluidToken.terminateAgreement implementation
    function terminateAgreement(bytes32 id, uint256 dataLength)
        external
        override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        require(
            FixedSizeData.hasData(slot, dataLength),
            "SuperfluidToken: agreement does not exist"
        );
        FixedSizeData.eraseData(slot, dataLength);
        emit AgreementTerminated(msg.sender, id);
    }

    /// @dev ISuperfluidToken.updateAgreementState implementation
    function updateAgreementStateSlot(
        address account,
        uint256 slotId,
        bytes32[] calldata slotData
    ) external override {
        bytes32 slot = keccak256(
            abi.encode("AgreementState", msg.sender, account, slotId)
        );
        FixedSizeData.storeData(slot, slotData);
        emit AgreementStateUpdated(msg.sender, account, slotId);
    }

    /// @dev ISuperfluidToken.getAgreementState implementation
    function getAgreementStateSlot(
        address agreementClass,
        address account,
        uint256 slotId,
        uint256 dataLength
    ) external view override returns (bytes32[] memory slotData) {
        bytes32 slot = keccak256(
            abi.encode("AgreementState", agreementClass, account, slotId)
        );
        slotData = FixedSizeData.loadData(slot, dataLength);
    }

    /// @dev ISuperfluidToken.settleBalance implementation
    function settleBalance(address account, int256 delta)
        external
        override
        onlyAgreement
    {
        // ignore delta: _balances[account] = _balances[account] + delta;
        // delta = (currentTimestamp - initialTimestamp) * flowRate

        // forced to make some odd modifications here
        // TODO: check these calculations / find better way to do this

        uint256 timestamp = block.timestamp; // TODO: check that this timestamp is always valid

        // get active agreements and see which one is calling settleBalance
        ISuperAgreement[] memory activeAgreements = getAccountActiveAgreements(
            account
        );
        for (uint256 i = 0; i < activeAgreements.length; i++) {
            if (address(activeAgreements[i]) == msg.sender) {
                // delegate to that agreement's calculation of the dynamic balance
                (int256 agreementDynamicBalance, , ) = activeAgreements[i]
                    .realtimeBalanceOf(this, account, timestamp);

                // some bad logic to check if the delta came from CFA
                if (agreementDynamicBalance == delta) {
                    // copy over same logic from realTimeBalanceOf:
                    // get account's flow timestamp
                    (uint256 initialTimestamp, , , ) = IConstantFlowAgreementV1(
                        address(
                            _host.getAgreementClass(
                                keccak256(
                                    "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
                                )
                            )
                        )
                    ).getAccountFlowInfo(this, account);

                    agreementDynamicBalance = _poolFactory.realtimeBalanceOf(
                        agreementDynamicBalance,
                        address(this),
                        account,
                        timestamp,
                        initialTimestamp
                    );

                    _settleBalance(account, agreementDynamicBalance);
                } else {
                    _settleBalance(account, delta);
                }
            }
        }
    }

    function _settleBalance(address account, int256 delta) internal {
        _balances[account] = _balances[account] + delta;
    }

    /// @dev ISuperfluidToken.makeLiquidationPayoutsV2 implementation
    function makeLiquidationPayoutsV2(
        bytes32 id,
        bytes memory liquidationTypeData,
        address liquidatorAccount, // the address executing the liquidation
        bool useDefaultRewardAccount, // Whether or not the default reward account receives the rewardAmount
        address targetAccount, // Account to be liquidated
        uint256 rewardAmount, // The amount the rewarded account will receive
        int256 targetAccountBalanceDelta // The delta amount the target account balance should change by
    ) external override onlyAgreement {
        address rewardAccount = _getRewardAccount();

        // we set the rewardAccount to the user who executed the liquidation if
        // no rewardAccount is set (aka. ANARCHY MODE - should not occur in reality, for testing purposes)
        if (rewardAccount == address(0)) {
            rewardAccount = liquidatorAccount;
        }

        address rewardAmountReceiver = useDefaultRewardAccount
            ? rewardAccount
            : liquidatorAccount;

        if (targetAccountBalanceDelta <= 0) {
            // LIKELY BRANCH: target account pays penalty to rewarded account
            assert(rewardAmount.toInt256() == -targetAccountBalanceDelta);

            _balances[rewardAmountReceiver] += rewardAmount.toInt256();
            _balances[targetAccount] += targetAccountBalanceDelta;
            EventsEmitter.emitTransfer(
                targetAccount,
                rewardAmountReceiver,
                rewardAmount
            );
        } else {
            // LESS LIKELY BRANCH: target account is bailed out
            // NOTE: useDefaultRewardAccount being true is undefined behavior
            // because the default reward account isn't receiving the rewardAmount by default
            assert(!useDefaultRewardAccount);
            _balances[rewardAccount] -= (rewardAmount.toInt256() +
                targetAccountBalanceDelta);
            _balances[liquidatorAccount] += rewardAmount.toInt256();
            _balances[targetAccount] += targetAccountBalanceDelta;
            EventsEmitter.emitTransfer(
                rewardAccount,
                liquidatorAccount,
                rewardAmount
            );
            EventsEmitter.emitTransfer(
                rewardAccount,
                targetAccount,
                uint256(targetAccountBalanceDelta)
            );
        }

        emit AgreementLiquidatedV2(
            msg.sender,
            id,
            liquidatorAccount,
            targetAccount,
            rewardAmountReceiver,
            rewardAmount,
            targetAccountBalanceDelta,
            liquidationTypeData
        );
    }

    /**************************************************************************
     * Modifiers
     *************************************************************************/

    modifier onlyAgreement() {
        require(
            _host.isAgreementClassListed(ISuperAgreement(msg.sender)),
            "SuperfluidToken: only listed agreeement"
        );
        _;
    }

    modifier onlyHost() {
        require(
            address(_host) == msg.sender,
            "SuperfluidToken: Only host contract allowed"
        );
        _;
    }
}
