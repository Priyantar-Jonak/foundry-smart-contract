// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator= helperConfig.getConfig().vrfCoordinator; // This will help create the subscription if it doesn't exist, by getting the vrfCoordinator address from the config
        (uint256 subId, )= createSubscription(vrfCoordinator);

        return (subId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator) public returns (uint256, address) {
        console.log("Creating subscription on ChainID: ", block.chainid);
        vm.startBroadcast();
        // Create a subscription using the vrfCoordinator address
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        // This is where you would call the VRFCoordinatorV2_5Mock.createSubscription() function
        // For example: VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        console.log("Subscription created with ID: ", subId);
        console.log("Please update the sunscription ID in HelperConfig.s.sol");
    
        return (subId, vrfCoordinator);
    }

    function run() public {
        createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script, CodeConstants {
    uint256 public constant FUND_AMOUNT = 3 ether; // 3 LINK // Amount to fund the subscription

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator; // This will help fund the subscription if it doesn't exist, by getting the vrfCoordinator address from the config
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId; // Get the subscription ID from the config
        address linkToken = helperConfig.getConfig().link; // Get the LINK token address from the config
        fundSubscription(vrfCoordinator, subscriptionId, linkToken);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken) public {
        console.log("Funding subscription on ChainID: ", block.chainid);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("Funding subscription with ID: ", subscriptionId);

        if(block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            // Fund the subscription using the vrfCoordinator address and subscription ID
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100); // Multiply by 100 to convert to pass 
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }
    }

    function run() public {
        fundSubscriptionUsingConfig();
    }

}

contract AddConsumer is Script {

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId; // Get the subscription ID from the config
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator; // This will help add consumers if it doesn't exist, by getting the vrfCoordinator address from the config
        
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subId);
    }

    function addConsumer(address contractToAddToVrf, address vrfCoordinator, uint256 subId) public {
        console.log("Adding consumer: ", contractToAddToVrf);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("Subscription ID: ", subId);

        vm.startBroadcast();
        // Add the consumer to the subscription using the vrfCoordinator address and subscription ID
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, contractToAddToVrf);
        vm.stopBroadcast();

        console.log("Consumer added successfully");
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid); // Get the most recently deployed Raffle contract address, wrap that and add it to the consumers array in the config
        addConsumerUsingConfig(mostRecentlyDeployed); 
    }

}