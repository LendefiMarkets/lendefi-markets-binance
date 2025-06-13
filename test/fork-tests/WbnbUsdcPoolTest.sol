// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {UniswapTickMath} from "../../contracts/markets/lib/UniswapTickMath.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";

// Minimal interface to interact with PancakeSwap V3 pool
interface IPancakeV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128);

    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

contract WbnbUsdcPoolTest is Test {
    // WBNB/USDC PancakeSwap V3 pool on BSC
    address public constant WBNB_USDC_POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    // WBNB/USDT pool for conversion comparison
    address public constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;

    IPancakeV3Pool public wbnbUsdcPool = IPancakeV3Pool(WBNB_USDC_POOL);
    IPancakeV3Pool public wbnbUsdtPool = IPancakeV3Pool(WBNB_USDT_POOL);

    function setUp() public {
        // Fork BSC mainnet at a recent block
        vm.createSelectFork("binance");
    }

    function test_WbnbUsdcPoolDebug() public view {
        console2.log("=== WBNB/USDC Pool Debug ===");
        console2.log("WBNB/USDC Pool:", WBNB_USDC_POOL);
        console2.log("Token0:", wbnbUsdcPool.token0());
        console2.log("Token1:", wbnbUsdcPool.token1());
        console2.log("Expected WBNB token:", WBNB);
        console2.log("Expected USDC token:", USDC);

        // Get decimals
        uint8 decimals0 = IERC20Metadata(wbnbUsdcPool.token0()).decimals();
        uint8 decimals1 = IERC20Metadata(wbnbUsdcPool.token1()).decimals();
        console2.log("Decimals0:", decimals0);
        console2.log("Decimals1:", decimals1);

        // Check if WBNB is in the pool
        bool hasWBNB = (wbnbUsdcPool.token0() == WBNB || wbnbUsdcPool.token1() == WBNB);
        bool wbnbIsToken0 = (wbnbUsdcPool.token0() == WBNB);
        console2.log("Pool has WBNB:", hasWBNB);
        console2.log("WBNB is token0:", wbnbIsToken0);

        // Check if USDC is in the pool
        bool hasUSDC = (wbnbUsdcPool.token0() == USDC || wbnbUsdcPool.token1() == USDC);
        console2.log("Pool has USDC:", hasUSDC);

        // Try different TWAP periods
        uint32[4] memory periods = [uint32(600), uint32(300), uint32(180), uint32(60)]; // 10min, 5min, 3min, 1min

        for (uint256 i = 0; i < periods.length; i++) {
            console2.log("--- Trying TWAP period:", periods[i], "seconds ---");

            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = periods[i];
            secondsAgos[1] = 0; // now

            // Try to observe
            try wbnbUsdcPool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
                // Calculate average tick over the time window
                int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
                int24 averageTick = int24(tickDelta / int56(uint56(secondsAgos[0])));

                console2.log("SUCCESS! Average tick:", uint256(int256(averageTick >= 0 ? averageTick : -averageTick)));
                console2.log("Tick is negative:", averageTick < 0);

                if (hasWBNB && hasUSDC) {
                    console2.log("--- Direct USD pool: WBNB/USDC ---");
                    
                    // Test both isToken0 values to see which gives correct price
                    uint256 wbnbPriceAsToken0 = UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDC_POOL), true, 1e6, periods[i]);
                    uint256 wbnbPriceAsToken1 = UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDC_POOL), false, 1e6, periods[i]);
                    
                    console2.log("WBNB price treating WBNB as token0:", wbnbPriceAsToken0);
                    console2.log("WBNB price treating WBNB as token1:", wbnbPriceAsToken1);
                    console2.log("Using isToken0=", wbnbIsToken0, "gives price:", wbnbIsToken0 ? wbnbPriceAsToken0 : wbnbPriceAsToken1);
                    
                    // Compare with USDT pool for reference
                    console2.log("--- Comparison with USDT pool ---");
                    uint256 wbnbPriceInUSDT = UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDT_POOL), false, 1e6, periods[i]);
                    console2.log("WBNB price in USD (from USDT pool):", wbnbPriceInUSDT);
                } else {
                    console2.log("ERROR: Pool doesn't contain both WBNB and USDC as expected");
                }

                break; // Stop at first successful period
            } catch {
                console2.log("FAILED - insufficient history for", periods[i], "seconds");
                continue;
            }
        }
    }
}