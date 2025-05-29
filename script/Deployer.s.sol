// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Script } from "forge-std/Script.sol";
import {RebaseToken} from 'src/RebaseToken.sol';
import {RebaseTokenPool} from 'src/RebaseTokenPool.sol';
import {Vault} from 'src/Vault.sol';
import {IRebaseToken} from 'src/interfaces/IRebaseToken.sol';

contract TokenAndPoolDeployer is Script {
    RebaseToken sourceToken;
    RebaseToken destToken;
    RebaseTokenPool sourceTokenPool;
    RebaseTokenPool destTokenPool;
    function run() external {

        vm.startBroadcast();
        // Deploy RebaseToken
        sourceToken = new RebaseToken();                              
        // Deploy RebaseTokenPool
        // RebaseTokenPool rebaseTokenPool = new RebaseTokenPool(IRebaseToken(address(rebaseToken)));
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
                  