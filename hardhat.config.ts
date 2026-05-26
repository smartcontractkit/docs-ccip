import { defineConfig, configVariable } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configData, npmFilesToBuild } from "./hardhat/scripts/helper-config";
import dotenv from "dotenv";
dotenv.config();

const networks: Record<string, any> = {};

for (const [name, config] of Object.entries(configData)) {
  const rpcVarName = `${config.chainNameIdentifier}_RPC_URL`;
  const networkName = name.toLowerCase().replace(/_/g, "");

  networks[networkName] = {
    type: "http" as const,
    chainId: config.chainId,
    url: configVariable(rpcVarName) ?? process.env[rpcVarName],
    accounts: [configVariable(process.env.KEYSTORE_NAME!)],
  };
}

export default defineConfig({
  plugins: [hardhatToolboxMochaEthers],
  solidity: {
    version: "0.8.24",
    npmFilesToBuild,
  },
  typechain: {
    outDir: "./typechain-types",
  },
  paths: {
    sources: "./contracts",
    tests: {
      mocha: "./hardhat/tests",
    },
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  networks,
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY || "UNSET",
      enabled: true,
    },
    blockscout: {
      enabled: false,
    },
  },
});
