import { type WarpCoreConfig } from '@hyperlane-xyz/sdk';

const ROUTER = '0x9245A985d2055CeA7576B293Da8649bb6C5af9D0';
const ROUTER_MAINNET = '0x5F69f9aeEB44e713fBFBeb136d712b22ce49eb88';
const USDC_MAINNET = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const USDC_OP = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85";
const USDC_ARB = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const USDC_BERA = "0x549943e04f40284185054145c6E4e9568C1D3241";
const USDC_FORM = "0xFBf489bb4783D4B1B2e7D07ba39873Fb8068507D";

// A list of Warp Route token configs
// These configs will be merged with the warp routes in the configured registry
// The input here is typically the output of the Hyperlane CLI warp deploy command
export const warpRouteConfigs: WarpCoreConfig = {
  tokens: [
    {
      addressOrDenom: USDC_MAINNET,
      chainName: 'ethereum',
      collateralAddressOrDenom: ROUTER_MAINNET,
      connections: [
        {token: 'ethereum|optimism|' + USDC_OP},
        {token: 'ethereum|arbitrum|' + USDC_ARB},
        {token: 'ethereum|base|' + USDC_BASE},
        {token: 'ethereum|berachain|' + USDC_BERA},
        {token: 'ethereum|form|' + USDC_FORM},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
    {
      addressOrDenom: USDC_OP,
      chainName: 'optimism',
      collateralAddressOrDenom: ROUTER,
      connections: [
        {token: 'ethereum|ethereum|' + USDC_MAINNET},
        {token: 'ethereum|arbitrum|' + USDC_ARB},
        {token: 'ethereum|base|' + USDC_BASE},
        {token: 'ethereum|berachain|' + USDC_BERA},
        {token: 'ethereum|form|' + USDC_FORM},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
    {
      addressOrDenom: USDC_ARB,
      chainName: 'arbitrum',
      collateralAddressOrDenom: ROUTER,
      connections: [
        {token: 'ethereum|ethereum|' + USDC_MAINNET},
        {token: 'ethereum|optimism|' + USDC_OP},
        {token: 'ethereum|base|' + USDC_BASE},
        {token: 'ethereum|berachain|' + USDC_BERA},
        {token: 'ethereum|form|' + USDC_FORM},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
    {
      addressOrDenom: USDC_BASE,
      chainName: 'base',
      collateralAddressOrDenom: ROUTER,
      connections: [
        {token: 'ethereum|ethereum|' + USDC_MAINNET},
        {token: 'ethereum|optimism|' + USDC_OP},
        {token: 'ethereum|arbitrum|' + USDC_ARB},
        {token: 'ethereum|berachain|' + USDC_BERA},
        {token: 'ethereum|form|' + USDC_FORM},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
    {
      addressOrDenom: USDC_FORM,
      chainName: 'form',
      collateralAddressOrDenom: ROUTER,
      connections: [
        {token: 'ethereum|ethereum|' + USDC_MAINNET},
        {token: 'ethereum|optimism|' + USDC_OP},
        {token: 'ethereum|arbitrum|' + USDC_ARB},
        {token: 'ethereum|base|' + USDC_BASE},
        {token: 'ethereum|berachain|' + USDC_BERA},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
    {
      addressOrDenom: USDC_BERA,
      chainName: 'berachain',
      collateralAddressOrDenom: ROUTER,
      connections: [
        {token: 'ethereum|ethereum|' + USDC_MAINNET},
        {token: 'ethereum|optimism|' + USDC_OP},
        {token: 'ethereum|arbitrum|' + USDC_ARB},
        {token: 'ethereum|base|' + USDC_BASE},
        {token: 'ethereum|form|' + USDC_FORM},
      ],
      decimals: 6,
      logoURI: '/deployments/warp_routes/USDC/logo.svg',
      name: 'USDC',
      standard: 'Intent',
      symbol: 'USDC',
      protocol: 'ethereum',
    },
  ],

  // Mainnet Op Arb Base Bera Form
  options: {
    interchainFeeConstants: [
      // demo: amount == USDC in WEI
      {
        amount: 75e4,
        origin: 'optimism',
        destination: 'ethereum',
        addressOrDenom: USDC_OP,
      },
      {
        amount: 75e4,
        origin: 'arbitrum',
        destination: 'ethereum',
        addressOrDenom: USDC_ARB,
      },
      {
        amount: 75e4,
        origin: 'base',
        destination: 'ethereum',
        addressOrDenom: USDC_BASE,
      },
      {
        amount: 75e4,
        origin: 'berachain',
        destination: 'ethereum',
        addressOrDenom: USDC_BERA,
      },
      {
        amount: 75e4,
        origin: 'form',
        destination: 'ethereum',
        addressOrDenom: USDC_FORM,
      },
      {
        amount: 35e4,
        origin: 'ethereum',
        destination: 'optimism101010arbitrum101010base101010berachain101010form',
        addressOrDenom: USDC_MAINNET,
      },
      {
        amount: 5e4,
        origin: 'optimism',
        destination: 'arbitrum101010base101010berachain101010form',
        addressOrDenom: USDC_OP,
      },
      {
        amount: 5e4,
        origin: 'arbitrum',
        destination: 'optimism101010base101010berachain101010form',
        addressOrDenom: USDC_ARB,
      },
      {
        amount: 5e4,
        origin: 'base',
        destination: 'optimism101010arbitrum101010berachain101010form',
        addressOrDenom: USDC_BASE,
      },
      {
        amount: 5e4,
        origin: 'berachain',
        destination: 'optimism101010arbitrum101010base101010form',
        addressOrDenom: USDC_BERA,
      },
      {
        amount: 5e4,
        origin: 'form',
        destination: 'optimism101010arbitrum101010base101010berachain',
        addressOrDenom: USDC_FORM,
      }
    ]
  },
};
