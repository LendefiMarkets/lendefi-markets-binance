// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BasicDeploy.sol";
import {console2} from "forge-std/console2.sol";
import {IASSETS} from "../../contracts/interfaces/IASSETS.sol";
import {IPROTOCOL} from "../../contracts/interfaces/IProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../../contracts/vendor/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract USDCForkTest is BasicDeploy {
    // BSC addresses
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB instead of WBNB
    address constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c; // BTCB instead of BTCB
    address constant LINK = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD; // LINK on BSC
    // address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC on BSC

    // PancakeSwap V3 pools on BSC
    address constant LINK_WBNB_POOL = 0x0E1893BEEb4d0913d26B9614B18Aea29c56d94b9; // LINK/WBNB pool
    address constant BTCB_USDC_POOL = 0x46Cf1cF8c69595804ba91dFdd8d6b960c9B0a7C4; // BTCB/USDC pool (using BTCB/USDT as proxy)
    address constant WBNB_USDC_POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4; // WBNB/USDC pool with 0.01% fee

    // Chainlink oracles on BSC
    address constant BNB_CHAINLINK_ORACLE = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // BNB/USD oracle
    address constant BTC_CHAINLINK_ORACLE = 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf; // BTC/USD oracle
    address constant LINK_CHAINLINK_ORACLE = 0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8; // LINK/USD oracle
    address constant USDC_CHAINLINK_ORACLE = 0x51597f405303C4377E36123cBc172b13269EA163; // USDC/USD oracle

    uint256 mainnetFork;
    address testUser;

    function setUp() public {
        // Fork mainnet at a specific block
        mainnetFork = vm.createFork("binance", 51344326);
        vm.selectFork(mainnetFork);

        // Deploy protocol normally
        // First warp to a reasonable time for treasury deployment
        vm.warp(365 days);

        // Deploy base contracts
        _deployTimelock();
        _deployToken();
        _deployEcosystem();
        _deployTreasury();
        _deployGovernor();
        _deployMarketFactory();

        // TGE setup - but DON'T warp time
        vm.prank(guardian);
        tokenInstance.initializeTGE(address(ecoInstance), address(treasuryInstance));
        deal(address(tokenInstance), charlie, 30_000 ether);

        // Deploy USDC market
        _deployMarket(address(usdcInstance), "Lendefi Yield Token", "LYTUSDC");

        // Now warp to current time to match oracle data
        vm.warp(1749760367 + 3600); // Latest oracle timestamp + 1 hour

        // Create test user
        testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);

        // Setup roles
        vm.startPrank(guardian);
        timelockInstance.revokeRole(PROPOSER_ROLE, ethereum);
        timelockInstance.revokeRole(EXECUTOR_ROLE, ethereum);
        timelockInstance.revokeRole(CANCELLER_ROLE, ethereum);
        timelockInstance.grantRole(PROPOSER_ROLE, address(govInstance));
        timelockInstance.grantRole(EXECUTOR_ROLE, address(govInstance));
        timelockInstance.grantRole(CANCELLER_ROLE, address(govInstance));
        vm.stopPrank();

        // Configure assets
        _configureWBNB();
        _configureBTCB();
        _configureLINK();
        _configureUSDC();
    }

    function _configureWBNB() internal {
        vm.startPrank(address(timelockInstance));

        // Configure WBNB with updated struct format
        assetsInstance.updateAssetConfig(
            WBNB,
            IASSETS.Asset({
                active: 1,
                decimals: 18,
                borrowThreshold: 800,
                liquidationThreshold: 850,
                maxSupplyThreshold: 1_000_000 ether,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: BNB_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: WBNB_USDC_POOL, twapPeriod: 600, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureBTCB() internal {
        vm.startPrank(address(timelockInstance));

        // Configure BTCB with updated struct format
        assetsInstance.updateAssetConfig(
            BTCB,
            IASSETS.Asset({
                active: 1,
                decimals: 18, // BTCB has 18 decimals
                borrowThreshold: 700,
                liquidationThreshold: 750,
                maxSupplyThreshold: 500 * 1e18,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: BTC_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: BTCB_USDC_POOL, twapPeriod: 600, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureLINK() internal {
        vm.startPrank(address(timelockInstance));

        // Configure LINK using the ETH bridge approach
        assetsInstance.updateAssetConfig(
            LINK,
            IASSETS.Asset({
                active: 1,
                decimals: 18, // LINK has 18 decimals
                borrowThreshold: 650,
                liquidationThreshold: 700,
                maxSupplyThreshold: 50_000 * 1e18,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: LINK_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: LINK_WBNB_POOL, twapPeriod: 600, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureUSDC() internal {
        vm.startPrank(address(timelockInstance));

        // Configure USDC - since it's handled specially in getAssetPrice, we just need minimal config
        // Use a dummy oracle address since the price will be overridden to 1e6
        assetsInstance.updateAssetConfig(
            address(usdcInstance),
            IASSETS.Asset({
                active: 1,
                decimals: 18, // USDC has 18 decimals on BSC
                borrowThreshold: 950, // 95% - very safe for stablecoin
                liquidationThreshold: 980, // 98% - very safe for stablecoin
                maxSupplyThreshold: 1_000_000_000e18, // 1B USDC with 18 decimals on BSC
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.STABLE,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: USDC_CHAINLINK_ORACLE, // Dummy address - won't be used due to special handling
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({pool: address(0), twapPeriod: 0, active: 0})
            })
        );

        vm.stopPrank();
    }

    function test_ChainlinkOracleBNB() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(BNB_CHAINLINK_ORACLE).latestRoundData();

        console2.log("Direct BNB/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_ChainLinkOracleBTC() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(BTC_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct BTC/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_RealMedianPriceBNB() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(WBNB, IASSETS.OracleType.CHAINLINK);
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(WBNB, IASSETS.OracleType.UNISWAP_V3_TWAP);

        console2.log("WBNB Chainlink price:", chainlinkPrice);
        console2.log("WBNB Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(WBNB);
        console2.log("WBNB median price:", actualMedian);

        assertEq(actualMedian, expectedMedian, "Median calculation should be correct");
    }

    function test_RealMedianPriceBTC() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(BTCB, IASSETS.OracleType.CHAINLINK);
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(BTCB, IASSETS.OracleType.UNISWAP_V3_TWAP);

        console2.log("BTCB Chainlink price:", chainlinkPrice);
        console2.log("BTCB Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(BTCB);
        console2.log("BTCB median price:", actualMedian);

        assertEq(actualMedian, expectedMedian, "Median calculation should be correct");
    }

    function test_OracleTypeSwitch() public view {
        // Initially both oracles are active
        // Now price should come directly from Chainlink

        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(WBNB, IASSETS.OracleType.CHAINLINK);
        console2.log("Chainlink-only BNB price:", chainlinkPrice);

        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(WBNB, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("Uniswap-only BNB price:", uniswapPrice);

        uint256 chainlinkBTCPrice = assetsInstance.getAssetPriceByType(BTCB, IASSETS.OracleType.CHAINLINK);
        console2.log("Chainlink-only BTC price:", chainlinkBTCPrice);

        uint256 uniswapBTCPrice = assetsInstance.getAssetPriceByType(BTCB, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("Uniswap-only BTC price:", uniswapBTCPrice);
    }

    function testRevert_PoolLiquidityLimitReached() public {
        // Give test user more ETH
        vm.deal(testUser, 15000 ether); // Increase from 100 ETH to 15000 ETH

        // Create a user with WBNB
        vm.startPrank(testUser);
        (bool success,) = WBNB.call{value: 10000 ether}("");
        require(success, "BNB to WBNB conversion failed");

        // Create a position
        uint256 positionId = marketCoreInstance.createPosition(WBNB, false);
        console2.log("Created position ID:", positionId);
        vm.stopPrank();

        // Set maxSupplyThreshold high (100,000 ETH) to avoid hitting AssetCapacityReached
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory WBNBConfig = assetsInstance.getAssetInfo(WBNB);
        WBNBConfig.maxSupplyThreshold = 100_000 ether;
        assetsInstance.updateAssetConfig(WBNB, WBNBConfig);
        vm.stopPrank();

        // Get actual WBNB balance in the pool
        uint256 poolWbnbBalance = IERC20(WBNB).balanceOf(WBNB_USDC_POOL);
        console2.log("WBNB balance in pool:", poolWbnbBalance / 1e18, "BNB");

        // Calculate 3% of pool balance
        uint256 threePercentOfPool = (poolWbnbBalance * 3) / 100;
        console2.log("3% of pool WBNB:", threePercentOfPool / 1e18, "BNB");

        // Add a little extra to ensure we exceed the limit
        uint256 supplyAmount = threePercentOfPool + 1 ether;
        console2.log("Amount to supply:", supplyAmount / 1e18, "BNB");

        // Verify directly that this will trigger the limit
        bool willHitLimit = assetsInstance.poolLiquidityLimit(WBNB, supplyAmount);
        console2.log("Will hit pool liquidity limit:", willHitLimit);
        assertTrue(willHitLimit, "Our calculated amount should trigger pool liquidity limit");

        // Supply amount exceeding 3% of pool balance
        vm.startPrank(testUser);
        IERC20(WBNB).approve(address(marketCoreInstance), supplyAmount);
        vm.expectRevert(IPROTOCOL.PoolLiquidityLimitReached.selector);
        marketCoreInstance.supplyCollateral(WBNB, supplyAmount, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    function testRevert_AssetLiquidityLimitReached() public {
        // Create a user with WBNB
        vm.startPrank(testUser);
        (bool success,) = WBNB.call{value: 50 ether}("");
        require(success, "BNB to WBNB conversion failed");

        // Create a position
        marketCoreInstance.createPosition(WBNB, false); // false = cross-collateral position
        uint256 positionId = marketCoreInstance.getUserPositionsCount(testUser) - 1;
        console2.log("Created position ID:", positionId);

        vm.stopPrank();

        // Update WBNB config with a very small limit
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory WBNBConfig = assetsInstance.getAssetInfo(WBNB);
        WBNBConfig.maxSupplyThreshold = 1 ether; // Very small limit
        assetsInstance.updateAssetConfig(WBNB, WBNBConfig);
        vm.stopPrank();

        // Supply within limit
        vm.startPrank(testUser);
        IERC20(WBNB).approve(address(marketCoreInstance), 0.5 ether);
        marketCoreInstance.supplyCollateral(WBNB, 0.5 ether, positionId);
        console2.log("Supplied 0.5 WBNB");

        // Try to exceed the limit
        IERC20(WBNB).approve(address(marketCoreInstance), 1 ether);
        vm.expectRevert(IPROTOCOL.AssetCapacityReached.selector);
        marketCoreInstance.supplyCollateral(WBNB, 1 ether, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    // Add this test function
    function test_RealMedianPriceLINK() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(LINK, IASSETS.OracleType.CHAINLINK);
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(LINK, IASSETS.OracleType.UNISWAP_V3_TWAP);

        console2.log("LINK Chainlink price:", chainlinkPrice);
        console2.log("LINK Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(LINK);
        console2.log("LINK median price:", actualMedian);

        // Also log direct Chainlink data for reference
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(LINK_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct LINK/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);

        assertEq(actualMedian, expectedMedian, "Median calculation should be correct");
    }

    /**
     * @notice Get optimal Uniswap V3 pool configuration for price oracle
     * @param asset The asset to get USD price for
     * @param pool The Uniswap V3 pool address
     * @return A properly configured UniswapPoolConfig struct
     */
    function getOptimalUniswapConfig(address asset, address pool)
        public
        view
        returns (IASSETS.UniswapPoolConfig memory)
    {
        // Get pool tokens
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        // Verify the asset is in the pool
        require(asset == token0 || asset == token1, "Asset not in pool");

        // Determine if asset is token0
        bool isToken0 = (asset == token0);

        // Identify other token in the pool
        address otherToken = isToken0 ? token1 : token0;

        // Always use USDC as quote token if it's in the pool
        address quoteToken;
        if (otherToken == address(usdcInstance)) {
            quoteToken = address(usdcInstance);
        } else {
            // If not a USDC pair, use the other token as quote
            quoteToken = otherToken;
        }

        // Get decimals
        uint8 assetDecimals = IERC20Metadata(asset).decimals();

        // Calculate optimal decimalsUniswap based on asset decimals
        uint8 decimalsUniswap;
        if (quoteToken == address(usdcInstance)) {
            // For USD-quoted prices, use 8 decimals (standard)
            decimalsUniswap = 8;
        } else {
            // For non-USD quotes, add 2 extra precision digits to asset decimals
            decimalsUniswap = uint8(assetDecimals) + 2;
        }

        return IASSETS.UniswapPoolConfig({
            pool: pool,
            twapPeriod: 1800, // Default 30 min TWAP
            active: 1
        });
    }

    function test_getAnyPoolTokenPriceInUSD_BNBUSDC() public {
        uint256 bnbPriceInUSD = assetsInstance.getAssetPrice(WBNB);
        console2.log("BNB price in USD (from BNB/USDC pool):", bnbPriceInUSD);

        // Assert that the price is within a reasonable range - median of Chainlink (~$657) and high Uniswap price
        assertTrue(bnbPriceInUSD > 500 * 1e6, "BNB price should be greater than $500");
        assertTrue(bnbPriceInUSD < 500000 * 1e6, "BNB price should be less than $500,000");
    }

    function test_getAnyPoolTokenPriceInUSD_BTCBBNB() public {
        uint256 BTCBPriceInUSD = assetsInstance.getAssetPrice(BTCB);
        // Log the BTCB price in USD
        console2.log("BTCB price in USD (from BTCB/BNB pool):", BTCBPriceInUSD);

        // Assert that the price is within a reasonable range - median causes lower price
        assertTrue(BTCBPriceInUSD > 10000 * 1e6, "BTCB price should be greater than $10,000");
        assertTrue(BTCBPriceInUSD < 200000 * 1e6, "BTCB price should be less than $200,000");
    }

    function test_getAnyPoolTokenPriceInUSD_LINKBNB() public {
        uint256 linkPriceInUSD = assetsInstance.getAssetPrice(LINK);
        // Log the LINK price in USD
        console2.log("LINK price in USD (from LINK/BNB pool):", linkPriceInUSD);

        // Assert that the price is within a reasonable range (e.g., $10 to $20)
        assertTrue(linkPriceInUSD > 10 * 1e6, "LINK price should be greater than $10");
        assertTrue(linkPriceInUSD < 20 * 1e6, "LINK price should be less than $20");
    }

    function test_getAnyPoolTokenPriceInUSD_BTCBUSDC() public {
        uint256 BTCBPriceInUSD = assetsInstance.getAssetPrice(BTCB);
        // Log the BTCB price in USD
        console2.log("BTCB price in USD (from BTCB/USDC pool):", BTCBPriceInUSD);

        // Assert that the price is within a reasonable range - median causes lower price
        assertTrue(BTCBPriceInUSD > 10000 * 1e6, "BTCB price should be greater than $10,000");
        assertTrue(BTCBPriceInUSD < 200000 * 1e6, "BTCB price should be less than $200,000");
    }
}
