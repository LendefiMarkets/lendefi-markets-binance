// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BasicDeploy.sol";
import {console2} from "forge-std/console2.sol";
import {IASSETS} from "../../contracts/interfaces/IASSETS.sol";
import {IPROTOCOL} from "../../contracts/interfaces/IProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../../contracts/vendor/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OracleForkTest is BasicDeploy {
    // BSC addresses
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB instead of WETH
    address constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c; // BTCB instead of WBTC
    address constant LINK = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD; // LINK on BSC
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC on BSC

    // PancakeSwap V3 pools on BSC
    // NOTE: These are placeholder addresses - need to get actual pool addresses
    address constant LINK_WBNB_POOL =
        address(0); // TODO: Get LINK/WBNB pool address
    address constant BTCB_USDC_POOL =
        address(0); // TODO: Get BTCB/USDC pool address
    address constant WBNB_USDC_POOL =
        0xf2688fb5b81049dfb7703ada5e770543770612c4; // WBNB/USDC pool with 0.01% fee

    // Chainlink oracles on BSC
    address constant BNB_CHAINLINK_ORACLE =
        0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // BNB/USD oracle
    address constant BTC_CHAINLINK_ORACLE =
        0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf; // BTC/USD oracle
    address constant LINK_CHAINLINK_ORACLE =
        0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8; // LINK/USD oracle
    address constant USDC_CHAINLINK_ORACLE =
        0x51597f405303C4377E36123cBc172b13269EA163; // USDC/USD oracle

    uint256 mainnetFork;
    address testUser;

    function setUp() public {
        // Fork mainnet at a specific block
        mainnetFork = vm.createFork("bsc", 22607428); // Fork BSC instead of mainnet
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

        // Deploy USDC market
        _deployMarket(address(usdcInstance), "Lendefi Yield Token", "LYTUSDC");

        // Now warp to current time to match oracle data
        vm.warp(1748748827 + 3600); // Oracle timestamp + 1 hour

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

        // TGE setup - but DON'T warp time
        vm.prank(guardian);
        tokenInstance.initializeTGE(
            address(ecoInstance),
            address(treasuryInstance)
        );

        // Configure assets
        _configureWBNB();
        _configureBTCB();
        _configureLINK();
        _configureUSDC();
    }

    function _configureWETH() internal {
        vm.startPrank(address(timelockInstance));

        // Configure WETH with updated struct format
        assetsInstance.updateAssetConfig(
            WETH,
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
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: WETH_CHAINLINK_ORACLE,
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({
                    pool: WETH_USDC_POOL,
                    twapPeriod: 1800,
                    active: 1
                })
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
                maxSupplyThreshold: 500 * 1e8,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: BTC_CHAINLINK_ORACLE,
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({
                    pool: BTCB_USDC_POOL,
                    twapPeriod: 1800,
                    active: 1
                })
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
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: LINK_CHAINLINK_ORACLE,
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({
                    pool: LINK_WETH_POOL,
                    twapPeriod: 1800,
                    active: 1
                })
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
                decimals: 6,
                borrowThreshold: 950, // 95% - very safe for stablecoin
                liquidationThreshold: 980, // 98% - very safe for stablecoin
                maxSupplyThreshold: 1_000_000_000e6, // 1B USDC
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.STABLE,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: USDC_CHAINLINK_ORACLE, // Dummy address - won't be used due to special handling
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({
                    pool: address(0),
                    twapPeriod: 0,
                    active: 0
                })
            })
        );

        vm.stopPrank();
    }

    function test_ChainlinkOracleETH() public view {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = AggregatorV3Interface(WETH_CHAINLINK_ORACLE).latestRoundData();

        console2.log("Direct ETH/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_ChainLinkOracleBTC() public view {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = AggregatorV3Interface(BTC_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct BTC/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_RealMedianPriceETH() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(
            WETH,
            IASSETS.OracleType.CHAINLINK
        );
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(
            WETH,
            IASSETS.OracleType.UNISWAP_V3_TWAP
        );

        console2.log("WETH Chainlink price:", chainlinkPrice);
        console2.log("WETH Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(WETH);
        console2.log("WETH median price:", actualMedian);

        assertEq(
            actualMedian,
            expectedMedian,
            "Median calculation should be correct"
        );
    }

    function test_RealMedianPriceBTC() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(
            WBTC,
            IASSETS.OracleType.CHAINLINK
        );
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(
            WBTC,
            IASSETS.OracleType.UNISWAP_V3_TWAP
        );

        console2.log("WBTC Chainlink price:", chainlinkPrice);
        console2.log("WBTC Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(WBTC);
        console2.log("WBTC median price:", actualMedian);

        assertEq(
            actualMedian,
            expectedMedian,
            "Median calculation should be correct"
        );
    }

    function test_OracleTypeSwitch() public view {
        // Initially both oracles are active
        // Now price should come directly from Chainlink

        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(
            WETH,
            IASSETS.OracleType.CHAINLINK
        );
        console2.log("Chainlink-only ETH price:", chainlinkPrice);

        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(
            WETH,
            IASSETS.OracleType.UNISWAP_V3_TWAP
        );
        console2.log("Uniswap-only ETH price:", uniswapPrice);

        uint256 chainlinkBTCPrice = assetsInstance.getAssetPriceByType(
            WBTC,
            IASSETS.OracleType.CHAINLINK
        );
        console2.log("Chainlink-only BTC price:", chainlinkBTCPrice);

        uint256 uniswapBTCPrice = assetsInstance.getAssetPriceByType(
            WBTC,
            IASSETS.OracleType.UNISWAP_V3_TWAP
        );
        console2.log("Uniswap-only BTC price:", uniswapBTCPrice);
    }

    function testRevert_PoolLiquidityLimitReached() public {
        // Give test user more ETH
        vm.deal(testUser, 15000 ether); // Increase from 100 ETH to 15000 ETH

        // Create a user with WETH
        vm.startPrank(testUser);
        (bool success, ) = WETH.call{value: 10000 ether}("");
        require(success, "BNB to WBNB conversion failed");

        // Create a position
        uint256 positionId = marketCoreInstance.createPosition(WETH, false);
        console2.log("Created position ID:", positionId);
        vm.stopPrank();

        // Set maxSupplyThreshold high (100,000 ETH) to avoid hitting AssetCapacityReached
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory wethConfig = assetsInstance.getAssetInfo(WETH);
        wethConfig.maxSupplyThreshold = 100_000 ether;
        assetsInstance.updateAssetConfig(WETH, wethConfig);
        vm.stopPrank();

        // Get actual WETH balance in the pool
        uint256 poolWbnbBalance = IERC20(WBNB).balanceOf(WBNB_USDC_POOL);
        console2.log("WBNB balance in pool:", poolWbnbBalance / 1e18, "BNB");

        // Calculate 3% of pool balance
        uint256 threePercentOfPool = (poolWbnbBalance * 3) / 100;
        console2.log("3% of pool WBNB:", threePercentOfPool / 1e18, "BNB");

        // Add a little extra to ensure we exceed the limit
        uint256 supplyAmount = threePercentOfPool + 1 ether;
        console2.log("Amount to supply:", supplyAmount / 1e18, "BNB");

        // Verify directly that this will trigger the limit
        bool willHitLimit = assetsInstance.poolLiquidityLimit(
            WETH,
            supplyAmount
        );
        console2.log("Will hit pool liquidity limit:", willHitLimit);
        assertTrue(
            willHitLimit,
            "Our calculated amount should trigger pool liquidity limit"
        );

        // Supply amount exceeding 3% of pool balance
        vm.startPrank(testUser);
        IERC20(WETH).approve(address(marketCoreInstance), supplyAmount);
        vm.expectRevert(IPROTOCOL.PoolLiquidityLimitReached.selector);
        marketCoreInstance.supplyCollateral(WETH, supplyAmount, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    function testRevert_AssetLiquidityLimitReached() public {
        // Create a user with WETH
        vm.startPrank(testUser);
        (bool success, ) = WETH.call{value: 50 ether}("");
        require(success, "BNB to WBNB conversion failed");

        // Create a position
        marketCoreInstance.createPosition(WETH, false); // false = cross-collateral position
        uint256 positionId = marketCoreInstance.getUserPositionsCount(
            testUser
        ) - 1;
        console2.log("Created position ID:", positionId);

        vm.stopPrank();

        // Update WETH config with a very small limit
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory wethConfig = assetsInstance.getAssetInfo(WETH);
        wethConfig.maxSupplyThreshold = 1 ether; // Very small limit
        assetsInstance.updateAssetConfig(WETH, wethConfig);
        vm.stopPrank();

        // Supply within limit
        vm.startPrank(testUser);
        IERC20(WETH).approve(address(marketCoreInstance), 0.5 ether);
        marketCoreInstance.supplyCollateral(WETH, 0.5 ether, positionId);
        console2.log("Supplied 0.5 WETH");

        // Try to exceed the limit
        IERC20(WETH).approve(address(marketCoreInstance), 1 ether);
        vm.expectRevert(IPROTOCOL.AssetCapacityReached.selector);
        marketCoreInstance.supplyCollateral(WETH, 1 ether, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    // Add this test function
    function test_RealMedianPriceLINK() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(
            LINK,
            IASSETS.OracleType.CHAINLINK
        );
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(
            LINK,
            IASSETS.OracleType.UNISWAP_V3_TWAP
        );

        console2.log("LINK Chainlink price:", chainlinkPrice);
        console2.log("LINK Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualMedian = assetsInstance.getAssetPrice(LINK);
        console2.log("LINK median price:", actualMedian);

        // Also log direct Chainlink data for reference
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = AggregatorV3Interface(LINK_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct LINK/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);

        assertEq(
            actualMedian,
            expectedMedian,
            "Median calculation should be correct"
        );
    }

    /**
     * @notice Get optimal Uniswap V3 pool configuration for price oracle
     * @param asset The asset to get USD price for
     * @param pool The Uniswap V3 pool address
     * @return A properly configured UniswapPoolConfig struct
     */
    function getOptimalUniswapConfig(
        address asset,
        address pool
    ) public view returns (IASSETS.UniswapPoolConfig memory) {
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

        return
            IASSETS.UniswapPoolConfig({
                pool: pool,
                twapPeriod: 1800, // Default 30 min TWAP
                active: 1
            });
    }

    function test_getAnyPoolTokenPriceInUSD_ETHUSDC() public {
        uint256 ethPriceInUSD = assetsInstance.getAssetPrice(WETH);
        console2.log("ETH price in USD (from ETH/USDC pool):", ethPriceInUSD);

        // Assert that the price is within a reasonable range (e.g., $1000 to $5000)
        assertTrue(
            ethPriceInUSD > 1700 * 1e6,
            "ETH price should be greater than $1700"
        );
        assertTrue(
            ethPriceInUSD < 5000 * 1e6,
            "ETH price should be less than $5000"
        );
    }

    function test_getAnyPoolTokenPriceInUSD_WBTCETH() public {
        uint256 wbtcPriceInUSD = assetsInstance.getAssetPrice(WBTC);
        // Log the WBTC price in USD
        console2.log("WBTC price in USD (from WBTC/ETH pool):", wbtcPriceInUSD);

        // Assert that the price is within a reasonable range (e.g., $90,000 to $120,000)
        assertTrue(
            wbtcPriceInUSD > 90000 * 1e6,
            "WBTC price should be greater than $90,000"
        );
        assertTrue(
            wbtcPriceInUSD < 120000 * 1e6,
            "WBTC price should be less than $120,000"
        );
    }

    function test_getAnyPoolTokenPriceInUSD_LINKETH() public {
        uint256 linkPriceInUSD = assetsInstance.getAssetPrice(LINK);
        // Log the LINK price in USD
        console2.log("LINK price in USD (from LINK/ETH pool):", linkPriceInUSD);

        // Assert that the price is within a reasonable range (e.g., $10 to $20)
        assertTrue(
            linkPriceInUSD > 10 * 1e6,
            "LINK price should be greater than $10"
        );
        assertTrue(
            linkPriceInUSD < 20 * 1e6,
            "LINK price should be less than $20"
        );
    }

    function test_getAnyPoolTokenPriceInUSD_WBTCUSDC() public {
        uint256 wbtcPriceInUSD = assetsInstance.getAssetPrice(WBTC);
        // Log the WBTC price in USD
        console2.log(
            "WBTC price in USD (from WBTC/USDC pool):",
            wbtcPriceInUSD
        );

        // Assert that the price is within a reasonable range (e.g., $90,000 to $120,000)
        assertTrue(
            wbtcPriceInUSD > 90000 * 1e6,
            "WBTC price should be greater than $90,000"
        );
        assertTrue(
            wbtcPriceInUSD < 120000 * 1e6,
            "WBTC price should be less than $120,000"
        );
    }
}
