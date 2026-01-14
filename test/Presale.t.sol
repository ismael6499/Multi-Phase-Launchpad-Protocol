// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// To run tests: forge test --fork-url https://arb1.arbitrum.io/rpc

import {Test} from "forge-std/Test.sol";
import {Presale} from "../src/Presale.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Mock Token for Sale
contract MockToken is ERC20 {
    constructor() ERC20("Sale Token", "SALE") {
        _mint(msg.sender, 1_000_000_000 * 1e18);
    }
}

contract MockToken19Decimals is ERC20 {
    constructor() ERC20("High Decimals", "HD") {
        _mint(msg.sender, 1000 * 1e19);
    }
    function decimals() public view virtual override returns (uint8) {
        return 19;
    }
}

contract MockRevertingReceiver {
    receive() external payable {
        revert("Refuse ETH");
    }
}

contract PresaleTest is Test {
    Presale public presale;

    receive() external payable {}
    MockToken public saleToken;
    
    // Arbitrum Addresses
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant DATA_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address public constant FUNDS_RECEIVER = 0x1234567890123456789012345678901234567890;

    address public user = address(0x123);

    uint256 public constant MAX_SELLING_AMOUNT = 1_000_000 * 1e18;
    Presale.Phase[3] public phases;

    function setUp() public { 
        
        saleToken = new MockToken();
        
        // Define phases
        // Phase format: [CumulativeTotalSoldLimit, PriceDenominator, EndTimestamp]
        // Price Calculation: tokenAmount = usdAmount * 1e6 / PriceDenominator
        // If PriceDenominator = 1e6 (1000000), then 1 USD = 1 Token
        // If PriceDenominator = 500000, then 1 USD = 2 Tokens (Half price)
        
        // Phase 1: Up to 100k tokens, 0.05 USD per token (1 USD = 20 Tokens)
        // PriceDenominator = 1e6 / 20 = 50000
        // Phase 1: Up to 100k tokens, 0.05 USD per token
        phases[0] = Presale.Phase({
            totalSoldLimit: 100_000 * 1e18,
            priceDenominator: 50_000,
            endTime: block.timestamp + 1 days
        });

        // Phase 2: Up to 500k tokens, 0.075 USD per token
        phases[1] = Presale.Phase({
            totalSoldLimit: 500_000 * 1e18,
            priceDenominator: 75_000,
            endTime: block.timestamp + 2 days
        });

        // Phase 3: Up to Max, 0.10 USD per token
        phases[2] = Presale.Phase({
            totalSoldLimit: MAX_SELLING_AMOUNT,
            priceDenominator: 100_000,
            endTime: block.timestamp + 5 days
        });
        
        // Deploy Presale
        presale = new Presale(
            address(saleToken),
            USDT,
            USDC,
            FUNDS_RECEIVER,
            DATA_FEED,
            MAX_SELLING_AMOUNT,
            phases,
            block.timestamp,      // Start time
            block.timestamp + 5 days // End time
        );

        // Fund Presale with Sale Tokens
        bool success = saleToken.transfer(address(presale), MAX_SELLING_AMOUNT);
        assertTrue(success, "Transfer failed");
    }

    function test_BuyWithUSDT() public {
        uint256 buyAmount = 100 * 1e6; // 100 USDT
        deal(USDT, user, buyAmount);

        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), buyAmount);
        
        // Check Phase 1 Price: 0.05 USD/Token -> 100 USD = 2000 Tokens
        uint256 expectedTokens = 2000 * 1e18; 
        
        uint256 initialReceiverBalance = IERC20(USDT).balanceOf(FUNDS_RECEIVER);

        presale.buyWithStableCoin(USDT, buyAmount);
        
        assertEq(saleToken.balanceOf(address(presale)), MAX_SELLING_AMOUNT); 
        assertEq(presale.userTokenBalance(user), expectedTokens);
        assertEq(IERC20(USDT).balanceOf(FUNDS_RECEIVER), initialReceiverBalance + buyAmount);
        
        vm.stopPrank();
    }

    function test_BuyWithUSDC() public {
        uint256 buyAmount = 100 * 1e6; // 100 USDC
        deal(USDC, user, buyAmount);

        vm.startPrank(user);
        IERC20(USDC).approve(address(presale), buyAmount);
        
        uint256 expectedTokens = 2000 * 1e18; // Same price phase 1
        
        uint256 initialReceiverBalance = IERC20(USDC).balanceOf(FUNDS_RECEIVER);
        
        presale.buyWithStableCoin(USDC, buyAmount);
        
        assertEq(presale.userTokenBalance(user), expectedTokens);
        assertEq(IERC20(USDC).balanceOf(FUNDS_RECEIVER), initialReceiverBalance + buyAmount);
        vm.stopPrank();
    }

    function test_BuyWithEth() public {
        uint256 ethAmount = 1 ether;
        deal(user, ethAmount);

        vm.startPrank(user);
        
        uint256 initialPresaleBalance = address(presale).balance;
        uint256 initialReceiverBalance = FUNDS_RECEIVER.balance;
        
        presale.buyWithEther{value: ethAmount}();
        
        // Check Funds moved to receiver
        assertEq(FUNDS_RECEIVER.balance, initialReceiverBalance + ethAmount);

        // Ensure Presale contract didn't keep any ETH
        assertEq(address(presale).balance, initialPresaleBalance);
        
        // Check User Token Balance > 0
        uint256 balance = presale.userTokenBalance(user);
        assertTrue(balance > 0);
        
        vm.stopPrank();
    }

    function test_CustomErrors_AmountExceedsMax() public {
        // Try to buy more than max
         // Max is 1M. Price 0.05. Cost = 50k USD.
         uint256 buyAmount = 60_000 * 1e6; // 60k USDT -> 1.2M Tokens
         deal(USDT, user, buyAmount);
         
         vm.startPrank(user);
         IERC20(USDT).approve(address(presale), buyAmount);
         
         vm.expectRevert(Presale.AmountExceedsMaxSellingAmount.selector);
         presale.buyWithStableCoin(USDT, buyAmount);
         vm.stopPrank();
    }

    function test_ClaimTokens() public {
        uint256 buyAmount = 100 * 1e6;
        deal(USDT, user, buyAmount);
        
        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), buyAmount);
        presale.buyWithStableCoin(USDT, buyAmount);
        
        uint256 expectedTokens = 2000 * 1e18;
        
        // Try claim before end
        vm.expectRevert(Presale.PresaleNotEnded.selector);
        presale.claimTokens();
        
        // Warp to end
        vm.warp(block.timestamp + 6 days);
        
        presale.claimTokens();
        assertEq(saleToken.balanceOf(user), expectedTokens);
        assertEq(presale.userTokenBalance(user), 0);
        
        vm.stopPrank();
    }

    function test_BlacklistFunctions() public {
        presale.blacklist(user);
        assertTrue(presale.blacklistedAddresses(user));
        
        vm.startPrank(user);
        uint256 buyAmount = 100 * 1e6;
        deal(USDT, user, buyAmount);
        IERC20(USDT).approve(address(presale), buyAmount);
        
        vm.expectRevert(Presale.UserBlacklisted.selector);
        presale.buyWithStableCoin(USDT, buyAmount);
        
        vm.deal(user, 1 ether);
        vm.expectRevert(Presale.UserBlacklisted.selector);
        presale.buyWithEther{value: 1 ether}();
        vm.stopPrank();

        presale.unblacklist(user);
        assertFalse(presale.blacklistedAddresses(user));
        
        vm.startPrank(user);
        presale.buyWithStableCoin(USDT, buyAmount);
        vm.stopPrank();
    }

    function test_EmergencyWithdraws() public {
        // ETH Withdraw
        uint256 ethAmount = 1 ether;
        vm.deal(address(presale), ethAmount);
        
        uint256 ownerBalBefore = address(this).balance;
        presale.emergencyEthWithdraw();
        assertEq(address(this).balance, ownerBalBefore + ethAmount);

        // ERC20 Withdraw
        uint256 tokenAmount = 1000 * 1e18;
        MockToken otherToken = new MockToken();
        bool success = otherToken.transfer(address(presale), tokenAmount);
        assertTrue(success, "Transfer failed");
        
        uint256 ownerTokenBalBefore = otherToken.balanceOf(address(this));
        presale.emergencyErc20Withdraw(address(otherToken), tokenAmount);
        assertEq(otherToken.balanceOf(address(this)), ownerTokenBalBefore + tokenAmount);
    }

    function test_TimeValidations() public {
        // Test Not Started
        // Redeploy with future start time
        Presale futurePresale = new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp + 1 days, block.timestamp + 5 days
        );
        
        vm.startPrank(user);
        uint256 buyAmount = 100 * 1e6;
        deal(USDT, user, buyAmount);
        IERC20(USDT).approve(address(futurePresale), buyAmount);
        
        vm.expectRevert(Presale.PresaleNotStarted.selector);
        futurePresale.buyWithStableCoin(USDT, buyAmount);
        vm.stopPrank();

        // Test Ended
        vm.warp(block.timestamp + 6 days);
        vm.startPrank(user);
        vm.expectRevert(Presale.PresaleEnded.selector);
        presale.buyWithStableCoin(USDT, buyAmount);
        vm.stopPrank();
    }

    function test_InvalidInputs() public {
        vm.startPrank(user);
        
        // Invalid Amount (0)
        vm.expectRevert(Presale.InvalidAmount.selector);
        presale.buyWithStableCoin(USDT, 0);

        // Invalid Stablecoin
        MockToken randomToken = new MockToken();
        vm.expectRevert(Presale.InvalidStablecoin.selector);
        presale.buyWithStableCoin(address(randomToken), 100);
        
        vm.stopPrank();
    }

    function test_PhaseTransitions() public {
        // Phase 1 Limit: 100k tokens. Price 0.05.
        // Buy exactly 100k tokens. Cost: 5000 USD.
        uint256 buyAmount = 5000 * 1e6;
        deal(USDT, user, buyAmount * 10); // plenty of funds
        
        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), type(uint256).max);
        
        // 1. Fill Phase 1
        presale.buyWithStableCoin(USDT, buyAmount);
        assertEq(presale.currentPhase(), 0); 
        
        // Now next buy should push it.
        // Buy 1 more token. 
        presale.buyWithStableCoin(USDT, 1 * 1e6); // Small amount
        assertEq(presale.currentPhase(), 1);
        
        vm.stopPrank();
    }

    function test_PhaseTimeTransition() public {
         // Phase 1 ends in 1 day.
         vm.warp(block.timestamp + 1 days + 1 seconds);
         
         vm.startPrank(user);
         uint256 buyAmount = 100 * 1e6;
         deal(USDT, user, buyAmount);
         IERC20(USDT).approve(address(presale), buyAmount);
         
         // Should trigger phase change due to time
         presale.buyWithStableCoin(USDT, buyAmount);
         assertEq(presale.currentPhase(), 1);
         vm.stopPrank();
    }

    function test_Constructor_InvalidTimeRange() public {
        vm.expectRevert(Presale.InvalidTimeRange.selector);
        new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp + 5 days, block.timestamp // Start > End
        );
    }

    function test_TokenDecimalsTooHigh() public {
        MockToken19Decimals highDecimalToken = new MockToken19Decimals();
        
        // Strategy: Deploy a special presale instance allowing this token.
        Presale hdPresale = new Presale(
            address(saleToken),
            address(highDecimalToken), // Treat this as USDT
            USDC,
            FUNDS_RECEIVER,
            DATA_FEED,
            MAX_SELLING_AMOUNT,
            phases,
            block.timestamp,
            block.timestamp + 5 days
        );
        
        // Fund user
        bool success = highDecimalToken.transfer(user, 100 * 1e19);
        assertTrue(success, "Transfer failed");
        
        vm.startPrank(user);
        require(highDecimalToken.decimals() == 19, "Mock failed"); // Sanity check
        highDecimalToken.approve(address(hdPresale), 100 * 1e19);
        
        vm.expectRevert(Presale.TokenDecimalsTooHigh.selector);
        hdPresale.buyWithStableCoin(address(highDecimalToken), 100 * 1e19);
        
        vm.stopPrank();
    }

    function test_BuyWithEther_ZeroValue() public {
        vm.startPrank(user);
        vm.expectRevert(Presale.InvalidAmount.selector);
        presale.buyWithEther{value: 0}();
        vm.stopPrank();
    }

    function test_IncrementalPhaseChange() public {
        // Walk through all phases
        // Limit Phase 1: 100k.
        // Limit Phase 2: 500k.
        
        deal(USDT, user, 1_000_000 * 1e6);
        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), type(uint256).max);
        
        // 1. Fill Phase 0 exactly (100k tokens)
        uint256 amountPhase0 = 5000 * 1e6; // 5000 USD / 0.05 = 100,000 tokens
        presale.buyWithStableCoin(USDT, amountPhase0);
        
        // Should still be phase 0 or 1?
        // Logic: if totalSold + amount > limit -> phase++. 
        // 100k + 0 !> 100k (False).
        // So hitting exact limit keeps it in phase 0 temporarily? 
        // Or rather, the check happens *before* adding? No, checkCurrentPhase(_amount).
        // totalSold (0) + 100k > 100k ? False.
        // So Phase stays 0.
        // Next buy triggers change.
        assertEq(presale.currentPhase(), 0);
        
        // 2. Push to Phase 1
        presale.buyWithStableCoin(USDT, 1 * 1e6); // Small buy
        // now totalSold > 100k -> Phase becomes 1.
        assertEq(presale.currentPhase(), 1);
        
        // 3. Fill Phase 1 (Target 500k total)
        // Current sold: 100k + (1e6/0.05=20) = 100,020.
        // Need to reach > 500k to enter Phase 2, but < 1M (Max).
        // Target 600k total. Need ~500k more.
        // Price Phase 1: 0.075. 500k * 0.075 = 37,500 USD.
        
        uint256 amountToPhase2 = 38_000 * 1e6; // 38k USD -> ~506k tokens
        presale.buyWithStableCoin(USDT, amountToPhase2);
        
        assertEq(presale.currentPhase(), 2);
        
        // 4. Buy in Phase 2 (checking loop skip)
        // Ensure we don't hit max. Recalc total: ~606k. Max 1M. Room for ~394k.
        presale.buyWithStableCoin(USDT, 100 * 1e6);
        assertEq(presale.currentPhase(), 2);

        vm.stopPrank();
    }

    function test_NoTokensToClaim() public {
        vm.warp(block.timestamp + 6 days);
        vm.startPrank(user);
        
        // User has 0 balance
        vm.expectRevert(Presale.NoTokensToClaim.selector);
        presale.claimTokens();
        
        vm.stopPrank();
    }
    function test_BuyWithEther_TransferFailed() public {
        MockRevertingReceiver revertingReceiver = new MockRevertingReceiver();
        
        Presale failPresale = new Presale(
            address(saleToken), USDT, USDC, address(revertingReceiver), DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp, block.timestamp + 5 days
        );
        
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        
        vm.expectRevert(Presale.ETHTransferFailed.selector);
        failPresale.buyWithEther{value: 1 ether}();
        
        vm.stopPrank();
    }

    function test_MultiPhaseJump() public {
        // Buy huge amount to jump from Phase 0 to Phase 2 immediately
        // Phase 1 limit: 100k. Phase 2 limit: 500k.
        // Price Phase 0: 0.05. 600k * 0.05 = 30k USD.
        
        deal(USDT, user, 1_000_000 * 1e6);
        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), type(uint256).max);
        
        // Check current phase 0
        assertEq(presale.currentPhase(), 0);
        
        // Phase 0 price: 0.05 (Divisor 50000).
        // I want > 500k total sold.
        
        presale.buyWithStableCoin(USDT, 30_000 * 1e6); 
        // 30k / 0.05 = 600k tokens.
        // 600k > 100k (Phase 0 limit) -> Phase 1
        // 600k > 500k (Phase 1 limit) -> Phase 2.
        
        assertEq(presale.currentPhase(), 2);
        vm.stopPrank();
    }

    function test_BuyWithEther_TimeAndLimits() public {
        // 1. Not Started
        Presale futurePresale = new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp + 1 days, block.timestamp + 5 days
        );
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        vm.expectRevert(Presale.PresaleNotStarted.selector);
        futurePresale.buyWithEther{value: 1 ether}();
        vm.stopPrank();

        // 2. Ended
        vm.warp(block.timestamp + 6 days);
        vm.startPrank(user);
        vm.expectRevert(Presale.PresaleEnded.selector);
        presale.buyWithEther{value: 1 ether}();
        vm.stopPrank();

        // 3. Max Amount
        // Reset time or use new deployment
        Presale maxPresale = new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp, block.timestamp + 5 days
        );
        // Fund it
        bool success = saleToken.transfer(address(maxPresale), MAX_SELLING_AMOUNT);
        assertTrue(success, "Transfer failed");
        
        uint256 hugeEth = 200 ether; 
        vm.deal(user, hugeEth);
        vm.startPrank(user);
        vm.expectRevert(Presale.AmountExceedsMaxSellingAmount.selector);
        maxPresale.buyWithEther{value: hugeEth}();
        vm.stopPrank();
    }

    function test_GetEtherPrice() public view {
        uint256 price = presale.getEtherPrice();
        assertTrue(price > 0);
    }

    function test_EmergencyETHWithdraw_Fail() public {
        MockRevertingReceiver revertingOwner = new MockRevertingReceiver();
        
        Presale ethPresale = new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, DATA_FEED, MAX_SELLING_AMOUNT, phases,
            block.timestamp, block.timestamp + 5 days
        );
        ethPresale.transferOwnership(address(revertingOwner));
        
        vm.deal(address(ethPresale), 1 ether);
        
        vm.startPrank(address(revertingOwner));
        vm.expectRevert(Presale.ETHTransferFailed.selector);
        ethPresale.emergencyEthWithdraw();
        vm.stopPrank();
    }

    function test_GetEtherPrice_Invalid() public {
        MockAggregator badFeed = new MockAggregator(-100);

        Presale badOraclePresale = new Presale(
            address(saleToken), USDT, USDC, FUNDS_RECEIVER, address(badFeed), MAX_SELLING_AMOUNT, phases,
            block.timestamp, block.timestamp + 5 days
        );

        vm.expectRevert(Presale.InvalidPrice.selector);
        badOraclePresale.getEtherPrice();
    }
}

