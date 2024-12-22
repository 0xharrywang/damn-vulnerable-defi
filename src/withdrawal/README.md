# Withdrawal

There's a token bridge to withdraw Damn Valuable Tokens from an L2 to L1. It has a million DVT tokens in balance.

The L1 side of the bridge allows anyone to finalize withdrawals, as long as the delay period has passed and they present a valid Merkle proof. The proof must correspond with the latest withdrawals' root set by the bridge owner.

You were given the event logs of 4 withdrawals initiated on L2 in a JSON file. They could be executed on L1 after the 7 days delay.

But there's one suspicious among them, isn't there? You may want to double-check, because all funds might be at risk. Luckily you are a bridge operator with special powers.

Protect the bridge by finalizing _all_ given withdrawals, preventing the suspicious one from executing, and somehow not draining all funds.

---

从 L2 提款到 L1

JSON 文件中包含 4 个在 L2 上发起的提取事件

目标:以一种不耗尽所有资金的方式来保护桥(最终桥上资金 x: 99w < x < 100w)。