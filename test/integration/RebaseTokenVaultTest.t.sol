// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 amount) internal {
        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        //send the amount to the vault
        (bool success,) = payable(address(vault)).call{value: amount}("");
        assertTrue(success, "Failed to send ETH to vault");
    }

    function testDepositLinear(uint256 amount) external {
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
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1, "Interest should be linear");
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) external {
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

    function testRedeemAfterTimePassed(uint256 amount, uint256 time) external {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        time = bound(time, 1000, type(uint96).max);
        //1. depositfunds
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");
        //2. warp the time
        vm.warp(block.timestamp + time);
        //3. Check the accrued interest
        uint256 interestAccrued = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        uint256 balanceAfterSomeTime = rebase.balanceOf(USER);
        //4. Add some rewards to the vault
        addRewardsToVault(balanceAfterSomeTime - amount);
        //5. redeem the entire balance
        vm.prank(USER);
        vault.redeem(type(uint256).max);

        uint256 endBalance = rebase.balanceOf(USER);
        uint256 ethUserBalance = address(USER).balance;
        assertEq(endBalance, 0, "Balance should be 0 after redeeming");
        assertGt(ethUserBalance, startBalance, "Balance should be greater than the amount deposited");
        assertEq(
            ethUserBalance,
            amount + interestAccrued,
            "Balance should be equal to the amount deposited + interest accrued"
        );
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, MIN_DEPOSIT + MIN_DEPOSIT, MAX_DEPOSIT);
        amountToSend = bound(amountToSend, MIN_DEPOSIT, amount - MIN_DEPOSIT);
        //1. deposit funds
        hoax(USER, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");
        //2. transfer some tokens to another user
        address recipient = makeAddr("recipient");
        uint256 recipientStartBalance = rebase.balanceOf(recipient);
        assertEq(recipientStartBalance, 0, "Recipient balance should be 0");
        // Owner reduces the interest rate to 4e10
        vm.prank(OWNER);
        rebase.setInterestRate(4e10);
        // Transfer the tokens
        vm.prank(USER);
        rebase.transfer(recipient, amountToSend);
        // the recipient's interest rate should have set to the sender's interest rate
        uint256 recipientInterestRate = rebase.getUserInterestRate(recipient);
        uint256 senderInterestRate = rebase.getUserInterestRate(USER);
        assertEq(
            recipientInterestRate,
            senderInterestRate,
            "Recipient interest rate should be equal to the sender's interest rate"
        );
        //3. check the recipient balance
        uint256 recipientBalance = rebase.balanceOf(recipient);
        assertEq(recipientBalance, amountToSend, "Recipient balance should be equal to the amount sent");
        //4. check the sender balance
        uint256 senderBalance = rebase.balanceOf(USER);
        assertEq(
            senderBalance, amount - amountToSend, "Sender balance should be equal to the amount deposited - amount sent"
        );
    }

    function testCanNotSetTheInterestRateByANonOwner(uint256 newInterestRate) public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        rebase.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCanNotCallMintAndBurnByNonMinter() public {
        vm.startPrank(USER);
        uint256 interestRate = rebase.getInterestRate();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER, rebase.getMintAndBurnRole()
            )
        );
        rebase.mint(USER, MIN_DEPOSIT, interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebase.burn(USER, MIN_DEPOSIT);
        vm.stopPrank();
    }

    function testGetRebaseTokenAddress() public view {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(
            rebaseTokenAddress, address(rebase), "Rebase token address should be equal to the rebase token address"
        );
    }

    function testGetPrincipleTokenAmount(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        //depodit funds
        hoax(USER, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebase.balanceOf(USER);
        assertEq(startBalance, amount, "Balance should be equal to the amount deposited");
        // get the principle token amount
        uint256 principleTokenAmount = rebase.principleBalanceOf(USER);
        assertEq(principleTokenAmount, amount, "Principle token amount should be equal to the amount deposited");

        //warp the time
        vm.warp(block.timestamp + 1 hours);
        //get the principle token amount again
        uint256 principleTokenAmountAfterTime = rebase.principleBalanceOf(USER);
        assertEq(
            principleTokenAmountAfterTime, amount, "Principle token amount should be equal to the amount deposited"
        );
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebase.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.startPrank(OWNER);
        vm.expectPartialRevert(IRebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebase.setInterestRate(newInterestRate);
        vm.stopPrank();
        assertEq(rebase.getInterestRate(), initialInterestRate, "Interest rate should not be changed");
    }
}
