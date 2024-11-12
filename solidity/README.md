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
