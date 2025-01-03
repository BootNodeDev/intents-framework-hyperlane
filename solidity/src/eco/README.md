# Eco Adapter

The Eco solver need to use and intermediary contract, [`EcoAdapter`](./src/eco/EcoAdapter.sol) when calling the
`Inbox.fulfillHyperInstant` in order to approve the token that are transferred to the Inbox and fill the intent in a
single tx to prevent the token being used by other solver. This is due the the way Eco created the intents which
requires the token to be deposited on the Inbox before filling the intent where such tokens are transferred from Inbox
to the `receiver` of the intent.

### Deploying an EcoAdapter and create an intent

- Run `npm install` from the root of the monorepo to install all the dependencies
- Create a `.env` file base on the [.env.example file](./.env.example) file, and set the required variables depending
  which script you are going to run.

Set the following environment variables required for running all the scripts, on each network.

- `NETWORK`: the name of the network you want to run the script
- `ETHERSCAN_API_KEY`: your Etherscan API key
- `API_KEY_ALCHEMY`: your Alchemy API key

#### Deploying the adapter

Set following variables:

- `ADAPTER_OWNER`: address of the owner of the adapter, probably the address of the solver
- `ECO_INBOX`: address of the Eco Inbox in the network

then run `yarn run:deployEcoAdapter`

#### Creating an Eco intent

Set the following variables:

- `ECO_INTENT_SOURCE`: Eco IntentSource contract address
- `ECO_DESTINATION_CHAIN`: destination chain id
- `ECO_INBOX`: Eco Inbox address on destination chain
- `ECO_TARGET_TOKEN`: target token on destination chain
- `ECO_RECEIVER_ADDRESS`: intent receiver address
- `ECO_RECEIVER_AMOUNT`: intent target token amount
- `ECO_REWARD_TOKENS`: reward tokens address separated by coma, tokens being paid to the solver of the intent
- `ECO_RECEIVER_AMOUNT`: reward tokens amount separated by coma
- `ECO_PROVER`: address of the prover in the local chain

then run `yarn run:createEcoIntent`
