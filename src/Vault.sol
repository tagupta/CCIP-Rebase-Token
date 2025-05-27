// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract Vault {
    //pass token address to the constructor
    //create a deposit function that mints tokens to the user equal to the amount of ETH deposited
    //create a redeem function that burns tokens from the user and send the user ETH
    //create a way to add rewards to the vault
    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Allows users to deposit ETH and mint rebase token of the same amount in return
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their deposited ETH and burn rebase tokens in return
     * @param _amount The amount of ETH to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // burn tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // tranfer the same amount of ETH back to user
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert Vault__RedeemFailed();
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
