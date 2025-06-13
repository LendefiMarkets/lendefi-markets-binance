// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IUniswapV3Pool} from "./contracts/interfaces/IUniswapV3Pool.sol";
import {LendefiConstants} from "./contracts/markets/lib/LendefiConstants.sol";
import {UniswapTickMath} from "./contracts/markets/lib/UniswapTickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract DebugPoolOrdering is Test {
    address constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    
    function setUp() public {
        vm.createSelectFork("binance");
    }
    
    function test_DebugPoolTokenOrder() public view {
        IUniswapV3Pool pool = IUniswapV3Pool(WBNB_USDT_POOL);
        
        console2.log("=== WBNB/USDT Pool Token Order Debug ===");
        console2.log("Pool address:", WBNB_USDT_POOL);
        console2.log("Token0:", pool.token0());
        console2.log("Token1:", pool.token1());
        console2.log("WBNB_BSC from constants:", LendefiConstants.WBNB_BSC);
        console2.log("USDT_BSC from constants:", LendefiConstants.USDT_BSC);
        
        // Check which token is which
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        if (token0 == LendefiConstants.WBNB_BSC) {
            console2.log("WBNB is token0, USDT is token1");
        } else if (token1 == LendefiConstants.WBNB_BSC) {
            console2.log("WBNB is token1, USDT is token0");
        } else {
            console2.log("WBNB not found in pool!");
        }
        
        if (token0 == LendefiConstants.USDT_BSC) {
            console2.log("USDT is token0, WBNB is token1");
        } else if (token1 == LendefiConstants.USDT_BSC) {
            console2.log("USDT is token1, WBNB is token0");
        } else {
            console2.log("USDT not found in pool!");
        }
        
        // Test price calculation
        bool wbnbIsToken0 = (token0 == LendefiConstants.WBNB_BSC);
        console2.log("wbnbIsToken0:", wbnbIsToken0);
        
        // Calculate WBNB price in USDT
        uint256 wbnbPriceInUSDT = UniswapTickMath.getRawPrice(pool, !wbnbIsToken0, 1e6, 900);
        console2.log("WBNB price in USDT (using !wbnbIsToken0):", wbnbPriceInUSDT);
        
        uint256 wbnbPriceInUSDT2 = UniswapTickMath.getRawPrice(pool, wbnbIsToken0, 1e6, 900);
        console2.log("WBNB price in USDT (using wbnbIsToken0):", wbnbPriceInUSDT2);
    }
}