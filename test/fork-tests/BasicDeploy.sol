// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol"; // solhint-disable-line
import {IASSETS} from "../../contracts/interfaces/IASSETS.sol";
import {IPROTOCOL} from "../../contracts/interfaces/IProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Treasury} from "../../contracts/ecosystem/Treasury.sol";
import {Ecosystem} from "../../contracts/ecosystem/Ecosystem.sol";
import {GovernanceToken} from "../../contracts/ecosystem/GovernanceToken.sol";
import {LendefiGovernor} from "../../contracts/ecosystem/LendefiGovernor.sol";
import {LendefiAssets} from "../../contracts/markets/LendefiAssets.sol";
import {LendefiPoRFeed} from "../../contracts/markets/LendefiPoRFeed.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
// Markets Layer imports
import {LendefiMarketFactory} from "../../contracts/markets/LendefiMarketFactory.sol";
import {LendefiCore} from "../../contracts/markets/LendefiCore.sol";
import {LendefiMarketVault} from "../../contracts/markets/LendefiMarketVault.sol";
import {LendefiPositionVault} from "../../contracts/markets/LendefiPositionVault.sol";
import {LendefiConstants} from "../../contracts/markets/lib/LendefiConstants.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DefenderOptions} from "openzeppelin-foundry-upgrades/Options.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BasicDeploy is Test {
    // Required role constants
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    // Required address constants
    address constant ethereum = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant gnosisSafe = address(0x9999987);
    address constant guardian = address(0x9999990);
    address constant charlie = address(0x9999993);

    // Required state variables
    GovernanceToken internal tokenInstance;
    Ecosystem internal ecoInstance;
    TimelockControllerUpgradeable internal timelockInstance;
    LendefiGovernor internal govInstance;
    Treasury internal treasuryInstance;
    LendefiAssets internal assetsInstance;
    // Markets Layer contracts
    LendefiMarketFactory internal marketFactoryInstance;
    LendefiCore internal marketCoreInstance;
    LendefiMarketVault internal marketVaultInstance;
    
    // Fork test specific IERC20 instances for BSC
    IERC20 usdcInstance = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); //real usdc BSC for fork testing
    IERC20 usdtInstance = IERC20(0x55d398326f99059fF775485246999027B3197955); //real usdt BSC for fork testing
    IERC20 usd1Instance = IERC20(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d); //real usd1 ethereum for fork testing

    /**
     * @notice Get network-specific addresses for oracle validation
     * @dev For fork tests, always returns BSC mainnet addresses from LendefiConstants
     * @return networkUSDT The USDT address for this network
     * @return networkWBNB The WBNB address for this network
     * @return UsdtWbnbPool The USDT/WBNB pool address for this network
     */
    function getNetworkAddresses()
        internal
        pure
        returns (address networkUSDT, address networkWBNB, address UsdtWbnbPool)
    {
        // Fork tests run on BSC mainnet, so use LendefiConstants addresses
        networkUSDT = LendefiConstants.USDT_BSC;
        networkWBNB = LendefiConstants.WBNB_BSC;
        UsdtWbnbPool = LendefiConstants.USDT_WBNB_POOL;
    }

    function _deployTimelock() internal {
        // timelock deploy
        uint256 timelockDelay = 24 * 60 * 60;
        address[] memory temp = new address[](1);
        temp[0] = ethereum;
        TimelockControllerUpgradeable timelock = new TimelockControllerUpgradeable();

        bytes memory initData = abi.encodeWithSelector(
            TimelockControllerUpgradeable.initialize.selector, timelockDelay, temp, temp, guardian
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(timelock), initData);
        timelockInstance = TimelockControllerUpgradeable(payable(address(proxy)));
    }

    function _deployToken() internal {
        if (address(timelockInstance) == address(0)) {
            _deployTimelock();
        }
        // token deploy
        bytes memory data = abi.encodeCall(GovernanceToken.initializeUUPS, (guardian, address(timelockInstance)));
        address payable proxy = payable(Upgrades.deployUUPSProxy("GovernanceToken.sol", data));
        tokenInstance = GovernanceToken(proxy);
        address tokenImplementation = Upgrades.getImplementationAddress(proxy);
        assertFalse(address(tokenInstance) == tokenImplementation);
    }

    function _deployEcosystem() internal {
        // ecosystem deploy
        bytes memory data =
            abi.encodeCall(Ecosystem.initialize, (address(tokenInstance), address(timelockInstance), gnosisSafe));
        address payable proxy = payable(Upgrades.deployUUPSProxy("Ecosystem.sol", data));
        ecoInstance = Ecosystem(proxy);
        address ecoImplementation = Upgrades.getImplementationAddress(proxy);
        assertFalse(address(ecoInstance) == ecoImplementation);
    }

    function _deployGovernor() internal {
        // deploy Governor
        bytes memory data = abi.encodeCall(LendefiGovernor.initialize, (tokenInstance, timelockInstance, gnosisSafe));
        address payable proxy = payable(Upgrades.deployUUPSProxy("LendefiGovernor.sol", data));
        govInstance = LendefiGovernor(proxy);
        address govImplementation = Upgrades.getImplementationAddress(proxy);
        assertFalse(address(govInstance) == govImplementation);
        assertEq(govInstance.uupsVersion(), 1);
    }

    function _deployTreasury() internal {
        // deploy Treasury
        uint256 startOffset = 180 days;
        uint256 vestingDuration = 3 * 365 days;
        bytes memory data =
            abi.encodeCall(Treasury.initialize, (address(timelockInstance), gnosisSafe, startOffset, vestingDuration));
        address payable proxy = payable(Upgrades.deployUUPSProxy("Treasury.sol", data));
        treasuryInstance = Treasury(proxy);
        address implAddress = Upgrades.getImplementationAddress(proxy);
        assertFalse(address(treasuryInstance) == implAddress);
    }

    /**
     * @notice Deploys the LendefiMarketFactory contract
     * @dev This contract creates Core+Vault pairs for different base assets
     */
    function _deployMarketFactory() internal {
        // Ensure dependencies are deployed
        require(address(timelockInstance) != address(0), "Timelock not deployed");
        require(address(treasuryInstance) != address(0), "Treasury not deployed");
        require(address(tokenInstance) != address(0), "Governance token not deployed");

        // Deploy implementations
        LendefiCore coreImpl = new LendefiCore();
        LendefiMarketVault marketVaultImpl = new LendefiMarketVault(); // For market vaults
        LendefiPositionVault positionVaultImpl = new LendefiPositionVault(); // For user position vaults
        LendefiAssets assetsImpl = new LendefiAssets(); // Assets implementation for cloning
        LendefiPoRFeed porFeedImpl = new LendefiPoRFeed();

        // Get network-specific addresses
        (address networkUSDT, address networkWBNB, address UsdtWbnbPool) = getNetworkAddresses();

        // Deploy factory using UUPS pattern with direct proxy deployment
        bytes memory factoryData = abi.encodeCall(
            LendefiMarketFactory.initialize,
            (
                address(timelockInstance),
                address(tokenInstance),
                gnosisSafe,
                address(ecoInstance),
                networkUSDT,
                networkWBNB,
                UsdtWbnbPool
            )
        );
        address payable factoryProxy = payable(Upgrades.deployUUPSProxy("LendefiMarketFactory.sol", factoryData));
        marketFactoryInstance = LendefiMarketFactory(factoryProxy);

        // Set implementations - pass the implementation address, NOT the proxy
        vm.prank(gnosisSafe);
        marketFactoryInstance.setImplementations(
            address(coreImpl),
            address(marketVaultImpl),
            address(positionVaultImpl),
            address(assetsImpl),
            address(porFeedImpl)
        );
    }

    /**
     * @notice Deploys a specific market (Core + Vault) for a base asset
     * @param baseAsset The base asset address for the market
     * @param name The name for the market
     * @param symbol The symbol for the market
     */
    function _deployMarket(address baseAsset, string memory name, string memory symbol) internal {
        require(address(marketFactoryInstance) != address(0), "Market factory not deployed");

        // Verify implementations are set
        require(marketFactoryInstance.coreImplementation() != address(0), "Core implementation not set");
        require(marketFactoryInstance.vaultImplementation() != address(0), "Vault implementation not set");

        // Grant MARKET_OWNER_ROLE to charlie (done by multisig which has DEFAULT_ADMIN_ROLE)
        vm.prank(gnosisSafe);
        marketFactoryInstance.grantRole(LendefiConstants.MARKET_OWNER_ROLE, charlie);

        // Add base asset to allowlist (done by multisig which has MANAGER_ROLE)
        vm.prank(gnosisSafe);
        marketFactoryInstance.addAllowedBaseAsset(baseAsset);

        // Create market via factory (charlie as market owner)
        vm.prank(charlie);
        marketFactoryInstance.createMarket(baseAsset, name, symbol);

        // Get deployed addresses (using charlie as market owner)
        IPROTOCOL.Market memory deployedMarket = marketFactoryInstance.getMarketInfo(charlie, baseAsset);
        marketCoreInstance = LendefiCore(deployedMarket.core);
        marketVaultInstance = LendefiMarketVault(deployedMarket.baseVault);

        // Get the assets module for this specific market from the market struct
        address marketAssetsModule = deployedMarket.assetsModule;
        assetsInstance = LendefiAssets(marketAssetsModule); // Update assetsInstance to point to the market's assets module

        // Grant necessary roles
        vm.startPrank(address(timelockInstance));
        ecoInstance.grantRole(REWARDER_ROLE, address(marketCoreInstance));
        vm.stopPrank();
    }
}