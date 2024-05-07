pragma solidity >=0.8.0 <0.9.0;
// SPDX-License-Identifier: MIT

// Contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Interfaces
import "./interfaces/ICallbackEmitter.sol";
import "./interfaces/ILoanRepaymentListener.sol";

  

 /*
        Ownership needs to be transferred to TellerV2 

 */
 
contract CallbackEmitter is  Initializable,
    OwnableUpgradeable,
    ICallbackEmitter
{
 
    constructor() {}

    function initialize() external initializer {
        __Ownable_init(); 
    }
  

    function sendRepayLoanCallback(
        address _loanRepaymentListener, 
        uint256 _bidId,
        address _msgSenderForMarket,
        uint256 _principalAmount,
        uint256 _interestAmount       
      ) external override onlyOwner  returns(bool) {

        uint256 csize;

        assembly {
            csize := extcodesize(_loanRepaymentListener)
        }

        if (csize == 0) {
            return false;
        }

        try
                ILoanRepaymentListener(_loanRepaymentListener).repayLoanCallback{
                    gas: 40000
                }( //limit gas costs to prevent lender griefing repayments
                    _bidId,
                    _msgSenderForMarket,
                    _principalAmount,
                    _interestAmount
                )
         {return true;} catch { return false;}
    }


}
