import { type CompactMetadata, CompactMetadataSchema } from "../types.js";

const metadata: CompactMetadata = {
  protocolName: "The Compact",
  arbiters: [
    {
      address: "0x088470910056221862d18fF2e65ffaeC96ec6dA4",
      chainName: "ethereum"
    },
    {
      address: "0x57F0638d4fba79DB978c4eE1B73d469ea21014b2",
      chainName: "optimism"
    },
    {
      address: "0x43b60b47764B6460c96349A1B414214BBa7F22c9",
      chainName: "base"
    }
  ]
};

CompactMetadataSchema.parse(metadata);

export default metadata;
