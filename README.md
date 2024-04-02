# Swap Terminal

The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap pool to exchange the tokens it received for tokens that another one of the project's terminals accepts. Then, it pays the project's primary terminal for the tokens it got from the pool, forwarding the specified beneficiary to receive any tokens or NFTs minted by that payment.

EXAMPLE: One of the "Clungle" project's terminals accepts ETH and mints $CLNG tokens. The Clungle project also has a swap terminal. If Jimmy pays the Clungle project with USDC and sets his address as the payment's beneficiary, the swap terminal will swap the USDC for ETH. Then it pays that ETH into the terminal which accepts ETH, minting $CLNG tokens for Jimmy.

_If you're having trouble understanding this contract, take a look at the [core protocol contracts](https://github.com/Bananapus/nana-core) and the [documentation](https://docs.juicebox.money/) first. If you have questions, reach out on [Discord](https://discord.com/invite/ErQYmth4dS)._

## Install

How to install `nana-swap-terminal` in another project.

For projects using `npm` to manage dependencies (recommended):

```bash
npm install @bananapus/swap-terminal
```

For projects using `forge` to manage dependencies (not recommended):

```bash
forge install Bananapus/nana-swap-terminal
```

If you're using `forge` to manage dependencies, add `@bananapus/swap-terminal/=lib/nana-swap-terminal/` to `remappings.txt`. You'll also need to install `nana-swap-terminal`'s dependencies and add similar remappings for them.

## Develop

`nana-swap-terminal` uses [npm](https://www.npmjs.com/) (version >=20.0.0) for package management and the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, [install Node.js](https://nodejs.org/en/download) and install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
npm ci && forge install
```

If you run into trouble with `forge install`, try using `git submodule update --init --recursive` to ensure that nested submodules have been properly initialized.

Some useful commands:

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `forge build`         | Compile the contracts and write artifacts to `out`. |
| `forge fmt`           | Lint.                                               |
| `forge test`          | Run the tests.                                      |
| `forge build --sizes` | Get contract sizes.                                 |
| `forge coverage`      | Generate a test coverage report.                    |
| `foundryup`           | Update foundry. Run this periodically.              |
| `forge clean`         | Remove the build artifacts and cache directories.   |

To learn more, visit the [Foundry Book](https://book.getfoundry.sh/) docs.

## Scripts

For convenience, several utility commands are available in `package.json`.

| Command                           | Description                            |
| --------------------------------- | -------------------------------------- |
| `npm test`                        | Run local tests.                       |
| `npm run test:fork`               | Run fork tests (for use in CI).        |
| `npm run coverage`                | Generate an LCOV test coverage report. |
| `npm run deploy:ethereum-mainnet` | Deploy to Ethereum mainnet             |
| `npm run deploy:ethereum-sepolia` | Deploy to Ethereum Sepolia testnet     |
| `npm run deploy:optimism-mainnet` | Deploy to Optimism mainnet             |
| `npm run deploy:optimism-testnet` | Deploy to Optimism testnet             |
| `npm run deploy:polygon-mainnet`  | Deploy to Polygon mainnet              |
| `npm run deploy:polygon-mumbai`   | Deploy to Polygon Mumbai testnet       |

## Terminals

Juicebox projects can accept funds through one or more _terminals_, which can manage both inflows (via payments) and outflows (via redemptions). Terminals usually only accept one token for payments, but if a project has a swap terminal, the swap terminal can accept any token and swap it for tokens which the project _can_ accept. After swapping, it redirects the payment to the primary terminal for the token it received.

A project can set its terminals (and primary terminals) in the `JBDirectory` contract.
