// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";
import {IProxyCreationCallback} from "safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";

/**
 * @notice A registry for Safe multisig wallets.
 *         When known beneficiaries deploy and register their wallets, the registry awards tokens to the wallet.
 * @dev The registry has embedded verifications to ensure only legitimate Safe wallets are stored.
 */
// 用于注册 Safe 多签钱包
// 当受益人部署并注册他们的钱包时，该合约会向这些钱包发放奖励代币
// !!! 该合约存在漏洞
contract WalletRegistry is IProxyCreationCallback, Ownable {
    uint256 private constant EXPECTED_OWNERS_COUNT = 1;
    uint256 private constant EXPECTED_THRESHOLD = 1;
    uint256 private constant PAYMENT_AMOUNT = 10e18;

    address public immutable singletonCopy;
    address public immutable walletFactory;
    IERC20 public immutable token;

    // 可以进行钱包创建的受益人列表, 有4个
    mapping(address => bool) public beneficiaries;

    // owner（第一个受益人） =>  wallet（钱包proxy地址）
    mapping(address => address) public wallets;

    error NotEnoughFunds();
    error CallerNotFactory();
    error FakeSingletonCopy();
    error InvalidInitialization();
    error InvalidThreshold(uint256 threshold);
    error InvalidOwnersCount(uint256 count);
    error OwnerIsNotABeneficiary();
    error InvalidFallbackManager(address fallbackManager);

    constructor(
        address singletonCopyAddress,   // Safe 合约地址
        address walletFactoryAddress,   // SafeProxyFactory 合约地址
        address tokenAddress,           // Token 地址
        address[] memory initialBeneficiaries  // 受益人地址
    ) {
        _initializeOwner(msg.sender);

        singletonCopy = singletonCopyAddress;
        walletFactory = walletFactoryAddress;
        token = IERC20(tokenAddress);

        for (uint256 i = 0; i < initialBeneficiaries.length; ++i) {
            unchecked {
                beneficiaries[initialBeneficiaries[i]] = true;
            }
        }
    }

    function addBeneficiary(address beneficiary) external onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    /**
     * @notice Function executed when user creates a Safe wallet via SafeProxyFactory::createProxyWithCallback
     *          setting the registry's address as the callback.
     */
    //  !核心方法
    // 执行 SafeProxyFactory::createProxyWithCallback 创建钱包 proxy 时进行回调
    // 向新创建的钱包者发送 10e18
    function proxyCreated(SafeProxy proxy, address singleton, bytes calldata initializer, uint256) external override {
        if (token.balanceOf(address(this)) < PAYMENT_AMOUNT) {
            // fail early
            revert NotEnoughFunds();
        }
        // proxy地址即为钱包地址
        address payable walletAddress = payable(proxy);

        // Ensure correct factory and copy
        // 调用者需为 factory
        if (msg.sender != walletFactory) {
            revert CallerNotFactory();
        }

        if (singleton != singletonCopy) {
            revert FakeSingletonCopy();
        }

        // Ensure initial calldata was a call to `Safe::setup`
        if (bytes4(initializer[:4]) != Safe.setup.selector) {
            revert InvalidInitialization();
        }

        // Ensure wallet initialization is the expected
        // 钱包签名阈值
        uint256 threshold = Safe(walletAddress).getThreshold();
        if (threshold != EXPECTED_THRESHOLD) {
            revert InvalidThreshold(threshold);
        }
        // 钱包所有owner
        address[] memory owners = Safe(walletAddress).getOwners();
        if (owners.length != EXPECTED_OWNERS_COUNT) {
            revert InvalidOwnersCount(owners.length);
        }

        // Ensure the owner is a registered beneficiary
        // 默认第0个为钱包拥有者为主拥有者
        address walletOwner;
        unchecked {
            walletOwner = owners[0];
        }
        if (!beneficiaries[walletOwner]) {
            revert OwnerIsNotABeneficiary();
        }
        // ?? 
        address fallbackManager = _getFallbackManager(walletAddress);
        if (fallbackManager != address(0)) {
            revert InvalidFallbackManager(fallbackManager);
        }

        // Remove owner as beneficiary
        beneficiaries[walletOwner] = false;

        // Register the wallet under the owner's address
        // 注册： 第一个 owner -> 钱包地址
        wallets[walletOwner] = walletAddress;

        // Pay tokens to the newly created wallet
        // 发送 Token 到多签钱包地址
        SafeTransferLib.safeTransfer(address(token), walletAddress, PAYMENT_AMOUNT);
    }

    function _getFallbackManager(address payable wallet) private view returns (address) {
        return abi.decode(
            Safe(wallet).getStorageAt(uint256(keccak256("fallback_manager.handler.address")), 0x20), (address)
        );
    }
}
