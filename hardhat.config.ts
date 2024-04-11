import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-waffle"; // Plugin for testing
import "@nomiclabs/hardhat-ethers"; // Plugin for interacting with contracts
import "hardhat-typechain"; // Plugin for generating TypeScript bindings for contracts

const config: HardhatUserConfig & { typechain: any } = {
  solidity: "0.8.24",
  networks: {
    // Define your network configurations here (e.g., local, testnet, mainnet)
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
