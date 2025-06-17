// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Minimal interface to interact with PancakeSwap V3 pool
interface IPancakeV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract SimplifiedUsdDetectionTest is Test {
    // Test pools and tokens
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant LINK = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD;

    // Pools
    address public constant WBNB_USDT_POOL = 0x36696169C63e42cd08ce11f5deeBbCeBae652050;
    address public constant WBNB_USDC_POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4;
    address public constant CAKE_WBNB_POOL = 0x133B3D95bAD5405d14d53473671200e9342896BF;
    address public constant LINK_WBNB_POOL = 0x0E1893BEEb4d0913d26B9614B18Aea29c56d94b9;

    function setUp() public {
        vm.createSelectFork("binance");
    }

    function test_SimplifiedUsdDetection() public view {
        console2.log("=== Simplified USD Detection Test ===");
        console2.log("Logic: If ANY token in pool has USD in symbol -> Direct USD pricing");
        console2.log("       If NO token has USD -> Convert through WBNB/USD");

        // Test pool analysis with simplified logic
        console2.log("\n--- Pool Analysis ---");
        _testSimplifiedPoolLogic(WBNB_USDT_POOL, "WBNB/USDT");
        _testSimplifiedPoolLogic(WBNB_USDC_POOL, "WBNB/USDC");
        _testSimplifiedPoolLogic(CAKE_WBNB_POOL, "CAKE/WBNB");
        _testSimplifiedPoolLogic(LINK_WBNB_POOL, "LINK/WBNB");
    }

    function _testSimplifiedPoolLogic(address poolAddress, string memory poolName) internal view {
        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();

        console2.log(string.concat("\n", poolName, " Pool:"));

        // Get symbols for both tokens
        string memory symbol0 = IERC20Metadata(token0).symbol();
        string memory symbol1 = IERC20Metadata(token1).symbol();

        console2.log(string.concat("Token0: ", symbol0));
        console2.log(string.concat("Token1: ", symbol1));

        // Check if either token has USD (simplified logic)
        bool token0HasUSD = _containsUSD(symbol0);
        bool token1HasUSD = _containsUSD(symbol1);
        bool isDirectUSDPool = token0HasUSD || token1HasUSD;

        console2.log("Token0 has USD:", token0HasUSD);
        console2.log("Token1 has USD:", token1HasUSD);
        console2.log("Is direct USD pool:", isDirectUSDPool);

        if (isDirectUSDPool) {
            console2.log("-> Should use direct USD pricing");
        } else {
            console2.log("-> Should convert through WBNB/USD");
        }
    }

    /**
     * @notice Check if a token symbol contains "USD"
     * @param symbol The token symbol to check
     * @return true if symbol contains "USD"
     */
    function _containsUSD(string memory symbol) internal pure returns (bool) {
        bytes memory symbolBytes = bytes(symbol);
        bytes3 usdPattern = "USD";

        if (symbolBytes.length < 3) return false;

        // Check each position for "USD" pattern
        for (uint256 i = 0; i <= symbolBytes.length - 3; i++) {
            if (
                symbolBytes[i] == usdPattern[0] && symbolBytes[i + 1] == usdPattern[1]
                    && symbolBytes[i + 2] == usdPattern[2]
            ) {
                return true;
            }
        }

        return false;
    }
}
