// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract PuppetPool is ReentrancyGuard {
    using Address for address payable;

    uint256 public constant DEPOSIT_FACTOR = 2;

    address public immutable uniswapPair;
    DamnValuableToken public immutable token;

    mapping(address => uint256) public deposits;

    error NotEnoughCollateral();
    error TransferFailed();

    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress);
        uniswapPair = uniswapPairAddress;
    }

    // Allows borrowing tokens by first depositing two times their value in ETH
    // 借amount数量的dvt: 用户投入 eth, 借得 dvt
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        // 根据要换的Token数量 amount 计算要求支付的 ETH 数量
        uint256 depositRequired = calculateDepositRequired(amount);

        if (msg.value < depositRequired) {
            revert NotEnoughCollateral();
        }

        if (msg.value > depositRequired) {
            unchecked {
                // 返还多余的 eth
                payable(msg.sender).sendValue(msg.value - depositRequired);
            }
        }

        unchecked {
            deposits[msg.sender] += depositRequired;
        }

        // Fails if the pool doesn't have enough tokens in liquidity
        // 转账
        if (!token.transfer(recipient, amount)) {
            revert TransferFailed();
        }

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
    }
    // !!! 漏洞：预言机
    // amount为要兑换的 token 数量
    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
    }

    // 通过预言机计算价格
    function _computeOraclePrice() private view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        // ETH / Token 的比值
        // 要使比值低，增大池子中 token 总值， 即用户用 token 换 eth
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
    }
}
