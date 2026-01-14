# 🚀 Multi-Phase Launchpad Protocol

![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
![Oracle](https://img.shields.io/badge/Oracle-Chainlink_Feeds-375bd2?style=flat-square&logo=chainlink)
![Testing](https://img.shields.io/badge/Testing-Mainnet_Forking-bf4904?style=flat-square)

A robust token distribution infrastructure designed for high-fidelity pricing and regulatory compliance.

This protocol manages the sale of ERC-20 assets through a **Dynamic Phased Architecture**, allowing for granular control over pricing denominators and supply caps per stage. Unlike static sale contracts, it integrates **Chainlink Oracles** to resolve ETH/USD valuations in real-time, ensuring fair market rates during volatility.

## 🏗 Architecture & Design Decisions

### 1. Oracle-Driven Pricing (Chainlink)
- **Real-Time Valuation:**
    - Implements `IAggregator` to fetch the latest round data from Chainlink Data Feeds.
    - **Defense Mechanism:** The `getEtherPrice` logic validates that the oracle answer is strictly positive (`answer > 0`), reverting with `InvalidPrice` to prevent pricing anomalies or stale data attacks during oracle downtime.

### 2. Finite State Automata (Automated Phasing)
- **Dynamic Transition Logic:**
    - The contract does not rely on manual admin intervention to switch sales phases. Instead, the `_updatePhase` internal logic automatically advances the state based on dual triggers: **Time Expiration** or **Supply Exhaustion** (`totalSoldLimit`).
    - **Efficiency:** This lazy-evaluation approach updates the phase only during user interaction, removing the need for expensive "Keeper" transactions to maintain state.

### 3. Compliance & Security (AML)
- **Sanctions Enforcement:**
    - Includes a `blacklistedAddresses` mapping to block specific actors (e.g., OFAC sanctioned addresses) from participating.
    - **Checks-Effects-Interactions:** Purchase logic (`_processPurchase`) strictly updates the `userTokenBalance` and `totalSold` state *before* any external token transfers are executed, mitigating reentrancy risks.

## 🧪 Testing Strategy (Forking & Fuzzing)

The Quality Assurance pipeline leverages Foundry's advanced capabilities to simulate mainnet conditions.

- **Mainnet Forking:**
    - Tests are executed against a forked state of the **Arbitrum One** network to interact with the live Chainlink Aggregator, validating the price feed integration against production data.
- **Fuzz Testing:**
    - Implements property-based tests (`testFuzz_BuyWithEth`) using `bound()` to validate purchase logic across thousands of random ETH amounts, ensuring mathematical precision in token calculation and phase limits.
- **Error Selector Assertions:**
    - Utilizes `try/catch` blocks in tests to assert specific revert reasons (e.g., `Presale.AmountExceedsMaxSellingAmount.selector`), ensuring the contract fails gracefully and predictably under stress.

## 🛠 Tech Stack

* **Core:** Solidity `^0.8.24`
* **Oracle:** Chainlink Data Feeds
* **Libraries:** OpenZeppelin (SafeERC20, Ownable)
* **Testing:** Foundry (Arbitrum Forking)

## 📝 Contract Interface

The protocol exposes a compliant purchase API:

```solidity
// Purchase with Native Currency (Oracle Priced)
function buyWithEther() external payable;

// Purchase with Stablecoins (Fixed Price)
function buyWithStableCoin(address token, uint256 amount) external;
```

---


*Reference implementation for secure token launch infrastructure.*