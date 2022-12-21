// SPDX-Licence-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Contracts
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Libraries
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

// Interfaces
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "./interfaces/ICollateralManager.sol";
import { Collateral, CollateralType, ICollateralEscrowV1 } from "./interfaces/escrow/ICollateralEscrowV1.sol";
import "./interfaces/ITellerV2.sol";


contract CollateralManager is OwnableUpgradeable, ICollateralManager {
    /* Storage */
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    ITellerV2 public tellerV2;
    address private collateralEscrowBeacon; // The address of the escrow contract beacon
    mapping(uint256 => address) public _escrows; // bidIds -> collateralEscrow
    // bidIds -> validated collateral info
    mapping(uint256 => CollateralInfo) internal _bidCollaterals;
    struct CollateralInfo {
        EnumerableSetUpgradeable.AddressSet collateralAddresses;
        mapping(address => Collateral) collateralInfo;
    }
    // Boolean indicating if a bid is backed by collateral
    mapping(uint256 => bool) _isBidCollateralBacked;

    /* Events */
    event CollateralEscrowDeployed(uint256 _bidId, address _collateralEscrow);
    event CollateralCommitted(
        uint256 _bidId,
        address _collateralAddress,
        uint256 _amount,
        uint256 _tokenId
    );
    event CollateralClaimed(uint256 _bidId);

    /* Modifiers */
    modifier onlyTellerV2() {
        require(_msgSender() == address(tellerV2), 'Sender not authorized');
        _;
    }

    /* External Functions */

    /**
     * @notice Initializes the collateral manager.
     * @param _collateralEscrowBeacon The address of the escrow implementation.
     * @param _tellerV2 The address of the protocol.
     */
    function initialize(address _collateralEscrowBeacon, address _tellerV2)
        external
        initializer
    {
        collateralEscrowBeacon = _collateralEscrowBeacon;
        tellerV2 = ITellerV2(_tellerV2);
    }

    /**
     * @notice Checks the validity of a borrower's multiple collateral balances and commits it to a bid.
     * @param _bidId The id of the associated bid.
     * @param _collateralInfo Additional information about the collateral assets.
     * @return validation_ Boolean indicating if the collateral balances were validated.
     */
    function commitCollateral(
        uint256 _bidId,
        Collateral[] calldata _collateralInfo
    ) public returns (bool validation_) {
        address borrower = tellerV2.getLoanBorrower(_bidId);
        (validation_, ) = checkBalances(borrower, _collateralInfo);
        if (validation_) {
            for (uint256 i; i < _collateralInfo.length; i++) {
                Collateral memory info = _collateralInfo[i];
                _commitCollateral(_bidId, info);
            }
            _isBidCollateralBacked[_bidId] = true;
        }
    }

    /**
     * @notice Checks the validity of a borrower's collateral balance and commits it to a bid.
     * @param _bidId The id of the associated bid.
     * @param _collateralInfo Additional information about the collateral asset.
     * @return validation_ Boolean indicating if the collateral balance was validated.
     */
    function commitCollateral(
        uint256 _bidId,
        Collateral calldata _collateralInfo
    ) public returns (bool validation_) {
        address borrower = tellerV2.getLoanBorrower(_bidId);
        validation_ = _checkBalance(borrower, _collateralInfo);
        if (validation_) {
            _commitCollateral(_bidId, _collateralInfo);
            _isBidCollateralBacked[_bidId] = true;
        }
    }

    /**
     * @notice Re-checks the validity of a borrower's collateral balance committed to a bid.
     * @param _bidId The id of the associated bid.
     * @return validation_ Boolean indicating if the collateral balance was validated.
     */
    function revalidateCollateral(uint256 _bidId)
        external
        returns (bool validation_)
    {
        Collateral[]
            memory collateralInfos = getCollateralInfo(_bidId);
        address borrower = tellerV2.getLoanBorrower(_bidId);
        (validation_, ) = _checkBalances(borrower, collateralInfos, true);
    }

    /**
     * @notice Checks the validity of a borrower's multiple collateral balances.
     * @param _borrowerAddress The address of the borrower holding the collateral.
     * @param _collateralInfo Additional information about the collateral assets.
     */
    function checkBalances(
        address _borrowerAddress,
        Collateral[] calldata _collateralInfo
    ) public returns (bool validated_, bool[] memory checks_) {
        return _checkBalances(_borrowerAddress, _collateralInfo, false);
    }

    /**
     * @notice Deploys a new collateral escrow and deposits collateral.
     * @param _bidId The associated bidId of the collateral escrow.
     */
    function deployAndDeposit(uint256 _bidId) external onlyTellerV2 {
        if (_isBidCollateralBacked[_bidId]) {
            (address proxyAddress, ) = _deployEscrow(_bidId);
            _escrows[_bidId] = proxyAddress;

            for (
                uint256 i;
                i < _bidCollaterals[_bidId].collateralAddresses.length();
                i++
            ) {
                _deposit(
                    _bidId,
                    _bidCollaterals[_bidId].collateralInfo[
                        _bidCollaterals[_bidId].collateralAddresses.at(i)
                    ]
                );
            }

            emit CollateralEscrowDeployed(_bidId, proxyAddress);
        }
    }

    /**
     * @notice Gets the address of a deployed escrow.
     * @notice _bidId The bidId to return the escrow for.
     * @return The address of the escrow.
     */
    function getEscrow(uint256 _bidId) external view returns (address) {
        return _escrows[_bidId];
    }

    /**
     * @notice Gets the collateral info for a given bid id.
     * @param _bidId The bidId to return the collateral info for.
     * @return infos_ The stored collateral info.
     */
    function getCollateralInfo(uint256 _bidId)
        public
        view
        returns (Collateral[] memory infos_)
    {
        CollateralInfo storage collateral = _bidCollaterals[_bidId];
        address[] memory collateralAddresses = collateral
            .collateralAddresses
            .values();
        infos_ = new Collateral[](
            collateralAddresses.length
        );
        for (uint256 i; i < collateralAddresses.length; i++) {
            infos_[i] = collateral.collateralInfo[collateralAddresses[i]];
        }
    }

    /**
     * @notice Withdraws deposited collateral from the created escrow of a bid.
     * @param _bidId The id of the bid to withdraw collateral for.
     */
    function withdraw(uint256 _bidId) external {
        if (_isBidCollateralBacked[_bidId]) {
            BidState bidState = tellerV2.getBidState(_bidId);
            require(
                bidState == BidState.PAID ||
                bidState == BidState.LIQUIDATED,
                "Loan has not been repaid or liquidated"
            );
            address receiver;
            if (bidState == BidState.LIQUIDATED) {
                receiver = tellerV2.getLoanLender(_bidId);
            } else {
                receiver = tellerV2.getLoanBorrower(_bidId);
            }
            _withdraw(_bidId, receiver);
        }
    }

    /**
     * @notice Allows collateral to be claimed for a defaulted loan.
     * @param _bidId The id of the bid to claim the collateral for.
     */
    function claimCollateral(uint256 _bidId)
        external
    {
        require(_isBidCollateralBacked[_bidId], 'Loan is not collateral backed');
        require(tellerV2.isLoanDefaulted(_bidId), 'Loan is not eligible to claim');
        address bidLender = tellerV2.getLoanLender(_bidId);
        _withdraw(_bidId, bidLender);
        emit CollateralClaimed(_bidId);
    }

    /* Internal Functions */

    /**
     * @notice Deploys a new collateral escrow.
     * @param _bidId The associated bidId of the collateral escrow.
     */
    function _deployEscrow(uint256 _bidId)
        internal
        returns (address proxyAddress_, address borrower_)
    {
        proxyAddress_ = _escrows[_bidId];
        // Get bid info
        borrower_ = tellerV2.getLoanBorrower(_bidId);
        if (proxyAddress_ == address(0)) {
            require(borrower_ != address(0), "Bid does not exist");

            BeaconProxy proxy = new BeaconProxy(
                collateralEscrowBeacon,
                abi.encodeWithSelector(
                    ICollateralEscrowV1.initialize.selector,
                    _bidId
                )
            );
            proxyAddress_ = address(proxy);
        }
    }

    function _deposit(
        uint256 _bidId,
        Collateral memory collateralInfo
    ) public payable {
        require(collateralInfo._amount > 0, "Collateral not validated");
        (address escrowAddress, address borrower) = _deployEscrow(_bidId);
        ICollateralEscrowV1 collateralEscrow = ICollateralEscrowV1(
            escrowAddress
        );
        // Pull collateral from borrower & deposit into escrow
        if (
            collateralInfo._collateralType ==
            CollateralType.ERC20
        ) {
            IERC20Upgradeable(collateralInfo._collateralAddress).transferFrom(
                borrower,
                address(this),
                collateralInfo._amount
            );
            IERC20Upgradeable(collateralInfo._collateralAddress).approve(
                escrowAddress,
                collateralInfo._amount
            );
            collateralEscrow.depositToken(
                collateralInfo._collateralAddress,
                collateralInfo._amount
            );
        }
        if (
            collateralInfo._collateralType ==
            CollateralType.ERC721
        ) {
            IERC721Upgradeable(collateralInfo._collateralAddress)
                .safeTransferFrom(
                    borrower,
                    address(this),
                    collateralInfo._tokenId
                );
            IERC721Upgradeable(collateralInfo._collateralAddress)
                .approve(
                    escrowAddress,
                    collateralInfo._tokenId
                );
            collateralEscrow.depositAsset(
                CollateralType.ERC721,
                collateralInfo._collateralAddress,
                collateralInfo._amount,
                collateralInfo._tokenId
            );
        }
        if (
            collateralInfo._collateralType ==
            CollateralType.ERC1155
        ) {
            bytes memory data;
            IERC1155Upgradeable(collateralInfo._collateralAddress)
                .safeTransferFrom(
                    borrower,
                    address(this),
                    collateralInfo._tokenId,
                    collateralInfo._amount,
                    data
                );
            IERC1155Upgradeable(collateralInfo._collateralAddress)
                .setApprovalForAll(
                    escrowAddress,
                    true
                );
            collateralEscrow.depositAsset(
                CollateralType.ERC1155,
                collateralInfo._collateralAddress,
                collateralInfo._amount,
                collateralInfo._tokenId
            );
        }
    }

    /**
     * @notice Withdraws collateral to a given receiver's address.
     * @param _bidId The id of the bid to withdraw collateral for.
     * @param _receiver The address to withdraw the collateral to.
     */
    function _withdraw(uint256 _bidId, address _receiver) internal {
        for (
            uint256 i;
            i < _bidCollaterals[_bidId].collateralAddresses.length();
            i++
        ) {
            // Get collateral info
            Collateral
            storage collateralInfo = _bidCollaterals[_bidId]
            .collateralInfo[
            _bidCollaterals[_bidId].collateralAddresses.at(i)
            ];
            // Withdraw collateral from escrow and send it to bid lender
            ICollateralEscrowV1(_escrows[_bidId]).withdraw(
                collateralInfo._collateralAddress,
                collateralInfo._amount,
                _receiver
            );
        }
    }

    /**
     * @notice Checks the validity of a borrower's collateral balance and commits it to a bid.
     * @param _bidId The id of the associated bid.
     * @param _collateralInfo Additional information about the collateral asset.
     */
    function _commitCollateral(
        uint256 _bidId,
        Collateral memory _collateralInfo
    ) internal {
        CollateralInfo storage collateral = _bidCollaterals[_bidId];
        collateral.collateralAddresses.add(_collateralInfo._collateralAddress);
        collateral.collateralInfo[
            _collateralInfo._collateralAddress
        ] = _collateralInfo;
        emit CollateralCommitted(
            _bidId,
            _collateralInfo._collateralAddress,
            _collateralInfo._amount,
            _collateralInfo._tokenId
        );
    }

    /**
     * @notice Checks the validity of a borrower's multiple collateral balances.
     * @param _borrowerAddress The address of the borrower holding the collateral.
     * @param _collateralInfo Additional information about the collateral assets.
     */
    function _checkBalances(
        address _borrowerAddress,
        Collateral[] memory _collateralInfo,
        bool _shortCircut
    ) internal returns (bool validated_, bool[] memory checks_) {
        checks_ = new bool[](_collateralInfo.length);
        validated_ = true;
        for (uint256 i; i < _collateralInfo.length; i++) {
            bool isValidated = _checkBalance(
                _borrowerAddress,
                _collateralInfo[i]
            );
            checks_[i] = isValidated;
            if (!isValidated) {
                validated_ = false;
                if (_shortCircut) {
                    return (validated_, checks_);
                }
            }
        }
    }

    /**
     * @notice Checks the validity of a borrower's single collateral balance.
     * @param _borrowerAddress The address of the borrower holding the collateral.
     * @param _collateralInfo Additional information about the collateral asset.
     * @return validation_ Boolean indicating if the collateral balances were validated.
     */
    function _checkBalance(
        address _borrowerAddress,
        Collateral memory _collateralInfo
    ) internal returns (bool) {
        CollateralType collateralType = _collateralInfo
            ._collateralType;
        if (collateralType == CollateralType.ERC20) {
            return
                _collateralInfo._amount <=
                IERC20Upgradeable(_collateralInfo._collateralAddress).balanceOf(
                    _borrowerAddress
                );
        }
        if (collateralType == CollateralType.ERC721) {
            return
                _borrowerAddress ==
                IERC721Upgradeable(_collateralInfo._collateralAddress).ownerOf(
                    _collateralInfo._tokenId
                );
        }
        if (collateralType == CollateralType.ERC1155) {
            return
                _collateralInfo._amount <=
                IERC1155Upgradeable(_collateralInfo._collateralAddress)
                    .balanceOf(_borrowerAddress, _collateralInfo._tokenId);
        }
        return false;
    }
}
