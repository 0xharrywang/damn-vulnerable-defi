// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {TrustfulOracle} from "./TrustfulOracle.sol";

contract TrustfulOracleInitializer {
    event NewTrustfulOracle(address oracleAddress);

    TrustfulOracle public oracle;
    // 设置oracle初始化：3 个 source 都为 999 ether
    constructor(address[] memory sources, string[] memory symbols, uint256[] memory initialPrices) {
        oracle = new TrustfulOracle(sources, true);
        oracle.setupInitialPrices(sources, symbols, initialPrices);
        emit NewTrustfulOracle(address(oracle));
    }
}
