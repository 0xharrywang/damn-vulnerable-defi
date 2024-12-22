// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ClimberTimelockBase} from "./ClimberTimelockBase.sol";
import {ADMIN_ROLE, PROPOSER_ROLE, MAX_TARGETS, MIN_TARGETS, MAX_DELAY} from "./ClimberConstants.sol";
import {
    InvalidTargetsCount,
    InvalidDataElementsCount,
    InvalidValuesCount,
    OperationAlreadyKnown,
    NotReadyForExecution,
    CallerNotTimelock,
    NewDelayAboveMax
} from "./ClimberErrors.sol";

/**
 * @title ClimberTimelock
 * @author
 */
// 该合约为Vault的拥有者
contract ClimberTimelock is ClimberTimelockBase {
    using Address for address;

    /**
     * @notice Initial setup for roles and timelock delay.
     * @param admin address of the account that will hold the ADMIN_ROLE role
     * @param proposer address of the account that will hold the PROPOSER_ROLE role
     */
    constructor(address admin, address proposer) {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);

        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, address(this)); // self administration
        _grantRole(PROPOSER_ROLE, proposer);

        delay = 1 hours;
    }

    // 只能被 PROPOSER 调用
    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external onlyRole(PROPOSER_ROLE) {
        if (targets.length == MIN_TARGETS || targets.length >= MAX_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        if (getOperationState(id) != OperationState.Unknown) {
            revert OperationAlreadyKnown(id);
        }

        operations[id].readyAtTimestamp = uint64(block.timestamp) + delay;
        operations[id].known = true;
    }

    /**
     * Anyone can execute what's been scheduled via `schedule`
     */
    // 执行底层交易
    function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata dataElements, bytes32 salt)
        external
        payable
    {
        if (targets.length <= MIN_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }
        // 计算一个唯一的id
        bytes32 id = getOperationId(targets, values, dataElements, salt);

        for (uint8 i = 0; i < targets.length; ++i) {
            // 执行提案
            targets[i].functionCallWithValue(dataElements[i], values[i]);
        }
        // !!! 漏洞：先执行交易，再进行检查，不满足CEI原则
        // 只有当 ReadyForExecution 时 才能往下执行
        if (getOperationState(id) != OperationState.ReadyForExecution) {
            revert NotReadyForExecution(id);
        }
        operations[id].executed = true;
    }

    function updateDelay(uint64 newDelay) external {
        if (msg.sender != address(this)) {
            revert CallerNotTimelock();
        }

        if (newDelay > MAX_DELAY) {
            revert NewDelayAboveMax();
        }

        delay = newDelay;
    }
}
