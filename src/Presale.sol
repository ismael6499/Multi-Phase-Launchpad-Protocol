// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregator} from "./interfaces/IAggregator.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    struct Phase {
        uint256 totalSoldLimit;
        uint256 priceDenominator;
        uint256 endTime;
    }

    address public immutable USDT_ADDRESS;
    address public immutable USDC_ADDRESS;
    address public immutable FUNDS_RECEIVER_ADDRESS;
    address public immutable DATA_FEED_ADDRESS;
    address public immutable SALE_TOKEN_ADDRESS;
    uint256 public immutable MAX_SELLING_AMOUNT;
    uint256 public immutable START_TIME;
    uint256 public immutable END_TIME;
    
    Phase[3] public phases;
    uint256 public currentPhase;
    uint256 public totalSold;
    
    mapping(address => bool) public blacklistedAddresses;
    mapping(address => uint256) public userTokenBalance;

    event TokenBought(address indexed user, uint256 amount);
    event PhaseChanged(uint256 indexed previousPhase, uint256 indexed newPhase);

    error InvalidTimeRange();
    error PresaleNotEnded();
    error PresaleNotStarted();
    error PresaleEnded();
    error NoTokensToClaim();
    error UserBlacklisted();
    error InvalidStablecoin();
    error TokenDecimalsTooHigh();
    error InvalidAmount();
    error AmountExceedsMaxSellingAmount();
    error ETHTransferFailed();
    error InvalidPrice();

    /// @notice Initializes the contract with the presale configuration
    constructor(
        address _saleTokenAddress,
        address _usdtAddress, 
        address _usdcAddress, 
        address _fundsReceiverAddress, 
        address _dataFeedAddress,
        uint256 _maxSellingAmount, 
        Phase[3] memory _phases,
        uint256 _startTime,
        uint256 _endTime
    ) Ownable(msg.sender) {
        if (_startTime >= _endTime) revert InvalidTimeRange();
        
        SALE_TOKEN_ADDRESS = _saleTokenAddress;
        USDT_ADDRESS = _usdtAddress;
        USDC_ADDRESS = _usdcAddress;
        FUNDS_RECEIVER_ADDRESS = _fundsReceiverAddress;
        DATA_FEED_ADDRESS = _dataFeedAddress;
        MAX_SELLING_AMOUNT = _maxSellingAmount;
        START_TIME = _startTime;
        END_TIME = _endTime;
        
        phases[0] = _phases[0];
        phases[1] = _phases[1];
        phases[2] = _phases[2];
    }

    function claimTokens() external {
        if (block.timestamp <= END_TIME) revert PresaleNotEnded();
        uint256 amount = userTokenBalance[msg.sender];
        if (amount == 0) revert NoTokensToClaim();
        
        delete userTokenBalance[msg.sender];
        IERC20(SALE_TOKEN_ADDRESS).safeTransfer(msg.sender, amount);
    }
    
    function blacklist(address _user) external onlyOwner {
        blacklistedAddresses[_user] = true;
    } 

    function unblacklist(address _user) external onlyOwner {
        blacklistedAddresses[_user] = false;
    } 

    function buyWithStableCoin(address _stableCoinAddress, uint256 _amount) external {
        _validatePurchase();
        if (_stableCoinAddress != USDT_ADDRESS && _stableCoinAddress != USDC_ADDRESS) revert InvalidStablecoin();
        
        uint256 decimals = ERC20(_stableCoinAddress).decimals();
        if (decimals > 18) revert TokenDecimalsTooHigh();
        
        uint256 tokenAmountToReceive = _amount * 10**(24 - decimals) / phases[currentPhase].priceDenominator;
        
        _processPurchase(tokenAmountToReceive);
        
        IERC20(_stableCoinAddress).safeTransferFrom(msg.sender, FUNDS_RECEIVER_ADDRESS, _amount);
        emit TokenBought(msg.sender, tokenAmountToReceive);
    }

    function buyWithEther() external payable {
        _validatePurchase();
        
        uint256 etherPrice = getEtherPrice();
        uint256 usdValue = msg.value * etherPrice / 1e18;
        uint256 tokenAmountToReceive = usdValue * 1e6 / phases[currentPhase].priceDenominator;
        
        _processPurchase(tokenAmountToReceive);
        
        (bool success, ) = FUNDS_RECEIVER_ADDRESS.call{value: msg.value}("");
        if (!success) revert ETHTransferFailed();

        emit TokenBought(msg.sender, tokenAmountToReceive);
    }

    function emergencyErc20Withdraw(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);
    }

    function emergencyEthWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) revert ETHTransferFailed();
    }

    function getEtherPrice() public view returns (uint256) {
        (, int256 answer, , , ) = IAggregator(DATA_FEED_ADDRESS).latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        return uint256(answer) * 1e10;
    }

    function _validatePurchase() private view {
        if (blacklistedAddresses[msg.sender]) revert UserBlacklisted();
        if (block.timestamp < START_TIME) revert PresaleNotStarted();
        if (block.timestamp > END_TIME) revert PresaleEnded();
    }

    function _processPurchase(uint256 _tokenAmount) private {
        if (_tokenAmount == 0) revert InvalidAmount();
        
        _updatePhase(_tokenAmount);
        
        totalSold += _tokenAmount;
        if (totalSold > MAX_SELLING_AMOUNT) revert AmountExceedsMaxSellingAmount();
        
        userTokenBalance[msg.sender] += _tokenAmount;
    }

    function _updatePhase(uint256 _amount) private {
        uint256 oldPhase = currentPhase;
        while (currentPhase < 2) {
            if (block.timestamp > phases[currentPhase].endTime || totalSold + _amount > phases[currentPhase].totalSoldLimit) {
                currentPhase++;
            } else {
                break;
            }
        }
        if (currentPhase != oldPhase) {
            emit PhaseChanged(oldPhase, currentPhase);
        }
    }
}
