# Solver Directory Overview

The solver directory contains the implementation of the Intent Solver, a TypeScript application designed to listen to blockchain events and process intents accordingly. This application plays a crucial role in handling events from different sources and executing the necessary actions based on those events.

## Table of Contents

- Directory Structure
- Installation
- Usage
- Adding a New Solver

## Directory Structure

```
solver/
├── index.ts
├── logger.ts
├── NonceKeeperWallet.ts
├── patch-bigint-buffer-warn.js
├── test/
├── config/
│  ├── index.ts
│  ├── allowBlockLists.ts
│  ├── chainMetadata.ts
│  └── types.ts
└── solvers/
    ├── index.ts
    ├── BaseFiller.ts
    ├── BaseListener.ts
    ├── types.ts
    ├── utils.ts
    ├── contracts/
    └── <eco|hyperlane7683>/
        ├── index.ts
        ├── listener.ts
        ├── filler.ts
        ├── types.ts
        ├── utils.ts
        ├── contracts/
        └── config/
            ├── index.ts
            ├── metadata.ts
            └── allowBlockLists.ts
```

### Description of Key Files and Directories

- **solver/index.ts**: The main entry point of the solver application. It initializes and starts the listeners and fillers for different solvers.

- **logger.ts**: Contains the Logger class used for logging messages with various formats and levels.

- **NonceKeeperWallet.ts**: A class that extends ethers Wallet and prevents nonces race conditions when the solver needs to fill different intents (from different solutions) in the same network.

- **patch-bigint-buffer-warn.js**: A script to suppress specific warnings related to BigInt and Buffer, ensuring cleaner console output.

- **solvers/**: Contains implementations of different solvers and common utilities.
  - **BaseListener.ts**: An abstract base class that provides common functionality for event listeners. It handles setting up contract connections and defines the interface for parsing event arguments.
  - **BaseFiller.ts**: An abstract base class that provides common functionality for fillers. It handles the solver's lifecycle `prepareIntent`, `fill`, and `settle`.
    - **`prepareIntent`**: evaluate allow/block lists, balances, and run the defined rules to decide wether to fill or not an intent.
    - **`fill`**: The actual filling.
    - **`settle`**: The settlement step, can be avoided.
  - **<eco|hyperlane7683>/**: Implements the solvers for the ECO and Hyperlane7683 domains.
    - **listener.ts**: Extends `BaseListener` to handle domain-specific events.
    - **filler.ts**: Extends `BaseFiller` to handle domain-specific intents.
    - **contracts/**: Contains contract ABI and type definitions for interacting with domain-specific contracts.
  - **index.ts**: Exports the solvers to be used in the main application.

## Installation

### Prerequisites

- [Node.js](https://nodejs.org/) (version compatible with your project's requirements)
- [Yarn](https://yarnpkg.com/)

### Steps

1. Navigate to the solver directory:

   ```sh
   cd typescript/solver
   ```

2. Install the dependencies:

   ```sh
   yarn install
   ```

3. Build the project:

   ```sh
   yarn build
   ```

## Usage

### Running the Solver Application

To start the solver application, execute:

```sh
yarn solver
```

This will run the compiled JavaScript code from the `dist` directory, starting all the listeners defined in index.ts.

### Development Mode

For development, you can run the application in watch mode to automatically restart on code changes:

```sh
yarn dev
```

### Intent filtering

Configure which intent to fill , and which to ignore

By default, the solver will attempt to fill intents sent from its origin chain to any destination chains.

Solvers may want to further filter the intents they attempt to fill. For example, fill intents coaming from a specific address or going to a subset of chains.

In order to do this, you can configure a block-list or a allow-list at a global level within the [allowBlockList.ts file](./config/allowBlockLists.ts) or at a specific solver level like e.g. [solvers/eco/config/allowBlockList.ts file](./solvers/eco/config/allowBlockLists.ts).

Such configs should be written in the `allowBlockLists` variable

```typescript
const allowBlockLists: AllowBlockLists = {
  allowList: [],
  blockList: [],
};
```

as object of the following format:

```typescript
type Wildcard = "*";

type AllowBlockListItem = {
   senderAddress: string | string[] | Wildcard
   destinationDomain: string | string[] | Wildcard
   recipientAddress: string | string[] | Wildcard
}

type AllowBlockLists = {
   allowList: AllowBlockListItem[]
   blockList: AllowBlockListItem[]
}
```

Both the allow-list and block-lists have "any" semantics. In other words, the Solver will deliver intents that match any of the allow-list filters, and ignore intents that match any of the block-list filters.

The clock-list supersedes the allow-list, i.e. if a message matches both the allow-list and the block-list, it will not be delivered.

### Logging

The application utilizes a custom Logger class for logging. You can adjust the log level and format by modifying the Logger instantiation in index.ts. By default it will log to `stdout` in a human-readable format using the `INFO` level.

You can customize the logging destination by using a pino transport of your choosing. There's an example for logging to a Syslog server running on `localhost` commented in [logger.ts](logger.ts). Check out the [pino transports docs](https://github.com/pinojs/pino/blob/main/docs/transports.md) for other available transports.

## Adding a New Solver

To integrate a new solver into the application, follow these steps:

1. **Create a New Solver Directory**: Inside solvers/, create a new directory for your solver:

   ```
   solvers/
   └── yourSolver/
       ├── listener.ts
       ├── filler.ts
       └── contracts/
           └── YourContract.json
   ```

2. **Implement the Listener**: In listener.ts, extend the `BaseListener` class and implement the required methods to handle your specific event.

3. **Implement the Filler**: In filler.ts, extend the `BaseFiller` class and implement the required logic to process events captured by your listener.

4. **Add Contract Definitions**: Place your contract ABI and type definitions in the `contracts/` directory.

5. **Generate Types from Contract Definitions**: Run the following command:

  ```sh
  yarn contracts:typegen
  ```

6. **Update the Index**: Export your new solver in index.ts:

   ```typescript
   export * as yourSolver from "./yourSolver/index.js";
   ```

7. **Initialize in Main Application**: In index.ts, import and initialize your solver:

   ```typescript
   import * as solvers from './solvers/index.js';

   // ... existing code ...

   const yourSolverListener = solvers['yourSolver'].listener.create();
   const yourSolverFiller = solvers['yourSolver'].filler.create(multiProvider);

   yourSolverListener(yourSolverFiller);
   ```
