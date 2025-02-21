# ERC7683 Reference Implementation

## Overview

This project is centered around the [Base7683](./src/Base7683.sol) contract, which serves as the foundational component
for implementing the interfaces defined in the
[ERC7683 specification](https://github.com/across-protocol/ERCs/blob/master/ERCS/erc-7683.md). The contract is designed
to be highly flexible, supporting any `orderDataType` and `orderData`. The logic for handling specific `orderData` types
within the process of resolving and filling orders is intentionally left unimplemented, allowing inheriting contracts to
define this behavior.

While adhering to the `ERC7683` standard, `Base7683` introduces additional functionality for `settling` and `refunding`
orders. These functions are not part of the `ERC7683` specification but are included to provide a unified interface for
solvers and users across all implementations built on this framework.

Inheriting contracts must implement several key internal functions to define their specific logic for order resolution,
filling, settlement, and refunds. These include:

- `_resolveOrder(GaslessCrossChainOrder memory _order)` and `_resolveOrder(OnchainCrossChainOrder memory _order)` for
  resolving orders into a hydrated format.
- `_fillOrder(bytes32 _orderId, bytes calldata _originData, bytes calldata _fillerData)` for processing and filling
  orders.
- `_settleOrders(bytes32[] calldata _orderIds, bytes[] memory _ordersOriginData, bytes[] memory _ordersFillerData)` for
  settling batches of orders.
- `_refundOrders` for both `OnchainCrossChainOrder` and `GaslessCrossChainOrder` types, enabling the implementation of
  specific refund logic.
- `_localDomain()` to retrieve the local domain identifier.
- `_getOrderId` for computing unique identifiers for both `GaslessCrossChainOrder` and `OnchainCrossChainOrder` types.

These functions ensure that each inheriting contract provides its specific behavior while maintaining a consistent
interface across the framework. You'll find more details of this function interfaces documented on the
[Base7683](./src/Base7683.sol).

As reference, the following contracts build upon `Base7683`:

1. [BasicSwap7683](./src/BasicSwap7683.sol) The `BasicSwap7683` contract extends `Base7683` by implementing logic for a
   specific `orderData` type as defined in the [OrderEncoder](./src/libs/OrderEncoder.sol). This implementation
   facilitates token swaps, enabling the exchange of an `inputToken` on the origin chain for an `outputToken` on the
   destination chain.

2. [Hyperlane7683](./src/Hyperlane7683.sol) The `Hyperlane7683` contract builds on `BasicSwap7683` by integrating
   `Hyperlane` as the interchain messaging layer. This layer ensures seamless communication between chains during order
   execution.

## Extensibility

Both `BasicSwap7683` and `Hyperlane7683` are designed to be modular and extensible. Developers can use them as reference
implementations to create custom solutions. For example:

- To implement a different `orderData` type, you could replace `BasicSwap7683` with a new contract that inherits from
  `Base7683`. The `Hyperlane7683` contract can remain unchanged and continue to provide messaging functionality.
- Alternatively, you could replace the Hyperlane-based messaging layer in `Hyperlane7683` with another interchain
  messaging protocol while retaining the `BasicSwap7683` logic.

This modular approach enables a high degree of flexibility, allowing developers to adapt the framework to various use
cases and requirements.

## Deployment Addresses

| Blockchain | Proxy | Implementation |
| ---------- | ----- | -------------- |
| Mainnet    | [`0x5F69f9aeEB44e713fBFBeb136d712b22ce49eb88`](https://etherscan.io/address/0x5F69f9aeEB44e713fBFBeb136d712b22ce49eb88) | [`0xF84c1bf6dC94f9DBdef81E61e974A6a8888263F9`](https://etherscan.io/address/0xF84c1bf6dC94f9DBdef81E61e974A6a8888263F9)  |
| Optimism   | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://optimistic.etherscan.io/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://optimistic.etherscan.io/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Arbitrum   | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://arbiscan.io/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://arbiscan.io/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Base       | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://basescan.org/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://basescan.org/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Gnosis     | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://gnosisscan.io/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://gnosisscan.io/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Berachain  | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://berascan.com/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://berascan.com/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Form       | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://explorer.form.network/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://explorer.form.network/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Unichain   | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://uniscan.xyz/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://uniscan.xyz/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |
| Artela     | [`0x9245A985d2055CeA7576B293Da8649bb6C5af9D0`](https://artscan.artela.network/address/0x9245A985d2055CeA7576B293Da8649bb6C5af9D0) | [`0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc`](https://artscan.artela.network/address/0x8f9508C68ED70A7A02A4f8190604a81Ca8D79BEc) |


## Scripts

### Deploy

- Run `npm install` from the root of the monorepo to install all the dependencies
- Create a `.env` file base on the [.env.example file](./.env.example) file, and set the required variables depending
  which script you are going to run.

Set the following environment variables required for running all the scripts, on each network.

- `NETWORK`: the name of the network you want to run the script
- `ETHERSCAN_API_KEY`: your Etherscan API key
- `API_KEY_ALCHEMY`: your Alchemy API key

If the network is not listed under the `rpc_endpoints` section of the [foundry.toml file](./foundry.toml) you'll have to
add a new entry for it.

For deploying the router you have to run the `yarn run:deployHyperlane7683`. Make sure the following environment
variable are set:

- `DEPLOYER_PK`: deployer private key
- `MAILBOX`: address of Hyperlane Mailbox contract on the chain
- `PERMIT2`: Permit2 address on `NETWORK_NAME`
- `ROUTER_OWNER`: address of the router owner
- `PROXY_ADMIN_OWNER`: address of the ProxyAdmin owner, `ROUTER_OWNER` would be used if this is not set. The router is
  deployed using a `TransparentUpgradeableProxy`, so a ProxyAdmin contract is deployed and set as the admin of the
  proxy.
- `HYPERLANE7683_SALT`: a single use by chain salt for deploying the the router. Make sure you use the same on all
  chains so the routers are deployed all under the same address.
- `DOMAINS`: the domains list of the routers to enroll, separated by commas

### Open an Order

For opening an onchain order you can run `yarn run:openOrder`. Make sure the following environment variable are set:

- `ROUTER_OWNER_PK`: the router's owner private key. Only the owner can enroll routers
- `ORDER_SENDER`: address of order sender
- `ORDER_RECIPIENT`: address of order recipient
- `ITT_INPUT`: token input address
- `ITT_OUTPUT`: token output address
- `AMOUNT_IN`: amount in
- `AMOUNT_OUT`: amount out
- `DESTINATION_DOMAIN`: destination domain id

### Refund Order

For refunding an expired order you can run `yarn run:refundOrder`. Make sure the following environment variable are set:

- `NETWORK`: the name of the network you want to run the script, it should be the destination network of your order
- `USER_PK`: the private key to use for executing the tx, the address should own some gas to pay for the Hyperlane message
- `ORDER_ORIGIN`: the chain id of the order's origin chain
- `ORDER_FILL_DEADLINE`: the `fillDeadline` used when opening the order
- `ORDER_DATA`: the `orderData` used when opening the order

you can find the `fillDeadline` and `orderData` inspecting the open transaction on etherscan

---

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ yarn build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ yarn clean
```

### Coverage

Get a test coverage report:

```sh
$ yarn coverage
```

### Format

Format the contracts:

```sh
$ yarn sol:fmt
```

### Gas Usage

### Lint

Lint the contracts:

```sh
$ yarn lint
```

### Test

Run the tests:

```sh
$ yarn test
```

Generate test coverage and output result to the terminal:

```sh
$ yarn test:coverage
```

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ yarn test:coverage:report
```
