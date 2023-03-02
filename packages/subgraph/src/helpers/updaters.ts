import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";

import { CollateralCommitted } from "../../generated/CollateralManager/CollateralManager";
import {
  Bid,
  Borrower,
  Collateral,
  Commitment,
  Lender,
  MarketPlace,
  Payment,
  TokenVolume
} from "../../generated/schema";
import {
  TellerV2,
  TellerV2__bidsResult
} from "../../generated/TellerV2/TellerV2";

import {
  getBid,
  loadBorrowerByMarketId,
  loadBorrowerTokenVolume,
  loadLenderByMarketId,
  loadLenderTokenVolume,
  loadMarketById,
  loadProtocolTokenVolume,
  loadTokenVolumeByMarketId
} from "./loaders";

export function updateTokenVolumeOnPayment(
  lastPayment: BigInt,
  lastInterestPayment: BigInt,
  bidState: string,
  tokenVolume: TokenVolume
): void {
  const outstandingTokenCapital = tokenVolume.outstandingCapital;
  if (outstandingTokenCapital) {
    tokenVolume.outstandingCapital = outstandingTokenCapital.minus(lastPayment);
    if (outstandingTokenCapital.minus(lastPayment).lt(BigInt.zero())) {
      tokenVolume.outstandingCapital = BigInt.zero();
    }
  }

  const totalRepaidInterest = tokenVolume.totalRepaidInterest;
  if (totalRepaidInterest) {
    tokenVolume.totalRepaidInterest = totalRepaidInterest.plus(
      lastInterestPayment
    );
    tokenVolume.save();
  }

  if (bidState == "Repaid") {
    const activeTokenLoanCount = tokenVolume.activeLoans;
    if (activeTokenLoanCount) {
      tokenVolume.activeLoans = activeTokenLoanCount.minus(BigInt.fromI32(1));
    }
    const closedTokenLoanCount = tokenVolume.closedLoans;
    if (closedTokenLoanCount) {
      tokenVolume.closedLoans = closedTokenLoanCount.plus(BigInt.fromI32(1));
    }
  }
}

export function updateBid(
  bid: Bid,
  event: ethereum.Event,
  bidState: string
): void {
  const tellerV2Instance = TellerV2.bind(event.address);
  const storedBid = getBid(event.address, bid.bidId);

  bid.totalRepaidPrincipal = storedBid.value5.totalRepaid.principal;
  bid.totalRepaidInterest = storedBid.value5.totalRepaid.interest;
  bid.lastRepaidTimestamp = storedBid.value5.lastRepaidTimestamp;

  const _lastPayment = storedBid.value5.totalRepaid.principal.minus(
    bid._lastTotalRepaidAmount
  );
  bid._lastTotalRepaidAmount = _lastPayment.plus(bid._lastTotalRepaidAmount);

  const _lastInterestPayment = storedBid.value5.totalRepaid.interest.minus(
    bid._lastTotalRepaidInterestAmount
  );
  bid._lastTotalRepaidInterestAmount = _lastInterestPayment.plus(
    bid._lastTotalRepaidInterestAmount
  );

  if (bidState !== "Liquidated") {
    // The outstanding capital and payment entities are not updated on liquidation events
    // because the Liquidation event is fired after the Repayment event
    updateOutstandingCapital(
      bid,
      storedBid,
      _lastPayment,
      _lastInterestPayment,
      bidState
    );

    const payment = new Payment(event.transaction.hash.toHex());
    payment.bid = bid.id;
    payment.principal = _lastPayment;
    payment.interest = _lastInterestPayment;
    payment.paymentDate = event.block.timestamp;
    payment.outstandingCapital = bid.principal.minus(bid.totalRepaidPrincipal);
    if (bid.nextDueDate && bid.nextDueDate < event.block.timestamp) {
      payment.status = "Late";
    } else {
      payment.status = "On Time";
    }
    payment.save();
  }

  if (bidState === "Repayment") {
    bid.nextDueDate = tellerV2Instance.calculateNextDueDate(bid.bidId);
  } else {
    bid.nextDueDate = BigInt.zero();
    bid.status = bidState;
  }

  bid.save();
}

