// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAggregator.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    address public immutable usdtAddress;
    address public immutable usdcAddress;
    address public immutable fundsReceiverAddress;
    address public dataFeedAddress;
    uint256 public maxSellingAmount;
    uint256[][3] public phases;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public currentPhase;
    address public saleTokenAddress;
    uint256 public totalSold;
    mapping(address => bool) public blacklistedAddresses;
    mapping(address => uint256) public userTokenBalance;

    event TokenBought(address indexed user, uint256 amount);

    /**
     * @notice Initializes the contract with the initial configuration
     * @param _usdtAddress The address of the USDT token
     * @param _usdcAddress The address of the USDC token
     * @param _fundsReceiverAddress The address that will receive the funds
     * @param _maxSellingAmount The maximum amount allowed for sale per user
     * @param _phases The configuration for the presale phases
     * @param _startTime The timestamp when the presale starts
     * @param _endTime The timestamp when the presale ends
     */
    constructor(
        address _saleTokenAddress,
        address _usdtAddress, 
        address _usdcAddress, 
        address _fundsReceiverAddress, 
        address _dataFeedAddress,
        uint256 _maxSellingAmount, 
        uint256[][3] memory _phases,
        uint256 _startTime,
        uint256 _endTime
    ) Ownable(msg.sender) {
        saleTokenAddress = _saleTokenAddress;
        usdtAddress = _usdtAddress;
        usdcAddress = _usdcAddress;
        fundsReceiverAddress = _fundsReceiverAddress;
        maxSellingAmount = _maxSellingAmount;
        phases = _phases;
        startTime = _startTime;
        endTime = _endTime;
        dataFeedAddress = _dataFeedAddress;
        require(startTime < endTime, "Invalid time range");
        IERC20(saleTokenAddress).safeTransferFrom(msg.sender, address(this), maxSellingAmount);
    }

    function getEtherPrice() public view returns (uint256) {
        (, int256 answer, , , ) = IAggregator(dataFeedAddress).latestRoundData();
        return uint256(answer) * 1e10;
    }

    function claimTokens() external {
        require(block.timestamp > endTime, "Presale has not ended");
        uint256 amount = userTokenBalance[msg.sender];
        require(amount > 0, "No tokens to claim");
        delete userTokenBalance[msg.sender];
        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }
    
    /**
     * @notice Adds an address to the blacklist
     * @param _user The address to blacklist
     */
    function blacklist(address _user) external onlyOwner {
        blacklistedAddresses[_user] = true;
    } 

    /**
     * @notice Removes an address from the blacklist
     * @param _user The address to unblacklist
     */
    function unblacklist(address _user) external onlyOwner {
        blacklistedAddresses[_user] = false;
    } 

    function checkCurrentPhase(uint256 _amount) private {
        while (currentPhase < 2) {
            if (block.timestamp > phases[currentPhase][2] || totalSold + _amount > phases[currentPhase][0]) {
                currentPhase++;
            } else {
                break;
            }
        }
    }

    /**
     * @notice Allows users to buy tokens using stablecoins
     * @param _stableCoinAddress The address of the stablecoin to use
     * @param _amount The amount of stablecoins to spend
     */
    function buyWithStableCoin(address _stableCoinAddress, uint256 _amount) external {
        require(!blacklistedAddresses[msg.sender], "User is blacklisted");
        require(block.timestamp >= startTime, "Presale has not started");
        require(block.timestamp <= endTime, "Presale has ended");
        require(_stableCoinAddress == usdtAddress || _stableCoinAddress == usdcAddress, "Invalid stablecoin");
        uint256 decimals = ERC20(_stableCoinAddress).decimals();
        require(decimals <= 18, "Token has too many decimals");
        uint256 tokenAmountToReceive = _amount * 10**(24 - decimals) / phases[currentPhase][1];
        require(tokenAmountToReceive > 0, "Invalid amount");
        checkCurrentPhase(tokenAmountToReceive);
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Amount exceeds max selling amount");
        
        userTokenBalance[msg.sender] += tokenAmountToReceive;
        IERC20(_stableCoinAddress).safeTransferFrom(msg.sender, fundsReceiverAddress, _amount);

        emit TokenBought(msg.sender, tokenAmountToReceive);
    }

    function buyWithEther() external payable {
        require(!blacklistedAddresses[msg.sender], "User is blacklisted");
        require(block.timestamp >= startTime, "Presale has not started");
        require(block.timestamp <= endTime, "Presale has ended");
        uint256 etherPrice = getEtherPrice();
        uint256 usdValue = msg.value * etherPrice / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase][1];
        require(tokenAmountToReceive > 0, "Invalid amount");
        checkCurrentPhase(tokenAmountToReceive);
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Amount exceeds max selling amount");
        
        userTokenBalance[msg.sender] += tokenAmountToReceive;
        (bool success, ) = fundsReceiverAddress.call{value: msg.value}("");
        require(success, "ETH transfer failed");

        emit TokenBought(msg.sender, tokenAmountToReceive);
    }

    /**
     * @notice Withdraws ERC20 tokens in case of emergency
     * @param _tokenAddress The address of the token to withdraw
     * @param _amount The amount to withdraw
     */
    function emergencyERC20Withdraw(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Withdraws ETH in case of emergency
     */
    function emergencyETHWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "ETH transfer failed");
    }


}


