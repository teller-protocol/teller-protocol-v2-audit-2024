// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/LenderCommitmentForwarder/SmartCommitmentForwarder.sol";
import "../../contracts/interfaces/IMarketRegistry.sol";
import "../../contracts/interfaces/ISmartCommitment.sol";
import "../../contracts/interfaces/IPausableTimestamp.sol";
import "../../contracts/interfaces/IProtocolPausingManager.sol";

contract SmartCommitmentForwarderTest is Test {
    address protocolAddress = address(0x1);
    address marketRegistryAddress = address(0x2);
    address smartCommitmentAddress = address(0x3);
    address collateralTokenAddress = address(0x4);
    address borrower = address(0x5);
    address recipient = address(0x6);
    address protocolPauser = address(0x7);
    address protocolOwner = address(0x8);

    SmartCommitmentForwarder forwarder;

    function setUp() public {
        // Deploy the SmartCommitmentForwarder contract
        forwarder = new SmartCommitmentForwarder(protocolAddress, marketRegistryAddress);

        // Mock ownership of the protocol
        vm.mockCall(
            protocolAddress,
            abi.encodeWithSelector(Ownable.owner.selector),
            abi.encode(protocolOwner)
        );

        // Mock pausing manager to return the protocol pauser
        address pausingManager = address(0x9);
        vm.mockCall(
            protocolAddress,
            abi.encodeWithSelector(IHasProtocolPausingManager.getProtocolPausingManager.selector),
            abi.encode(pausingManager)
        );
        vm.mockCall(
            pausingManager,
            abi.encodeWithSelector(IProtocolPausingManager.isPauser.selector, protocolPauser),
            abi.encode(true)
        );
    }

    function test_setLiquidationProtocolFeePercent() public {
        vm.startPrank(protocolOwner);

        uint256 newFeePercent = 500; // 5%
        forwarder.setLiquidationProtocolFeePercent(newFeePercent);

        assertEq(forwarder.getLiquidationProtocolFeePercent(), newFeePercent);
        vm.stopPrank();
    }

    function test_setLiquidationProtocolFeePercent_RevertsIfNotOwner() public {
        uint256 newFeePercent = 500; // 5%
        vm.expectRevert("Sender not authorized");
        forwarder.setLiquidationProtocolFeePercent(newFeePercent);
    }

    function test_acceptSmartCommitmentWithRecipient() public {
        uint256 principalAmount = 1000 ether;
        uint256 collateralAmount = 500 ether;
        uint256 collateralTokenId = 1;
        uint16 interestRate = 500; // 5%
        uint32 loanDuration = 30 days;

        // Mock the Smart Commitment contract
        vm.mockCall(
            smartCommitmentAddress,
            abi.encodeWithSelector(ISmartCommitment.getCollateralTokenType.selector),
            abi.encode(CommitmentCollateralType.ERC20)
        );
        vm.mockCall(
            smartCommitmentAddress,
            abi.encodeWithSelector(ISmartCommitment.getMarketId.selector),
            abi.encode(1)
        );
        vm.mockCall(
            smartCommitmentAddress,
            abi.encodeWithSelector(ISmartCommitment.getPrincipalTokenAddress.selector),
            abi.encode(address(0x10))
        );

        // Mock the submission of a bid
        uint256 bidId = 12345;
        vm.mockCall(
            protocolAddress,
            abi.encodeWithSelector(
                TellerV2MarketForwarder_G3._submitBidWithCollateral.selector
            ),
            abi.encode(bidId)
        );

        // Mock accepting funds for the bid
        vm.mockCall(
            smartCommitmentAddress,
            abi.encodeWithSelector(
                ISmartCommitment.acceptFundsForAcceptBid.selector,
                borrower,
                bidId,
                principalAmount,
                collateralAmount,
                collateralTokenAddress,
                collateralTokenId,
                loanDuration,
                interestRate
            ),
            ""
        );

        // Call the function and verify bid creation
        uint256 createdBidId = forwarder.acceptSmartCommitmentWithRecipient(
            smartCommitmentAddress,
            principalAmount,
            collateralAmount,
            collateralTokenId,
            collateralTokenAddress,
            recipient,
            interestRate,
            loanDuration
        );

        assertEq(createdBidId, bidId);
    }

    function test_pause() public {
        vm.startPrank(protocolPauser);

        forwarder.pause();
        assertTrue(forwarder.paused());

        vm.stopPrank();
    }

    function test_unpause() public {
        vm.startPrank(protocolPauser);

        forwarder.pause();
        forwarder.unpause();

        assertFalse(forwarder.paused());
        vm.stopPrank();
    }

    function test_pause_RevertsIfNotPauser() public {
        vm.expectRevert("Sender not authorized");
        forwarder.pause();
    }

    function test_setOracle() public {
        vm.startPrank(protocolOwner);

        address newOracle = address(0x11);
        forwarder.setOracle(newOracle);

        assertEq(forwarder.getOracle(), newOracle);
        vm.stopPrank();
    }

    function test_setIsStrictMode() public {
        vm.startPrank(protocolOwner);

        forwarder.setIsStrictMode(true);
        assertTrue(forwarder.isStrictMode());

        forwarder.setIsStrictMode(false);
        assertFalse(forwarder.isStrictMode());

        vm.stopPrank();
    }
}
