// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants{
    /* VRF Mock Values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // Base fee for the VRF mock
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; // Gas price for the VRF mock
    // LINK / ETH price in wei
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15; // 0.004 LINK per wei

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111; // Sepolia Testnet Chain ID
    uint256 public constant LOCAL_CHAIN_ID = 31337; // Local Chain ID
}

contract HelperConfig is CodeConstants,Script{
    error HelperConfig__InvalidChainId();

    // This contract is a placeholder for the HelperConfig contract
    // It can be used to store configuration data for the Raffle contract
    // such as entrance fee, interval, key hash, subscription ID, and callback gas limit.

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link; // LINK token address, if needed
        address account; // Account address, if needed
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        // Initialize the local network configuration
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig(); // Sepolia Testnet
    }

    function getConfigByChainId(uint256 chainId) public returns(NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }

    }

    function getConfig() public returns(NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    } 

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B, // With actual VRF Coordinator address
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // Replace with actual gas lane key hash
            callbackGasLimit: 500000, // 500k gas limit for the callback function
            subscriptionId: 107619426351958819046237450084643758260490638633942570858061043000512121414146, // Our function will create a subscription for us if we don't already have one
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // LINK token address on Sepolia
            account: 0x588aBBd15eA5aA3862cfF146Eb821bcfd806025B
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we set an active network conifg
        // This function can be used to create or retrieve the Anvil local network configuration
        // For now, we will return a dummy configuration
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        // Deploy mocks and such
        vm.startBroadcast();

        VRFCoordinatorV2_5Mock vrfCoordinator = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);
        
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: address(vrfCoordinator), // Address of the VRF Coordinator mock
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // Replace with actual gas lane key hash
            callbackGasLimit: 500000, // 500k gas limit for the callback function
            subscriptionId: 0, // Our function will create a subscription for us if we don't already have one
            link: address(linkToken), // LINK token address on the local network
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        });
        return localNetworkConfig;
    }
}