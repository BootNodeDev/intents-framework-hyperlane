import {
  type Hyperlane7683Metadata,
  Hyperlane7683MetadataSchema,
} from "../types.js";

const metadata: Hyperlane7683Metadata = {
  protocolName: "Hyperlane7683",
  originSettler: {
    address: "0x376dc8E71A223Af488D885ce04A7021f32C2D1e0",
    chainName: "optimismsepolia",
  },
};

Hyperlane7683MetadataSchema.parse(metadata);

export default metadata;
