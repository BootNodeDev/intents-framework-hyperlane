# Intents Framework

## Description

The Intents Framework is a modular and interoperable system designed to interpret and execute user intents on any EVM-compatible blockchain. It leverages a combination of smart contracts, solvers, and an optional UI component to provide a comprehensive solution for decentralized intent management.

## Features

- **Modular Components**: Easily interchangeable modules including smart contracts, solvers, and UI components.
- **EIP-7683 Compliance**: Ensures compatibility and standardization across Ethereum blockchain.
- **Cross-Chain Functionality**: Facilitates operations across multiple blockchain platforms.

## Directory Structure

- `solidity/` - Contains the smart contract code written in Solidity.
- `typescript/solvers/` - Houses the TypeScript implementations of the solvers that execute the intents.

## Getting Started

### Prerequisites

- Node.js
- yarn
- Git

### Installation

```bash
git clone https://github.com/BootNodeDev/intents-framework.git
cd intents-framework
yarn
```

### Running the Solver

Run the following commands from the root directory (you need `docker` installed)

```bash
docker build -t solver .
```

Once it finish building the image

```bash
docker run -it -e [PRIVATE_KEY=SOME_PK_YOU_OWN | MNEMONIC=SOME_MNEMONIC_YOU_OWN] solver
```

The solver is run using `pm2` inside the docker container so `pm2` commands can still be used inside a container with the docker exec command:

```bash
# Monitoring CPU/Usage of each process
docker exec -it <container-id> pm2 monit
# Listing managed processes
docker exec -it <container-id> pm2 list
# Get more information about a process
docker exec -it <container-id> pm2 show
# 0sec downtime reload all applications
docker exec -it <container-id> pm2 reload all
```

### Versioning

For the versions available, see the tags on this repository.

### Releasing packages to NPM

We use [changesets](https://github.com/changesets/changesets) to release to NPM. You can use the `release` script in `package.json` to publish.

Currently the only workspace being released as an NPM package is the one in `solidity`, which contains the contracts and typechain artifacts.

### License

This project is licensed under the Apache 2.0 License - see the LICENSE.md file for details.
