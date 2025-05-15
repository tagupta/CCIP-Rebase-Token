// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebase;
    address private OWNER = makeAddr("owner");
    address private USER = makeAddr("user");
    address private NEW_USER = makeAddr("new user");
    address private MINTER_BURNER = makeAddr("mint and burn role");
    uint256 private constant INITIAL_INTEREST_RATE = 5e10;
    uint256 private constant INITIAL_VALUE = 10 ether;

    function setUp() external {
        vm.startPrank(OWNER);
        rebase = new RebaseToken();
        rebase.grantMintAndBurnRole(MINTER_BURNER);
        vm.stopPrank();

        vm.prank(MINTER_BURNER);
        rebase.mint(USER, INITIAL_VALUE);
    }

    /*//////////////////////////////////////////////////////////////
                              BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckOwner() external view {
        address owner = rebase.owner();
        assert(owner == OWNER);
    }

    function test_CheckTokenNameAndSymbol() external view {
        string memory name = rebase.name();
        string memory symbol = rebase.symbol();
        assert(keccak256(abi.encode(name)) == keccak256(abi.encode(rebase.NAME())));
        assert(keccak256(abi.encode(symbol)) == keccak256(abi.encode(rebase.SYMBOL())));
    }

    function test_InterestRateIsZero() external view {
        uint256 interestRate = rebase.getUserInterestRate(USER);
        assertEq(interestRate, INITIAL_INTEREST_RATE);
    }

    function test_GlobalInterestRate() external view {
        assertEq(rebase.getInterestRate(), INITIAL_INTEREST_RATE);
    }

    function test_RevertIfNewInterestRateIsMoreThanPrevious() external {
        uint256 newInterestRate = 5e11;
        vm.expectRevert(
            abi.encodeWithSelector(
                IRebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, INITIAL_INTEREST_RATE, newInterestRate
            )
        );
        vm.prank(OWNER);
        rebase.setInterestRate(newInterestRate);
    }

    function test_SetNewInterestRate() external {
        uint256 newInterestRate = 4e10;
        vm.expectEmit(false, false, false, true);
        emit IRebaseToken.InterestRateSet(newInterestRate);
        vm.prank(OWNER);
        rebase.setInterestRate(newInterestRate);
    }

    function test_PrincipleBalanceAfterMint() external view {
        assertEq(rebase.principleBalanceOf(USER), INITIAL_VALUE);
    }

    function test_ZeroBalanceNoInterestAccrual() public {
        address zeroBalanceUser = makeAddr("zeroBalance");
        assertEq(rebase.calculateAccumulatedInterestSinceLastUpdate(zeroBalanceUser), 0);
    }

    function test_InterestAfterRateChange() public {
        uint256 newRate = 4e10;
        vm.prank(OWNER);
        rebase.setInterestRate(newRate);

        // Verify old users keep old rate, new users get new rate
        vm.prank(MINTER_BURNER);
        rebase.mint(NEW_USER, 1 ether);
        assertEq(rebase.getUserInterestRate(USER), INITIAL_INTEREST_RATE);
        assertEq(rebase.getUserInterestRate(NEW_USER), newRate);
    }

    /*//////////////////////////////////////////////////////////////
                          ONLY OWNER AND MINTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerCanSetTheMintAndBurnRole() external {
        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x123)));
        rebase.grantMintAndBurnRole(USER);
    }

    function test_OnlyOwnerCanSetInterestRate() external {
        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x123)));
        rebase.setInterestRate(5e11);
    }

    function test_OnlyMinterCanCallMint() external {
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0x123), rebase.getMintAndBurnRole()
            )
        );
        rebase.mint(USER, INITIAL_VALUE);
        vm.stopPrank();
    }

    function test_OnlyBurnerCanCallBurn() external {
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0x123), rebase.getMintAndBurnRole()
            )
        );
        rebase.burn(USER, INITIAL_VALUE);
        vm.stopPrank();
    }

    function test_RevokeMintBurnRole() public {
        vm.startPrank(OWNER);
        rebase.revokeMintAndBurnRole(rebase.getMintAndBurnRole(), MINTER_BURNER);
        vm.stopPrank();

        vm.startPrank(MINTER_BURNER);
        //AccessControlUnauthorizedAccount(account, role);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, MINTER_BURNER, rebase.getMintAndBurnRole()
            )
        ); // Should fail after role revoked
        rebase.mint(USER, 1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InterestAccruedBalance() external {
        uint256 startTime = block.timestamp;
        vm.warp(startTime + 10);
        vm.roll(block.number + 1);
        uint256 timeElapsed = block.timestamp - rebase.getLastInteractionTimeStamp(USER);

        //check the balance of the interestAccrued;
        uint256 userInterestRate = rebase.getUserInterestRate(USER);
        uint256 accruedBalance = INITIAL_VALUE * userInterestRate * timeElapsed / rebase.getPrecisionFactor();
        assertEq(accruedBalance, rebase.calculateAccumulatedInterestSinceLastUpdate(USER));
    }

    function test_CheckAccruedBalanceAndMintRebase() external {
        vm.warp(block.timestamp + 10);
        vm.roll(block.number + 1);
        uint256 totalBalance = rebase.balanceOf(USER);
        uint256 primaryBalance = rebase.principleBalanceOf(USER);
        uint256 accruedBalance = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);

        assertEq(totalBalance - primaryBalance, accruedBalance);
    }

    modifier changeTimeStamp() {
        vm.warp(block.timestamp + 10);
        vm.roll(block.number + 1);
        _;
    }

    function test_MintNewRebaseTokens() external changeTimeStamp {
        uint256 newAmountToBurn = 1 ether;
        vm.prank(MINTER_BURNER);
        rebase.mint(USER, newAmountToBurn);

        assertEq(rebase.balanceOf(USER), rebase.principleBalanceOf(USER));
    }

    function test_MultipleConsecutiveMints() public changeTimeStamp {
        uint256 primaryBalance = rebase.principleBalanceOf(USER);

        vm.startPrank(MINTER_BURNER);
        uint256 accruedBalance = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        rebase.mint(USER, 1 ether);

        vm.warp(block.timestamp + 10);
        vm.roll(block.number + 1);
        accruedBalance += rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        rebase.mint(USER, 1 ether);

        vm.warp(block.timestamp + 10);
        vm.roll(block.number + 1);
        accruedBalance += rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        rebase.mint(USER, 1 ether);
        vm.stopPrank();

        uint256 expectedBalance = primaryBalance + accruedBalance + 3 ether;
        assertEq(expectedBalance, rebase.balanceOf(USER));
    }

    function test_ExtremeTimeDifference() public {
        uint256 initialBalance = rebase.principleBalanceOf(USER);
        vm.warp(block.timestamp + 365 days * 10); // 10 years
        vm.roll(block.number + 1);
        uint256 interest = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        vm.prank(MINTER_BURNER);
        rebase.mint(USER, 1 ether);

        assert(initialBalance + interest + 1 ether == rebase.balanceOf(USER));
    }

    /*//////////////////////////////////////////////////////////////
                               BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintAccruedBalanceToBurn() external changeTimeStamp {
        uint256 accruedBalance = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        vm.prank(MINTER_BURNER);
        rebase.burn(USER, INITIAL_VALUE);
        uint256 leftOverBalance = rebase.principleBalanceOf(USER);
        assertEq(accruedBalance, leftOverBalance);
    }

    function test_BurnCompleteBalance() external {
        vm.prank(MINTER_BURNER);
        rebase.burn(USER, type(uint256).max);
        assertEq(rebase.balanceOf(USER), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSFER TEST
    //////////////////////////////////////////////////////////////*/

    function test_TransferToSelf() public changeTimeStamp {
        uint256 initialBalance = rebase.balanceOf(USER);
        vm.prank(USER);
        rebase.transfer(USER, 1 ether);
        assertEq(rebase.balanceOf(USER), initialBalance); // Should be same (minus gas)
    }

    function test_TransferToANewWallet() external changeTimeStamp {
        uint256 accruedInterest = rebase.calculateAccumulatedInterestSinceLastUpdate(USER);
        address newWallet = makeAddr("new wallet");

        vm.prank(USER);
        rebase.transfer(newWallet, INITIAL_VALUE);

        assertEq(rebase.principleBalanceOf(USER), accruedInterest);
        assertEq(rebase.getUserInterestRate(USER), rebase.getUserInterestRate(newWallet));
    }

    function test_AssignNewInterestRateIfBalanceZero() external changeTimeStamp {
        uint256 newInterestRate = 4e10;
        uint256 amountToTransfer = 1e18;
        vm.prank(OWNER);
        rebase.setInterestRate(newInterestRate);

        assertEq(rebase.getUserInterestRate(USER), INITIAL_INTEREST_RATE);

        //New USER -> IR = e4e10, USER -> IR = 5e10
        vm.prank(MINTER_BURNER);
        rebase.mint(NEW_USER, INITIAL_VALUE); //Tokens minted using new interest rate

        //if USER tries to transfer all the funds to NEW_USER, then USER's IR changes to new Interest rate
        vm.prank(USER);
        rebase.transfer(NEW_USER, type(uint256).max);

        assertEq(rebase.balanceOf(USER), 0);

        //let new user transfer some funds to USER
        vm.prank(NEW_USER);
        rebase.transfer(USER, amountToTransfer);

        assertEq(rebase.getUserInterestRate(NEW_USER), rebase.getUserInterestRate(USER));
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferFrom() external {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, INITIAL_VALUE)
        );
        //transferring without approval
        rebase.transferFrom(USER, NEW_USER, INITIAL_VALUE);
    }

    function test_transferFundsFromOneUserToAnother() external changeTimeStamp {
        vm.prank(USER);
        rebase.approve(address(this), INITIAL_VALUE);
        rebase.transferFrom(USER, NEW_USER, INITIAL_VALUE);
        assert(rebase.getUserInterestRate(USER) == rebase.getUserInterestRate(NEW_USER));
        assert(rebase.getLastInteractionTimeStamp(USER) == block.timestamp);
    }
}
