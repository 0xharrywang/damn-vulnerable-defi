// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {FlashLoanReceiver} from "./FlashLoanReceiver.sol";
import {Multicall} from "./Multicall.sol";
import {WETH} from "solmate/tokens/WETH.sol";

// 闪电贷合约
// 实现了 Multicall
contract NaiveReceiverPool is Multicall, IERC3156FlashLender {
    uint256 private constant FIXED_FEE = 1e18; // not the cheapest flash loan
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    WETH public immutable weth;
    address public immutable trustedForwarder;
    address public immutable feeReceiver;

    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    error RepayFailed();
    error UnsupportedCurrency();
    error CallbackFailed();

    constructor(address _trustedForwarder, address payable _weth, address _feeReceiver) payable {
        weth = WETH(_weth);
        trustedForwarder = _trustedForwarder;
        feeReceiver = _feeReceiver;
        // 初始资金 deployer:1000
        _deposit(msg.value);
    }

    function maxFlashLoan(address token) external view returns (uint256) {
        if (token == address(weth)) return weth.balanceOf(address(this));
        return 0;
    }

    function flashFee(address token, uint256) external view returns (uint256) {
        if (token != address(weth)) revert UnsupportedCurrency();
        return FIXED_FEE;
    }


    // 闪电贷功能
    // 1.通过手续费 将 receiver 的余额掏空，但是需要 10 次交易
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (token != address(weth)) revert UnsupportedCurrency();

        // Transfer WETH and handle control to receiver
        // 资金借给 receiver
        weth.transfer(address(receiver), amount);
        totalDeposits -= amount;

        // 进行资金使用
        if (receiver.onFlashLoan(msg.sender, address(weth), amount, FIXED_FEE, data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }
        // 固定 1 个 weth 手续费
        uint256 amountWithFee = amount + FIXED_FEE;
        // receiver 还回资金
        weth.transferFrom(address(receiver), address(this), amountWithFee);

        totalDeposits += amountWithFee;
        // 给 feeReceiver 1 ETH
        deposits[feeReceiver] += FIXED_FEE; // 1 ETH

        return true;
    }
    // 3.通过 withdraw 将池子的余额掏空
    function withdraw(uint256 amount, address payable receiver) external {
        // Reduce deposits
        // 通过 _msgSender() 得到转账者
        // 只有当 trustedForwarder 时，可以修改为 指定账户
        deposits[_msgSender()] -= amount;
        totalDeposits -= amount;

        // Transfer ETH to designated receiver
        // 向 receiver 转账
        weth.transfer(receiver, amount);
    }

    function deposit() external payable {
        _deposit(msg.value);
    }

    function _deposit(uint256 amount) private {
        weth.deposit{value: amount}();

        deposits[_msgSender()] += amount;
        totalDeposits += amount;
    }

    function _msgSender() internal view override returns (address) {
        // !!! 漏洞,可以通过msg.data操控
        // 如果是 trustedForwarder 且 data 大于 20，则为 data 中指定字段
        if (msg.sender == trustedForwarder && msg.data.length >= 20) {
            return address(bytes20(msg.data[msg.data.length - 20:]));
        } else {
            return super._msgSender();
        }
    }
}
