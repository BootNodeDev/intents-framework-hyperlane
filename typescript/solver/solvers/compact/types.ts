export type CompactMetadata = {
  solverName: string;
  arbiters: Array<{
    address: string;
    chainId: number;
    chainName?: string;
  }>;
};

export type Compact = {
  hash: string;
  claimChain: number;
  compact: {
    arbiter: string;
    sponsor: string;
    nonce: string;
    expires: string;
    id: string;
    amount: string;
  };
  intent: {
    token: string;
    amount: string;
    fee: string;
    chainId: number;
    recipient: string;
  };
  allocatorSignature: string;
  sponsorSignature: string;
  filled: boolean;
};
