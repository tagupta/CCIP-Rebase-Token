// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

contract TokenAndPoolDeployer is Script {
    RegistryModuleOwnerCustom registryModuleOwnerCustom;
    TokenAdminRegistry tokenAdminRegistry;

    function run() external returns (RebaseToken rebaseToken, RebaseTokenPool rebaseTokenPool) {
        CCIPLocalSimulatorFork ccipSimulator = new CCIPLocalSimulatorFork();
        vm.startBroadcast();
        // Deploy RebaseToken
        rebaseToken = new RebaseToken();
        Register.NetworkDetails memory networkDetails = ccipSimulator.getNetworkDetails(block.chainid);
        // Deploy RebaseTokenPool
        rebaseTokenPool = new RebaseTokenPool(
            IERC20(address(rebaseToken)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );
        // Grant mint and burn role to RebaseTokenPool
        rebaseToken.grantMintAndBurnRole(address(rebaseTokenPool));
        //Register the admin of the rebase token
        registryModuleOwnerCustom = RegistryModuleOwnerCustom(networkDetails.tokenAdminRegistryAddress);
        registryModuleOwnerCustom.registerAdminViaOwner(address(rebaseToken));
        tokenAdminRegistry = TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress);
        //Complete the registration of the admin role
        tokenAdminRegistry.acceptAdminRole(address(rebaseToken));
        //Associate token with the pool
        tokenAdminRegistry.setPool(address(rebaseToken), address(rebaseTokenPool));
        vm.stopBroadcast();
    }
}

contract VaultDeployer is Script {
    function run(address sourceToken) external returns (Vault vault) {
        vm.startBroadcast();
        // Deploy Vault
        vault = new Vault(IRebaseToken(sourceToken));
        IRebaseToken(sourceToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
    }
}
