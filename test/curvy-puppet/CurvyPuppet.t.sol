// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";

// adding
import {CurvyPuppetExploit} from "./CurvyPuppetExploit.sol";

contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    // 使用 Uniswap permit2进行 token 授权
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // 主网 curve 合约, vyper 写的
    IStableSwap constant curvePool = IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Fork from mainnet state at specific block
        // 模拟主网环境 
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        // 设置价格
        // 设置 ETH 的价格, curve pool中第一个 token 为 ETH
        oracle.setPrice({asset: ETH, value: ETHER_PRICE, expiration: block.timestamp + 1 days});
        // 设置 dvt 的价格
        oracle.setPrice({asset: address(dvt), value: DVT_PRICE, expiration: block.timestamp + 1 days});

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt),
            _curvePool: curvePool,
            _permit2: permit2,
            _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        // 模拟主网 LP 代币持有者
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        // 向借贷池投入 1000 LP
        IERC20(curvePool.lp_token()).transfer(address(lending), LENDER_INITIAL_LP_BALANCE);
        // 向 treasury 65 LP
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        // 向 player 授权 200 WETH
        weth.approve(player, TREASURY_WETH_BALANCE);
        // 向 player 授权 65 LP Token
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            // 每个人持有 dvt
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        // 向 lending 合约授权
        permit2.approve({
            token: lending.collateralAsset(), // 抵押品, dvt
            spender: address(lending), // lending 合约
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE), // 2500 dvt
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        // 存入抵押物
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);  //  抵入 2500 dvt
        // 借贷
        lending.borrow(USER_BORROW_AMOUNT);     // 借  1 LP
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(treasury), TREASURY_LP_BALANCE);

        // Curve pool trades the expected assets
        // Curve pool 中 第一个 token 为 ETH
        // 第二个 token 为 stETH
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);

            // User is sufficiently collateralized
            assertGt(lending.getCollateralValue(collateralAmount) / lending.getBorrowValue(borrowAmount), 3);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        CurvyPuppetExploit curvyPuppetExploit = new CurvyPuppetExploit(
            curvePool, 
            lending, 
            IERC20(curvePool.lp_token()), 
            address(player), 
            stETH,
            weth,
            address(treasury),dvt
        );
        // 
        IERC20(curvePool.lp_token()).transferFrom(address(treasury), address(curvyPuppetExploit), TREASURY_LP_BALANCE);
        weth.transferFrom(address(treasury), address(curvyPuppetExploit), TREASURY_WETH_BALANCE);

        curvyPuppetExploit.executeExploit();
    
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lending.getCollateralAmount(users[i]), 0, "User position still has collateral assets");
            assertEq(lending.getBorrowAmount(users[i]), 0, "User position still has borrowed assets");
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(IERC20(curvePool.lp_token()).balanceOf(treasury), 0, "Treasury doesn't have any LP tokens left");
        assertEq(dvt.balanceOf(treasury), USER_INITIAL_COLLATERAL_BALANCE * 3, "Treasury doesn't have the users' DVT");

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0, "Player still has LP tokens");
    }
}