export function updateBidTokenVolumesOnAccept(bid: Bid, lender: Lender): void {
  incrementLenderStats(lender, bid);

  // Update the market's token volume
  const tokenVolume = loadTokenVolumeByMarketId(
    Address.fromBytes(bid.lendingTokenAddress),
    bid.marketplace
  );
  updateTokenVolumeOnAccept(tokenVolume, bid);

  // Update the protocol's overall token volume
  const protocolVolume = loadProtocolTokenVolume(
    Address.fromBytes(bid.lendingTokenAddress)
  );
  updateTokenVolumeOnAccept(protocolVolume, bid);

  // Update the borrower's token volume
  const borrowerVolume = loadBorrowerTokenVolume(
    Address.fromBytes(bid.lendingTokenAddress),
    bid.borrower
  );
  updateTokenVolumeOnAccept(borrowerVolume, bid);
}

function updateTokenVolumeOnAccept(tokenVolume: TokenVolume, bid: Bid): void {
  if (tokenVolume.lendingTokenAddress == Address.zero()) {
    tokenVolume.lendingTokenAddress = bid.lendingTokenAddress;
  }
  const outstandingTokenCapital = tokenVolume.outstandingCapital;
  if (outstandingTokenCapital) {
    tokenVolume.outstandingCapital = outstandingTokenCapital.plus(
      bid.principal
    );
  }
  const tokenActiveLoans = tokenVolume.activeLoans;
  const tokenClosedLoans = tokenVolume.closedLoans;
  const tokenAprTotal = tokenVolume._aprTotal;
  const tokenDurationTotal = tokenVolume._durationTotal;
  const loaned = tokenVolume.totalLoaned;
  if (
    tokenAprTotal &&
    tokenActiveLoans &&
    tokenClosedLoans &&
    loaned &&
    tokenDurationTotal
  ) {
    const updatedAPRTotal = tokenAprTotal.plus(bid.apr);
    tokenVolume._aprTotal = updatedAPRTotal;
    const updatedTokenActiveLoans = tokenActiveLoans.plus(BigInt.fromI32(1));
    const totalTokenLoans = updatedTokenActiveLoans.plus(tokenClosedLoans);
    tokenVolume.activeLoans = updatedTokenActiveLoans;

    tokenVolume.aprAverage = updatedAPRTotal.div(totalTokenLoans);
    const updatedTokenLoanTotal = loaned.plus(bid.principal);
    tokenVolume.loanAverage = updatedTokenLoanTotal.div(totalTokenLoans);

    const updatedDurationTotal = tokenDurationTotal.plus(bid.loanDuration);
    tokenVolume._durationTotal = updatedDurationTotal;
    tokenVolume.durationAverage = updatedDurationTotal.div(totalTokenLoans);
  }
  const totalTokensLoaned = tokenVolume.totalLoaned;
  const highestLoan = tokenVolume.highestLoan;
  const lowestLoan = tokenVolume.lowestLoan;
  if (totalTokensLoaned && highestLoan && lowestLoan) {
    tokenVolume.totalLoaned = totalTokensLoaned.plus(bid.principal);
    tokenVolume.highestLoan =
      bid.principal > highestLoan ? bid.principal : highestLoan;
    tokenVolume.lowestLoan = lowestLoan.equals(BigInt.zero())
      ? bid.principal
      : bid.principal < lowestLoan
      ? bid.principal
      : lowestLoan;
  }
  tokenVolume.save();
}

