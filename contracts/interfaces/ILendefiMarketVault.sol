// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPROTOCOL} from "./IProtocol.sol";
import {IASSETS} from "./IASSETS.sol";

interface ILendefiMarketVault is IERC4626 {
    // ========== STRUCTS ==========

    /**
     * @notice Configuration parameters for protocol operations and rewards
     * @dev Centralized storage for all adjustable protocol parameters
     */
    struct ProtocolConfig {
        uint256 profitTargetRate; // Rate in 1e6
        uint256 borrowRate; // Rate in 1e6
        uint256 rewardAmount; // Amount of governance tokens
        uint256 rewardInterval; // Reward interval in blocks
        uint256 rewardableSupply; // Minimum rewardable supply
        uint32 flashLoanFee; // Flash loan fee in basis points (max 100 = 1%)
    }

    // ========== EVENTS ==========

    event Initialized(address indexed admin);
    event SupplyLiquidity(address indexed user, uint256 amount);
    event YieldBoosted(address indexed user, uint256 amount);
    event Exchange(address indexed user, uint256 shares, uint256 amount);
    event FlashLoan(address indexed user, address indexed receiver, address indexed asset, uint256 amount, uint256 fee);
    event ProtocolConfigUpdated(ProtocolConfig config);
    event MarketParametersUpdated(uint256 borrowRate, uint32 flashLoanFee);
    event Reward(address indexed user, uint256 amount);

    // ========== ERRORS ==========

    error ZeroAddress();
    error MEVSameBlockOperation();
    error ZeroAmount();
    error LowLiquidity();
    error FlashLoanFailed();
    error RepaymentFailed();
    error InvalidFee();

    // ========== STATE VARIABLE GETTERS ==========

    function baseDecimals() external view returns (uint256);
    function totalSuppliedLiquidity() external view returns (uint256);
    function totalAccruedInterest() external view returns (uint256);
    function totalBase() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function version() external view returns (uint32);
    function lendefiCore() external view returns (address);
    function ecosystem() external view returns (address);
    function borrowerDebt(address borrower) external view returns (uint256);
    function protocolConfig() external view returns (ProtocolConfig memory);

    // ========== INITIALIZATION ==========

    function initialize(
        address timelock,
        address core,
        address baseAsset,
        address _ecosystem,
        address _assetsModule,
        string memory name,
        string memory symbol
    ) external;

    // ========== CORE FUNCTIONS ==========

    function flashLoan(address receiver, uint256 amount, bytes calldata params) external;
    function deposit(uint256 amount, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function borrow(uint256 amount, address receiver) external;
    function repay(uint256 amount, address sender) external;
    function boostYield(address user, uint256 amount) external;
    function claimReward() external returns (uint256 finalReward);

    // ========== ADMIN FUNCTIONS ==========

    function pause() external;
    function unpause() external;
    function loadProtocolConfig(ProtocolConfig calldata config) external;
    function updateMarketParameters(uint256 borrowRate, uint32 flashLoanFee) external;

    // ========== VIEW FUNCTIONS ==========

    function totalAssets() external view returns (uint256);
    function utilization() external view returns (uint256);
    function isRewardable(address user) external view returns (bool);
    function getSupplyRate() external view returns (uint256);
    function getBorrowRate(IASSETS.CollateralTier tier) external view returns (uint256);
}
