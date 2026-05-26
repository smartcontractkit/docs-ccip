// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint64 chainSelector;
        address router;
        address link;
        address ccipBnM;
        address usdc;
        uint256 confirmations;
        string chainName;
        string chainNameIdentifier;
        string explorerUrl;
        string nativeCurrencySymbol;
    }

    // CCIP Explorer
    string public constant CCIP_EXPLORER_BASE_URL = "https://ccip.chain.link/#/side-drawer/msg/";

    // Chain IDs
    uint256 public constant ETHEREUM_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ZERO_G_TESTNET_CHAIN_ID = 16602;
    uint256 public constant PLUME_TESTNET_CHAIN_ID = 98867;
    uint256 public constant INK_SEPOLIA_CHAIN_ID = 763373;
    uint256 public constant MANTLE_SEPOLIA_CHAIN_ID = 5003;

    // Deployed contract addresses
    mapping(uint256 => address payable) public deployedContracts;

    constructor() {
        // Initialize deployed contracts from environment variables
        _initializeDeployedContract(ETHEREUM_SEPOLIA_CHAIN_ID);
        _initializeDeployedContract(ZERO_G_TESTNET_CHAIN_ID);
        _initializeDeployedContract(PLUME_TESTNET_CHAIN_ID);
        _initializeDeployedContract(INK_SEPOLIA_CHAIN_ID);
        _initializeDeployedContract(MANTLE_SEPOLIA_CHAIN_ID);
    }

    /// @dev Helper to initialize deployed contract address from environment variable
    function _initializeDeployedContract(uint256 chainId) private {
        string memory envVarName = string.concat(getNetworkConfig(chainId).chainNameIdentifier, "_CONTRACT");
        deployedContracts[chainId] = payable(vm.envOr(envVarName, address(0)));
    }

    function getEthereumSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethereumSepoliaConfig = NetworkConfig({
            chainSelector: 16015286601757825753,
            router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            ccipBnM: 0x9a97F119cFE1D5Ea77c264441C0A0aBC9B34E119,
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            confirmations: 2,
            chainName: "Ethereum Sepolia",
            chainNameIdentifier: "ETHEREUM_SEPOLIA",
            explorerUrl: "https://sepolia.etherscan.io",
            nativeCurrencySymbol: "ETH"
        });
        return ethereumSepoliaConfig;
    }

    function getZeroGTestnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory zeroGTestnetConfig = NetworkConfig({
            chainSelector: 6892437333620424805,
            router: 0xD610B8f58689de7755947C05342A2DFaC30ebD57,
            link: 0xe5e3a4fF1773d043a387b16Ceb3c91cC49bAFD54,
            ccipBnM: 0xDbB255D37BC7c9e2b08e5a1C9f9506c9E85F1644,
            usdc: 0x0000000000000000000000000000000000000000,
            confirmations: 2,
            chainName: "0g Galileo Testnet",
            chainNameIdentifier: "ZERO_G_TESTNET",
            explorerUrl: "https://chainscan-galileo.0g",
            nativeCurrencySymbol: "OG"
        });
        return zeroGTestnetConfig;
    }

    function getPlumeTestnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory plumeTestnetConfig = NetworkConfig({
            chainSelector: 13874588925447303949,
            router: 0x5e5Fd4720E1CE826138D043aF578D69f48af502F,
            link: 0xB97e3665AEAF96BDD6b300B2e0C93C662104A068,
            ccipBnM: 0x225fAc4130595d1C7dabbE61A8bA9B051440b76c,
            usdc: 0xcB5f30e335672893c7eb944B374c196392C19D18,
            confirmations: 2,
            chainName: "Plume Testnet",
            chainNameIdentifier: "PLUME_TESTNET",
            explorerUrl: "https://testnet-explorer.plume.org",
            nativeCurrencySymbol: "PLUME"
        });
        return plumeTestnetConfig;
    }

    function getInkSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory inkSepoliaConfig = NetworkConfig({
            chainSelector: 9763904284804119144,
            router: 0x17fCda531D8E43B4e2a2A2492FBcd4507a1685A1,
            link: 0x3423C922911956b1Ccbc2b5d4f38216a6f4299b4,
            ccipBnM: 0x414dbe1d58dd9BA7C84f7Fc0e4f82bc858675d37,
            usdc: 0xFabab97dCE620294D2B0b0e46C68964e326300Ac,
            confirmations: 2,
            chainName: "Ink Sepolia",
            chainNameIdentifier: "INK_SEPOLIA",
            explorerUrl: "https://explorer-sepolia.inkonchain.com",
            nativeCurrencySymbol: "INK"
        });
        return inkSepoliaConfig;
    }

    function getMantleSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory mantleSepoliaConfig = NetworkConfig({
            chainSelector: 8236463271206331221,
            router: 0xFd33fd627017fEf041445FC19a2B6521C9778f86,
            link: 0x22bdEdEa0beBdD7CfFC95bA53826E55afFE9DE04,
            ccipBnM: 0xBB370F829bdB6fC44f3D34e2A2107578bB2c3F0B,
            usdc: 0x0000000000000000000000000000000000000000,
            confirmations: 2,
            chainName: "Mantle Sepolia",
            chainNameIdentifier: "MANTLE_SEPOLIA",
            explorerUrl: "https://sepolia.mantlescan.xyz",
            nativeCurrencySymbol: "MNT"
        });
        return mantleSepoliaConfig;
    }

    function getNetworkConfig(uint256 chainId) public pure returns (NetworkConfig memory) {
        if (chainId == ETHEREUM_SEPOLIA_CHAIN_ID) {
            return getEthereumSepoliaConfig();
        } else if (chainId == ZERO_G_TESTNET_CHAIN_ID) {
            return getZeroGTestnetConfig();
        } else if (chainId == PLUME_TESTNET_CHAIN_ID) {
            return getPlumeTestnetConfig();
        } else if (chainId == INK_SEPOLIA_CHAIN_ID) {
            return getInkSepoliaConfig();
        } else if (chainId == MANTLE_SEPOLIA_CHAIN_ID) {
            return getMantleSepoliaConfig();
        } else {
            revert("Unsupported chain ID");
        }
    }

    function getDeployedContract(uint256 chainId) public view returns (address payable) {
        return deployedContracts[chainId];
    }

    function parseChainName(string memory chainName) public pure returns (uint256) {
        bytes32 nameHash = keccak256(abi.encodePacked(chainName));

        if (nameHash == keccak256(abi.encodePacked(getEthereumSepoliaConfig().chainNameIdentifier))) {
            return ETHEREUM_SEPOLIA_CHAIN_ID;
        }
        if (nameHash == keccak256(abi.encodePacked(getZeroGTestnetConfig().chainNameIdentifier))) {
            return ZERO_G_TESTNET_CHAIN_ID;
        }
        if (nameHash == keccak256(abi.encodePacked(getPlumeTestnetConfig().chainNameIdentifier))) {
            return PLUME_TESTNET_CHAIN_ID;
        }
        if (nameHash == keccak256(abi.encodePacked(getInkSepoliaConfig().chainNameIdentifier))) {
            return INK_SEPOLIA_CHAIN_ID;
        }
        if (nameHash == keccak256(abi.encodePacked(getMantleSepoliaConfig().chainNameIdentifier))) {
            return MANTLE_SEPOLIA_CHAIN_ID;
        }
        revert("Invalid chain name");
    }

    function getChainName(uint256 chainId) public pure returns (string memory) {
        return getNetworkConfig(chainId).chainName;
    }

    function getNativeCurrencySymbol(uint256 chainId) public pure returns (string memory) {
        return getNetworkConfig(chainId).nativeCurrencySymbol;
    }

    function getExplorerUrl(uint256 chainId, string memory pathType, address contractAddress)
        public
        pure
        returns (string memory)
    {
        return string.concat(getNetworkConfig(chainId).explorerUrl, pathType, vm.toString(contractAddress));
    }

    function getCCIPExplorerUrl(bytes32 messageId) public pure returns (string memory) {
        return string(abi.encodePacked(CCIP_EXPLORER_BASE_URL, vm.toString(messageId)));
    }
}