export function updateOutstandingCapital(
  bid: Bid,
  storedBid: TellerV2__bidsResult,
  _lastPayment: BigInt,
  _lastInterestPayment: BigInt,
  bidState: string
): void {
  const market = loadMarketById(storedBid.value3.toString());
  const lender = loadLenderByMarketId(storedBid.value2, market.id);
  const borrower: Borrower = loadBorrowerByMarketId(
    storedBid.value0,
    market.id
  );

  if (bidState == "Repaid") {
    const activeLoanCount = lender.activeLoans;
    const closedLoanCount = lender.closedLoans;
    if (activeLoanCount) {
      lender.activeLoans = activeLoanCount.minus(BigInt.fromI32(1));
    }
    if (closedLoanCount) {
      lender.closedLoans = closedLoanCount.plus(BigInt.fromI32(1));
    }
    const borrowerActiveLoans = borrower.activeLoans;
    const borrowerClosedLoans = borrower.closedLoans;
    if (borrowerActiveLoans) {
      borrower.activeLoans = borrowerActiveLoans.minus(BigInt.fromI32(1));
    }
    if (borrowerClosedLoans) {
      borrower.closedLoans = borrowerClosedLoans.plus(BigInt.fromI32(1));
    }
  }

  if (bidState == "Repaid") {
    const acLoanCount = market.activeLoans;
    const clLoanCount = market.closedLoans;
    if (acLoanCount) {
      market.activeLoans = acLoanCount.minus(BigInt.fromI32(1));
    }
    if (clLoanCount) {
      market.closedLoans = clLoanCount.plus(BigInt.fromI32(1));
    }
  }

  // Update market's token volume
  const tokenVolume = loadTokenVolumeByMarketId(
    storedBid.value5.lendingToken,
    market.id
  );
  updateTokenVolumeOnPayment(
    _lastPayment,
    _lastInterestPayment,
    bidState,
    tokenVolume
  );
  tokenVolume.save();

  // Update protocol's overall token volume
  const protocolVolume = loadProtocolTokenVolume(storedBid.value5.lendingToken);
  updateTokenVolumeOnPayment(
    _lastPayment,
    _lastInterestPayment,
    bidState,
    protocolVolume
  );
  protocolVolume.save();

  // Update lender's token volume
  const lenderVolume = loadLenderTokenVolume(
    storedBid.value5.lendingToken,
    bid.lender!
  );
  updateTokenVolumeOnPayment(
    _lastPayment,
    _lastInterestPayment,
    bidState,
    lenderVolume
  );
  const earnedLenderInterest = lenderVolume.commissionEarned;
  if (earnedLenderInterest) {
    lenderVolume.commissionEarned = earnedLenderInterest.plus(
      _lastInterestPayment
    );
  }
  lenderVolume.save();

  const commitmentId = bid.commitment;
  if (commitmentId) {
    const commitment = Commitment.load(commitmentId);
    if (commitment) {
      const commitmentStats = TokenVolume.load(commitment.stats);
      updateTokenVolumeOnPayment(
        _lastPayment,
        _lastInterestPayment,
        bidState,
        commitmentStats!
      );
      if (commitmentStats && commitmentStats.commissionEarned) {
        commitmentStats.commissionEarned = commitmentStats.commissionEarned.plus(
          _lastInterestPayment
        );
        commitmentStats.save();
      }
    }
  }

  // Update borrower's token volume
  const borrowerVolume = loadBorrowerTokenVolume(
    Address.fromBytes(bid.lendingTokenAddress),
    bid.borrower
  );
  updateTokenVolumeOnPayment(
    _lastPayment,
    _lastInterestPayment,
    bidState,
    borrowerVolume
  );
  borrowerVolume.save();

  lender.save();
  market.save();
  borrower.save();
}

export function updateCollateral(
  collateral: Collateral,
  event: ethereum.Event
): void {
  const evt = changetype<CollateralCommitted>(event);
  collateral.amount = evt.params._amount;
  collateral.tokenId = evt.params._tokenId;
  collateral.type = getTypeString(evt.params._type);
  collateral.collateralAddress = evt.params._collateralAddress;
}
function getTypeString(tokenType: i32): string {
  let type = "";
  if (tokenType == i32(0)) {
    type = "ERC20";
  } else if (tokenType == i32(1)) {
    type = "ERC721";
  } else if (tokenType == i32(2)) {
    type = "ERC1155";
  }
  return type;
}

export function incrementLenderStats(lender: Lender, bid: Bid): void {
  // If this is the lenders first loan, increment the totalNumberOfLenders on the associated Market
  if (lender.totalLoaned.isZero()) {
    const market = MarketPlace.load(bid.marketplace);
    if (market) {
      const numLenders = market.totalNumberOfLenders;
      market.totalNumberOfLenders = numLenders.plus(BigInt.fromI32(1));
      market.save();
    }
  }

  lender.activeLoans = lender.activeLoans.plus(BigInt.fromI32(1));
  lender.totalLoaned = lender.totalLoaned.plus(bid.principal);
  lender.bidsAccepted = lender.bidsAccepted.plus(BigInt.fromI32(1));
  lender.save();

  // Update the lender's token volume
  const lenderVolume = loadLenderTokenVolume(
    Address.fromBytes(bid.lendingTokenAddress),
    bid.lender!
  );
  updateTokenVolumeOnAccept(lenderVolume, bid);
}

export function decrementLenderStats(lender: Lender, bid: Bid): void {
  lender.activeLoans = lender.activeLoans.minus(BigInt.fromI32(1));
  lender.totalLoaned = lender.totalLoaned.minus(bid.principal);
  lender.bidsAccepted = lender.bidsAccepted.minus(BigInt.fromI32(1));
  lender.save();
}
