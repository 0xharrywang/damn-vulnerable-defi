// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {L1Gateway} from "./L1Gateway.sol";

contract L1Forwarder is ReentrancyGuard, Ownable {
    using Address for address;

    mapping(bytes32 messageId => bool seen) public successfulMessages;
    mapping(bytes32 messageId => bool seen) public failedMessages;
    // l1Gateway 实例
    L1Gateway public gateway;
    address public l2Handler;

    struct Context {
        address l2Sender;
    }
    // 上一笔交易发生情况
    Context public context;

    error AlreadyForwarded(bytes32 messageId);
    error BadTarget();

    constructor(L1Gateway _gateway) {
        _initializeOwner(msg.sender);
        gateway = _gateway;
    }

    function setL2Handler(address _l2Handler) external onlyOwner {
        l2Handler = _l2Handler;
    }

    // 将 L2 的信息转发到 L1 gateway
    // message 为 L1Gateway.finalizeWithdrawal
    function forwardMessage(uint256 nonce, address l2Sender, address target, bytes memory message)
        external
        payable
        nonReentrant
    {
        bytes32 messageId = keccak256(
            abi.encodeWithSignature("forwardMessage(uint256,address,address,bytes)", nonce, l2Sender, target, message)
        );
        // 既没有失败也没有成功时，只有gateway可以调用该函数
        if (msg.sender == address(gateway) && gateway.xSender() == l2Handler) {
            require(!failedMessages[messageId]);
        } else { // 如果之前调用失败, 任何人都可调用
            require(failedMessages[messageId]);
        }

        if (successfulMessages[messageId]) {
            revert AlreadyForwarded(messageId);
        }

        // target 不能是 gateway
        if (target == address(this) || target == address(gateway)) revert BadTarget();

        Context memory prevContext = context;
        context = Context({l2Sender: l2Sender});
        bool success;
        // 执行 target(合约地址), message(calldata)
        // 交易执行失败会记录,但不会 revert
        assembly {
            success := call(gas(), target, 0, add(message, 0x20), mload(message), 0, 0) // call with 0 value. Don't copy returndata.
        }
        context = prevContext;
        // 当执行不成功时(第三笔交易),此处会记录
        if (success) {
            successfulMessages[messageId] = true;
        } else {
            failedMessages[messageId] = true;
        }
    }

    // 获取 l2 上发送者
    function getSender() external view returns (address) {
        return context.l2Sender;
    }
}
