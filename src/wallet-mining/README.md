# Wallet Mining

There’s a contract that incentivizes users to deploy Safe wallets, rewarding them with 1 DVT. It integrates with an upgradeable authorization mechanism, only allowing certain deployers (a.k.a. wards) to be paid for specific deployments.

The deployer contract only works with a Safe factory and copy set during deployment. It looks like the [Safe singleton factory](https://github.com/safe-global/safe-singleton-factory) is already deployed.

The team transferred 20 million DVT tokens to a user at `0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b`, where her plain 1-of-1 Safe was supposed to land. But they lost the nonce they should use for deployment.

To make matters worse, there's been rumours of a vulnerability in the system. The team's freaked out. Nobody knows what to do, let alone the user. She granted you access to her private key.

You must save all funds before it's too late!

Recover all tokens from the wallet deployer contract and send them to the corresponding ward. Also save and return all user's funds.

In a single transaction.

---

该合约激励用户去部署Safe钱包，奖励 1 DVT， 只能由deployers支付
团队向`0x8be6a88D3871f793aD5D5e24eF39e1bf5be31d2b`地址发送 20 million DVT
丢失了nonce

目标：
- 救援钱包deployer合约的所有 Token
- 1笔交易