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

contract LinkPancakeTwapTest is Test {
    // LINK/WBNB PancakeSwap V3 pool on BSC 0x0e1893beeb4d0913d26b9614b18aea29c56d94b9
    address public constant LINK_WBNB_POOL = 0x0E1893BEEb4d0913d26B9614B18Aea29c56d94b9;
    // WBNB/USDT pool for conversion
    address public constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;

    IPancakeV3Pool public linkPool = IPancakeV3Pool(LINK_WBNB_POOL);
    IPancakeV3Pool public wbnbPool = IPancakeV3Pool(WBNB_USDT_POOL);

    function setUp() public {
        // Fork BSC mainnet at a recent block
        vm.createSelectFork("binance");
    }

    function test_LinkWbnbPoolDebug() public view {
        console2.log("=== LINK/WBNB Pool Debug ===");
        console2.log("LINK/WBNB Pool:", LINK_WBNB_POOL);
        console2.log("Token0:", linkPool.token0());
        console2.log("Token1:", linkPool.token1());

        // Get decimals
        uint8 decimals0 = IERC20Metadata(linkPool.token0()).decimals();
        uint8 decimals1 = IERC20Metadata(linkPool.token1()).decimals();
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
            try linkPool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
                // Calculate average tick over the time window
                int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
                int24 averageTick = int24(tickDelta / int56(uint56(secondsAgos[0])));

                console2.log("SUCCESS! Average tick:", uint256(int256(averageTick >= 0 ? averageTick : -averageTick)));
                console2.log("Tick is negative:", averageTick < 0);

                // Get LINK price directly using UniswapTickMath
                // LINK is token1, so isToken0 = false
                uint256 linkPriceInWBNB =
                    UniswapTickMath.getRawPrice(IUniswapV3Pool(LINK_WBNB_POOL), false, 1e18, periods[i]);
                console2.log("LINK price in WBNB (1e18):", linkPriceInWBNB);

                // Get WBNB price in USDT
                uint256 wbnbPriceInUSDT =
                    UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDT_POOL), false, 1e6, periods[i]);
                console2.log("WBNB price in USDT (1e6):", wbnbPriceInUSDT);

                // Convert LINK price to USD
                uint256 linkPriceInUSD = FullMath.mulDiv(linkPriceInWBNB, wbnbPriceInUSDT, 1e18);
                console2.log("LINK price in USD (calculated):", linkPriceInUSD);

                // Also try getting LINK price directly in 1e6 precision
                uint256 linkPriceDirect =
                    UniswapTickMath.getRawPrice(IUniswapV3Pool(LINK_WBNB_POOL), false, 1e6, periods[i]);
                console2.log("LINK price direct (1e6):", linkPriceDirect);

                break; // Stop at first successful period
            } catch {
                console2.log("FAILED - insufficient history for", periods[i], "seconds");
                continue;
            }
        }
    }

    function test_WbnbUsdtPoolDebug() public view {
        console2.log("=== WBNB/USDT Pool Debug ===");
        console2.log("WBNB/USDT Pool:", WBNB_USDT_POOL);
        console2.log("Token0:", wbnbPool.token0());
        console2.log("Token1:", wbnbPool.token1());

        // Get WBNB price in USDT (WBNB is token1, USDT is token0)
        uint256 wbnbPriceInUSDT = UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDT_POOL), false, 1e6, 600);
        console2.log("WBNB price in USDT:", wbnbPriceInUSDT);
    }
}
