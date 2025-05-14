// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';

/**
 * @title Rebase Token
 * @author Tanu Gupta
 * @notice This is a cross chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate, that's the global interest rate at the time of deposit
 */
contract RebaseToken is Ownable, ERC20, AccessControl {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private s_interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastMintedAt) private s_userLastUpdatedTimestamp;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event InterestRateSet(uint256 newInterestRate);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor() ERC20("Rebase token", "RBT") Ownable(msg.sender){}

    /**
     * @notice This is to restrict the minting and burning of rebase tokens
     * @param _account The account to grant access to for minting and burning rebase tokens
     * @dev Only the owner of the contract can grant MINT_AND_BURN permission to others.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner{
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit in the value
     * @param _to The user to mint tokens to
     * @param _amount The amount to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){
        //set the interest rate for users
        //get accured interest
        //then mint the amount + accured interest over rebase token
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from the account to burn tokens from
     * @param _amount the amount to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){
        // Measure to mitigate against dust which could have accumulated since the transaction submitted till transaction execution
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        //mint the accrued interest first
        //burn all the tokens from the balance of the user
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculates the balance of the user including the interest that has accumulated since the last update
     * principle balance  + some accrued interest
     * @param _user The user to get balance for
     * @return The balance of the user including interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // find the current balance of the rebase tokens that have been minted to them - Principle balance
        // calculate the interest balance
        // return the collective value as multiply the principle balance by the interest rate that has accumulated in time since the balance was last updated
        // principleAmount + principleAmount * interestRate * timeElapsed
        return super.balanceOf(_user) * _calculateAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice For transferring tokens from one user to another
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount to transfer
     * @return True, if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        //Check to see if they are sending their entire balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender The user to transfer tokens from
     * @param _recipient The user to receive tokens
     * @param _amount The amount to transfer
     * @return True, if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        //if the caller is trying to send complete balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice To check principle balance of a user that's the amount of tokens minted so far and excluding the interest accrued since the last time user interacted with the protocol
     * @param _user The user to check balance of
     */
    function principleBalanceOf(address _user) external view returns(uint256){
        return super.balanceOf(_user);
    }

    /**
     * Calculates the interest that has last accumulated
     * @param _user The user to calculate the accumulated interest for
     * @return linearInterest The interest that has accumulated since the last update
     */
    function _calculateAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // principleAmount + principleAmount * interestRate * timeElapsed
        // principleAmount * (1 + interestRate * timeElapsed);
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        uint256 interestRate = s_userInterestRate[_user];
        linearInterest = PRECISION_FACTOR + interestRate * timeElapsed;
    }

    /**
     * Mint the accrued interest to the user since the last time they interacted with the protocol. (burn/ mint/ transfer)
     * @param _user User to mint the interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // find the current balance of the rebase tokens that have been minted to them - Principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // Calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // no of tokens that need to be minted => balanceOf - Principle balance
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // update the lastMintedAt timeStamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Returns the interest rate of the user address
     * @param user The address to get interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }
    
    /**
     * @notice Get the interest rate that is currently set for the contract. Any future depositors will receive this interest rate.
     * @return Returns the interest rate for the contract
     */
    function getInterestRate() external view returns(uint256){
        return s_interestRate;
    }
}
