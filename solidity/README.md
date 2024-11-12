# ERC7683 Router

A reference ERC7683 implementation

TODO - add some more description

## Deploy a Router7683

- Run `npm install` from the root of the monorepo to install all the dependencies
- Create a `.env` file base on the [.env.example file](./.env.example) file, and set the required variables depending
  which script you are going to run.

Set the following environment variables required for running all the scripts, on each network.

- `NETWORK`: the name of the network you want to run the script
- `ETHERSCAN_API_KEY`: your Etherscan API key
- `API_KEY_ALCHEMY`: your Alchemy API key

If the network is not listed under the `rpc_endpoints` section of the [foundry.toml file](./foundry.toml) you'll have to
add a new entry for it.

For deploying the router you have to run the `npm run run:deployRouter7683`. Make sure the following environment
variable are set:

- `DEPLOYER_PK`: deployer private key
- `MAILBOX`: address of Hyperlane Mailbox contract on the chain
- `PERMIT2`: Permit2 address on `NETWORK_NAME`
- `ROUTER_OWNER`: address of the router owner
- `PROXY_ADMIN_OWNER`: address of the ProxyAdmin owner, `ROUTER_OWNER` would be used if this is not set. The router is
  deployed using a `TransparentUpgradeableProxy`, so a ProxyAdmin contract is deployed and set as the admin of the
  proxy.
- `ROUTER7683_SALT`: a single use by chain salt for deploying the the router. Make sure you use the same on all chains
  so the routers are deployed all under the same address.
- `DOMAINS`: the domains list of the routers to enroll, separated by commas

For opening an onchain order you can run `npm run run:openOrder`. Make sure the following environment variable are set:

- `ROUTER_OWNER_PK`: the router's owner private key. Only the owner can enroll routers
- `ORDER_SENDER`: address of order sender
- `ORDER_RECIPIENT`: address of order recipient
- `ITT_INPUT`: token input address
- `ITT_OUTPUT`: token output address
- `AMOUNT_IN`: amount in
- `AMOUNT_OUT`: amount out
- `DESTINATION_DOMAIN`: destination domain id

## Eco

The Eco solver need to use and intermediary contract, [`EcoAdapter`](./src//eco/EcoAdapter.sol) when calling the
`Inbox.fulfillHyperInstant` in order to approve the token that are transferred to the Inbox and fill the intent in a
single tx to prevent the token being used by other solver. This is due the the way Eco created the intents which
requires the token to be deposited on the Inbox before filling the intent where such tokens are transferred from Inbox
to the `receiver` of the intent.

### Deploying an EcoAdapter and create an intent

Set the following environment variables required for running all the scripts, on each network.

- `NETWORK`: the name of the network you want to run the script
- `ETHERSCAN_API_KEY`: your Etherscan API key
- `API_KEY_ALCHEMY`: your Alchemy API key

For deploying the adapter you also need the to set following variables:

- `ADAPTER_OWNER`: address of the owner of the adapter, probably the address of the solver
- `ECO_INBOX`: address of the Eco Inbox in the network

run `yarn run:deployEcoAdapter`

For creating an Eco intent set the following variables:

- `ECO_INTENT_SOURCE`: Eco IntentSource contract address
- `ECO_DESTINATION_CHAIN`: destination chain id
- `ECO_INBOX`: Eco Inbox address on destination chain
- `ECO_TARGET_TOKEN`: target token on destination chain
- `ECO_RECEIVER_ADDRESS`: intent receiver address
- `ECO_RECEIVER_AMOUNT`: intent target token amount
- `ECO_REWARD_TOKENS`: reward tokens address separated by coma, tokens being paid to the solver of the intent
- `ECO_RECEIVER_AMOUNT`: reward tokens amount separated by coma
- `ECO_PROVER`: address of the prover in the local chain

run `yarn run:createEcoIntent`

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ npm run lint
```

### Test

Run the tests:

```sh
$ forge test
```

Generate test coverage and output result to the terminal:

```sh
$ npm run test:coverage
```

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ npm run test:coverage:report
```
