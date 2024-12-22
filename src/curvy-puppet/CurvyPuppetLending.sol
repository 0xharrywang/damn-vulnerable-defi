// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {CurvyPuppetOracle} from "./CurvyPuppetOracle.sol";
import {console} from "forge-std/console.sol";

// 借贷合约
contract CurvyPuppetLending is ReentrancyGuard {
    using FixedPointMathLib for uint256;

    address public immutable borrowAsset;     // 借出资产, curve lp token 
    address public immutable collateralAsset; // 抵押资产, dvt
    IStableSwap public immutable curvePool;
    IPermit2 public immutable permit2;
    CurvyPuppetOracle public immutable oracle;

    struct Position {
        uint256 collateralAmount; // 抵押资产数量
        uint256 borrowAmount;     // 已借资产数量
    }
    // 管理每个用户的头寸
    mapping(address who => Position) public positions;

    error InvalidAmount();
    error NotEnoughCollateral();
    error HealthyPosition(uint256 borrowValue, uint256 collateralValue);
    error UnhealthyPosition();

    constructor(address _collateralAsset, IStableSwap _curvePool, IPermit2 _permit2, CurvyPuppetOracle _oracle) {
        borrowAsset = _curvePool.lp_token(); // curve lp token
        collateralAsset = _collateralAsset;
        curvePool = _curvePool;
        permit2 = _permit2;
        oracle = _oracle;
    }
    // 存入抵押资产
    function deposit(uint256 amount) external nonReentrant {
        positions[msg.sender].collateralAmount += amount;
        _pullAssets(collateralAsset, amount);
    }

    // 提取抵押资产
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        // 进行检查
        uint256 remainingCollateral = positions[msg.sender].collateralAmount - amount;
        uint256 remainingCollateralValue = getCollateralValue(remainingCollateral);
        uint256 borrowValue = getBorrowValue(positions[msg.sender].borrowAmount);

        if (borrowValue * 175 > remainingCollateralValue * 100) revert UnhealthyPosition();

        positions[msg.sender].collateralAmount = remainingCollateral;
        // 提取抵押资产
        IERC20(collateralAsset).transfer(msg.sender, amount);
    }

    // 借贷
    function borrow(uint256 amount) external {
        // Get current collateral and borrow values
        uint256 collateralValue = getCollateralValue(positions[msg.sender].collateralAmount);
        uint256 currentBorrowValue = getBorrowValue(positions[msg.sender].borrowAmount);

        uint256 maxBorrowValue = collateralValue * 100 / 175;
        uint256 availableBorrowValue = maxBorrowValue - currentBorrowValue;

        if (amount == type(uint256).max) {
            // set amount to as much borrow tokens as possible, given the available borrow value and the borrow asset's price
            amount = availableBorrowValue.divWadDown(_getLPTokenPrice());
        }

        if (amount == 0) revert InvalidAmount();

        // Now do solvency check
        uint256 borrowAmountValue = getBorrowValue(amount);
        // 进行检查
        if (currentBorrowValue + borrowAmountValue > maxBorrowValue) revert NotEnoughCollateral();

        // Update caller's position and transfer borrowed assets
        positions[msg.sender].borrowAmount += amount;
        // 向调用者借款 amount
        IERC20(borrowAsset).transfer(msg.sender, amount);
    }

    // 还款
    // amount: 还的借贷资金数额
    function redeem(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        // 还账
        positions[msg.sender].borrowAmount -= amount;
        _pullAssets(borrowAsset, amount);

        if (positions[msg.sender].borrowAmount == 0) {
            uint256 returnAmount = positions[msg.sender].collateralAmount;
            positions[msg.sender].collateralAmount = 0;
            // 将抵押资产转给调用者
            IERC20(collateralAsset).transfer(msg.sender, returnAmount);
        }
    }
    // 清算
    function liquidate(address target) external nonReentrant {
        // 已借资产数量
        uint256 borrowAmount = positions[target].borrowAmount;
        // 抵押资产数量
        uint256 collateralAmount = positions[target].collateralAmount;

        uint256 collateralValue = getCollateralValue(collateralAmount) * 100;
        uint256 borrowValue = getBorrowValue(borrowAmount) * 175;
        // 未达到清算条件
        if (collateralValue >= borrowValue) revert HealthyPosition(borrowValue, collateralValue);

        delete positions[target];
        // 清算人支付借款
        _pullAssets(borrowAsset, borrowAmount);
        // 抵押资产给清算人,价格差为获利
        IERC20(collateralAsset).transfer(msg.sender, collateralAmount);
    }

    function getBorrowValue(uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        return amount.mulWadUp(_getLPTokenPrice());
    }
    // 抵押资产数量对应具体的价值
    function getCollateralValue(uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        // amount * oracle.value / 1e18
        return amount.mulWadDown(oracle.getPrice(collateralAsset).value);
    }

    function getBorrowAmount(address who) external view returns (uint256) {
        return positions[who].borrowAmount;
    }

    function getCollateralAmount(address who) external view returns (uint256) {
        return positions[who].collateralAmount;
    }
    // 调用者转给本合约
    function _pullAssets(address asset, uint256 amount) private {
        permit2.transferFrom({from: msg.sender, to: address(this), amount: SafeCast.toUint160(amount), token: asset});
    }
    // ?? 从 curvePool 获取价格数据
    function _getLPTokenPrice() private view returns (uint256) {
        // ETH * curvePool.get_virtual_price()
        return oracle.getPrice(curvePool.coins(0)).value.mulWadDown(curvePool.get_virtual_price());
    }
}
