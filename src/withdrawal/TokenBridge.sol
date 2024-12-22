// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {L1Forwarder} from "../withdrawal/L1Forwarder.sol";

contract TokenBridge {
    DamnValuableToken public immutable token;
    L1Forwarder public immutable l1Forwarder;
    address public immutable otherBridge;

    uint256 public totalDeposits;

    error Unauthorized();

    constructor(DamnValuableToken _token, L1Forwarder _forwarder, address _otherBridge) {
        token = _token;
        l1Forwarder = _forwarder;
        otherBridge = _otherBridge;
    }
    // 唯一提币入口
    function executeTokenWithdrawal(address receiver, uint256 amount) external {
        // 允许 l1Forwarder 调用, 如果不是l1Forwarder
        // l1Forwarder的上次发送者非 otherBridge
        if (msg.sender != address(l1Forwarder) || l1Forwarder.getSender() == otherBridge) revert Unauthorized();
        totalDeposits -= amount;
        token.transfer(receiver, amount);
    }

    /**
     * functions for deposits and that kind of bridge stuff
     * [...]
     */
}
