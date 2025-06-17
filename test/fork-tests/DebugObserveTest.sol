// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";

contract DebugObserveTest is Test {
    // BSC PancakeSwap V3 pools
    address constant WBNB_USDC_POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4; // WBNB/USDC pool with 0.01% fee
    address constant BTCB_USDC_POOL = 0x46Cf1cF8c69595804ba91dFdd8d6b960c9B0a7C4; // BTCB/USDC pool
    address constant LINK_WBNB_POOL = 0x0E1893BEEb4d0913d26B9614B18Aea29c56d94b9; // LINK/WBNB pool

    uint256 mainnetFork;

    function setUp() public {
        // Fork BSC mainnet
        mainnetFork = vm.createFork("binance", 51344326);
        vm.selectFork(mainnetFork);

        // Warp to current time to match oracle data
        vm.warp(1749760367 + 3600); // Latest oracle timestamp + 1 hour
    }

    function test_DebugWBNBUSDCObserve() public view {
        IUniswapV3Pool pool = IUniswapV3Pool(WBNB_USDC_POOL);

        console2.log("=== WBNB/USDC Pool Debug ===");
        console2.log("Pool address:", address(pool));
        console2.log("Token0:", pool.token0());
        console2.log("Token1:", pool.token1());

        // Test different TWAP periods
        uint32[] memory twapPeriods = new uint32[](3);
        twapPeriods[0] = 600; // 10 minutes
        twapPeriods[1] = 1800; // 30 minutes
        twapPeriods[2] = 3600; // 1 hour

        for (uint256 i = 0; i < twapPeriods.length; i++) {
            uint32 twapPeriod = twapPeriods[i];
            console2.log("\n--- TWAP Period:", twapPeriod, "seconds ---");

            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapPeriod;
            secondsAgos[1] = 0;

            try pool.observe(secondsAgos) returns (
                int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s
            ) {
                console2.log("Observe successful for period:", twapPeriod);
                console2.log("tickCumulatives[0] (older):", tickCumulatives[0]);
                console2.log("tickCumulatives[1] (newer):", tickCumulatives[1]);

                int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
                console2.log("Tick delta:", tickDelta);

                int24 averageTick = int24(tickDelta / int56(uint56(twapPeriod)));
                console2.log("Average tick:", averageTick);

                console2.log("secondsPerLiquidity[0]:", secondsPerLiquidityCumulativeX128s[0]);
                console2.log("secondsPerLiquidity[1]:", secondsPerLiquidityCumulativeX128s[1]);
            } catch {
                console2.log("Observe FAILED for period:", twapPeriod);
            }
        }
    }

    function test_DebugBTCBUSDCObserve() public view {
        IUniswapV3Pool pool = IUniswapV3Pool(BTCB_USDC_POOL);

        console2.log("\n=== BTCB/USDC Pool Debug ===");
        console2.log("Pool address:", address(pool));
        console2.log("Token0:", pool.token0());
        console2.log("Token1:", pool.token1());

        uint32 twapPeriod = 600;
        console2.log("TWAP Period:", twapPeriod, "seconds");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapPeriod;
        secondsAgos[1] = 0;

        try pool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            console2.log("Observe successful");
            console2.log("tickCumulatives[0] (older):", tickCumulatives[0]);
            console2.log("tickCumulatives[1] (newer):", tickCumulatives[1]);

            int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
            console2.log("Tick delta:", tickDelta);

            int24 averageTick = int24(tickDelta / int56(uint56(twapPeriod)));
            console2.log("Average tick:", averageTick);
        } catch {
            console2.log("Observe FAILED");
        }
    }

    function test_DebugLINKWBNBObserve() public view {
        IUniswapV3Pool pool = IUniswapV3Pool(LINK_WBNB_POOL);

        console2.log("\n=== LINK/WBNB Pool Debug ===");
        console2.log("Pool address:", address(pool));
        console2.log("Token0:", pool.token0());
        console2.log("Token1:", pool.token1());

        uint32 twapPeriod = 600;
        console2.log("TWAP Period:", twapPeriod, "seconds");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapPeriod;
        secondsAgos[1] = 0;

        try pool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            console2.log("Observe successful");
            console2.log("tickCumulatives[0] (older):", tickCumulatives[0]);
            console2.log("tickCumulatives[1] (newer):", tickCumulatives[1]);

            int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
            console2.log("Tick delta:", tickDelta);

            int24 averageTick = int24(tickDelta / int56(uint56(twapPeriod)));
            console2.log("Average tick:", averageTick);
        } catch {
            console2.log("Observe FAILED");
        }
    }

    function test_DebugMultiplePeriodsWBNBUSDC() public view {
        IUniswapV3Pool pool = IUniswapV3Pool(WBNB_USDC_POOL);

        console2.log("\n=== Multiple Periods Debug for WBNB/USDC ===");

        // Try observing from different starting points
        uint32[] memory periods = new uint32[](5);
        periods[0] = 300; // 5 minutes
        periods[1] = 600; // 10 minutes
        periods[2] = 900; // 15 minutes
        periods[3] = 1800; // 30 minutes
        periods[4] = 3600; // 1 hour

        for (uint256 i = 0; i < periods.length; i++) {
            uint32 period = periods[i];

            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = period;
            secondsAgos[1] = 0;

            try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
                int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
                int24 averageTick = int24(tickDelta / int56(uint56(period)));

                console2.log("Period:", period);
                console2.log("Delta:", tickDelta);
                console2.log("Avg Tick:", averageTick);
            } catch {
                console2.log("Period FAILED:", period);
            }
        }
    }
}
