// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import "forge-std/Test.sol";
import "../../contracts/libraries/UniswapPricingLibrary.sol";
 

import { Testable } from "../Testable.sol";

import { UniswapV3PoolMock } from "../../contracts/mock/uniswap/UniswapV3PoolMock.sol";

import "../../contracts/mock/MarketRegistryMock.sol";


import { IUniswapPricingLibrary } from "../../contracts/interfaces/IUniswapPricingLibrary.sol";

import "../../contracts/TellerV2Context.sol";

import "forge-std/console.sol";



contract UniswapPricingLibraryTest is Testable {

    LenderCommitmentForwarderTest_TellerV2Mock private tellerV2Mock;
    MarketRegistryMock mockMarketRegistry;

   // using UniswapPricingLibrary for IUniswapPricingLibrary.PoolRouteConfig[];

    UniswapV3PoolMock mockUniswapPool;
    UniswapV3PoolMock mockUniswapPoolSecondary;

    function setUp() public {


        tellerV2Mock = new LenderCommitmentForwarderTest_TellerV2Mock();
        mockMarketRegistry = new MarketRegistryMock();

        mockUniswapPool = new UniswapV3PoolMock();

        mockUniswapPoolSecondary = new UniswapV3PoolMock();

    }

   function test_getUniswapPriceRatioForPool_same_price() public {
      
        bool zeroForOne = false; // ??

        mockUniswapPool.set_mockSqrtPriceX96(1 * 2**96);

        uint32 twapInterval = 0;

        IUniswapPricingLibrary.PoolRouteConfig
            memory routeConfig = IUniswapPricingLibrary.PoolRouteConfig({
                pool: address(mockUniswapPool),
                zeroForOne: zeroForOne,
                twapInterval: twapInterval,
                token0Decimals: 18,
                token1Decimals: 18
            });

        uint256 priceRatio = UniswapPricingLibrary
            .getUniswapPriceRatioForPool(routeConfig);

        

        assertEq(  1e18 , priceRatio  , "unexpected price ratio") ;
    }


      function test_getUniswapPriceRatioForPool_different_price() public {
      
        bool zeroForOne = false; // ??

        
        //i think this means the ratio is 100:1
        mockUniswapPool.set_mockSqrtPriceX96(10 * 2**96);


        uint32 twapInterval = 0;

        IUniswapPricingLibrary.PoolRouteConfig
            memory routeConfig = IUniswapPricingLibrary.PoolRouteConfig({
                pool: address(mockUniswapPool),
                zeroForOne: zeroForOne,
                twapInterval: twapInterval,
                token0Decimals: 18,
                token1Decimals: 18
            });

        uint256 priceRatio = UniswapPricingLibrary
            .getUniswapPriceRatioForPool(routeConfig);

        

        assertEq(  1e16 , priceRatio  , "unexpected price ratio") ;
    }



  function test_getUniswapPriceRatioForPool_decimal_scenario_A() public {
      
        bool zeroForOne = false; // ??

        uint256  principalTokenDecimals = 18;
        uint256 collateralTokenDecimals = 6;

          

        mockUniswapPool.set_mockSqrtPriceX96(1 * 2**96);

        uint32 twapInterval = 0;

    //decimals dont affect raw ratios 
        IUniswapPricingLibrary.PoolRouteConfig
            memory routeConfig = IUniswapPricingLibrary.PoolRouteConfig({
                pool: address(mockUniswapPool),
                zeroForOne: zeroForOne,
                twapInterval: twapInterval,
                token0Decimals: collateralTokenDecimals,
                token1Decimals: principalTokenDecimals
            });

        uint256 priceRatio = UniswapPricingLibrary
            .getUniswapPriceRatioForPool(routeConfig);

        

        assertEq(  1e18 , priceRatio  , "unexpected price ratio") ;
    }



    
}




contract LenderCommitmentForwarderTest_TellerV2Mock is TellerV2Context {
    constructor() TellerV2Context(address(0)) {}

    function __setMarketRegistry(address _marketRegistry) external {
        marketRegistry = IMarketRegistry(_marketRegistry);
    }

    function getSenderForMarket(uint256 _marketId)
        external
        view
        returns (address)
    {
        return _msgSenderForMarket(_marketId);
    }

    function getDataForMarket(uint256 _marketId)
        external
        view
        returns (bytes calldata)
    {
        return _msgDataForMarket(_marketId);
    }
}
