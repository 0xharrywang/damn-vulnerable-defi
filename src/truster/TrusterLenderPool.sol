// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract TrusterLenderPool is ReentrancyGuard {
    using Address for address;

    DamnValuableToken public immutable token;

    error RepayFailed();

    constructor(DamnValuableToken _token) {
        token = _token;
    }

    // borrower
    // target
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        uint256 balanceBefore = token.balanceOf(address(this));

        token.transfer(borrower, amount);
        // !!! 漏洞
        // token.transfer -> token.approve(attacker)
        target.functionCall(data);

        // erc20 余额检查
        // 此处绕开原理：在该函数内只执行了 approve， balance不变
        // 结束该函数后，再执行 transfrom
        if (token.balanceOf(address(this)) < balanceBefore) {
            revert RepayFailed();
        }

        return true;
    }
}
