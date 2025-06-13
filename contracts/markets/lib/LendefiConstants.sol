// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @title Lendefi Constants
 * @notice Shared constants for Lendefi and LendefiAssets contracts
 * @author alexei@lendefimarkets(dot)xyz
 * @custom:copyright Copyright (c) 2025 Nebula Holding Inc. All rights reserved.
 */
library LendefiConstants {
    /// @notice Standard decimals for percentage calculations (1e6 = 100%)
    uint256 internal constant WAD = 1e6;

    /// @notice Address of the PancakeSwap V3 USDT/WBNB pool with 0.01% fee tier (higher liquidity than USDC)
    address internal constant USDT_WBNB_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    
    /// @notice USDT address on BSC (18 decimals)
    address internal constant USDT_BSC = 0x55d398326f99059fF775485246999027B3197955;
    
    /// @notice USDC address on BSC (18 decimals)
    address internal constant USDC_BSC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    
    /// @notice WBNB address on BSC (18 decimals)
    address internal constant WBNB_BSC = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /// @notice Role identifier for users authorized to pause/unpause the protocol
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role identifier for users authorized to manage protocol parameters
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role identifier for users authorized to upgrade the contract
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role identifier for users authorized to access borrow/repay functions in the LendefiMarketVault
    bytes32 internal constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    /// @notice Role identifier for addresses that can create new markets
    bytes32 internal constant MARKET_OWNER_ROLE = keccak256("MARKET_OWNER_ROLE");

    /// @notice Duration of the timelock for upgrade operations (3 days)
    uint256 internal constant UPGRADE_TIMELOCK_DURATION = 3 days;

    /// @notice Max liquidation threshold, percentage on a 1000 scale
    uint16 internal constant MAX_LIQUIDATION_THRESHOLD = 990;

    /// @notice Min liquidation threshold, percentage on a 1000 scale
    uint16 internal constant MIN_THRESHOLD_SPREAD = 10;

    /// @notice Max assets supported by platform
    uint32 internal constant MAX_ASSETS = 3000;
}
