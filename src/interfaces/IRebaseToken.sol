// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRebaseToken {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);
    event InterestRateSet(uint256 newInterestRate);

    function grantMintAndBurnRole(address _account) external;
    function revokeMintAndBurnRole(bytes32 _role, address _account) external;
    function setInterestRate(uint256 _newInterestRate) external;
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address _user) external view returns (uint256);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
    function principleBalanceOf(address _user) external view returns (uint256);
    function getUserInterestRate(address user) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
    function getLastInteractionTimeStamp(address _user) external view returns (uint256);
    function calculateAccumulatedInterestSinceLastUpdate(address _user) external view returns (uint256);
    function getPrecisionFactor() external pure returns (uint256);
    function getMintAndBurnRole() external pure returns (bytes32);
}
