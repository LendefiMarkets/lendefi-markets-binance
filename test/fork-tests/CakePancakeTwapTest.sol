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

contract CakePancakeTwapTest is Test {
    // CAKE/WBNB PancakeSwap V3 pool on BSC
    address public constant CAKE_WBNB_POOL = 0x133B3D95bAD5405d14d53473671200e9342896BF;
    address public constant CAKE_TOKEN = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    // WBNB/USDT pool for conversion
    address public constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;

    IPancakeV3Pool public cakePool = IPancakeV3Pool(CAKE_WBNB_POOL);
    IPancakeV3Pool public wbnbPool = IPancakeV3Pool(WBNB_USDT_POOL);

    function setUp() public {
        // Fork BSC mainnet at a recent block
        vm.createSelectFork("binance");
    }

    function test_CakeWbnbPoolDebug() public view {
        console2.log("=== CAKE/WBNB Pool Debug ===");
        console2.log("CAKE/WBNB Pool:", CAKE_WBNB_POOL);
        console2.log("Token0:", cakePool.token0());
        console2.log("Token1:", cakePool.token1());
        console2.log("Expected CAKE token:", CAKE_TOKEN);

        // Get decimals
        uint8 decimals0 = IERC20Metadata(cakePool.token0()).decimals();
        uint8 decimals1 = IERC20Metadata(cakePool.token1()).decimals();
        console2.log("Decimals0:", decimals0);
        console2.log("Decimals1:", decimals1);

        // Try different TWAP periods
        uint32[4] memory periods = [uint32(600), uint32(300), uint32(180), uint32(60)]; // 10min, 5min, 3min, 1min

        for (uint256 i = 0; i < periods.length; i++) {
            console2.log("--- Trying TWAP period:", periods[i], "seconds ---");

            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = periods[i];
            secondsAgos[1] = 0; // now

            // Try to observe
            try cakePool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
                // Calculate average tick over the time window
                int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
                int24 averageTick = int24(tickDelta / int56(uint56(secondsAgos[0])));

                console2.log("SUCCESS! Average tick:", uint256(int256(averageTick >= 0 ? averageTick : -averageTick)));
                console2.log("Tick is negative:", averageTick < 0);

                // NEW APPROACH: Check if WBNB is in the pool
                address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
                bool hasWBNB = (cakePool.token0() == WBNB || cakePool.token1() == WBNB);
                bool cakeIsToken0 = (cakePool.token0() == CAKE_TOKEN);
                console2.log("Pool has WBNB:", hasWBNB);
                console2.log("CAKE is token0:", cakeIsToken0);

                if (hasWBNB) {
                    console2.log("--- WBNB pool: Converting through WBNB/USDT ---");
                    uint256 cakePriceInWBNB =
                        UniswapTickMath.getRawPrice(IUniswapV3Pool(CAKE_WBNB_POOL), cakeIsToken0, 1e18, 600);
                    uint256 wbnbPriceInUSDT =
                        UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDT_POOL), false, 1e6, 600);
                    uint256 cakePriceInUSD = FullMath.mulDiv(cakePriceInWBNB, wbnbPriceInUSDT, 1e18);
                    console2.log("CAKE price in USD (calculated):", cakePriceInUSD);
                } else {
                    console2.log("--- Direct USD pool: Getting price directly ---");
                    uint256 cakePriceInUSD =
                        UniswapTickMath.getRawPrice(IUniswapV3Pool(CAKE_WBNB_POOL), cakeIsToken0, 1e6, 600);
                    console2.log("CAKE price in USD (direct):", cakePriceInUSD);
                }

                break; // Stop at first successful period
            } catch {
                console2.log("FAILED - insufficient history for", periods[i], "seconds");
                continue;
            }
        }
    }
}
