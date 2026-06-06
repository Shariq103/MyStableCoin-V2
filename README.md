## Foundry

# MyStableCoin Engine V2

## Protocol Overview

MyStableCoin is an algorithmic, exogenous, multiple collateral stablecoin protocol. The engine maintains a strict peg with the US Dollar through cryptographic overcollateralization. The system natively accepts arbitrary ERC20 tokens with varying decimal precisions, currently optimized for Wrapped Bitcoin (8 decimals) and Wrapped Ethereum (18 decimals).

## Live Deployment

Network: Base Sepolia L2
Contract Address: 0xF950e29b396c1Af01e1D5a3747Af65A045be2A03
Lead Architect: Mohd Shariq

## System Architecture

The core engine functions on three mathematical pillars:

- Dynamic Decimal Scaling: Chainlink price feeds and arbitrary collateral decimals are securely scaled to standard 18 decimal precision prior to state manipulation. This logic actively prevents decimal truncation attacks native to low precision assets like Wrapped Bitcoin.

- Health Factor Mechanics: Protocol users must maintain a strict minimum collateralization ratio. The system executes an immediate state reversion if a withdrawal or minting action compromises the user account health factor.

- Incentivized Liquidation: The protocol relies on rational market actors to liquidate undercollateralized debt positions. Liquidators receive a 10 percent collateral bonus for restoring global protocol solvency.

## Security and Fuzzing

The protocol architecture is rigorously verified using Foundry invariant testing suites. The system state machine was subjected to deep stateful fuzzing logic.

- Fuzzer Configuration: Seed routed multiple collateral handler.
- Total Fuzz Runs: 128000 randomized state transitions.
- Core Invariant Assessed: Total Collateral Value in USD must always exceed Total MyStableCoin Minted.
- Final Audit Result: Zero invariant breaches.

## Local Environment Initialization

Ensure the Foundry toolkit is installed on your local machine.

1. Clone the repository
2. Install the Foundry standard library
3. Compile the smart contracts using the terminal command: forge build
4. Run the comprehensive test suite using the terminal command: forge test
# MyStableCoin-V2
