// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IMarketLiquidityRewards.sol";

import "./interfaces/IMarketRegistry.sol";
import "./interfaces/ICollateralManager.sol";
import "./interfaces/ITellerV2.sol";

import {  BidState } from "./TellerV2Storage.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/*
- Claim reward for a loan based on loanId (use a brand new contract)
- This contract holds the reward tokens in escrow.
- There will be an allocateReward() function, only called by marketOwner, deposits tokens in escrow
- There will be a claimReward() function -> reads state of loans , only called by borrower -> withdraws tokens from escrow and makes those loans as having claimed rewards
- unallocateReward()

This contract could give out 1 OHM when someone takes out a loan (for every 1000 USDC)


    ryan ideas : 


    thinking through conditionals we’d add to liquidity mining
1. the claimer could be the lender or borrower  - not yet implemented
ie we might be incentivizing one or the other, or both  (or some other address? idk a use case yet tho)
principalTokenAddress
2.ie the loan had to be made in USDC or x token
collateralTokenAddress
ie Olympus wants to incentivize holders to lock up gOHM as collateral
maxPrincipalPerCollateral
3. ie we might incentivize a collateral ratio greater than or less than some number. or this might be blank (would not use an oracle but raw units ? )

4. make sure loans are REPAID before any reward  ? 

