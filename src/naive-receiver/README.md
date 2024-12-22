# Naive Receiver

There’s a pool with 1000 WETH in balance offering flash loans. It has a fixed fee of 1 WETH. The pool supports meta-transactions by integrating with a permissionless forwarder contract. 

A user deployed a sample contract with 10 WETH in balance. Looks like it can execute flash loans of WETH.

All funds are at risk! Rescue all WETH from the user and the pool, and deposit it into the designated recovery account.

---

通关要求：拯救所有 WETH

1. player交易要少于两笔
2. receiver 合约余额为0
3. pool 合约余额为0
4. 余额都转到 recovery 账户



合约布局：

- NaiveReceiverPool 为资金池合约
  - 接受存款
  - 闪电贷
- FlashLoanReceiver 为接受方合约
  - 执行闪电贷接口

- BasicForwarder 
  - Pool合约信任的转发合约
  - 通过该合约调用Pool逻辑