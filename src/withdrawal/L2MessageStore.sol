// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @notice This contract is not deployed in the challenge.
 *         We just include it for you to understand how the withdrawal logs were created. 
 */
contract L2MessageStore {
    uint256 public nonce;
    // 存储消息
    mapping(bytes32 messageId => bool seen) public messageStore;

    // 事件,有 3 个 index参数
    event MessageStored(
        bytes32 id, uint256 indexed nonce, address indexed caller, address indexed target, uint256 timestamp, bytes data
    );

    function store(address target, bytes memory data) external {
        // 可以用来验证
        bytes32 id = keccak256(abi.encode(nonce, msg.sender, target, block.timestamp, data));

        messageStore[id] = true;

        // 事件
        emit MessageStored(id, nonce, msg.sender, target, block.timestamp, data);

        unchecked {
            nonce++;
        }
    }
}
