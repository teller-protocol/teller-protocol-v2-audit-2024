

abstract contract ICallbackEmitter   {
 
    function sendRepayLoanCallback(
        address _loanRepaymentListener, 
        uint256 _bidId,
        address _msgSenderForMarket,
        uint256 _principalAmount,
        uint256 _interestAmount       
      ) external virtual returns (bool);
}
