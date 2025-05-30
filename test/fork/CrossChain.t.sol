// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrosschainTest is Test {
    uint256 private sepoliaFork;
    uint256 private arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    //Sepolia
    RebaseToken sepoliaToken;
    RebaseTokenPool sepoliaTokenPool;
    Register.NetworkDetails sepoliaNetworkDetails;
    TokenAdminRegistry sepoliaTokenAdminRegistry;
    Vault vault;
    //Arbitrum Sepolia
    RebaseToken arbSepoliaToken;
    RebaseTokenPool arbSepoliaTokenPool;
    Register.NetworkDetails arbSepoliaNetworkDetails;
    TokenAdminRegistry arbTokenAdminRegistry;

    address private OWNER = makeAddr("owner");
    address private USER = makeAddr("user");
    uint256 private constant SEND_VALUE = 1e5;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepoliaEth");
        arbSepoliaFork = vm.createFork("arbSepolia");
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        //Source chain setup
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(OWNER);

        sepoliaToken = new RebaseToken();
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        sepoliaTokenAdminRegistry = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        sepoliaTokenAdminRegistry.acceptAdminRole(address(sepoliaToken));
        sepoliaTokenAdminRegistry.setPool(address(sepoliaToken), address(sepoliaTokenPool));
        vm.stopPrank();

        //Destination chain setup
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(OWNER);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        arbTokenAdminRegistry = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        arbTokenAdminRegistry.acceptAdminRole(address(arbSepoliaToken));
        arbTokenAdminRegistry.setPool(address(arbSepoliaToken), address(arbSepoliaTokenPool));
        vm.stopPrank();

        // Configure the token pools for cross-chain communication
        configureTokenPool({
            fork: sepoliaFork,
            localPool: address(sepoliaTokenPool),
            remotePool: address(arbSepoliaTokenPool),
            remoteTokenAddress: address(arbSepoliaToken),
            remoteNetworkDetails: arbSepoliaNetworkDetails
        });
        configureTokenPool({
            fork: arbSepoliaFork,
            localPool: address(arbSepoliaTokenPool),
            remotePool: address(sepoliaTokenPool),
            remoteTokenAddress: address(sepoliaToken),
            remoteNetworkDetails: sepoliaNetworkDetails
        });
    }

    function configureTokenPool(
        uint256 fork, //local fork to configure
        address localPool,
        address remotePool,
        address remoteTokenAddress,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(OWNER);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        RateLimiter.Config memory outboundRateLimiter = RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
        RateLimiter.Config memory inboundRateLimiter = RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAddresses[0],
            //abi.encode(remotePool), // Placeholder, will be set later
            remoteTokenAddress: abi.encode(remoteTokenAddress), // Placeholder, will be set later
            outboundRateLimiterConfig: outboundRateLimiter,
            inboundRateLimiterConfig: inboundRateLimiter
        });
        // uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        RebaseTokenPool(localPool).applyChainUpdates(chainsToAdd);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        //create the message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(USER),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false}))
        });
        // Get the fee required to send the message
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, evm2AnyMessage);
        ccipLocalSimulatorFork.requestLinkFromFaucet(USER, fee);
        //approve the router to take LINK for fees
        vm.prank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(address(localNetworkDetails.routerAddress), fee);
        //approve the router to take tokens for burning
        vm.prank(USER);

        IERC20(address(localToken)).approve(address(localNetworkDetails.routerAddress), amountToBridge);

        //get the local balance before bridging
        uint256 localBalanceBefore = localToken.balanceOf(USER);
        //send the message
        vm.prank(USER);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, evm2AnyMessage);
        //check the local balance after bridging
        uint256 localBalanceAfter = localToken.balanceOf(USER);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge, "Local balance mismatch");
        uint256 localInterestRate = localToken.getUserInterestRate(USER);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes); // Simulate time passing for the message to be processed
        //check the remote balance after bridging
        uint256 remoteBalanceBefore = remoteToken.balanceOf(USER);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        assertEq(remoteToken.balanceOf(USER), remoteBalanceBefore + amountToBridge, "Remote balance mismatch");
        uint256 remoteInterestRate = remoteToken.getUserInterestRate(USER);
        // Verify that the interest rates are the same
        assertEq(localInterestRate, remoteInterestRate, "Interest rate mismatch between local and remote tokens");
    }

    function testBridgeAllTokens() public {
        //sepolia => arbitrum sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(USER, SEND_VALUE);
        vm.prank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 amountToBridge = sepoliaToken.balanceOf(USER);
        assertEq(amountToBridge, SEND_VALUE, "Initial balance mismatch");
        bridgeTokens(
            amountToBridge,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }

    function testBridgeAllTokensBack() public {
        //sepolia => arbitrum sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(USER, SEND_VALUE);
        vm.prank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 amountToBridge = sepoliaToken.balanceOf(USER);
        assertEq(amountToBridge, SEND_VALUE, "Initial balance mismatch");
        bridgeTokens(
            amountToBridge,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        //bridge back the tokens from arbitrum sepolia to sepolia
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes); // Simulate time passing for the message to be processed
        uint256 arbAmountToBridge = arbSepoliaToken.balanceOf(USER);
        bridgeTokens(
            arbAmountToBridge,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }

    function testBridgeTwice() public {
        //sepolia => arbitrum sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(USER, SEND_VALUE);
        vm.prank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 amountToBridge = sepoliaToken.balanceOf(USER);
        assertEq(amountToBridge, SEND_VALUE, "Initial balance mismatch");
        bridgeTokens(
            amountToBridge / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        //wait for an hour for interest to accrue
        //send interest from sepolia => arbitrum sepolia
        vm.warp(block.timestamp + 1 hours);
        vm.selectFork(sepoliaFork);
        uint256 amountToBridgeAgain = sepoliaToken.balanceOf(USER);
        //bridge again the same amount
        bridgeTokens(
            amountToBridgeAgain,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }
}
