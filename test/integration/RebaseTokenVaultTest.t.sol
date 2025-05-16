// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract RebaseTokenVaultTest is Test {
    RebaseToken private rebase;
    Vault private vault;
    address private OWNER = makeAddr("owner");
    address private USER = makeAddr("user");
    uint256 private constant INITIAL_SUPPLY = 1e27;
    uint256 private constant MIN_DEPOSIT = 1e5;
    uint256 private constant MAX_DEPOSIT = type(uint96).max;

    function setUp() public {
        vm.startPrank(OWNER);
        vm.deal(OWNER, INITIAL_SUPPLY);
        rebase = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebase)));
        rebase.grantMintAndBurnRole(address(vault));
        // (bool success, ) = payable(address(vault)).call{value: INITIAL_SUPPLY}("");
        // console.log("Vault balance: ", address(vault).balance);
        // assertTrue(success, "Failed to send ETH to vault");
        vm.stopPrank();
    }

    function addewardsToVault(uint256 amount) internal{
        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        //send the amount to the vault
        (bool success, ) = payable(address(vault)).call{value: amount}("");   
    }

    function testDepositLinear(uint256 amount) external{
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        //deposit
        vm.startPrank(USER);
        vm.deal(USER, amount);

        //check our rebase balance
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        console.log("Start balance: ", startBalance);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");

        //warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebase.balanceOf(USER);  
        console.log("Middle Balance: ", middleBalance);
        assertGt(middleBalance, startBalance, "New Balance should be greater than the start balance");

        //warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebase.balanceOf(USER);
        console.log("End Balance: ", endBalance);
        assertGt(endBalance, middleBalance, "New Balance should be greater than the middle balance");

        //check if the interest is linear
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance,1, "Interest should be linear");
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) external{
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        //1. Deposit funds
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        console.log("Start balance: ", startBalance);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");
        //2. Redeem the entire balance straight away
        vault.redeem(type(uint256).max);
        uint256 endBalance = rebase.balanceOf(USER);
        console.log("End balance: ", endBalance);
        assertEq(endBalance, 0, "Balance should be 0 after redeeming");
        assertEq(address(USER).balance, amount, "Balance should be equal to the amount deposited");
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 amount, uint time) external{
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        // time = bound(time, 1000, type(uint256).max);
        time = bound(time, 1000, type(uint96).max);
        //1. depositfunds
        
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        console.log("Start balance: ", startBalance);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");
        //2. warp the time
        vm.warp(block.timestamp + time);
        //3. Check the accrued interest
        uint256 interestAccrued = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        uint256 balanceAfterSomeTime = rebase.balanceOf(USER);
        //4. Add some rewards to the vault
        addewardsToVault(balanceAfterSomeTime - amount);
        console.log("Balance difference after some time: ", balanceAfterSomeTime - amount);
        //5. redeem the entire balance
        vm.prank(USER);
        vault.redeem(type(uint256).max);

        uint256 endBalance = rebase.balanceOf(USER);
        uint256 ethUserBalance = address(USER).balance;
        console.log("User balance: ", ethUserBalance);
        console.log("End balance: ", endBalance);
        assertEq(endBalance, 0, "Balance should be 0 after redeeming");
        assertGt(ethUserBalance, startBalance, "Balance should be greater than the amount deposited");
        assertEq(ethUserBalance, amount + interestAccrued, "Balance should be equal to the amount deposited + interest accrued");
        
    }
}
    