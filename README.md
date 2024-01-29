# Swap Terminal

The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap pool to exchange the tokens it received for tokens that the project's primary terminal accepts. Then, it pays the project's primary terminal with the tokens it got from the pool, forwarding the original payer as the beneficiary for any tokens or NFTs minted by that payment.

EXAMPLE: The "Clungle" project's primary terminal accepts ETH and mints $CLNG tokens. It also has a swap terminal. If Jimmy tries to pay Clungle with USDC, the swap terminal will swap the USDC for ETH. Then it pays that ETH into the primary terminal, minting $CLNG tokens for Jimmy.

*If you're having trouble understanding this contract, take a look at the [core Juicebox contracts](https://github.com/bananapus/juice-contracts-v4) and the [documentation](https://docs.juicebox.money/) first. If you have questions, reach out on [Discord](https://discord.com/invite/ErQYmth4dS).*

## Develop

`juice-swap-terminal` uses the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
forge install
```

If you run into trouble with `forge install`, try using `git submodule update --init --recursive` to ensure that nested submodules have been properly initialized.

Some useful commands:

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `forge install`       | Install the dependencies.                           |
| `forge build`         | Compile the contracts and write artifacts to `out`. |
| `forge fmt`           | Lint.                                               |
| `forge test`          | Run the tests.                                      |
| `forge build --sizes` | Get contract sizes.                                 |
| `forge coverage`      | Generate a test coverage report.                    |
| `foundryup`           | Update foundry. Run this periodically.              |
| `forge clean`         | Remove the build artifacts and cache directories.   |

To learn more, visit the [Foundry Book](https://book.getfoundry.sh/) docs.

We recommend using [Juan Blanco's solidity extension](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) for VSCode.

## Utilities

For convenience, several utility commands are available in `util.sh`. To see a list, run:

```bash
`bash util.sh --help`.
```

Or make the script executable and run:

```bash
./util.sh --help
```

## Terminals

Juicebox projects can accept funds through one or more *terminals*, which can manage both inflows (via payments) and outflows (via redemptions). When someone attempts to pay a project with a token, if the project both (i) has a swap terminal and (ii) does not have another terminal which accepts that token, the payment is routed to the swap terminal, which swaps their tokens for a the token that the project's primary (default) terminal *does* accept, and then redirects the payment to the primary terminal.

A project can set its terminals (and primary terminal) in the `JBDirectory` contract.
