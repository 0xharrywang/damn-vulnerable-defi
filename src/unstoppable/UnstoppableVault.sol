// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib, ERC4626, ERC20} from "solmate/tokens/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";

/**
 * An ERC4626-compliant tokenized vault offering flashloans for a fee.
 * An owner can pause the contract and execute arbitrary changes.
 */
contract UnstoppableVault is IERC3156FlashLender, ReentrancyGuard, Owned, ERC4626, Pausable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant FEE_FACTOR = 0.05 ether;
    uint64 public constant GRACE_PERIOD = 30 days;

    uint64 public immutable end = uint64(block.timestamp) + GRACE_PERIOD;

    address public feeRecipient;

    error InvalidAmount(uint256 amount);
    error InvalidBalance();
    error CallbackFailed();
    error UnsupportedCurrency();

    event FeeRecipientUpdated(address indexed newFeeRecipient);

    constructor(ERC20 _token, address _owner, address _feeRecipient)
        ERC4626(_token, "Too Damn Valuable Token", "tDVT")
        Owned(_owner)
    {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    function maxFlashLoan(address _token) public view nonReadReentrant returns (uint256) {
        if (address(asset) != _token) {
            return 0;
        }

        return totalAssets();
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    function flashFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        if (address(asset) != _token) {
            revert UnsupportedCurrency();
        }

        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        } else {
            return _amount.mulWadUp(FEE_FACTOR);
        }
    }

    /**
     * @inheritdoc ERC4626
     */
    function totalAssets() public view override nonReadReentrant returns (uint256) {
        // 该 vault （ERC4626）中 资产总余额 
        return asset.balanceOf(address(this));
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
     // 核心逻辑：闪电贷
     // receiver 借款者（合约）
     // _token  资产地址
     // amount 为欲借资产数量
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        // 闪电贷金额不能为 0
        if (amount == 0) revert InvalidAmount(0); // fail early
         // 传入的token应为valut中的资产
        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        // valut池子中总资产
        uint256 balanceBefore = totalAssets();
        
        // ERC4626
        // 保障措施，闪电贷未还款时阻止再进行
        // !!! 强制使 总份额 和 总资产 相等
        // assets.mulDivDown(supply, totalAssets())
        // 
        // shares = assets * totalSupply / totalAssets
        // 
        // -> totalSupply * totalSupply / totalAssets  = totalAssets
        // -> totalSupply = totalAssets
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement

        // transfer tokens out + execute callback on receiver
        // 将资产 DVT 借给了 receiver
        ERC20(_token).safeTransfer(address(receiver), amount);

        // callback must return magic value, otherwise assume it failed
        uint256 fee = flashFee(_token, amount);
        if (
            // receiver进行使用资产，并随后进行 approve
            // receive.onFlashLoan 调用应该始终返回 keccak256("IERC3156FlashBorrower.onFlashLoan")
            receiver.onFlashLoan(msg.sender, address(asset), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // pull amount + fee from receiver, then pay the fee to the recipient
        // 要求还回相应资产 DVT（上面 receiver.onFlashLoan 中已进行 approve）
        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);
        // 合约向指定地址支付相应手续费
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }

    /**
     * @inheritdoc ERC4626
     */
    function beforeWithdraw(uint256 assets, uint256 shares) internal override nonReentrant {}

    /**
     * @inheritdoc ERC4626
     */
    function afterDeposit(uint256 assets, uint256 shares) internal override nonReentrant whenNotPaused {}

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
            emit FeeRecipientUpdated(_feeRecipient);
        }
    }

    // Allow owner to execute arbitrary changes when paused
    function execute(address target, bytes memory data) external onlyOwner whenPaused {
        (bool success,) = target.delegatecall(data);
        require(success);
    }

    // Allow owner pausing/unpausing this contract
    function setPause(bool flag) external onlyOwner {
        if (flag) _pause();
        else _unpause();
    }
}
