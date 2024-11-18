// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../libraries/UniswapPricingLibrary.sol";
import "../interfaces/uniswap/IUniswapV3Pool.sol";
import "../interfaces/IUniswapPricingLibrary.sol";
import "../libraries/uniswap/TickMath.sol";
import "../libraries/uniswap/FixedPoint96.sol";
import "../libraries/uniswap/FullMath.sol";

contract UniswapPricingLibraryTest is Test {
    using UniswapPricingLibrary for IUniswapPricingLibrary.PoolRouteConfig[];

    IUniswapV3Pool mockPool1;
    IUniswapV3Pool mockPool2;

    function setUp() public {
        // Create mock Uniswap V3 pools
        mockPool1 = IUniswapV3Pool(address(0x1));
        mockPool2 = IUniswapV3Pool(address(0x2));
    }

   function test_getUniswapPriceRatioForPoolRoutes_SingleRoute() public {
    uint160 mockSqrtPriceX96 = 500000000000000000; // Mock sqrt price
    uint32 twapInterval = 30; // Mock TWAP interval
 

    // Configure a single route
    IUniswapPricingLibrary.PoolRouteConfig[] memory poutes[0] = IUniswapPricingLibrary.PoolRouteConfig({
        pool: address(mockPool1),
        twapInterval: twapInterval,
        zeroForOne: true
    });

    // Calculate the price ratio
    uint256 priceRatio = UniswapPricingLibrary.getUniswapPriceRatioForPoolRoutes(poolRoutes);

    // Assert the price ratio is greater than zero
    assertTrue(priceRatio > 0, "Price ratio should be calculated");
}

    function test_getUniswapPriceRatioForPoolRoutes_MultipleRoutes() public {
        uint160 mockSqrtPriceX96_1 = 500000000000000000; // Mock sqrt price for pool 1
        uint160 mockSqrtPriceX96_2 = 300000000000000000; // Mock sqrt price for pool 2
        uint32 twapInterval = 30; // Mock TWAP interval

        // Mock Uniswap pool behavior for pool 1
        vm.mockCall(
            address(mockPool1),
            abi.encodeWithSelector(IUniswapV3Pool.slot0.selector),
            abi.encode(mockSqrtPriceX96_1, 0, 0, 0, 0, 0, 0)
        );

        // Mock Uniswap pool behavior for pool 2
        vm.mockCall(
            address(mockPool2),
            abi.encodeWithSelector(IUniswapV3Pool.slot0.selector),
            abi.encode(mockSqrtPriceX96_2, 0, 0, 0, 0, 0, 0)
        );

        // Configure multiple routes
        IUniswapPricingLibrary.PoolRouteConfig[] memory poolRoutes[0] = IUniswapPricingLibrary.PoolRouteConfig({
            pool: address(mockPool1),
            twapInterval: twapInterval,
            zeroForOne: true
        });
        poolRoutes[1] = IUniswapPricingLibrary.PoolRouteConfig({
            pool: address(mockPool2),
            twapInterval: twapInterval,
            zeroForOne: false
        });

        uint256 priceRatio = poolRoutes.getUniswapPriceRatioForPoolRoutes();

        assertTrue(priceRatio > 0, "Price ratio should be calculated for multiple routes");
    }

    function test_getPriceX96FromSqrtPriceX96() public {
        uint160 sqrtPriceX96 = 500000000000000000; // Mock sqrt price

        uint256 priceX96 = UniswapPricingLibrary.getPriceX96FromSqrtPriceX96(sqrtPriceX96);

        assertTrue(priceX96 > 0, "PriceX96 should be calculated");
    }

    function test_getSqrtTwapX96_CurrentPrice() public {
        uint160 mockSqrtPriceX96 = 500000000000000000; // Mock sqrt price

        // Mock Uniswap pool `slot0`
        vm.mockCall(
            address(mockPool1),
            abi.encodeWithSelector(IUniswapV3Pool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, 0)
        );

        uint160 sqrtPriceX96 = UniswapPricingLibrary.getSqrtTwapX96(
            address(mockPool1),
            0 // TWAP interval of 0 (current price)
        );

        assertEq(sqrtPriceX96, mockSqrtPriceX96, "Should return current sqrt price");
    }

    function test_getSqrtTwapX96_TWAPCalculation() public {
        uint32 twapInterval = 30; // Mock TWAP interval
        int56 tickCumulativeBefore = 1000000;
        int56 tickCumulativeAfter = 2000000;

        // Mock Uniswap pool `observe`
        vm.mockCall(
            address(mockPool1),
            abi.encodeWithSelector(IUniswapV3Pool.observe.selector, new uint32 ),
        bi.encode(new int56 , new uint160 )    );

     nt160 sqrtPriceX96 = UniswapPricingLibrary.getSqrtTwapX96(
            address(mockPool1),
            twapInterval
        );

        assertTrue(sqrtPriceX96 > 0, "Should return calculated sqrt TWAP price");
    }
}
