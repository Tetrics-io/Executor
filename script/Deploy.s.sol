// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/UniExecutor.sol";
import "../src/security/PriceValidator.sol";
import "../src/security/MultiSigManager.sol";
import "../src/oracles/RedStoneOracle.sol";
import "../src/adapters/ethereum/LidoAdapter.sol";
import "../src/adapters/ethereum/WstETHAdapter.sol";
import "../src/adapters/ethereum/MorphoAdapter.sol";
import "../src/adapters/cross-chain/AcrossAdapter.sol";
import "../src/adapters/hyperliquid/StakedHypeAdapter.sol";
import "../src/adapters/hyperliquid/HyperLendAdapter.sol";
import "../src/adapters/hyperliquid/FelixAdapter.sol";
import "../src/adapters/hyperliquid/HyperBeatAdapter.sol";

/// @title Deploy Script
/// @notice Unified deployment script for all networks with incremental deployment support
contract DeployScript is Script {
    // ============ Configuration ============

    struct NetworkConfig {
        string network;
        uint256 chainId;
        bool useRealOracle;
        address[] multiSigOwners;
        uint256 requiredConfirmations;
        address emergencyOperator;
    }

    struct ProtocolAddresses {
        // Ethereum protocols
        address lidoStETH;
        address lidoWstETH;
        address wstethToken;
        address morphoBlue;
        address morphoWstEthUsdcMarket;
        address acrossSpokePool;
        address acrossWeth;
        address weth;
        address usdc;
        address usdt;
        // Hyperliquid protocols (if applicable)
        address hypeToken;
        address hypeStaking;
        address hyperlendPool;
        address felixCdp;
        address hyperbeatVault;
        // Hyperliquid token addresses
        address behypeToken;
        address hypeUsdc;
        address fusdcToken;
        // HyperBeat vault addresses
        address metaVault;
        address deltaNeutralVault;
    }

    // ============ State Variables ============

    NetworkConfig public config;
    ProtocolAddresses public protocols;

    // Core contracts
    MultiSigManager public multiSig;
    RedStoneOracle public oracle;
    PriceValidator public priceValidator;
    UniExecutor public executor;

    // Ethereum adapters
    LidoAdapter public lidoAdapter;
    WstETHAdapter public wstethAdapter;
    MorphoAdapter public morphoAdapter;
    AcrossAdapter public acrossAdapter;

    // Hyperliquid adapters (if deploying on Hyperliquid)
    StakedHypeAdapter public stakedHypeAdapter;
    HyperLendAdapter public hyperlendAdapter;
    FelixAdapter public felixAdapter;
    HyperBeatAdapter public hyperbeatAdapter;
    UniExecutor public hyperliquidExecutor;
    address public deployerAddress;
    bool public newExecutorDeployed;
    bool public newHyperliquidExecutorDeployed;

    // ============ Main Deployment ============

    function run() external {
        // Load configuration from environment
        _loadConfiguration();

        console.log("=== Tetrics Unified Deployment ===");
        console.log("Network:", config.network);
        console.log("Chain ID:", config.chainId);
        console.log("Use Real Oracle:", config.useRealOracle);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        deployerAddress = deployer;

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Deploy or reuse MultiSig
        _deployMultiSig();

        // Phase 2: Deploy or reuse Oracle system
        _deployOracleSystem();

        // Phase 3: Deploy or reuse main executor
        _deployExecutor(deployer);

        // Phase 4: Deploy protocol adapters based on network
        if (config.chainId == 31337 || config.chainId == 1 || config.chainId == 11155111) {
            // Ethereum or Ethereum fork
            _deployEthereumAdapters();
        }

        if (config.chainId == 31338 || config.chainId == 999) {
            // Hyperliquid or Hyperliquid fork
            _deployHyperliquidAdapters(deployer);
        }

        if (config.chainId == 31337) {
            // Local development - deploy both chains
            _deployHyperliquidAdapters(deployer);
        }

        // Phase 5: Initialize system
        _initializeSystem();

        vm.stopBroadcast();

        // Phase 6: Update environment variables
        _updateEnvironmentVariables();

        // Phase 7: Print summary
        _printDeploymentSummary();
    }

    // ============ Configuration Loading ============

    function _loadConfiguration() internal {
        config.network = vm.envString("NETWORK");
        config.chainId = vm.envUint("CHAIN_ID");
        config.useRealOracle = vm.envBool("USE_REAL_ORACLE");
        config.requiredConfirmations = vm.envUint("MULTISIG_REQUIRED_CONFIRMATIONS");
        config.emergencyOperator = vm.envAddress("EMERGENCY_OPERATOR");

        // Load multisig owners
        address[] memory owners = new address[](5);
        owners[0] = vm.envOr("MULTISIG_OWNER_1", address(0));
        owners[1] = vm.envOr("MULTISIG_OWNER_2", address(0));
        owners[2] = vm.envOr("MULTISIG_OWNER_3", address(0));
        owners[3] = vm.envOr("MULTISIG_OWNER_4", address(0));
        owners[4] = vm.envOr("MULTISIG_OWNER_5", address(0));

        // Filter out zero addresses and resize array
        uint256 validOwners = 0;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] != address(0)) validOwners++;
        }

        config.multiSigOwners = new address[](validOwners);
        uint256 index = 0;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] != address(0)) {
                config.multiSigOwners[index] = owners[i];
                index++;
            }
        }

        // Load protocol addresses
        protocols.lidoStETH = vm.envAddress("LIDO_STETH");
        protocols.lidoWstETH = vm.envAddress("LIDO_WSTETH");
        protocols.wstethToken = vm.envAddress("WSTETH_TOKEN");
        protocols.morphoBlue = vm.envAddress("MORPHO_BLUE");
        protocols.morphoWstEthUsdcMarket = vm.envAddress("MORPHO_WSTETH_USDC_MARKET");
        protocols.acrossSpokePool = vm.envAddress("ACROSS_SPOKE_POOL");
        protocols.acrossWeth = vm.envAddress("ACROSS_WETH");
        protocols.weth = vm.envAddress("WETH");
        protocols.usdc = vm.envAddress("USDC");
        protocols.usdt = vm.envAddress("USDT");

        // Load Hyperliquid addresses if available
        protocols.hypeToken = vm.envOr("HYPE_TOKEN", address(0));
        protocols.hypeStaking = vm.envOr("HYPE_STAKING", address(0));
        protocols.hyperlendPool = vm.envOr("HYPERLEND_POOL", address(0));
        protocols.felixCdp = vm.envOr("FELIX_CDP", address(0));
        protocols.hyperbeatVault = vm.envOr("HYPERBEAT_VAULT", address(0));

        // Load Hyperliquid token addresses
        protocols.behypeToken = vm.envOr("BEHYPE_TOKEN", address(0));
        protocols.hypeUsdc = vm.envOr("HYPE_USDC", address(0));
        protocols.fusdcToken = vm.envOr("FUSDC_TOKEN", address(0));

        // Load HyperBeat vault addresses
        protocols.metaVault = vm.envOr("META_VAULT", address(0));
        protocols.deltaNeutralVault = vm.envOr("DELTA_NEUTRAL_VAULT", address(0));
    }

    // ============ Deployment Phases ============

    function _deployMultiSig() internal {
        address existingMultiSig = vm.envOr("MULTISIG_ADDRESS", address(0));

        if (existingMultiSig != address(0)) {
            multiSig = MultiSigManager(payable(existingMultiSig));
            console.log("Using existing MultiSig:", address(multiSig));
        } else {
            multiSig =
                new MultiSigManager(config.multiSigOwners, config.requiredConfirmations, config.emergencyOperator);
            console.log("MultiSig deployed at:", address(multiSig));
        }
    }

    function _deployOracleSystem() internal {
        address existingOracle = vm.envOr("ORACLE_ADDRESS", address(0));
        address existingPriceValidator = vm.envOr("PRICE_VALIDATOR_ADDRESS", address(0));

        if (existingOracle != address(0)) {
            oracle = RedStoneOracle(existingOracle);
            console.log("Using existing Oracle:", address(oracle));
        } else {
            if (config.useRealOracle) {
                address redStoneAddress = vm.envOr("REDSTONE_ORACLE_ADDRESS", address(0));
                if (redStoneAddress != address(0)) {
                    oracle = RedStoneOracle(redStoneAddress);
                    console.log("Using existing RedStone Oracle:", address(oracle));
                } else {
                    oracle = new RedStoneOracle(address(multiSig));
                    console.log("RedStone Oracle deployed at:", address(oracle));
                }
            } else {
                MockRedStoneOracle mockOracle = new MockRedStoneOracle();
                oracle = RedStoneOracle(address(mockOracle));
                console.log("Mock Oracle deployed at:", address(oracle));
            }
        }

        if (existingPriceValidator != address(0)) {
            priceValidator = PriceValidator(existingPriceValidator);
            console.log("Using existing PriceValidator:", address(priceValidator));
        } else {
            priceValidator = new PriceValidator(address(oracle));
            console.log("PriceValidator deployed at:", address(priceValidator));
        }
    }

    function _deployExecutor(address deployer) internal {
        address existingExecutor = vm.envOr("EXECUTOR_ADDRESS", address(0));

        if (existingExecutor != address(0)) {
            executor = UniExecutor(payable(existingExecutor));
            console.log("Using existing Executor:", address(executor));
            newExecutorDeployed = false;
        } else {
            executor = new UniExecutor(deployer);
            executor.setPriceValidator(address(priceValidator));
            console.log("Executor deployed at:", address(executor));
            newExecutorDeployed = true;
        }
    }

    function _deployEthereumAdapters() internal {
        console.log("\\nDeploying Ethereum Adapters...");

        // Deploy Lido Adapter
        address existingLido = vm.envOr("LIDO_ADAPTER_ADDRESS", address(0));
        if (existingLido != address(0)) {
            lidoAdapter = LidoAdapter(existingLido);
            console.log("Using existing LidoAdapter:", address(lidoAdapter));
        } else {
            lidoAdapter = new LidoAdapter(protocols.lidoStETH);
            console.log("LidoAdapter deployed at:", address(lidoAdapter));
        }

        // Deploy WstETH Adapter
        address existingWstETH = vm.envOr("WSTETH_ADAPTER_ADDRESS", address(0));
        if (existingWstETH != address(0)) {
            wstethAdapter = WstETHAdapter(existingWstETH);
            console.log("Using existing WstETHAdapter:", address(wstethAdapter));
        } else {
            wstethAdapter = new WstETHAdapter(protocols.lidoStETH, protocols.wstethToken);
            console.log("WstETHAdapter deployed at:", address(wstethAdapter));
        }

        // Deploy Morpho Adapter
        address existingMorpho = vm.envOr("MORPHO_ADAPTER_ADDRESS", address(0));
        if (existingMorpho != address(0)) {
            morphoAdapter = MorphoAdapter(existingMorpho);
            console.log("Using existing MorphoAdapter:", address(morphoAdapter));
        } else {
            morphoAdapter = new MorphoAdapter(protocols.morphoBlue, protocols.morphoWstEthUsdcMarket);
            console.log("MorphoAdapter deployed at:", address(morphoAdapter));
        }

        // Deploy Across Adapter
        address existingAcross = vm.envOr("ACROSS_ADAPTER_ADDRESS", address(0));
        if (existingAcross != address(0)) {
            acrossAdapter = AcrossAdapter(existingAcross);
            console.log("Using existing AcrossAdapter:", address(acrossAdapter));
        } else {
            acrossAdapter = new AcrossAdapter(protocols.acrossSpokePool);
            console.log("AcrossAdapter deployed at:", address(acrossAdapter));
        }
    }

    function _deployHyperliquidAdapters(address deployer) internal {
        console.log("\\nDeploying Hyperliquid Adapters...");

        // Deploy Hyperliquid Executor if needed
        address existingHyperliquidExecutor = vm.envOr("HYPERLIQUID_EXECUTOR_ADDRESS", address(0));
        if (existingHyperliquidExecutor != address(0)) {
            hyperliquidExecutor = UniExecutor(payable(existingHyperliquidExecutor));
            console.log("Using existing Hyperliquid Executor:", address(hyperliquidExecutor));
            newHyperliquidExecutorDeployed = false;
        } else {
            hyperliquidExecutor = new UniExecutor(deployer);
            console.log("Hyperliquid Executor deployed at:", address(hyperliquidExecutor));
            newHyperliquidExecutorDeployed = true;
        }

        // Deploy HYPE Staking Adapter
        if (protocols.hypeStaking != address(0)) {
            address existingHypeStaking = vm.envOr("HYPE_STAKING_ADAPTER_ADDRESS", address(0));
            if (existingHypeStaking != address(0)) {
                stakedHypeAdapter = StakedHypeAdapter(payable(existingHypeStaking));
                console.log("Using existing StakedHypeAdapter:", address(stakedHypeAdapter));
            } else {
                stakedHypeAdapter =
                    new StakedHypeAdapter(address(hyperliquidExecutor), protocols.hypeToken, protocols.hypeStaking);
                console.log("StakedHypeAdapter deployed at:", address(stakedHypeAdapter));
            }
        }

        // Deploy HyperLend Adapter
        if (protocols.hyperlendPool != address(0)) {
            address existingHyperLend = vm.envOr("HYPERLEND_ADAPTER_ADDRESS", address(0));
            if (existingHyperLend != address(0)) {
                hyperlendAdapter = HyperLendAdapter(existingHyperLend);
                console.log("Using existing HyperLendAdapter:", address(hyperlendAdapter));
            } else {
                hyperlendAdapter = new HyperLendAdapter(
                    address(hyperliquidExecutor), protocols.hyperlendPool, protocols.behypeToken, protocols.hypeUsdc
                );
                console.log("HyperLendAdapter deployed at:", address(hyperlendAdapter));
            }
        }

        // Deploy Felix Adapter
        if (protocols.felixCdp != address(0)) {
            address existingFelix = vm.envOr("FELIX_ADAPTER_ADDRESS", address(0));
            if (existingFelix != address(0)) {
                felixAdapter = FelixAdapter(existingFelix);
                console.log("Using existing FelixAdapter:", address(felixAdapter));
            } else {
                felixAdapter = new FelixAdapter(
                    address(hyperliquidExecutor), protocols.felixCdp, protocols.behypeToken, protocols.fusdcToken
                );
                console.log("FelixAdapter deployed at:", address(felixAdapter));
            }
        }

        // Deploy HyperBeat Adapter
        if (protocols.hyperbeatVault != address(0)) {
            address existingHyperBeat = vm.envOr("HYPERBEAT_ADAPTER_ADDRESS", address(0));
            if (existingHyperBeat != address(0)) {
                hyperbeatAdapter = HyperBeatAdapter(existingHyperBeat);
                console.log("Using existing HyperBeatAdapter:", address(hyperbeatAdapter));
            } else {
                hyperbeatAdapter = new HyperBeatAdapter(
                    address(hyperliquidExecutor),
                    protocols.hyperbeatVault,
                    protocols.hypeUsdc,
                    protocols.behypeToken,
                    protocols.metaVault,
                    protocols.deltaNeutralVault
                );
                console.log("HyperBeatAdapter deployed at:", address(hyperbeatAdapter));
            }
        }
    }

    function _initializeSystem() internal {
        console.log("\\nInitializing System...");

        // Register Ethereum protocols only when we deployed a fresh executor
        if (address(lidoAdapter) != address(0) && address(executor) != address(0) && newExecutorDeployed) {
            string[] memory protocolNames = new string[](4);
            address[] memory targets = new address[](4);

            protocolNames[0] = "lido";
            targets[0] = address(lidoAdapter);

            protocolNames[1] = "wsteth";
            targets[1] = address(wstethAdapter);

            protocolNames[2] = "morpho";
            targets[2] = address(morphoAdapter);

            protocolNames[3] = "across";
            targets[3] = address(acrossAdapter);

            executor.registerProtocols(protocolNames, targets);
            console.log("Ethereum protocols registered");
        }

        // Register Hyperliquid protocols if deployed
        if (address(hyperliquidExecutor) != address(0)) {
            uint256 protocolCount = 0;
            if (address(stakedHypeAdapter) != address(0)) protocolCount++;
            if (address(hyperlendAdapter) != address(0)) protocolCount++;
            if (address(felixAdapter) != address(0)) protocolCount++;
            if (address(hyperbeatAdapter) != address(0)) protocolCount++;

            if (protocolCount > 0 && newHyperliquidExecutorDeployed) {
                string[] memory hyperliquidProtocols = new string[](protocolCount);
                address[] memory hyperliquidTargets = new address[](protocolCount);

                uint256 index = 0;
                if (address(stakedHypeAdapter) != address(0)) {
                    hyperliquidProtocols[index] = "hype-staking";
                    hyperliquidTargets[index] = address(stakedHypeAdapter);
                    index++;
                }
                if (address(hyperlendAdapter) != address(0)) {
                    hyperliquidProtocols[index] = "hyperlend";
                    hyperliquidTargets[index] = address(hyperlendAdapter);
                    index++;
                }
                if (address(felixAdapter) != address(0)) {
                    hyperliquidProtocols[index] = "felix";
                    hyperliquidTargets[index] = address(felixAdapter);
                    index++;
                }
                if (address(hyperbeatAdapter) != address(0)) {
                    hyperliquidProtocols[index] = "hyperbeat";
                    hyperliquidTargets[index] = address(hyperbeatAdapter);
                    index++;
                }

                hyperliquidExecutor.registerProtocols(hyperliquidProtocols, hyperliquidTargets);
                console.log("Hyperliquid protocols registered");
            }
        }

        // Set emergency operators
        if (address(executor) != address(0) && newExecutorDeployed) {
            executor.addEmergencyOperator(config.emergencyOperator);
        }
        if (address(hyperliquidExecutor) != address(0) && newHyperliquidExecutorDeployed) {
            hyperliquidExecutor.addEmergencyOperator(config.emergencyOperator);
        }

        console.log("Emergency operators configured");
    }

    function _updateEnvironmentVariables() internal {
        console.log("\\nUpdating environment variables...");

        // Note: In a production setup, you'd use a more sophisticated approach
        // to update the .env files programmatically. For now, we'll just print
        // the values that should be updated.

        console.log("Update .env file with these addresses:");
        if (address(multiSig) != address(0)) {
            console.log("MULTISIG_ADDRESS=%s", address(multiSig));
        }
        if (address(oracle) != address(0)) {
            console.log("ORACLE_ADDRESS=%s", address(oracle));
        }
        if (address(priceValidator) != address(0)) {
            console.log("PRICE_VALIDATOR_ADDRESS=%s", address(priceValidator));
        }
        if (address(executor) != address(0)) {
            console.log("EXECUTOR_ADDRESS=%s", address(executor));
        }
        if (address(lidoAdapter) != address(0)) {
            console.log("LIDO_ADAPTER_ADDRESS=%s", address(lidoAdapter));
        }
        if (address(wstethAdapter) != address(0)) {
            console.log("WSTETH_ADAPTER_ADDRESS=%s", address(wstethAdapter));
        }
        if (address(morphoAdapter) != address(0)) {
            console.log("MORPHO_ADAPTER_ADDRESS=%s", address(morphoAdapter));
        }
        if (address(acrossAdapter) != address(0)) {
            console.log("ACROSS_ADAPTER_ADDRESS=%s", address(acrossAdapter));
        }
        if (address(hyperliquidExecutor) != address(0)) {
            console.log("HYPERLIQUID_EXECUTOR_ADDRESS=%s", address(hyperliquidExecutor));
        }
        if (address(stakedHypeAdapter) != address(0)) {
            console.log("HYPE_STAKING_ADAPTER_ADDRESS=%s", address(stakedHypeAdapter));
        }
        if (address(hyperlendAdapter) != address(0)) {
            console.log("HYPERLEND_ADAPTER_ADDRESS=%s", address(hyperlendAdapter));
        }
        if (address(felixAdapter) != address(0)) {
            console.log("FELIX_ADAPTER_ADDRESS=%s", address(felixAdapter));
        }
        if (address(hyperbeatAdapter) != address(0)) {
            console.log("HYPERBEAT_ADAPTER_ADDRESS=%s", address(hyperbeatAdapter));
        }
    }

    function _printDeploymentSummary() internal view {
        console.log("\\n=== DEPLOYMENT COMPLETE ===");
        console.log("Network: %s (Chain ID: %s)", config.network, config.chainId);
        console.log("Use Real Oracle: %s", config.useRealOracle);

        console.log("\\nCORE CONTRACTS:");
        if (address(multiSig) != address(0)) {
            console.log("  MultiSig: %s", address(multiSig));
        }
        if (address(oracle) != address(0)) {
            console.log("  Oracle: %s", address(oracle));
        }
        if (address(priceValidator) != address(0)) {
            console.log("  PriceValidator: %s", address(priceValidator));
        }
        if (address(executor) != address(0)) {
            console.log("  Executor: %s", address(executor));
        }

        console.log("\\nETHEREUM ADAPTERS:");
        if (address(lidoAdapter) != address(0)) {
            console.log("  LidoAdapter: %s", address(lidoAdapter));
        }
        if (address(wstethAdapter) != address(0)) {
            console.log("  WstETHAdapter: %s", address(wstethAdapter));
        }
        if (address(morphoAdapter) != address(0)) {
            console.log("  MorphoAdapter: %s", address(morphoAdapter));
        }
        if (address(acrossAdapter) != address(0)) {
            console.log("  AcrossAdapter: %s", address(acrossAdapter));
        }

        if (address(hyperliquidExecutor) != address(0)) {
            console.log("\\nHYPERLIQUID CONTRACTS:");
            console.log("  HyperliquidExecutor: %s", address(hyperliquidExecutor));
            if (address(stakedHypeAdapter) != address(0)) {
                console.log("  StakedHypeAdapter: %s", address(stakedHypeAdapter));
            }
            if (address(hyperlendAdapter) != address(0)) {
                console.log("  HyperLendAdapter: %s", address(hyperlendAdapter));
            }
            if (address(felixAdapter) != address(0)) {
                console.log("  FelixAdapter: %s", address(felixAdapter));
            }
            if (address(hyperbeatAdapter) != address(0)) {
                console.log("  HyperBeatAdapter: %s", address(hyperbeatAdapter));
            }
        }

        console.log("\\nSECURITY:");
        console.log("  MultiSig Required Confirmations: %s", config.requiredConfirmations);
        console.log("  Emergency Operator: %s", config.emergencyOperator);
        console.log("  Price Validation: Enabled");

        console.log("\\n=== DEPLOYMENT SUMMARY END ===");
    }
}

