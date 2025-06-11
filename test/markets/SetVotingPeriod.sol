// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../BasicDeploy.sol";
import {console2} from "forge-std/console2.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
// Proposal parameters:
//   - Target: 0xD6BbDE9174b1CdAa358d2Cf4D57D1a9F7178FBfF
//   - Value: 0
//   - Calldata:
//   0xe540d01d0000000000000000000000000000000000000000000000000000000000001c20
//   - Description: Set voting period to 7200 blocks

contract SetVotingPeriodTest is BasicDeploy {
    uint256 constant NEW_VOTING_PERIOD = 7200; // 1 day in blocks

    function setUp() public {
        vm.warp(365 days);
        deployComplete();

        // Setup roles
        vm.startPrank(guardian);
        timelockInstance.revokeRole(PROPOSER_ROLE, ethereum);
        timelockInstance.revokeRole(EXECUTOR_ROLE, ethereum);
        timelockInstance.revokeRole(CANCELLER_ROLE, ethereum);
        timelockInstance.grantRole(PROPOSER_ROLE, address(govInstance));
        timelockInstance.grantRole(EXECUTOR_ROLE, address(govInstance));
        timelockInstance.grantRole(CANCELLER_ROLE, address(govInstance));
        vm.stopPrank();

        // TGE setup
        vm.prank(guardian);
        tokenInstance.initializeTGE(address(ecoInstance), address(treasuryInstance));

        // Guardian delegates to themselves
        vm.prank(guardian);
        tokenInstance.delegate(guardian);

        // Move forward to establish voting power
        vm.roll(365 days + 1);
    }

    function test_GenerateCalldataForSetVotingPeriod() public view {
        console2.log("\n=== GENERATING CALLDATA FOR setVotingPeriod ===");

        // Get the function selector
        bytes4 selector = govInstance.setVotingPeriod.selector;
        console2.log("Function selector for setVotingPeriod:");
        console2.logBytes4(selector);

        // Encode the full calldata
        bytes memory calldataBytes = abi.encodeWithSelector(selector, uint32(NEW_VOTING_PERIOD));

        console2.log("\nComplete calldata for setVotingPeriod(7200):");
        console2.logBytes(calldataBytes);
        console2.log("Calldata as hex string:");
        console2.log(vm.toString(calldataBytes));

        // Show the breakdown
        console2.log("\nBreakdown:");
        console2.log("- Selector: %s", vm.toString(abi.encodePacked(selector)));
        console2.log("- Parameter uint32(7200) encoded:");
        console2.log("  %s", vm.toString(abi.encode(uint32(NEW_VOTING_PERIOD))));
    }

    function test_GenerateProposalCalldata() public view {
        console2.log("\n=== GENERATING PROPOSAL CALLDATA ===");

        // Prepare proposal parameters
        address[] memory targets = new address[](1);
        targets[0] = address(govInstance);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(govInstance.setVotingPeriod.selector, uint32(NEW_VOTING_PERIOD));

        string memory description = "Set voting period to 7200 blocks";

        console2.log("Proposal parameters:");
        console2.log("- Target (governor): %s", targets[0]);
        console2.log("- Value: %s", values[0]);
        console2.log("- Calldata for setVotingPeriod(7200):");
        console2.logBytes(calldatas[0]);
        console2.log("  Hex: %s", vm.toString(calldatas[0]));
        console2.log("- Description: %s", description);

        // Generate propose calldata
        bytes memory proposeCalldata =
            abi.encodeWithSelector(govInstance.propose.selector, targets, values, calldatas, description);

        console2.log("\nComplete calldata for propose function:");
        console2.log("Length: %s bytes", proposeCalldata.length);
        console2.log("\nFirst 100 bytes:");
        console2.logBytes(proposeCalldata);

        // Calculate expected proposal ID
        bytes32 descriptionHash = keccak256(bytes(description));
        uint256 expectedProposalId = govInstance.hashProposal(targets, values, calldatas, descriptionHash);

        console2.log("\nExpected proposal ID: %s", expectedProposalId);
    }

    function test_ChangeVotingPeriod() public {
        console2.log("\n=== TESTING VOTING PERIOD CHANGE ===");
        console2.log("Current voting period: %s", govInstance.votingPeriod());
        console2.log("Guardian voting power: %s", tokenInstance.getVotes(guardian));
        console2.log("Proposal threshold: %s", govInstance.proposalThreshold());

        // Check guardian has enough voting power
        uint256 guardianVotes = tokenInstance.getVotes(guardian);
        require(guardianVotes >= govInstance.proposalThreshold(), "Guardian doesn't have enough votes");

        // Create proposal with the exact calldata we isolated
        address[] memory targets = new address[](1);
        targets[0] = address(govInstance);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = hex"e540d01d0000000000000000000000000000000000000000000000000000000000001c20"; // setVotingPeriod(7200)

        string memory description = "Set voting period to 7200 blocks";

        console2.log("\nProposal parameters:");
        console2.log("- Target: %s", targets[0]);
        console2.log("- Value: %s", values[0]);
        console2.log("- Calldata:");
        console2.logBytes(calldatas[0]);
        console2.log("- Description: %s", description);

        console2.log("\nCreating proposal...");
        vm.prank(guardian);
        uint256 proposalId = govInstance.propose(targets, values, calldatas, description);

        console2.log("Proposal created with ID: %s", proposalId);
        console2.log("Initial state: %s (0=Pending, 1=Active, 4=Succeeded)", uint256(govInstance.state(proposalId)));

        // Move past voting delay
        vm.roll(block.number + govInstance.votingDelay() + 1);
        console2.log("\nAfter voting delay, state: %s", uint256(govInstance.state(proposalId)));

        // Vote
        vm.prank(guardian);
        govInstance.castVote(proposalId, 1); // Vote FOR
        console2.log("Guardian voted FOR");

        // Check vote counts
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = govInstance.proposalVotes(proposalId);
        console2.log("Vote counts - Against: %s, For: %s, Abstain: %s", againstVotes, forVotes, abstainVotes);

        // Move past voting period
        vm.roll(block.number + govInstance.votingPeriod() + 1);
        console2.log("After voting period, state: %s", uint256(govInstance.state(proposalId)));

        // Queue
        console2.log("\nQueueing proposal...");
        govInstance.queue(targets, values, calldatas, keccak256(bytes(description)));
        console2.log("Proposal queued, state: %s", uint256(govInstance.state(proposalId)));

        // Move past timelock
        uint256 eta = govInstance.proposalEta(proposalId);
        console2.log("ETA: %s, Current time: %s", eta, block.timestamp);
        vm.warp(eta + 1);

        // Execute
        console2.log("\nExecuting proposal...");
        govInstance.execute(targets, values, calldatas, keccak256(bytes(description)));
        console2.log("Proposal executed!");

        console2.log("\nResults:");
        console2.log("Old voting period: 50400");
        console2.log("New voting period: %s", govInstance.votingPeriod());
        assertEq(govInstance.votingPeriod(), NEW_VOTING_PERIOD, "Voting period not updated");
        console2.log("Voting period successfully changed!");
    }

    function test_DirectCallFails() public {
        console2.log("\n=== TESTING DIRECT CALL FAILS ===");

        // Try direct call - should fail
        vm.expectRevert();
        govInstance.setVotingPeriod(uint32(NEW_VOTING_PERIOD));
        console2.log("Direct call reverted as expected");

        // Try from timelock - should also fail
        vm.prank(address(timelockInstance));
        vm.expectRevert();
        govInstance.setVotingPeriod(uint32(NEW_VOTING_PERIOD));
        console2.log("Call from timelock reverted as expected");
    }
}
