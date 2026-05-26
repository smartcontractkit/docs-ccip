import { createPublicClient, createWalletClient, http, type Chain, type Address, type PublicClient, type WalletClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";

export const CCIP_EXPLORER_BASE_URL =
  "https://ccip.chain.link/#/side-drawer/msg/";

export const npmFilesToBuild = [
  "@openzeppelin/contracts/token/ERC20/IERC20.sol",
  "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol",
  "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiverV2.sol",
];

// Network configuration data (matching Foundry's HelperConfig.s.sol structure)
// chainNameIdentifier is automatically set from the object key
const rawConfigData = {
  ETHEREUM_SEPOLIA: {
    chainId: 11155111,
    chainSelector: "16015286601757825753",
    router: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
    link: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
    usdc: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
    ccipBnM: "0x9a97f119cfe1d5ea77c264441c0a0abc9b34e119",
    confirmations: 2,
    chainName: "Ethereum Sepolia",
    explorerUrl: "https://sepolia.etherscan.io",
    nativeCurrencySymbol: "ETH",
  },
  ZERO_G_TESTNET: {
    chainId: 16602,
    chainSelector: "6892437333620424805",
    router: "0xD610B8f58689de7755947C05342A2DFaC30ebD57",
    link: "0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54",
    ccipBnM: "0xDbB255D37BC7c9e2b08e5a1C9f9506c9E85F1644",
    usdc: "0x0000000000000000000000000000000000000000",
    confirmations: 2,
    chainName: "0g Galileo Testnet",
    explorerUrl: "https://chainscan-galileo.0g",
    nativeCurrencySymbol: "OG",
  },
  PLUME_TESTNET: {
    chainId: 98867,
    chainSelector: "13874588925447303949",
    router: "0x5e5Fd4720E1CE826138D043aF578D69f48af502F",
    link: "0xB97e3665AEAF96BDD6b300B2e0C93C662104A068",
    ccipBnM: "0x225fAc4130595d1C7dabbE61A8bA9B051440b76c",
    usdc: "0xcB5f30e335672893c7eb944B374c196392C19D18",
    confirmations: 2,
    chainName: "Plume Testnet",
    explorerUrl: "https://testnet-explorer.plume.org",
    nativeCurrencySymbol: "PLUME",
  },
  INK_SEPOLIA: {
    chainId: 763373,
    chainSelector: "9763904284804119144",
    router: "0x17fCda531D8E43B4e2a2A2492FBcd4507a1685A1",
    link: "0x3423C922911956b1Ccbc2b5d4f38216a6f4299b4",
    ccipBnM: "0x414dbe1d58dd9BA7C84f7Fc0e4f82bc858675d37",
    usdc: "0xFabab97dCE620294D2B0b0e46C68964e326300Ac",
    confirmations: 2,
    chainName: "Ink Sepolia",
    explorerUrl: "https://explorer-sepolia.inkonchain.com",
    nativeCurrencySymbol: "INK",
  },
  MANTLE_SEPOLIA: {
    chainId: 5003,
    chainSelector: "8236463271206331221",
    router: "0xFd33fd627017fEf041445FC19a2B6521C9778f86",
    link: "0x22bdEdEa0beBdD7CfFC95bA53826E55afFE9DE04",
    ccipBnM: "0xBB370F829bdB6fC44f3D34e2A2107578bB2c3F0B",
    usdc: "0x0000000000000000000000000000000000000000",
    confirmations: 2,
    chainName: "Mantle Sepolia",
    explorerUrl: "https://sepolia.mantlescan.xyz",
    nativeCurrencySymbol: "MNT",
  },
} as const;

// Automatically add chainNameIdentifier from the object key
export const configData: Record<string, {
  chainId: number;
  chainSelector: string;
  router: string;
  link: string;
  ccipBnM: string;
  usdc: string;
  confirmations: number;
  chainName: string;
  chainNameIdentifier: string;
  explorerUrl: string;
  nativeCurrencySymbol: string;
}> = Object.fromEntries(
  Object.entries(rawConfigData).map(([key, config]) => [
    key,
    { ...config, chainNameIdentifier: key }
  ])
) as any;

export interface NetworkConfig {
  chainId: number;
  chainSelector: string;
  router: Address;
  link: Address;
  ccipBnM: Address;
  usdc: Address;
  confirmations: number;
  chainName: string;
  explorerUrl: string;
  nativeCurrencySymbol: string;
}

export function getNetworkConfig(chainName: string): NetworkConfig {
  const config = configData[chainName];
  if (!config) {
    throw new Error(`Network ${chainName} not found in config`);
  }

  return {
    chainId: config.chainId,
    chainSelector: config.chainSelector,
    router: config.router as Address,
    link: config.link as Address,
    ccipBnM: config.ccipBnM as Address,
    usdc: config.usdc as Address,
    confirmations: config.confirmations,
    chainName: config.chainName,
    explorerUrl: config.explorerUrl,
    nativeCurrencySymbol: config.nativeCurrencySymbol,
  };
}

export async function getClients(chainName: string): Promise<{
  publicClient: PublicClient;
  walletClient: WalletClient;
  account: ReturnType<typeof privateKeyToAccount>;
  chain: Chain;
}> {
  // Dynamic import to avoid circular dependency with hardhat.config.ts
  const { config } = await import("hardhat");

  const chainConfig = configData[chainName];
  if (!chainConfig) {
    throw new Error(`Network ${chainName} not found in config`);
  }

  const hardhatNetworkName = chainName.toLowerCase().replace(/_/g, '');

  const networkConfig = config.networks[hardhatNetworkName];
  if (!networkConfig || networkConfig.type !== "http") {
    throw new Error(
      `Network "${hardhatNetworkName}" not found in Hardhat config or not an HTTP network`
    );
  }

  // Read RPC URL from Hardhat's resolved config (keystore / env var)
  const rpcUrl = await networkConfig.url.getUrl();

  // Read private key from Hardhat's resolved config (keystore / env var)
  const { accounts } = networkConfig;
  if (!Array.isArray(accounts) || accounts.length === 0) {
    throw new Error(
      `No accounts configured for network "${hardhatNetworkName}". ` +
      `Create a Hardhat keystore entry and set KEYSTORE_NAME to that entry name in your .env file.`
    );
  }
  const privateKey = await accounts[0].getHexString();

  const account = privateKeyToAccount(privateKey as `0x${string}`);

  const chain: Chain = {
    id: chainConfig.chainId,
    name: chainName,
    nativeCurrency: {
      name: chainConfig.nativeCurrencySymbol,
      symbol: chainConfig.nativeCurrencySymbol,
      decimals: 18,
    },
    rpcUrls: {
      default: { http: [rpcUrl] },
      public: { http: [rpcUrl] },
    },
  };

  const publicClient = createPublicClient({
    chain,
    transport: http(rpcUrl),
  }) as PublicClient;

  const walletClient = createWalletClient({
    chain,
    transport: http(rpcUrl),
    account,
  }) as WalletClient;

  return { publicClient, walletClient, account, chain };
}

export function getEnvVar(name: string, required: boolean = true): string {
  const value = process.env[name];
  if (!value && required) {
    throw new Error(`Environment variable ${name} not set`);
  }
  return value || "";
}


export function getDeployedContract(chainName: string): Address {
  const config = configData[chainName];
  if (!config) {
    throw new Error(`Network ${chainName} not found in config`);
  }
  const envVarName = `${config.chainNameIdentifier}_CONTRACT`;
  const address = getEnvVar(envVarName, true);
  return address as Address;
}

export function getUSDCAddress(chainName: string): Address {
  const config = configData[chainName];
  if (!config) {
    throw new Error(`Network ${chainName} not found in config`);
  }
  if (!config.usdc) {
    throw new Error(`USDC address not configured for network ${chainName}`);
  }
  return config.usdc as Address;
}

export function getExplorerUrl(chainName: string, path: string, address: string): string {
  const config = configData[chainName];
  if (!config) {
    throw new Error(`Network ${chainName} not found in config`);
  }
  return `${config.explorerUrl}${path}${address}`;
}

export function getCCIPExplorerUrl(messageId: string): string {
  return `${CCIP_EXPLORER_BASE_URL}${messageId}`;
}
