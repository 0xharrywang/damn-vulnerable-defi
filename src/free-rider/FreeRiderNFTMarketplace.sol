// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

contract FreeRiderNFTMarketplace is ReentrancyGuard {
    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public offersCount;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);

    error InvalidPricesAmount();
    error InvalidTokensAmount();
    error InvalidPrice();
    error CallerNotOwner(uint256 tokenId);
    error InvalidApproval();
    error TokenNotOffered(uint256 tokenId);
    error InsufficientPayment();

    constructor(uint256 amount) payable {
        DamnValuableNFT _token = new DamnValuableNFT();
        _token.renounceOwnership();
        // 铸造 6 个 NFT，拥有者为 market 本合约
        for (uint256 i = 0; i < amount;) {
            _token.safeMint(msg.sender);
            unchecked {
                ++i;
            }
        }
        token = _token;
    }
    // 给出价格、上架
    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant {
        uint256 amount = tokenIds.length;
        if (amount == 0) {
            revert InvalidTokensAmount();
        }

        if (amount != prices.length) {
            revert InvalidPricesAmount();
        }

        for (uint256 i = 0; i < amount; ++i) {
            unchecked {
                _offerOne(tokenIds[i], prices[i]);
            }
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        DamnValuableNFT _token = token; // gas savings

        if (price == 0) {
            revert InvalidPrice();
        }

        if (msg.sender != _token.ownerOf(tokenId)) {
            revert CallerNotOwner(tokenId);
        }

        if (_token.getApproved(tokenId) != address(this) && !_token.isApprovedForAll(msg.sender, address(this))) {
            revert InvalidApproval();
        }

        offers[tokenId] = price;

        assembly {
            // gas savings
            sstore(0x02, add(sload(0x02), 0x01))
        }

        emit NFTOffered(msg.sender, tokenId, price);
    }
    // !!! 漏洞, 没有对多个NFT检查msg.value
    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            unchecked {
                _buyOne(tokenIds[i]);
            }
        }
    }

    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        if (priceToPay == 0) {
            revert TokenNotOffered(tokenId);
        }
        // !!!漏洞： msg.sender 只需大于每一个的价格即可
        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }

        --offersCount;

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        // !!! 执行完成后会将 owner 改为新的
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token
        // !!!漏洞： 此时 nft 的 owner 为新的
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }

    receive() external payable {}
}
