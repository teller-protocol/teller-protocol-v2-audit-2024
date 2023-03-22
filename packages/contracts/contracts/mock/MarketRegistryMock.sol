pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../interfaces/IMarketRegistry.sol";
import { PaymentType } from "../libraries/V2Calculations.sol";

contract MarketRegistryMock is IMarketRegistry {
    address marketOwner;

    constructor(address _marketOwner) {
        marketOwner = _marketOwner;
    }

    function initialize(TellerAS _tellerAS) external {}

    function isVerifiedLender(uint256 _marketId, address _lenderAddress)
        public
        view
        returns (bool isVerified_, bytes32 uuid_)
    {
        isVerified_ = true;
    }

    function isMarketClosed(uint256 _marketId) public view returns (bool) {
        return false;
    }

    function isVerifiedBorrower(uint256 _marketId, address _borrower)
        public
        view
        returns (bool isVerified_, bytes32 uuid_)
    {
        isVerified_ = true;
    }

    function getMarketOwner(uint256 _marketId) public view override returns (address) {
        return address(marketOwner);
    }

    function getMarketFeeRecipient(uint256 _marketId)
        public
        view
        returns (address)
    {
        return address(marketOwner);
    }

    function getMarketURI(uint256 _marketId)
        public
        view
        returns (string memory)
    {
        return "url://";
    }

    function getPaymentCycle(uint256 _marketId)
        public
        view
        returns (uint32, PaymentCycleType)
    {
        return (1000, PaymentCycleType.Seconds);
    }

    function getPaymentDefaultDuration(uint256 _marketId)
        public
        view
        returns (uint32)
    {
        return 1000;
    }

    function getBidExpirationTime(uint256 _marketId)
        public
        view
        returns (uint32)
    {
        return 1000;
    }

    function getMarketplaceFee(uint256 _marketId) public view returns (uint16) {
        return 1000;
    }

    function setMarketOwner(address _owner) public {
        marketOwner = _owner;
    }

    function getPaymentType(uint256 _marketId)
        public
        view
        returns (PaymentType)
    {}

    function createMarket(
        address _initialOwner,
        uint32 _paymentCycleDuration,
        uint32 _paymentDefaultDuration,
        uint32 _bidExpirationTime,
        uint16 _feePercent,
        bool _requireLenderAttestation,
        bool _requireBorrowerAttestation,
        PaymentType _paymentType,
        PaymentCycleType _paymentCycleType,
        string calldata _uri
    ) public returns (uint256) {}

    function createMarket(
        address _initialOwner,
        uint32 _paymentCycleDuration,
        uint32 _paymentDefaultDuration,
        uint32 _bidExpirationTime,
        uint16 _feePercent,
        bool _requireLenderAttestation,
        bool _requireBorrowerAttestation,
        string calldata _uri
    ) public returns (uint256) {}
}
