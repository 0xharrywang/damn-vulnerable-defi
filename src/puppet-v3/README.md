# Puppet V3

Bear or bull market, true DeFi devs keep building. Remember that lending pool you helped? A new version is out.

They’re now using Uniswap V3 as an oracle. That’s right, no longer using spot prices! This time the pool queries the time-weighted average price of the asset, with all the recommended libraries.

The Uniswap market has 100 WETH and 100 DVT in liquidity. The lending pool has a million DVT tokens.

Starting with 1 ETH and some DVT, you must save all from the vulnerable lending pool. Don't forget to send them to the designated recovery account.

_NOTE: this challenge requires a valid RPC URL to fork mainnet state into your local environment._

---
使用UniswapV3 TWAP

初始条件
- market： 100 WETH，100 DVT
- lending pool（即PuppetV3Pool合约）： 100_0000 DVT
- player: 1 ETH , 一些 DVT

目标：拯救lending pool所有资产到指定账户recovery