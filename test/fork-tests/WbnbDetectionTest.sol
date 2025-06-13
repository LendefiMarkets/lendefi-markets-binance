// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {UniswapTickMath} from "../../contracts/markets/lib/UniswapTickMath.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";
import {LendefiConstants} from "../../contracts/markets/lib/LendefiConstants.sol";

contract WbnbDetectionTest is Test {
    // BSC addresses
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant LINK = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD;

    // Pool addresses
    address public constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    address public constant CAKE_WBNB_POOL = 0x133B3D95bAD5405d14d53473671200e9342896BF;
    address public constant LINK_WBNB_POOL = 0x0E1893BEEb4d0913d26B9614B18Aea29c56d94b9;

    function setUp() public {
        vm.createSelectFork("binance");
    }

    function testWbnbDetectionLogic() public view {
        console2.log("=== Testing WBNB Detection Logic ===");
        
        // Test WBNB/USDT pool (direct USD pool)
        console2.log("\n--- WBNB/USDT Pool ---");
        _testPool(WBNB_USDT_POOL, WBNB, "WBNB");
        
        // Test CAKE/WBNB pool (needs conversion)
        console2.log("\n--- CAKE/WBNB Pool ---");
        _testPool(CAKE_WBNB_POOL, CAKE, "CAKE");
        
        // Test LINK/WBNB pool (needs conversion)
        console2.log("\n--- LINK/WBNB Pool ---");
        _testPool(LINK_WBNB_POOL, LINK, "LINK");
    }

    function _testPool(address poolAddress, address token, string memory tokenName) internal view {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (address token0, address token1) = (pool.token0(), pool.token1());
        
        console2.log(string.concat(tokenName, " pool:"), poolAddress);
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        
        // Check if token is in pool
        if (token != token0 && token != token1) {
            console2.log("ERROR: Token not in pool!");
            return;
        }
        
        bool isToken0 = (token == token0);
        console2.log(string.concat(tokenName, " is token0:"), isToken0);
        
        // Check WBNB detection
        bool hasWBNB = (token0 == WBNB || token1 == WBNB);
        console2.log("Pool has WBNB:", hasWBNB);
        
        // Check if this is the WBNB/USDT pool specifically
        bool isWbnbUsdtPool = (poolAddress == WBNB_USDT_POOL);
        console2.log("Is WBNB/USDT pool:", isWbnbUsdtPool);
        
        // Apply the logic
        if (hasWBNB && !isWbnbUsdtPool) {
            console2.log("-> WBNB pool: Should convert through WBNB/USDT");
            
            // Use 60 seconds for pools with limited history
            uint32 twapPeriod = (poolAddress == LINK_WBNB_POOL) ? 60 : 600;
            
            // Get token price in WBNB
            uint256 tokenPriceInWBNB = UniswapTickMath.getRawPrice(pool, isToken0, 1e18, twapPeriod);
            console2.log(string.concat(tokenName, " price in WBNB:"), tokenPriceInWBNB);
            
            // Get WBNB price in USDT  
            uint256 wbnbPriceInUSDT = UniswapTickMath.getRawPrice(IUniswapV3Pool(WBNB_USDT_POOL), false, 1e6, 600);
            console2.log("WBNB price in USDT:", wbnbPriceInUSDT);
            
            // Calculate final USD price
            uint256 tokenPriceInUSD = FullMath.mulDiv(tokenPriceInWBNB, wbnbPriceInUSDT, 1e18);
            console2.log(string.concat(tokenName, " price in USD (calculated):"), tokenPriceInUSD);
        } else {
            console2.log("-> Direct USD pool: Should get price directly");
            
            uint256 tokenPriceInUSD = UniswapTickMath.getRawPrice(pool, isToken0, 1e6, 600);
            console2.log(string.concat(tokenName, " price in USD (direct):"), tokenPriceInUSD);
        }
    }
}