// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Types} from "../utils/Types.sol";
import {IInterestModel} from "../interfaces/IInterestModel.sol";
import {IReputationHook} from "../interfaces/IReputationHook.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title LendingPoolStorage
/// @notice Storage layout for {LendingPool}.
abstract contract LendingPoolStorage {
    /// @notice Protocol fee (bps) taken from accrued interest on full repay.
    uint16 public protocolFeeBps;

    /// @notice Origination fee (bps) charged on borrow (taken from borrowed asset).
    uint16 public originationFeeBps;

    /// @notice Active risk engine module.
    IRiskEngine public riskEngine;

    /// @notice Active interest model module.
    IInterestModel public interestModel;

    /// @notice Reputation hook module (required in strict v0 setup).
    IReputationHook public reputationHook;

    /// @notice Treasury address (liquidity source placeholder for v0).
    address public treasury;

    /// @notice Next loan id to be assigned (starts from 1).
    uint256 public nextLoanId;

    /// @notice Loan storage by id.
    mapping(uint256 loanId => Types.Loan loan) internal loans;

    /// @notice Active loan id for a borrower (0 if none).
    mapping(address borrower => uint256 loanId) public activeLoanIdOf;

    uint256[49] private __gap;
}
