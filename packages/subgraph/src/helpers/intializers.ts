import { Address, BigInt } from "@graphprotocol/graph-ts";

import { TokenVolume } from "../../generated/schema";

import { loadLoanCounts } from "./loaders";

export function initTokenVolume(
  token: TokenVolume,
  tokenAddress: Address
): void {
  token.lendingTokenAddress = tokenAddress;
  token.bids = [];

  const loans = loadLoanCounts(`token-volume-${token.id}`);
  token.loans = loans.id;

  token.outstandingCapital = BigInt.zero();
  token.totalLoaned = BigInt.zero();
  token.loanAverage = BigInt.zero();

  token.commissionEarned = BigInt.zero();
  token.totalRepaidInterest = BigInt.zero();

  token._aprTotal = BigInt.zero();
  token.aprAverage = BigInt.zero();

  token._durationTotal = BigInt.zero();
  token.durationAverage = BigInt.zero();
}
