// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TrustfulOracle} from "./TrustfulOracle.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

contract Exchange is ReentrancyGuard {
    using Address for address payable;
    // NFT
    DamnValuableNFT public immutable token;
    TrustfulOracle public immutable oracle;

    error InvalidPayment();
    error SellerNotOwner(uint256 id);
    error TransferNotApproved();
    error NotEnoughFunds();

    event TokenBought(address indexed buyer, uint256 tokenId, uint256 price);
    event TokenSold(address indexed seller, uint256 tokenId, uint256 price);

    constructor(address _oracle) payable {
        // 部署 NFT, Exchange 合约有 MINT 权限
        token = new DamnValuableNFT();
        token.renounceOwnership();
        oracle = TrustfulOracle(_oracle);
    }

    // 外部用户调用购买
    function buyOne() external payable nonReentrant returns (uint256 id) {
        if (msg.value == 0) {
            revert InvalidPayment();
        }

        // Price should be in [wei / NFT]
        uint256 price = oracle.getMedianPrice(token.symbol());
        if (msg.value < price) {
            revert InvalidPayment();
        }
        // min 一个 NFT
        // 如果是合约调用，需要执行_checkOnERC721Received
        id = token.safeMint(msg.sender);
        unchecked {
            // 向合约转 ETH
            payable(msg.sender).sendValue(msg.value - price);
        }

        emit TokenBought(msg.sender, id, price);
    }

    // 用户出售 NFT
    function sellOne(uint256 id) external nonReentrant {
        if (msg.sender != token.ownerOf(id)) {
            revert SellerNotOwner(id);
        }

        if (token.getApproved(id) != address(this)) {
            revert TransferNotApproved();
        }

        // Price should be in [wei / NFT]
        uint256 price = oracle.getMedianPrice(token.symbol());
        if (address(this).balance < price) {
            revert NotEnoughFunds();
        }

        token.transferFrom(msg.sender, address(this), id);
        token.burn(id);

        payable(msg.sender).sendValue(price);

        emit TokenSold(msg.sender, id, price);
    }

    receive() external payable {}
}
