import {
  type Hyperlane7683Metadata,
  Hyperlane7683MetadataSchema,
} from "../types.js";

const metadata: Hyperlane7683Metadata = {
  protocolName: "Hyperlane7683",
  originSettlers: [
    // mainnet
    {
      address: "0x5F69f9aeEB44e713fBFBeb136d712b22ce49eb88",
      chainName: "ethereum",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "optimism",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "arbitrum",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "base",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "gnosis",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "berachain",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "form",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "unichain",
    },
    {
      address: "0x9245A985d2055CeA7576B293Da8649bb6C5af9D0",
      chainName: "artela",
    },

    // testnet
    // {
    //   address: "0x6d2175B89315A9EB6c7eA71fDE54Ac0f294aDC34",
    //   chainName: "optimismsepolia",
    // },
    // {
    //   address: "0x6d2175B89315A9EB6c7eA71fDE54Ac0f294aDC34",
    //   chainName: "arbitrumsepolia",
    // },
    // {
    //   address: "0x6d2175B89315A9EB6c7eA71fDE54Ac0f294aDC34",
    //   chainName: "sepolia",
    // },
    // {
    //   address: "0x6d2175B89315A9EB6c7eA71fDE54Ac0f294aDC34",
    //   chainName: "basesepolia",
    // },
    // {
    //   address: "0x6d2175B89315A9EB6c7eA71fDE54Ac0f294aDC34",
    //   chainName: "basesepolia",
    //   initialBlock: 21491220,
    //   pollInterval: 1000,
    //   confirmationBlocks: 2,
    // },
  ],
};

Hyperlane7683MetadataSchema.parse(metadata);

export default metadata;
