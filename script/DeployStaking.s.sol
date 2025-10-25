// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/security/MultiSigManager.sol";
import "../src/oracles/RedStoneOracle.sol";
import "../src/security/PriceValidator.sol";
import "../src/UniExecutor.sol";
import "../src/adapters/ethereum/LidoAdapter.sol";

/// @title DeployStakingScript
/// @notice Minimal deployment flow for ETH → stETH staking governed by MultiSig + RedStone oracle
contract DeployStakingScript is Script {
    struct OwnersConfig {
        address[] owners;
        uint256 requiredConfirmations;
        address emergencyOperator;
    }

    event DeploymentSummary(
        address multiSig,
        address oracle,
        address priceValidator,
        address executor,
        address lidoAdapter
    );

    MultiSigManager public multiSig;
    RedStoneOracle public oracle;
    PriceValidator public priceValidator;
    UniExecutor public executor;
    LidoAdapter public lidoAdapter;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        OwnersConfig memory ownersConfig = _loadOwnersConfig(deployer);
        address lidoStETH = vm.envAddress("LIDO_STETH");
        address existingOracleAddr = vm.envOr("REDSTONE_ORACLE_ADDRESS", address(0));

        vm.startBroadcast(deployerKey);

        // Phase 1: Governance
        multiSig = new MultiSigManager(
            ownersConfig.owners, ownersConfig.requiredConfirmations, ownersConfig.emergencyOperator
        );

        // Phase 2: Oracle stack (reuse if supplied)
        if (existingOracleAddr != address(0)) {
            oracle = RedStoneOracle(existingOracleAddr);
        } else {
            oracle = new RedStoneOracle(address(multiSig));
        }
        priceValidator = new PriceValidator(address(oracle));

        // Phase 3: Executor + adapter
        executor = new UniExecutor(deployer);
        executor.setPriceValidator(address(priceValidator));
        executor.addEmergencyOperator(ownersConfig.emergencyOperator);

        // Deploy staking adapter and register
        lidoAdapter = new LidoAdapter(lidoStETH);
        string[] memory protocols = new string[](1);
        address[] memory targets = new address[](1);
        protocols[0] = "lido";
        targets[0] = address(lidoAdapter);
        executor.registerProtocols(protocols, targets);

        // Hand solver rights over to the multisig
        executor.setSolver(address(multiSig));

        vm.stopBroadcast();

        emit DeploymentSummary(
            address(multiSig), address(oracle), address(priceValidator), address(executor), address(lidoAdapter)
        );
        _logSummary(ownersConfig);
    }

    function _loadOwnersConfig(address deployer) internal returns (OwnersConfig memory config) {
        address[5] memory rawOwners;
        rawOwners[0] = vm.envAddress("MULTISIG_OWNER_1");
        rawOwners[1] = vm.envAddress("MULTISIG_OWNER_2");
        rawOwners[2] = vm.envAddress("MULTISIG_OWNER_3");
        rawOwners[3] = vm.envOr("MULTISIG_OWNER_4", address(0));
        rawOwners[4] = vm.envOr("MULTISIG_OWNER_5", address(0));

        uint256 count;
        for (uint256 i = 0; i < rawOwners.length; i++) {
            if (rawOwners[i] != address(0)) count++;
        }

        config.owners = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < rawOwners.length; i++) {
            if (rawOwners[i] != address(0)) {
                config.owners[idx++] = rawOwners[i];
            }
        }

        config.requiredConfirmations = vm.envOr("MULTISIG_REQUIRED_CONFIRMATIONS", uint256(2));
        config.emergencyOperator = vm.envOr("EMERGENCY_OPERATOR", deployer);
    }

    function _logSummary(OwnersConfig memory ownersConfig) internal view {
        console.log("\n=== ETH Staking Deployment Summary ===");
        console.log("MultiSigManager: %s", address(multiSig));
        console.log(" - Owners:");
        for (uint256 i = 0; i < ownersConfig.owners.length; i++) {
            console.log("   %s", ownersConfig.owners[i]);
        }
        console.log(" - Required confirmations: %s", ownersConfig.requiredConfirmations);
        console.log(" - Emergency operator: %s", ownersConfig.emergencyOperator);

        console.log("RedStoneOracle: %s", address(oracle));
        console.log("PriceValidator: %s", address(priceValidator));
        console.log("UniExecutor: %s", address(executor));
        console.log("LidoAdapter: %s", address(lidoAdapter));
        console.log("======================================\n");
    }
}
