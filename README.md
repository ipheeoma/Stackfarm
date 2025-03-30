# Yield Farming Token Contract

## Overview

This sophisticated Yield Farming Token Contract is implemented in Clarity for the Stacks blockchain. The contract allows users to stake tokens across multiple pools with varying risk and reward characteristics, providing a flexible and secure yield farming mechanism.

## Features

### Token Management
- Fungible token (yield-token) with minting capabilities
- Initial token allocation of 1,000,000 tokens

### Staking Pools
- Multiple staking pools with different risk factors and reward multipliers
- Pools include:
  - Conservative Pool: Low risk, 80% base rewards
  - Balanced Pool: Medium risk, 120% base rewards
  - Aggressive Pool: High risk, 200% base rewards

### Key Functions

#### User Functions
- `stake-in-pool`: Stake tokens in a specific pool
- `unstake-from-pool`: Unstake tokens and claim rewards
- `emergency-withdraw`: Withdraw tokens during emergency mode (with penalty)

#### Admin Functions
- `create-pool`: Create new staking pools
- `update-pool`: Modify existing pool parameters
- `set-emergency-mode`: Activate/deactivate emergency withdrawal mode
- `set-emergency-penalty`: Set penalty rate for emergency withdrawals
- `update-reward-rate`: Adjust global reward rate

### Security Features
- Owner-only administrative functions
- Input validation for all critical operations
- Emergency mode with configurable withdrawal penalty
- Risk-based pool design

## Error Handling

The contract includes comprehensive error codes:
- `ERR-TRANSFER-FAILED`: Token transfer issues
- `ERR-INSUFFICIENT-BALANCE`: Insufficient token balance
- `ERR-UNAUTHORIZED`: Unauthorized access attempt
- `ERR-INVALID-AMOUNT`: Invalid token amount
- `ERR-INVALID-RATE`: Invalid reward or risk rate
- `ERR-INVALID-POOL`: Pool configuration error

## Reward Calculation

Rewards are calculated based on:
- Base reward rate (tokens per block)
- Pool-specific reward multiplier
- User's staked amount
- Total pool staked amount

## Deployment and Initialization

1. Deploy the contract
2. Call `initialize-farm()` to:
   - Mint initial tokens
   - Set base reward rate
   - Create default pools

## Read-Only Functions

- `get-user-pool-stake`: Retrieve user's stake in a specific pool
- `get-pool-info`: Get detailed information about a pool
- `get-total-staked`: Check total tokens staked across all pools
- `get-emergency-mode`: Check current emergency mode status

## Backward Compatibility

Includes `stake` and `unstake` functions for the default pool to maintain compatibility with older interfaces.

## Security Considerations

- Only contract owner can modify core parameters
- Emergency mode provides a safety mechanism for users
- Configurable emergency withdrawal penalty
- Strict input validation

## Usage Example

```clarity
;; Stake 100 tokens in the Balanced pool
(contract-call? .yield-farming-contract stake-in-pool u1 u100)

;; Unstake from the Balanced pool
(contract-call? .yield-farming-contract unstake-from-pool u1 u50)
```
