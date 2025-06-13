// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../BasicDeploy.sol";
import {LendefiView} from "../../contracts/markets/helper/LendefiView.sol";
import {ILENDEFIVIEW} from "../../contracts/interfaces/ILendefiView.sol";
import {IPROTOCOL} from "../../contracts/interfaces/IProtocol.sol";
import {ILendefiMarketVault} from "../../contracts/interfaces/ILendefiMarketVault.sol";
import {IASSETS} from "../../contracts/interfaces/IASSETS.sol";
import {MockPriceOracle} from "../../contracts/mock/MockPriceOracle.sol";
import {WBNBPriceConsumerV3} from "../../contracts/mock/WBNBOracle.sol";
import {WBNB} from "../../contracts/mock/WBNB.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LendefiViewTest
 * @notice Comprehensive test suite for LendefiView contract
 * @dev Tests all view functions and aggregation logic for complete coverage
 */
contract LendefiViewTest is BasicDeploy {
    LendefiView public lendefiView;
    WBNBPriceConsumerV3 public wbnbOracleInstance;

    // Test constants
    uint256 constant INITIAL_DEPOSIT = 100_000e18; // 100k USDC
    uint256 constant WBNB_COLLATERAL = 10 ether; // 10 WBNB
    uint256 constant BORROW_AMOUNT = 15_000e18; // 15k USDC
    uint256 constant BNB_PRICE = 2500e8; // $2500 per BNB

    function setUp() public {
        // Deploy complete system
        deployMarketsWithUSDC();
        vm.prank(guardian);
        tokenInstance.initializeTGE(address(ecoInstance), address(treasuryInstance));

        // Deploy WBNB and its oracle
        wbnbInstance = new WBNB();
        wbnbOracleInstance = new WBNBPriceConsumerV3();
        wbnbOracleInstance.setPrice(int256(BNB_PRICE));

        // Configure assets
        vm.startPrank(address(timelockInstance));

        // Configure USDC as base asset (needed for operations)
        WBNBPriceConsumerV3 usdcOracle = new WBNBPriceConsumerV3();
        usdcOracle.setPrice(int256(1e8)); // $1 per USDC
        assetsInstance.updateAssetConfig(
            address(usdcInstance),
            IASSETS.Asset({
                active: 1,
                decimals: 18,
                borrowThreshold: 950,
                liquidationThreshold: 980,
                maxSupplyThreshold: 100_000_000e18,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.STABLE,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: address(usdcOracle), active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: address(0), twapPeriod: 0, active: 0})
            })
        );

        // Configure WBNB as collateral asset
        assetsInstance.updateAssetConfig(
            address(wbnbInstance),
            IASSETS.Asset({
                active: 1,
                decimals: 18,
                borrowThreshold: 800,
                liquidationThreshold: 850,
                maxSupplyThreshold: 1_000_000e18,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: address(wbnbOracleInstance), active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: address(0), twapPeriod: 0, active: 0})
            })
        );
        vm.stopPrank();

        // Deploy LendefiView contract
        lendefiView = new LendefiView(address(marketCoreInstance), address(marketVaultInstance), address(ecoInstance));

        // Setup initial state
        _setupInitialState();
    }

    function _setupInitialState() internal {
        // Provide initial liquidity from alice
        usdcInstance.mint(alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdcInstance.approve(address(marketCoreInstance), INITIAL_DEPOSIT);
        uint256 expectedShares = marketVaultInstance.previewDeposit(INITIAL_DEPOSIT);
        marketCoreInstance.depositLiquidity(INITIAL_DEPOSIT, expectedShares, 100);
        vm.stopPrank();

        // Setup borrowing position for bob
        vm.deal(bob, WBNB_COLLATERAL);
        vm.startPrank(bob);
        wbnbInstance.deposit{value: WBNB_COLLATERAL}();
        vm.stopPrank();

        // Create position and supply collateral
        uint256 positionId = _createPosition(bob, address(wbnbInstance), false);
        _supplyCollateral(bob, positionId, address(wbnbInstance), WBNB_COLLATERAL);
        _borrow(bob, positionId, BORROW_AMOUNT);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function test_Constructor() public {
        // Verify constructor sets immutable variables correctly
        LendefiView newView =
            new LendefiView(address(marketCoreInstance), address(marketVaultInstance), address(ecoInstance));

        // Test the view functions to verify contracts are set correctly
        ILENDEFIVIEW.ProtocolSnapshot memory snapshot = newView.getProtocolSnapshot();
        assertTrue(snapshot.totalBorrow > 0, "Should have borrowing data");
        assertTrue(snapshot.totalSuppliedLiquidity > 0, "Should have liquidity data");
    }

    function test_Revert_Constructor_ZeroProtocol() public {
        vm.expectRevert("ZERO_ADDRESS");
        new LendefiView(address(0), address(marketVaultInstance), address(ecoInstance));
    }

    function test_Revert_Constructor_ZeroMarketVault() public {
        vm.expectRevert("ZERO_ADDRESS");
        new LendefiView(address(marketCoreInstance), address(0), address(ecoInstance));
    }

    function test_Revert_Constructor_ZeroEcosystem() public {
        vm.expectRevert("ZERO_ADDRESS");
        new LendefiView(address(marketCoreInstance), address(marketVaultInstance), address(0));
    }

    function test_Revert_Constructor_AllZeroAddresses() public {
        vm.expectRevert("ZERO_ADDRESS");
        new LendefiView(address(0), address(0), address(0));
    }

    // ========== POSITION SUMMARY TESTS ==========

    function test_GetPositionSummary_WithCollateralAndDebt() public {
        uint256 positionId = 0; // Bob's position from setup

        ILENDEFIVIEW.PositionSummary memory summary = lendefiView.getPositionSummary(bob, positionId);

        // Verify collateral value (10 BNB * $2500 = $25,000)
        // BNB_PRICE is in 8 decimals, WBNB_COLLATERAL is 18 decimals, result should be 18 decimals (USDC)
        uint256 expectedCollateralValue = (WBNB_COLLATERAL * BNB_PRICE) / 1e8;
        assertEq(summary.totalCollateralValue, expectedCollateralValue, "Collateral value should match");

        // Verify debt is at least the borrowed amount
        assertGe(summary.currentDebt, BORROW_AMOUNT, "Current debt should be at least borrowed amount");

        // Verify available credit is reasonable (should be positive since healthy position)
        assertGt(summary.availableCredit, 0, "Available credit should be positive");

        // Verify health factor > 1 (healthy position)
        assertGt(summary.healthFactor, 1e6, "Health factor should be > 1 for healthy position");

        // Verify position properties
        assertFalse(summary.isIsolated, "Position should not be isolated");
        assertEq(uint8(summary.status), uint8(IPROTOCOL.PositionStatus.ACTIVE), "Position should be active");
    }

    function test_GetPositionSummary_EmptyPosition() public {
        // Create a position with no collateral or debt
        uint256 positionId = _createPosition(charlie, address(wbnbInstance), false);

        ILENDEFIVIEW.PositionSummary memory summary = lendefiView.getPositionSummary(charlie, positionId);

        assertEq(summary.totalCollateralValue, 0, "Empty position should have zero collateral value");
        assertEq(summary.currentDebt, 0, "Empty position should have zero debt");
        assertEq(summary.availableCredit, 0, "Empty position should have zero credit");
        assertEq(summary.healthFactor, type(uint256).max, "Empty position should have max health factor");
        assertFalse(summary.isIsolated, "Position should not be isolated");
        assertEq(uint8(summary.status), uint8(IPROTOCOL.PositionStatus.ACTIVE), "Position should be active");
    }

    function test_Revert_GetPositionSummary_InvalidPosition() public {
        vm.expectRevert();
        lendefiView.getPositionSummary(alice, 999); // Non-existent position
    }

    // ========== LP INFO TESTS ==========

    function test_GetLPInfo_WithBalance() public {
        (
            uint256 lpTokenBalance,
            uint256 usdcValue,
            uint256 lastAccrualBlock,
            bool isRewardEligible,
            uint256 pendingRewards
        ) = lendefiView.getLPInfo(alice);

        // Alice deposited INITIAL_DEPOSIT in setup
        assertGt(lpTokenBalance, 0, "LP token balance should be positive");

        // USDC value should approximately equal deposited amount (might be slightly different due to interest)
        assertApproxEqAbs(usdcValue, INITIAL_DEPOSIT, 1000e18, "USDC value should approximate deposit");

        // Last accrual block is set to 0 (as noted in contract)
        assertEq(lastAccrualBlock, 0, "Last accrual block should be 0");

        // Reward eligibility and pending rewards depend on configuration
        // These are initially false/0 since not enough time has passed
        assertFalse(isRewardEligible, "Should not be reward eligible initially");
        assertEq(pendingRewards, 0, "Should have no pending rewards initially");
    }

    function test_GetLPInfo_ZeroBalance() public {
        (
            uint256 lpTokenBalance,
            uint256 usdcValue,
            uint256 lastAccrualBlock,
            bool isRewardEligible,
            uint256 pendingRewards
        ) = lendefiView.getLPInfo(charlie); // Charlie has no LP tokens

        assertEq(lpTokenBalance, 0, "LP token balance should be zero");
        assertEq(usdcValue, 0, "USDC value should be zero");
        assertEq(lastAccrualBlock, 0, "Last accrual block should be 0");
        assertFalse(isRewardEligible, "Should not be reward eligible with zero balance");
        assertEq(pendingRewards, 0, "Pending rewards should be zero");
    }

    // ========== PROTOCOL SNAPSHOT TESTS ==========

    function test_GetProtocolSnapshot() public {
        ILENDEFIVIEW.ProtocolSnapshot memory snapshot = lendefiView.getProtocolSnapshot();

        // Verify utilization is reasonable (should be > 0 since we have borrows)
        assertGt(snapshot.utilization, 0, "Utilization should be positive with active borrows");
        assertLe(snapshot.utilization, 1e18, "Utilization should not exceed 100%");

        // Verify rates
        assertGe(snapshot.borrowRate, 0, "Borrow rate should be non-negative");
        assertGe(snapshot.supplyRate, 0, "Supply rate should be non-negative");

        // Verify total amounts
        assertGe(snapshot.totalBorrow, BORROW_AMOUNT, "Total borrow should be at least borrowed amount");
        assertGe(snapshot.totalSuppliedLiquidity, INITIAL_DEPOSIT, "Total liquidity should be at least initial deposit");

        // Verify config values
        assertGt(snapshot.targetReward, 0, "Target reward should be positive");
        assertGt(snapshot.rewardInterval, 0, "Reward interval should be positive");
        assertGt(snapshot.rewardableSupply, 0, "Rewardable supply should be positive");
        assertGt(snapshot.baseProfitTarget, 0, "Base profit target should be positive");
        assertGt(snapshot.liquidatorThreshold, 0, "Liquidator threshold should be positive");
        assertGe(snapshot.flashLoanFee, 0, "Flash loan fee should be non-negative");

        // Verify flash loan fee is reasonable (should be small percentage)
        assertLe(snapshot.flashLoanFee, 1000, "Flash loan fee should be reasonable"); // <= 10%
    }

    function test_GetProtocolSnapshot_ConfigValues() public {
        // Test that snapshot correctly reflects protocol configuration
        ILendefiMarketVault.ProtocolConfig memory config =
            ILendefiMarketVault(address(marketVaultInstance)).protocolConfig();
        ILENDEFIVIEW.ProtocolSnapshot memory snapshot = lendefiView.getProtocolSnapshot();

        assertEq(snapshot.targetReward, config.rewardAmount, "Target reward should match config");
        assertEq(snapshot.rewardInterval, config.rewardInterval, "Reward interval should match config");
        assertEq(snapshot.rewardableSupply, config.rewardableSupply, "Rewardable supply should match config");
        assertEq(snapshot.baseProfitTarget, config.profitTargetRate, "Base profit target should match config");
        assertEq(
            snapshot.liquidatorThreshold,
            marketCoreInstance.liquidatorThreshold(),
            "Liquidator threshold should match core"
        );
        assertEq(snapshot.flashLoanFee, config.flashLoanFee, "Flash loan fee should match config");
    }

    // ========== EDGE CASE TESTS ==========

    function test_View_WithMultiplePositions() public {
        // Create multiple positions for the same user
        uint256 position1 = _createPosition(alice, address(wbnbInstance), false);
        uint256 position2 = _createPosition(alice, address(wbnbInstance), false);

        // Add collateral to both
        uint256 collateral1 = 5 ether;
        uint256 collateral2 = 3 ether;

        vm.deal(alice, collateral1 + collateral2);
        vm.startPrank(alice);
        wbnbInstance.deposit{value: collateral1 + collateral2}();
        vm.stopPrank();

        _supplyCollateral(alice, position1, address(wbnbInstance), collateral1);
        _supplyCollateral(alice, position2, address(wbnbInstance), collateral2);

        // Borrow from both positions
        _borrow(alice, position1, 8000e18);
        _borrow(alice, position2, 4000e18);

        // Get summaries for both positions
        ILENDEFIVIEW.PositionSummary memory summary1 = lendefiView.getPositionSummary(alice, position1);
        ILENDEFIVIEW.PositionSummary memory summary2 = lendefiView.getPositionSummary(alice, position2);

        // Both positions should be active and healthy
        assertEq(uint8(summary1.status), uint8(IPROTOCOL.PositionStatus.ACTIVE), "Position 1 should be active");
        assertEq(uint8(summary2.status), uint8(IPROTOCOL.PositionStatus.ACTIVE), "Position 2 should be active");
        assertGt(summary1.healthFactor, 1e6, "Position 1 should be healthy");
        assertGt(summary2.healthFactor, 1e6, "Position 2 should be healthy");

        // Position 1 should have more collateral value than position 2
        assertGt(summary1.totalCollateralValue, summary2.totalCollateralValue, "Position 1 should have more collateral");
        assertGt(summary1.currentDebt, summary2.currentDebt, "Position 1 should have more debt");
    }

    // ========== REWARD ELIGIBLE TESTS ==========

    function test_GetLPInfo_RewardEligibleScenario() public {
        // Configure rewards properly
        vm.startPrank(address(timelockInstance));

        // Grant the REWARDER_ROLE to the vault contract for ecosystem rewards
        ecoInstance.grantRole(REWARDER_ROLE, address(marketVaultInstance));

        // Configure protocol for rewards
        ILendefiMarketVault.ProtocolConfig memory config =
            ILendefiMarketVault(address(marketVaultInstance)).protocolConfig();
        config.rewardAmount = 1_000e18; // Set target reward to 1000 tokens
        config.rewardInterval = 180 * 24 * 60 * 5; // 180 days in blocks (5 blocks per minute)
        config.rewardableSupply = 50_000e18; // Set rewardable supply threshold to 50k USDC
        marketVaultInstance.loadProtocolConfig(config);

        vm.stopPrank();

        // Charlie deposits enough to meet threshold
        uint256 depositAmount = 150_000e18; // More than 50k threshold
        usdcInstance.mint(charlie, depositAmount);
        vm.startPrank(charlie);
        usdcInstance.approve(address(marketCoreInstance), depositAmount);

        // Move to next block to avoid MEV protection
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 expectedShares = marketVaultInstance.previewDeposit(depositAmount);
        marketCoreInstance.depositLiquidity(depositAmount, expectedShares, 100);
        vm.stopPrank();

        // Fast-forward past the reward interval
        vm.roll(block.number + config.rewardInterval + 1);

        // Now test getLPInfo for the eligible user
        (
            uint256 lpTokenBalance,
            uint256 usdcValue,
            uint256 lastAccrualBlock,
            bool isRewardEligible,
            uint256 pendingRewards
        ) = lendefiView.getLPInfo(charlie);

        // Verify basic LP info
        assertGt(lpTokenBalance, 0, "LP token balance should be positive");
        assertApproxEqAbs(usdcValue, depositAmount, 1000e18, "USDC value should approximate deposit");
        assertEq(lastAccrualBlock, 0, "Last accrual block should be 0");

        // Verify reward eligibility and pending rewards
        assertTrue(isRewardEligible, "User should be reward eligible");
        assertGt(pendingRewards, 0, "Should have pending rewards");

        // Verify pending rewards don't exceed maximum
        uint256 maxReward = ecoInstance.maxReward();
        assertLe(pendingRewards, maxReward, "Pending rewards should not exceed max reward");

        // Verify reward calculation is reasonable (should be approximately the configured amount)
        assertApproxEqAbs(
            pendingRewards, config.rewardAmount, config.rewardAmount / 10, "Pending rewards should be reasonable"
        );
    }

    // ========== HELPER FUNCTIONS ==========

    function _createPosition(address user, address asset, bool isolated) internal returns (uint256) {
        vm.prank(user);
        marketCoreInstance.createPosition(asset, isolated);
        return marketCoreInstance.getUserPositionsCount(user) - 1;
    }

    function _supplyCollateral(address user, uint256 positionId, address asset, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(marketCoreInstance), amount);
        marketCoreInstance.supplyCollateral(asset, amount, positionId);
        vm.stopPrank();
    }

    function _borrow(address user, uint256 positionId, uint256 amount) internal {
        vm.startPrank(user);
        uint256 creditLimit = marketCoreInstance.calculateCreditLimit(user, positionId);
        marketCoreInstance.borrow(positionId, amount, creditLimit, 100);
        vm.stopPrank();
    }
}
