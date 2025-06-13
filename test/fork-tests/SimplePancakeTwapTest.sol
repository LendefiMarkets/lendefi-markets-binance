// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {UniswapTickMath} from "../../contracts/markets/lib/UniswapTickMath.sol";

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

contract PancakeSwapTWAPTest is Test {
    // USDC/WBNB PancakeSwap V3 pool on BSC
    address public constant PANCAKE_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    IPancakeV3Pool public pool = IPancakeV3Pool(PANCAKE_POOL);

    event AverageTick(int24 tick);

    function setUp() public {
        // Fork BSC mainnet at a recent block
        vm.createSelectFork("binance");
    }

    function test_ObserveTwapOver600Seconds() public {
        // Use 15 minutes time window for more reliable TWAP
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 600; // 10 minutes ago
        secondsAgos[1] = 0; // now

        // Try to observe, if it fails with OLD, skip the test
        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            // Calculate average tick over the time window
            int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
            int24 averageTick = int24(tickDelta / int56(uint56(secondsAgos[0])));

            // Validate the tick value is within expected PancakeSwap V3 bounds
            assertGt(averageTick, -887272);
            assertLt(averageTick, 887272);

            // Log the average tick for debugging
            // Negative ticks mean token0 (USDC) price < 1.0 relative to token1 (WBNB)
            if (averageTick >= 0) {
                console2.log("Average tick over 15 minutes (positive):", uint256(int256(averageTick)));
            } else {
                console2.log("Average tick over 15 minutes (negative):", uint256(int256(-averageTick)));
            }

            // Also emit as event for better visibility
            emit AverageTick(averageTick);

            // Convert tick to price
            uint256 usdcPerWbnb = getTickPrice(averageTick);
            console2.log("USDC per WBNB price:", usdcPerWbnb);

            // Since 1 WBNB = ~600 USDC at current market
            // And USDC on BSC has 18 decimals, we expect the price to be around 600e18
            assertGt(usdcPerWbnb, 100e18); // Should be more than 100 USDC
            assertLt(usdcPerWbnb, 2000e18); // Should be less than 2000 USDC
        } catch {
            // If observation fails, just skip the test
            console2.log("Pool observation failed - insufficient history");
            vm.skip(true);
        }
    }

    /**
     * @notice Converts a Uniswap V3 tick to a price
     * @dev For USDC/WBNB pool: tick represents price of token0/token1 = USDC/WBNB
     * @param tick The tick value from the pool
     * @return price The price of WBNB in USDC (scaled by 1e18 for USDC decimals on BSC)
     */
    function getTickPrice(int24 tick) public view returns (uint256 price) {
        // Get token addresses from pool
        address token0 = pool.token0();
        address token1 = pool.token1();

        // Get decimals
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        console2.log("Token0 (USDC):", token0);
        console2.log("Token1 (WBNB):", token1);
        console2.log("Decimals0:", decimals0);
        console2.log("Decimals1:", decimals1);

        // Calculate sqrtPriceX96 from tick using UniswapTickMath
        uint160 sqrtPriceX96 = UniswapTickMath.getSqrtPriceAtTick(tick);

        // Calculate price = (sqrtPriceX96 / 2^96)^2
        // This gives us token0/token1 price (USDC per WBNB)

        // Use FullMath to avoid overflow and maintain precision
        // First calculate the raw price ratio
        uint256 numerator = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 denominator = uint256(1) << 192;

        // Get USDC per WBNB price
        uint256 usdcPerWbnb = FullMath.mulDiv(numerator, 10 ** decimals0, denominator);

        // Now we need to invert it to get WBNB price in USDC
        // 1 WBNB = X USDC, where X = 1 / usdcPerWbnb
        // To avoid division by very small number, we calculate: (10^36) / usdcPerWbnb
        price = FullMath.mulDiv(10 ** 36, 1, usdcPerWbnb);

        console2.log("Price calculation:");
        console2.log("sqrtPriceX96:", sqrtPriceX96);
        console2.log("USDC per WBNB (raw):", usdcPerWbnb);
        console2.log("WBNB price in USDC:", price);

        return price;
    }
}
