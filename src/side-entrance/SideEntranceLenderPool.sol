// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceLenderPool {
    mapping(address => uint256) public balances;

    error RepayFailed();

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    // 存款
    function deposit() external payable {
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }
  
    function withdraw() external {
        uint256 amount = balances[msg.sender];

        delete balances[msg.sender];
        emit Withdraw(msg.sender, amount);

        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    // !入口
    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        // slither: sends eth to arbitrary user
        // 调用闪电贷合约的 execute 函数
        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        // eth 余额检查
        // !!!漏洞：将池子里余额通过deposit转入个人，该条件依然不变
        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
}