/// @notice Mock RedStone Oracle for testing
contract MockRedStoneOracle {
    mapping(bytes32 => uint256) public prices;

    constructor() {
        prices[keccak256(abi.encodePacked("ETH"))] = 4150 * 1e8;
        prices[keccak256(abi.encodePacked("USDC"))] = 1 * 1e8;
        prices[keccak256(abi.encodePacked("WETH"))] = 4150 * 1e8;
        prices[keccak256(abi.encodePacked("stETH"))] = 4140 * 1e8;
        prices[keccak256(abi.encodePacked("wstETH"))] = 4890 * 1e8;
        prices[keccak256(abi.encodePacked("HYPE"))] = 25 * 1e8;
    }

    function getOracleNumericValueFromTxMsg(bytes32 dataFeedId) external view returns (uint256) {
        uint256 price = prices[dataFeedId];
        require(price > 0, "Price not found");
        return price;
    }

    function getOracleNumericValuesFromTxMsg(bytes32[] memory dataFeedIds) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](dataFeedIds.length);
        for (uint256 i = 0; i < dataFeedIds.length; i++) {
            result[i] = prices[dataFeedIds[i]];
            require(result[i] > 0, "Price not found");
        }
        return result;
    }

    function validateRedStoneData(bytes32, uint256) external pure returns (bool) {
        return true;
    }
}