contract MockAggregator {
    int256 public price;
    
    constructor(int256 _price) {
        price = _price;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, 0, 0);
    }
}

contract PresaleTestFuzz is PresaleTest {
    function testFuzz_BuyWithStableCoin(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 1e6);
        
        deal(USDT, user, amount);
        
        vm.startPrank(user);
        IERC20(USDT).approve(address(presale), amount);
        
        try presale.buyWithStableCoin(USDT, amount) {
            uint256 sold = presale.totalSold();
            assertTrue(sold <= MAX_SELLING_AMOUNT, "Sold exceeded max");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            bool isExpected = 
                selector == Presale.AmountExceedsMaxSellingAmount.selector || 
                selector == Presale.PresaleEnded.selector;
            
            assertTrue(isExpected, "Unexpected revert in fuzz test");
        }
        vm.stopPrank();
    }

    function testFuzz_BuyWithEth(uint256 amount) public {
        amount = bound(amount, 1 wei, 10_000 ether);
        
        deal(user, amount);
        vm.startPrank(user);
        
        try presale.buyWithEther{value: amount}() {
            uint256 sold = presale.totalSold();
            assertTrue(sold <= MAX_SELLING_AMOUNT, "Sold exceeded max");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            bool isExpected = 
                selector == Presale.AmountExceedsMaxSellingAmount.selector || 
                selector == Presale.ETHTransferFailed.selector;
            assertTrue(isExpected, "Unexpected revert in fuzz test");
        }
        vm.stopPrank();
    }
}