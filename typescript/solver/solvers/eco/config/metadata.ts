import { type EcoMetadata, EcoMetadataSchema } from "../types.js";

const metadata: EcoMetadata = {
  protocolName: "Eco",
  intentSource: {
    address: "0x734a3d5a8D691d9b9,11674E682De5f06517c79ec",
    chainName: "optimismsepolia",
  },
  adapters: [
    {
      address: "0x218FB5210d4eE248f046F3EC8B5Dd1c7Bc0756e5",
      chainName: "basesepolia",
    },
  ],
};

EcoMetadataSchema.parse(metadata);

export default metadata;
