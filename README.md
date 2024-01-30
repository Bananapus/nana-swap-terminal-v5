# Swap Terminal

The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap pool to exchange the tokens it received for tokens that another one of the project's terminals accepts. Then, it pays the project's primary terminal for the tokens it got from the pool, forwarding the specified beneficiary to receive any tokens or NFTs minted by that payment.

EXAMPLE: One of the "Clungle" project's terminals accepts ETH and mints $CLNG tokens. The Clungle project also has a swap terminal. If Jimmy pays the Clungle project with USDC and sets his address as the payment's beneficiary, the swap terminal will swap the USDC for ETH. Then it pays that ETH into the terminal which accepts ETH, minting $CLNG tokens for Jimmy.

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

Juicebox projects can accept funds through one or more *terminals*, which can manage both inflows (via payments) and outflows (via redemptions). Terminals usually only accept one token for payments, but if a project has a swap terminal, the swap terminal can accept any token and swap it for tokens which the project *can* accept. After swapping, it redirects the payment to the primary terminal for the token it received.

A project can set its terminals (and primary terminals) in the `JBDirectory` contract.
