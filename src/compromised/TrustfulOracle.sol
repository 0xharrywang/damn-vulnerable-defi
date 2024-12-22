// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {LibSort} from "solady/utils/LibSort.sol";

/**
 * @notice A price oracle with a number of trusted sources that individually report prices for symbols.
 *         The oracle's price for a given symbol is the median price of the symbol over all sources.
 */
contract TrustfulOracle is AccessControlEnumerable {
    uint256 public constant MIN_SOURCES = 1;
    bytes32 public constant TRUSTED_SOURCE_ROLE = keccak256("TRUSTED_SOURCE_ROLE");
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");

    // Source address => (symbol => price)
    mapping(address => mapping(string => uint256)) private _pricesBySource;

    error NotEnoughSources();

    event UpdatedPrice(address indexed source, string indexed symbol, uint256 oldPrice, uint256 newPrice);

    constructor(address[] memory sources, bool enableInitialization) {
        if (sources.length < MIN_SOURCES) {
            revert NotEnoughSources();
        }
        // 0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        // 0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        // 0xab3600bF153A316dE44827e2473056d56B774a40
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                // 授予地址 TRUSTED_SOURCE_ROLE 权限
                _grantRole(TRUSTED_SOURCE_ROLE, sources[i]);
                ++i;
            }
        }
        if (enableInitialization) { 
                // 授予 msg.sender INITIALIZER_ROLE权限
            _grantRole(INITIALIZER_ROLE, msg.sender);
        }
    }

    // A handy utility allowing the deployer to setup initial prices (only once)
    function setupInitialPrices(address[] calldata sources, string[] calldata symbols, uint256[] calldata prices)
        external
        onlyRole(INITIALIZER_ROLE)
    {
        // Only allow one (symbol, price) per source
        require(sources.length == symbols.length && symbols.length == prices.length);
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                _setPrice(sources[i], symbols[i], prices[i]);
                ++i;
            }
        }
        renounceRole(INITIALIZER_ROLE, msg.sender);
    }

    function postPrice(string calldata symbol, uint256 newPrice) external onlyRole(TRUSTED_SOURCE_ROLE) {
        _setPrice(msg.sender, symbol, newPrice);
    }

    function getMedianPrice(string calldata symbol) external view returns (uint256) {
        return _computeMedianPrice(symbol);
    }

    function getAllPricesForSymbol(string memory symbol) public view returns (uint256[] memory prices) {
        // 获取3个可信地址
        uint256 numberOfSources = getRoleMemberCount(TRUSTED_SOURCE_ROLE);
        prices = new uint256[](numberOfSources);
        for (uint256 i = 0; i < numberOfSources;) {
            address source = getRoleMember(TRUSTED_SOURCE_ROLE, i);
            // 获取每个地址的 price
            prices[i] = getPriceBySource(symbol, source);
            unchecked {
                ++i;
            }
        }
    }

    function getPriceBySource(string memory symbol, address source) public view returns (uint256) {
        return _pricesBySource[source][symbol];
    }
    // 设置 price
    function _setPrice(address source, string memory symbol, uint256 newPrice) private {
        uint256 oldPrice = _pricesBySource[source][symbol];
        _pricesBySource[source][symbol] = newPrice;
        emit UpdatedPrice(source, symbol, oldPrice, newPrice);
    }
    // 计算平均价格
    function _computeMedianPrice(string memory symbol) private view returns (uint256) {
        uint256[] memory prices = getAllPricesForSymbol(symbol);
        LibSort.insertionSort(prices);
        if (prices.length % 2 == 0) {
            uint256 leftPrice = prices[(prices.length / 2) - 1];
            uint256 rightPrice = prices[prices.length / 2];
            return (leftPrice + rightPrice) / 2;
        } else {
            // 取排序后的中间值
            return prices[prices.length / 2];
        }
    }
}
