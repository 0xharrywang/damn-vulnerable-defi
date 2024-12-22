// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {Test, console} from "forge-std/Test.sol";

struct Distribution {
    uint256 remaining;          // 剩余代币数量
    uint256 nextBatchNumber;    // ?? 下一批次
    mapping(uint256 batchNumber => bytes32 root) roots; // 分发批次对应的merkle树根
    // ??用户领取记录：  claimer => 第几个 word => 第几个 bit
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims;
}

// 用户请求凭证结构
struct Claim {
    uint256 batchNumber;
    uint256 amount;
    uint256 tokenIndex;
    // Merkle
    bytes32[] proof;
}

/**
 * An efficient token distributor contract based on Merkle proofs and bitmaps
 */
// 奖励分发
contract TheRewarderDistributor {
    // 使用位图存储大量bool类型
    using BitMaps for BitMaps.BitMap;
    // 合约拥有者
    address public immutable owner = msg.sender;

    // 多种代币分发记录
    mapping(IERC20 token => Distribution) public distributions;

    // 定义的错误
    error StillDistributing();
    error InvalidRoot();
    error AlreadyClaimed();
    error InvalidProof();
    error NotEnoughTokensToDistribute();

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }
    
    // 创建一个新的分发批次
    // token:   指定token
    // newRoot: 默克尔树根
    // amount:  分发数量
    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        if (amount == 0) revert NotEnoughTokensToDistribute();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        if (distributions[token].remaining != 0) revert StillDistributing();

        distributions[token].remaining = amount;

        uint256 batchNumber = distributions[token].nextBatchNumber;
        distributions[token].roots[batchNumber] = newRoot;
        distributions[token].nextBatchNumber++;

        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    // 清理未领取的代币
    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            // ?? remaining为0，为什么还要转 
            if (distributions[token].remaining == 0) {
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    // Allow claiming rewards of multiple tokens in a single transaction
    // !入口，用户领取奖励，可以在单笔交易中领取多种代币奖励

    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // accumulator
        uint256 amount;

        for (uint256 i = 0; i < inputClaims.length; i++) {
            inputClaim = inputClaims[i];
            // wordPosition 和 bitPosition：用来定位用户在位图中的领取记录
            // 位图使用的是 256 位（uint256）
            uint256 wordPosition = inputClaim.batchNumber / 256;
            uint256 bitPosition = inputClaim.batchNumber % 256;
            // token初始为 address(0)
            // !!! 漏洞：逻辑缺陷，相同 token 的交易没有进行检查
            // 如执行 [A,A,A,B,B,B] ，只记录[A,B]，所以使用连续的
            if (token != inputTokens[inputClaim.tokenIndex]) { // 仅当与上一次 Token类别 不一致时执行
                // 非第一次，变换Token类别时执行
                if (address(token) != address(0)) {
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }
                // 第一次时执行
                token = inputTokens[inputClaim.tokenIndex];
                // 左移 bitPosition 位
                bitsSet = 1 << bitPosition; // set bit at given position
                amount = inputClaim.amount;
            } else { // 相同 claim 执行
                bitsSet = bitsSet | 1 << bitPosition; // bitsSet不变
                amount += inputClaim.amount;          // amount 累加
            }

            // for the last claim
            // 只对最后一次 claim 进行记录
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }
            // 计算出leaf {地址:数量} ，msg.sender是调用者
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            // 分发批次的merkle树根
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];
            // 使用merkle树根验证proof
            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();
            // 通过后才能被领取
            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }
    // 更新用户领取状态
    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        // 当前用户领取的“记录字”
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];
        // 检查是否已经领取，位是否图中已存在
        // 若第一次领取
        // 0000...0000 （没有记录）
        // 0000...0100
        // ->
        // 0000...0000
        if ((currentWord & newBits) != 0) return false;

        // update state
        // 
        // 0000...0000
        // 0000...0100
        // ->
        // 0000...0100 （存储记录）
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;
        distributions[token].remaining -= amount;
        return true;
    }
}
