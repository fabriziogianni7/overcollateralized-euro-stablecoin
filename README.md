![Stablecoin demo](https://raw.githubusercontent.com/fabriziogianni7/overcollateralized-euro-stablecoin/refs/heads/main/public/stablecoin-gif.gif)

## Overcollateralized EURO Stablecoin

### Index
- [What is it](#what-is-it)
- [How the stablecoin works](#how-the-stablecoin-works)
- [How to run locally](#how-to-run-locally)
- [How to test](#how-to-test)
- [How to contribute](#how-to-contribute)

### What is it
This repo contains a prototype EUR-pegged stablecoin system built with Foundry. The system issues a token called `DSC` and keeps it overcollateralized using ETH and BTC-based collateral, with price data from Chainlink feeds.
I was inspired by the one and only Patrick Collins to do this project and I tried to do it in my own way. [This is the class from patrick](https://www.youtube.com/watch?v=8dRAd-Bzc_E) - he, tho, makes a USD pegged stable, while this project is about an EUR stablecoin.

### How the stablecoin works
- **Core contracts**
  - `DecentralizedStablecoin.sol` is the ERC-20 token; only `DSCEngine` can mint/burn.
  - `DSCEngine.sol` tracks collateral and debt, enforces safety checks, and handles liquidations.
- **Collateral types**
  - WETH, WBTC, and native ETH deposits are accepted as collateral.
- **Peg and minting**
  - Mint amounts are computed from EUR/USD, ETH/USD, and BTC/USD Chainlink feeds.
  - The system targets a **minimum 150% collateralization** (health factor > 1).
- **Redeem and burn**
  - Burning `DSC` allows you to redeem the corresponding collateral amount.
- **Liquidations**
  - If a position’s health factor falls below 1, anyone can liquidate part of the debt.
  - Liquidators receive the repaid collateral plus a 10% bonus.

### How to run locally
#### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

#### Install dependencies
```bash
forge install
```

#### Build contracts
```bash
forge build
```

#### Run a local deployment (Anvil)
```bash
anvil
```
In a second terminal:
```bash
forge script script/DeployDSC.s.sol:DeployDSC --rpc-url http://localhost:8545 --broadcast
```
The local config deploys mock Chainlink feeds and mock WETH/WBTC with large balances for the deployer.

### How to test
Run the full test suite:
```bash
forge test -vvv
```

Run only invariant tests:
```bash
forge test --match-path test/invariant/DSCEngine.invariant.t.sol -vvv
```

Format checks:
```bash
forge fmt --check
```

### How to contribute
- Fork the repo and create a feature branch.
- Keep changes focused and add/extend tests.
- Run `forge fmt --check` and `forge test` before opening a PR.
- Open a PR with a clear description of the change and rationale.
