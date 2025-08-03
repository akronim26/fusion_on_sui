# Escrow Contracts

A Move-based smart contract system for Sui blockchain implementing secure escrow functionality with hashlock and timelock mechanisms for cross-chain atomic swaps.

## Overview

This project provides a robust escrow system that enables secure fund transfers between parties with cryptographic guarantees. The contracts implement both source-chain and destination-chain escrow patterns, making them ideal for cross-chain atomic swaps and decentralized trading scenarios.

### Key Features

- **Cross-Chain Escrow**: Implements both source (`src`) and destination (`des`) escrow patterns for cross-chain transactions
- **Hashlock Security**: Uses cryptographic hashlocks to ensure only intended recipients can claim funds
- **Timelock Protection**: Implements timelocks to prevent indefinite fund locking
- **Deterministic ID Generation**: Uses CREATE2-like deterministic address generation for escrow contracts
- **Security Deposits**: Requires minimum security deposits to prevent spam and malicious behavior
- **Fusion Orders**: Advanced order system for complex trading scenarios
- **Factory Patterns**: Factory contracts for simplified escrow creation

## Architecture

The contract system consists of several key modules:

### Core Modules

1. **Escrow Contracts** (`escrow_src.move`, `escrow_des.move`)
   - Main escrow implementation with claim and refund functionality
   - Hashlock and timelock enforcement
   - Security deposit management

2. **Order Types** (`order_types.move`)
   - Core data structures for orders and escrow creation
   - Deterministic ID generation utilities
   - Order lifecycle management

3. **Factory Contracts** (`escrow_factory_src.move`, `escrow_factory_des.move`)
   - Factory patterns for simplified escrow creation
   - Ownership and access control mechanisms

4. **Fusion Orders** (`fusion_order.move`)
   - Advanced order system for complex trading scenarios
   - Event emission for order lifecycle tracking
   - Cross-chain trade parameter management

## Getting Started

### Prerequisites

- [Sui CLI](https://docs.sui.io/devnet/build/install)
- Rust and Cargo (for Move development)
- Node.js (for frontend integration, optional)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/akronim26/fusion_on_sui
   cd escrow_contracts
   ```

2. Install dependencies:
   ```bash
   sui move compile
   ```

3. Run tests:
   ```bash
   sui move test
   ```