*/
 

 
contract MarketLiquidityRewards is 
IMarketLiquidityRewards,
Initializable
{
    address immutable tellerV2;
    address immutable marketRegistry;
    address immutable collateralManager;

    uint256 allocationCount;
 

    //allocationId => rewardAllocation
    mapping(uint256 => RewardAllocation) public allocatedRewards;

    //bidId => allocationId => rewardWasClaimed 
    mapping(uint256 => mapping(uint256 =>bool) ) public rewardClaimedForBid;


    modifier onlyMarketOwner(uint256 _marketId){
        require(msg.sender == IMarketRegistry(marketRegistry).getMarketOwner(_marketId), "Only market owner can call this function.");
        _;
    }

    event CreatedAllocation(uint256 allocationId, address allocator, uint256 marketId);

    event IncreasedAllocation(uint256 allocationId, uint256 amount);

    event DecreasedAllocation(uint256 allocationId, uint256 amount);

    event DeletedAllocation(uint256 allocationId);

    event ClaimedRewards(uint256 allocationId, uint256 bidId, address recipient, uint256 amount);
    

    constructor(address _tellerV2, address _marketRegistry, address _collateralManager) {
        tellerV2 = _tellerV2;
        marketRegistry = _marketRegistry;
        collateralManager = _collateralManager;
    }

    function initialize() external initializer {
 
    }


/**

 */

    function allocateRewards(
        RewardAllocation calldata _allocation        
    ) public virtual returns (uint256 allocationId_ ) { 

        allocationId_ = allocationCount++;

         require(
            _allocation.allocator == msg.sender,
            "Invalid allocator address"
        );

        IERC20Upgradeable(_allocation.rewardTokenAddress).transferFrom( msg.sender , address(this), _allocation.rewardTokenAmount );

        allocatedRewards[allocationId_] = _allocation ;

          
        emit CreatedAllocation( 
            allocationId_,
            _allocation.allocator,
            _allocation.marketId
        );
    }

    function increaseAllocationAmount(
        uint256 _allocationId,
        uint256 _tokenAmount 
    ) public virtual {
        

        IERC20Upgradeable(allocatedRewards[_allocationId].rewardTokenAddress).transferFrom(msg.sender,address(this),_tokenAmount);
        allocatedRewards[_allocationId].rewardTokenAmount += _tokenAmount;

           
        emit IncreasedAllocation( 
            _allocationId,
            _tokenAmount
        );
    }

    function deallocateRewards(
        uint256 _allocationId,
        uint256 _tokenAmount
    ) public virtual {

        require(msg.sender == allocatedRewards[_allocationId].allocator,"Only the allocator can deallocate rewards.");

        //subtract amount reward before transfer 
        allocatedRewards[_allocationId].rewardTokenAmount -= _tokenAmount;

        IERC20Upgradeable(allocatedRewards[_allocationId].rewardTokenAddress).transfer(msg.sender , _tokenAmount );


            emit DecreasedAllocation( 
                _allocationId,
                _tokenAmount
            );
            

         if( allocatedRewards[_allocationId].rewardTokenAmount == 0 ) {
            delete allocatedRewards[_allocationId];               
               
            emit DeletedAllocation( 
                _allocationId 
            );
        }
    

    }


    function claimRewards(
        uint256 _allocationId,
        uint256 _bidId       
    ) external virtual {

        RewardAllocation storage allocatedReward = allocatedRewards[_allocationId];

        require(!rewardClaimedForBid[_bidId][_allocationId],"reward already claimed");
        rewardClaimedForBid[_bidId][_allocationId] = true; // leave this here to defend against re-entrancy 

        //optimize gas by turning these into one single call 
      
        ( address borrower,
          address lender,
          uint256 marketId,
          address principalTokenAddress,
          uint256 principalAmount,
          uint32 timestamp,
          BidState bidState
        ) = ITellerV2(tellerV2).getLoanSummary(_bidId);

        address collateralTokenAddress = allocatedReward.requiredCollateralTokenAddress;


        //make sure the loan follows the rules related to the allocation 

        //require that loan status is PAID  
        _verifyLoanStatus( bidState, BidState.PAID );

        //require that the loan was started in the correct timeframe 
        _verifyLoanStartTime(timestamp, allocatedReward.bidStartTimeMin, allocatedReward.bidStartTimeMax);


        if(collateralTokenAddress != address(0)){
             uint256 collateralAmount = ICollateralManager(collateralManager).getCollateralAmount(_bidId, collateralTokenAddress);

             //require collateral amount 
             _verifyCollateralAmount(collateralAmount, principalAmount, allocatedReward.minimumCollateralPerPrincipalAmount);
        }
       
        _verifyPrincipalTokenAddress(
            principalTokenAddress,
            allocatedReward.requiredPrincipalTokenAddress
        );

        _verifyCollateralTokenAddress(
            collateralTokenAddress,
            allocatedReward.requiredCollateralTokenAddress
        );

        uint256 amountToReward = _calculateRewardAmount(
            principalAmount,
            allocatedRewards[_allocationId].rewardPerLoanPrincipalAmount            
            );

        //require that msgsender is the loan borrower 
        require(msg.sender == borrower, "Only the borrower can claim reward.");

        require(marketId == allocatedRewards[_allocationId].marketId, "MarketId mismatch for allocation");

        //transfer tokens reward to the msgsender 
        IERC20Upgradeable(allocatedRewards[_allocationId].rewardTokenAddress).transfer(msg.sender, amountToReward);

        _decrementAllocatedAmount(_allocationId,amountToReward);
        
    
        emit ClaimedRewards(
            _allocationId,
            _bidId,
            msg.sender,
            amountToReward
        );

    }   

    function _decrementAllocatedAmount(uint256 _allocationId, uint256 _amount) internal {
        allocatedRewards[_allocationId].rewardTokenAmount -= _amount;
    }

 
    function _calculateRewardAmount(uint256 _loanPrincipal, uint256 rewardPerLoanPrincipalAmount) internal view returns (uint256) {
        
        //change calc -- maybe based on something set by the market owner in teh struct 
       
        return _loanPrincipal / 1000;
    }

    function _verifyCollateralAmount(uint256 collateralAmount, uint256 principalAmount, uint256 minimumCollateralPerPrincipalAmount) internal {

        // require()

    }

    function _verifyLoanStatus(BidState actualBidState, BidState expectedBidState) internal {
 
        require(actualBidState == expectedBidState, "Invalid bid state for loan.");

    }

    function _verifyLoanStartTime(uint32 loanStartTime, uint32 minStartTime, uint32 maxStartTime) internal {

            require(minStartTime == 0 || loanStartTime > minStartTime, "Loan was submitted before the min start time.");
            require(maxStartTime == 0 || loanStartTime < maxStartTime, "Loan was submitted after the max start time.");

        }

    function _verifyPrincipalTokenAddress(address loanTokenAddress, address expectedTokenAddress) internal {

            require(expectedTokenAddress == address(0) || loanTokenAddress == expectedTokenAddress,"Invalid principal token address.");

        }

    function _verifyCollateralTokenAddress(address loanTokenAddress, address expectedTokenAddress) internal {

                require(expectedTokenAddress == address(0) || loanTokenAddress == expectedTokenAddress,"Invalid collateral token address.");


        }




}
