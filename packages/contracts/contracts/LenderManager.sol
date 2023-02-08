pragma solidity >=0.8.0 <0.9.0;
// SPDX-Licence-Identifier: MIT

// Contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";

import "./LenderManager/ERC721UpgradeableMod.sol";

// Interfaces
import "./interfaces/ILenderManager.sol";
import "./interfaces/ITellerV2.sol";
import "./interfaces/IMarketRegistry.sol";

contract LenderManager is
Initializable,
OwnableUpgradeable,
ERC2771ContextUpgradeable,
ERC721UpgradeableMod,
ILenderManager
{
    IMarketRegistry public immutable marketRegistry;

    // Mapping of loans to current active lenders - using erc721 now 
   // mapping(uint256 => address) internal _loanActiveLender;
 

    /** Events **/
    event NewLoanRegistered(address indexed newLender, uint256 bidId);

    constructor(address _trustedForwarder, address _marketRegistry)
    ERC2771ContextUpgradeable(_trustedForwarder)
    {
        marketRegistry = IMarketRegistry(_marketRegistry);
    }

    function initialize() external initializer {
        __LenderManager_init();
        
    }

    function __LenderManager_init() internal onlyInitializing {
        __Ownable_init();
        __ERC721_init("TellerLoan", "TLN");
    }


    /**
     * @notice Registers a new active lender for a loan, minting the nft
     * @param _bidId The id for the loan to set.
     * @param _newLender The address of the new active lender. 
     */
    function registerLoan(uint256 _bidId, address _newLender )
    public
    override
    {
        address currentLender = _getActiveLender(_bidId);
        if (currentLender == address(0)) {
            _checkOwner(); //why is this necessary 
        } else {
            require(currentLender == _msgSender(), "Not loan owner");
        }
       

        require(_hasMarketApproval(_newLender,_bidId), "Not approved by market");


        if (currentLender != _newLender) {

            _safeMint(_newLender,_bidId);
 
            emit NewLoanRegistered(_newLender, _bidId);
        }
    }

    

    /**
     * @notice Returns the address of the lender that owns a given loan/bid.
     * @param _bidId The id of the bid to return the lender for
     * @return The address of the lender.
     */
    function getActiveLoanLender(uint256 _bidId)
    external
    view
    override
    returns (address)
    {
        return _getActiveLender(_bidId);
    }

    /**
     * @notice Returns the address of the lender that owns a given loan/bid.
     * @param _bidId The id of the bid to return the lender for
     * @return lender_ The address of the lender.
     */
    function _getActiveLender(uint256 _bidId)
    internal
    view
    returns (address lender_)
    {
        if(_exists(_bidId)){
            return ownerOf(_bidId);
        }else{
            //CAUTION: If a loan NFT is burned, this branch of code will be executed
            return ITellerV2(owner()).getLoanLender(_bidId);
        }
       
    }

    function _getLoanMarketId(uint256 _bidId)
    internal
    view
    returns (uint256)
    { 
        return ITellerV2(owner()).getLoanMarketId(_bidId); 
    }



    function _hasMarketApproval(address guy, uint256 _bidId) 
    internal
    view 
    returns (bool)
    {
        //address currentLender = _getActiveLender(_bidId);
        //require(currentLender == _msgSender(), "Not loan owner");

        uint256 marketId = _getLoanMarketId(_bidId);

        (bool isVerified, ) = marketRegistry.isVerifiedLender(
            marketId,
            guy
        );

        return isVerified;
    }


    /**  ERC721 Functions **/

     /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {

        require(_hasMarketApproval(to,tokenId), "Not approved by market");

        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        require(_hasMarketApproval(to,tokenId), "Not approved by market");

        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function _baseURI() internal view override returns (string memory) {
        return "";
    }


    /** OpenZeppelin Override Functions **/

    function _msgSender()
    internal
    view
    virtual
    override(ERC2771ContextUpgradeable, ContextUpgradeable)
    returns (address sender)
    {
        sender = ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
    internal
    view
    virtual
    override(ERC2771ContextUpgradeable, ContextUpgradeable)
    returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
}